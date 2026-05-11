#!/usr/bin/bash
# slash-bash.bash - sourceable library that intercepts /commands at the
# readline layer and dispatches to handler functions, bypassing bash's
# normal path-execution behaviour for slash-prefixed input.
#
# Mechanism: bind \C-xs to an interceptor function, then rebind \C-m so
# that pressing Enter expands to the chord "\C-xs\C-j" - interceptor first
# (rewrites READLINE_LINE if input starts with /), then the original
# accept-line. This catches the line BEFORE bash parses it for execution.
#
# Sourcing in non-interactive contexts is a no-op.

# Source-detection guard - this file MUST be sourced, not executed. If
# someone runs `bash slash-bash.bash` directly, BASH_SOURCE[0] equals $0
# and we abort before installing readline bindings into the wrong context.
[[ ${BASH_SOURCE[0]} != "$0" ]] || {
  >&2 printf 'slash-bash.bash: must be sourced, not executed\n'
  exit 1
}

# Interactive guard - sourcing in a non-interactive script is a no-op.
# The chord-binding trick at the bottom of this file requires a real TTY.
# TEST_SHIM_GUARD_BEGIN
[[ $- == *i* ]] || return 0
# TEST_SHIM_GUARD_END

# DELIBERATE: `set -euo pipefail` is NOT enabled here. This library is sourced
# into the live interactive slash-bash session; errexit would terminate the
# user's shell on any handler failure. Handlers use defensive `|| return N`
# patterns instead.

# TEST_SHIM_PREEXEC_BEGIN
# Vendor: bash-preexec.sh in the same directory. Existence-checked so a
# missing dep produces a clean diagnostic rather than bash's stock cryptic
# `source: No such file or directory`.
declare -- _sb_preexec="${BASH_SOURCE[0]%/*}"/bash-preexec.sh
[[ -f $_sb_preexec ]] || {
  >&2 printf 'slash-bash.bash: missing dependency %s\n' "${_sb_preexec@Q}"
  return 1
}
# shellcheck source=bash-preexec.sh
source -- "$_sb_preexec"
unset -v _sb_preexec
# TEST_SHIM_PREEXEC_END

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

declare -g  -- _SB_AGENT="${SB_AGENT:-leet}"
declare -ga    _SB_AGENT_LIST=()               # populated lazily by _sb_load_agent_list
declare -g  -- _SB_MODEL="${SB_MODEL:-claude-opus-4-7}"
declare -ga    _SB_MODEL_LIST
read -r -a _SB_MODEL_LIST <<<"${SB_MODEL_LIST:-claude-opus-4-7 claude-opus-4-6 claude-sonnet-4-6 claude-haiku-4-6}"
# VECTORDBS is a cross-project Okusi convention; reused, not new.
declare -g  -- _SB_KB_ROOT="${VECTORDBS:-/var/lib/vectordbs}"
declare -g  -- _SB_KB=''
declare -ga    _SB_KB_LIST=()                  # populated lazily by _sb_load_kb_list
declare -ig    _SB_MAX_TOKENS="${SB_MAX_TOKENS:-32000}"
declare -ig    _SB_OLLAMA="${SB_OLLAMA:-0}"
declare -g  -- _SB_HISTORY_FILE="${SB_HISTORY_FILE:-${XDG_CACHE_HOME:-$HOME/.cache}/slash-bash/history}"
declare -g  -- _SB_LAST_ORIGINAL=''
# Captured rendered prompt (${PS1@P}) at intercept time, used by
# _sb_redraw_original to reprint exactly what the user saw - re-expanding
# PS1 in preexec would yield stale prompt fields (\!, \T, \@) that drift
# by one between Enter and exec.
declare -g  -- _SB_LAST_PROMPT=''
# History dir is created lazily on first write (see _sb_log_dispatch) so
# sourcing this library does not mutate the filesystem.

# Conversation binding - the JSONL UUID slash-bash resumes via
# `claude.agent --resume <uuid>`. _SB_SESSION_CWD defaults to the cwd at
# library-source time, preserving the historical "lock to entry cwd"
# behaviour. _SB_SESSION_UUID is empty until first /ask resolves it; the
# /ask handler adopts the freshly-minted JSONL after the synchronous
# claude.agent call returns. _SB_SESSION_LAST_ASK gates the dirty prompt
# in /rebase: 0 = never asked, otherwise EPOCHSECONDS of last /ask. All
# four are seeded from like-named SB_SESSION_* / SB_DIRTY_WINDOW env vars
# so `eval "$(/status)"` in a parent shell round-trips the binding into
# the next slash-bash source.
declare -g  -- _SB_SESSION_CWD="${SB_SESSION_CWD:-$PWD}"
declare -g  -- _SB_SESSION_UUID="${SB_SESSION_UUID:-}"
declare -ig    _SB_SESSION_LAST_ASK="${SB_SESSION_LAST_ASK:-0}"
declare -ig    _SB_DIRTY_WINDOW="${SB_DIRTY_WINDOW:-300}"

# Slash-command registry. Each handler file under handlers.d/ registers
# itself by appending to these maps; the dispatcher and first-word
# completer read them. _SB_HANDLERS is the source of truth (every alias
# is a separate key); _SB_HELP holds one-line synopses keyed by canonical
# alias; _SB_COMPLETE binds /cmd -> _sb_complete_<name> for arg
# completion. Bare `/' is special-cased in __sb_dispatch (NOT a key) -
# see comment there.
declare -gA _SB_HANDLERS=()
declare -gA _SB_HELP=()
declare -gA _SB_COMPLETE=()

# Master list of slash commands for first-word TAB completion. Derived
# from ${!_SB_HANDLERS[@]} at end-of-init (after handlers.d/*.bash is
# sourced and before the site hook runs). Kept declared (not deleted)
# because site hooks at $_SB_SITE_BASH are documented to append to it
# (e.g. `_SB_SLASH_CMDS+=(/myticket)') for completion-only entries; the
# registry path (`_SB_HANDLERS[/myticket]=_sb_cmd_myticket') is
# preferred for new commands.
declare -ga _SB_SLASH_CMDS=()

# Output buffers for __sb_split_redirect (overwritten on every call).
declare -g  -- _SB_SPLIT_CMD=''
declare -g  -- _SB_SPLIT_TAIL=''

# ---------------------------------------------------------------------------
# Messaging - BCS _msg() pattern, __-prefixed to match _error convention.
# Single primitive __msg; severity helpers wrap it with sigil+colour. Gating
# flags _VERBOSE/_DEBUG seed from the SB_* env-var family. Colours are
# read-only globals set once at source time; on a non-TTY (stdout or stderr
# redirected) every colour expands to ''. Prefix uses the same fallback
# chain as the original _error: agent name -> SCRIPT_NAME -> literal.
# ---------------------------------------------------------------------------

declare -ig _VERBOSE="${SB_VERBOSE:-0}"
declare -ig _DEBUG="${SB_DEBUG:-0}"

# Extended ANSI palette. In-tree consumers reference _RED/_GREEN/_YELLOW/_CYAN/_NC
# (via _error/_warn/_info/_success/_debug) and _BOLD (handlers.d/_help.bash).
# _BLUE, _MAGENTA, _DIM, _ITALIC, _UNDERLINE, _REVERSE are intentionally
# retained for future handlers.d/ commands and $SB_SITE_BASH site hooks.
# shellcheck disable=SC2034  # palette retained for future / site-hook consumers
if [[ -t 1 && -t 2 ]]; then
  declare -gr _RED=$'\033[0;31m'    _GREEN=$'\033[0;32m'   _YELLOW=$'\033[0;33m'
  declare -gr _BLUE=$'\033[0;34m'   _MAGENTA=$'\033[0;35m' _CYAN=$'\033[0;36m'
  declare -gr _BOLD=$'\033[1m'      _DIM=$'\033[2m'        _ITALIC=$'\033[3m'
  declare -gr _UNDERLINE=$'\033[4m' _REVERSE=$'\033[7m'    _NC=$'\033[0m'
else
  declare -gr _RED='' _GREEN='' _YELLOW='' _BLUE='' _MAGENTA='' _CYAN=''
  declare -gr _BOLD='' _DIM='' _ITALIC='' _UNDERLINE='' _REVERSE='' _NC=''
fi

# __msg PREFIX MSG... - emit one stderr line per MSG with session identity
# and a sigil. SC2059 is intentional: $1 carries the caller's sigil (which
# may include ANSI escapes), the agent prefix expands from an internal
# global (_SB_AGENT/SCRIPT_NAME) never user input, and %s handles the
# variadic payload. All in-tree callers pass literal sigil strings.
# shellcheck disable=SC2059
__msg()     { >&2 printf "${_SB_AGENT:-${SCRIPT_NAME:-slash-bash}}: $1 %s\n" "${@:2}"; }

_error()   { __msg "${_RED}✗${_NC}" "$@"; }
_warn()    { __msg "${_YELLOW}▲${_NC}" "$@"; }
_info()    { ((_VERBOSE)) || return 0; __msg "${_CYAN}◉${_NC}" "$@"; }
_success() { ((_VERBOSE)) || return 0; __msg "${_GREEN}✓${_NC}" "$@"; }
_debug()   { ((_DEBUG))   || return 0; __msg "${_RED}⦿${_NC}" "$@"; }
_vecho()   { ((_VERBOSE)) || return 0; >&2 printf "${_SB_AGENT:-${SCRIPT_NAME:-slash-bash}}: %s\n" "$@"; }
# _die N MSG... - print error and return N. Uses `return`, not `exit`,
# because this library is sourced into the user's interactive shell (see
# the `set -euo pipefail` rationale at lines 27-30); `exit` would kill the
# user's terminal session.
_die()     { (($# < 2)) || _error "${@:2}"; return "${1:-1}"; }

# ---------------------------------------------------------------------------
# Lazy loaders
# ---------------------------------------------------------------------------

_sb_load_agent_list() {
  ((${#_SB_AGENT_LIST[@]})) && return 0 ||:
  command -v claude.agent >/dev/null || return 1
  readarray -t _SB_AGENT_LIST < <(
    claude.agent --list 2>/dev/null \
      | sed -E 's/\x1b\[[0-9;]*m//g' \
      | awk '{print $1}' \
      | sort -u
  )
}

# Resolve the default Agents.json path by deriving from claude.agent's
# location in PATH (the registry lives next to the binary in the Okusi
# tree, exposed via .symlink). Empty result if claude.agent is not in
# PATH; callers fall through to their own missing-file diagnostic. Used
# by _sb_agent_key and _sb_cmd_systemprompt as the fallback when
# AGENTS_JSON is unset.
_sb_default_agents_json() {
  local -- ca
  ca=$(command -v claude.agent 2>/dev/null) || return 0
  ca=$(realpath -- "$ca" 2>/dev/null) || return 0
  printf '%s\n' "${ca%/*}/Agents.json"
}

# Populate _SB_KB_LIST from $_SB_KB_ROOT (default /var/lib/vectordbs) by
# globbing for <name>/<name>.cfg pairs. Override with SB_KB_LIST="kb1 kb2"
# for a curated menu (short-circuits the glob). Lazy: idempotent on repeat
# calls.
_sb_load_kb_list() {
  ((${#_SB_KB_LIST[@]})) && return 0 ||:
  if [[ -n ${SB_KB_LIST:-} ]]; then
    read -r -a _SB_KB_LIST <<<"$SB_KB_LIST"
    return 0
  fi
  [[ -d $_SB_KB_ROOT ]] || return 0
  local -- d name cfg
  for d in "$_SB_KB_ROOT"/*/; do
    [[ -d $d ]] || continue
    name=${d%/}; name=${name##*/}
    cfg=$d$name.cfg
    [[ -f $cfg ]] && _SB_KB_LIST+=("$name")
  done
}

# ISO-8601 timestamp with portable fallback. GNU date supports -Iseconds;
# BSD/busybox does not. Used by the preexec history logger.
_sb_iso_now() {
  date -Iseconds 2>/dev/null || date +'%Y-%m-%dT%H:%M:%S%z'
}

# Hour-granular timestamp matching claude.agent's spacetime_string
# (claude.agent:68-80). Used to substitute {{spacetime}} in systemprompt
# display so output mirrors what the model actually sees at runtime. Hour
# granularity keeps the prompt cache stable within each hour window.
# NOTE: format duplicated from claude.agent - keep in sync if that script
# changes its format.
_sb_spacetime() {
  local -- tzname=''
  if [[ -v TZ && -n ${TZ:-} ]]; then
    tzname=$TZ
  elif [[ -r /etc/timezone ]]; then
    read -r tzname < /etc/timezone
  else
    tzname=UTC
  fi
  printf '%(%A %F %H:00 %z)T %s\n' -1 "$tzname"
}

# ---------------------------------------------------------------------------
# Shared handler helpers - referenced by multiple handlers in handlers.d/.
# Per-command handler bodies live under handlers.d/_*.bash; this section
# only retains primitives that more than one handler reuses.
# ---------------------------------------------------------------------------

# _sb_print_list LABEL CURRENT_VAR ITEMS...
# Print "available <label>s:" / dashed list / "current: <value>".
_sb_print_list() {
  local -- label=$1
  local -n __sb_print_target=$2
  shift 2
  >&2 printf 'available %ss:\n' "$label"
  >&2 printf '  - %s\n' "$@"
  >&2 printf 'current: %s\n' "${__sb_print_target:-<none>}"
}

# _sb_select_from_list LABEL CURRENT_VAR ITEMS...
# Mutates the var named in $2 (must match ^_SB_[A-Z]+$) on selection.
# Returns 0 on selection, 1 on cancel/EOF/empty list/non-TTY.
# 'q'/'Q'/empty REPLY/Ctrl-D = cancel.
_sb_select_from_list() {
  local -- label=$1
  [[ $2 =~ ^_SB_[A-Z]+$ ]] || { _error 'internal: bad target var'; return 2; }
  local -n __sb_sel_target=$2
  shift 2
  (($#)) || { _error "no ${label}s available"; return 1; }
  [[ -t 0 ]] || { _error "/${label}s --select requires an interactive terminal"; return 1; }
  >&2 printf 'current %s: %s\n' "$label" "${__sb_sel_target:-<none>}"
  local -- picked=''
  local -- PS3="select ${label} number (q to cancel): "
  select picked in "$@"; do
    case ${REPLY:-} in
      q|Q|'') return 1 ;;
      *)      ;;
    esac
    if [[ -n $picked ]]; then
      __sb_sel_target=$picked
      >&2 printf '%s set to: %s\n' "$label" "$__sb_sel_target"
      return 0
    fi
    _error "invalid choice ${REPLY@Q}"
    continue
  done
  return 1
}

# Resolve a user-typed agent short name against _SB_AGENT_LIST.
# Tries case-insensitive exact match first, then prefix match. Echoes the
# canonical short name on success; returns 1 if no match.
# Caller must have already invoked _sb_load_agent_list.
_sb_resolve_agent_name() {
  local -- needle=${1,,}
  local -- candidate
  for candidate in "${_SB_AGENT_LIST[@]}"; do
    [[ ${candidate,,} == "$needle" ]] && { printf '%s\n' "$candidate"; return 0; }
  done
  for candidate in "${_SB_AGENT_LIST[@]}"; do
    [[ ${candidate,,} == "$needle"* ]] && { printf '%s\n' "$candidate"; return 0; }
  done
  return 1
}

# Look up the full Agents.json key for a short agent name. Mirrors the
# resolve_agent jq snippet in claude.agent:273-274.
_sb_agent_key() {
  local -- name=$1
  local -r agents_json=${AGENTS_JSON:-$(_sb_default_agents_json)}
  [[ -n $agents_json && -f $agents_json ]] || return 1
  jq -r --arg name "$name" \
    'keys[] | select((split(" - ")[0] | ascii_downcase) == ($name | ascii_downcase))' \
    "$agents_json" | head -n1
}

# _sb_pick_newest_uuid OUTVAR CWD [MIN_MTIME] - resolve the most-recent
# JSONL session in $SB_CLAUDE_PROJECTS_DIR/<encoded-cwd>/ and write its
# UUID into the named output var. Optional MIN_MTIME (find's %T@ format,
# epoch.nanosec) skips JSONLs at or before that cutoff. Empty result on
# missing dir, empty dir, or every entry filtered by MIN_MTIME. The
# enumeration goes through `find -printf` rather than a bash glob, so
# this function does not touch the caller's nullglob state.
_sb_pick_newest_uuid() {
  # Caller passes either a module global (_SB_SESSION_UUID) or a function
  # local (e.g. `newest` in _sb_cmd_rebase), so the guard accepts any
  # valid bash identifier rather than the stricter _SB_-prefixed pattern
  # used by _sb_select_from_list. Optional 3rd arg is a minimum-mtime
  # cutoff in `%T@` format (epoch.nanosec) - JSONLs at or before that
  # cutoff are skipped. Used by /ask to avoid silently adopting a
  # sibling slash-bash shell's JSONL when both run in the same cwd.
  [[ $1 =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || { _error 'internal: bad target var'; return 2; }
  local -n __sb_pick_out=$1
  local -- cwd=$2
  local -- min_mtime=${3:-}
  local -- root=${SB_CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}
  local -- enc_dir=$root/${cwd//\//-}
  __sb_pick_out=''
  [[ -d $enc_dir ]] || return 0
  # `find -printf '%T@'` gives nanosecond-precision mtime as a fixed-
  # format string ("1234567890.123456789"), so lexical comparison is
  # ordering-correct across the file list. `stat -c %Y`'s 1-second
  # resolution cannot distinguish concurrent JSONL writes from sibling
  # shells in the same cwd; the rc==0 gate at the /ask call site
  # masked the cross-shell hijack but a same-second write race would
  # still adopt the wrong UUID under the old strict (mt > best_mtime)
  # tiebreaker (lexically-first glob entry won, independent of writer).
  local -a entries=()
  readarray -t entries < <(
    find "$enc_dir" -maxdepth 1 -name '*.jsonl' \
      -printf '%T@\t%f\n' 2>/dev/null
  )
  local -- entry mt f best='' best_mtime=''
  for entry in "${entries[@]}"; do
    [[ -n $entry ]] || continue
    mt=${entry%%$'\t'*}
    f=${entry#*$'\t'}
    [[ -z $min_mtime ]] || [[ $mt > $min_mtime ]] || continue
    if [[ -z $best_mtime || $mt > $best_mtime ]]; then
      best=$f
      best_mtime=$mt
    fi
  done
  [[ -n $best ]] || return 0
  __sb_pick_out=${best%.jsonl}
}

# ---------------------------------------------------------------------------
# Completion handlers
# ---------------------------------------------------------------------------

# First-word completion (registered via `complete -I`). For words starting
# with /, completes against the registered slash commands (keys of
# _SB_HANDLERS). Otherwise falls through to standard command-name
# completion so non-slash commands tab-complete normally.
_sb_complete_first() {
  local -- cur=${COMP_WORDS[COMP_CWORD]}
  COMPREPLY=()
  if [[ $cur == /* ]]; then
    readarray -t COMPREPLY < <(compgen -W "${!_SB_HANDLERS[*]}" -- "$cur")
    # Mirror __sb_intercept's path carve-out: when no registered slash
    # command prefix-matches cur, fall through to pathname completion so
    # absolute paths like /usr/local/bin/foo complete natively. compopt
    # -o filenames requests bash's filename-aware display (trailing / on
    # directories, no trailing space after a dir name). The 2>/dev/null
    # swallows the harmless "not currently executing completion function"
    # diagnostic when this function is invoked outside a live completion.
    if (( ${#COMPREPLY[@]} == 0 )); then
      readarray -t COMPREPLY < <(compgen -f -- "$cur")
      # compopt errors out (rc=1) when invoked outside an active
      # completion (e.g. ad-hoc / bats invocation). Tolerate that so the
      # function stays usable both in live readline and in tests.
      compopt -o filenames 2>/dev/null ||:
    fi
    return 0
  fi
  readarray -t COMPREPLY < <(compgen -c -- "$cur")
}

# ---------------------------------------------------------------------------
# Dispatcher - registry-driven. Each /cmd resolves to a handler function
# via _SB_HANDLERS (populated by handlers.d/_*.bash files). Bare `/' is
# special-cased as the documented shorthand for /ask rather than
# registered as a key, to keep the first-word completion list clean and
# preserve the `${#_SB_HANDLERS[@]} == 26` invariant tested by the suite.
# ---------------------------------------------------------------------------

__sb_dispatch() {
  local -- line=${1:-}
  # Strip leading whitespace.
  line=${line#"${line%%[![:space:]]*}"}

  local -- cmd args
  if [[ $line == *' '* ]]; then
    cmd=${line%% *}
    args=${line#* }
    args=${args#"${args%%[![:space:]]*}"}
  else
    cmd=$line
    args=''
  fi

  # Bare `/' is the documented shorthand for /ask.
  [[ $cmd == / ]] && cmd=/ask

  local -- fn=${_SB_HANDLERS[$cmd]:-}
  if [[ -z $fn ]]; then
    _error "unknown slash command: ${cmd@Q}"
    return 1
  fi
  "$fn" "$args"
}

# ---------------------------------------------------------------------------
# Quote-aware split at first unquoted shell metachar (>, <, |, ;, &). Lets
# the interceptor pass redirection / pipe / sequence syntax through to bash
# verbatim while keeping the command portion safely @Q-quoted.
#
# Output globals (overwritten on every call):
#   _SB_SPLIT_CMD   text before the metachar (trailing whitespace stripped)
#   _SB_SPLIT_TAIL  text from the metachar onward (or empty if none found)
# ---------------------------------------------------------------------------

__sb_split_redirect() {
  local -- line=$1
  local -i in_squote=0 in_dquote=0 escape=0
  local -i i len=${#line}
  local -- ch
  for (( i=0; i<len; i++ )); do
    ch=${line:i:1}
    if (( escape )); then escape=0; continue; fi
    if (( in_squote )); then
      [[ $ch == "'" ]] && in_squote=0
      continue
    fi
    if (( in_dquote )); then
      [[ $ch == $'\\' ]] && { escape=1; continue; }
      [[ $ch == '"' ]] && in_dquote=0
      continue
    fi
    case $ch in
      "'") in_squote=1 ;;
      '"') in_dquote=1 ;;
      $'\\') escape=1 ;;
      '>'|'<'|'|'|';'|'&')
        _SB_SPLIT_CMD=${line:0:i}
        _SB_SPLIT_CMD=${_SB_SPLIT_CMD%"${_SB_SPLIT_CMD##*[![:space:]]}"}
        _SB_SPLIT_TAIL=${line:i}
        return 0 ;;
    esac
  done
  _SB_SPLIT_CMD=$line
  _SB_SPLIT_TAIL=''
}

# ---------------------------------------------------------------------------
# Interceptor - inspects READLINE_LINE BEFORE accept-line submits it.
# If first non-whitespace char is /, rewrites the line into a dispatch call
# so bash never tries to execve(/foo). Splits at the first unquoted shell
# metachar so redirection / pipe / sequencing syntax in the tail is parsed
# by bash, not swallowed by the @Q quote.
# ---------------------------------------------------------------------------

__sb_intercept() {
  local -- line=$READLINE_LINE

  # Pass through anything that does not start with a slash.
  [[ $line =~ ^[[:space:]]*/ ]] || return 0

  # Path carve-out: every registered slash-command key is a single
  # segment (/word with no internal slash) - see _SB_HANDLERS in
  # handlers.d/. If the first whitespace-separated token contains
  # another '/' after its leading one, it's an absolute path the user
  # wants bash to execve() directly (e.g. /usr/local/bin/foo), not a
  # slash command. Leave READLINE_LINE unmutated so bash's parser
  # dispatches normally.
  local -- _stripped=${line#"${line%%[![:space:]]*}"}
  local -- _first=${_stripped%%[[:space:]]*}
  [[ ${_first:1} == */* ]] && return 0

  _SB_LAST_ORIGINAL=$line
  # ${PS1@P} expands prompt escapes but preserves the \[ \] non-printing
  # markers as \001 \002. Readline consumes those internally; if we echo
  # them back via printf, terminals see literal SOH/STX. Strip both.
  _SB_LAST_PROMPT=${PS1@P}
  _SB_LAST_PROMPT=${_SB_LAST_PROMPT//$'\001'/}
  _SB_LAST_PROMPT=${_SB_LAST_PROMPT//$'\002'/}
  # Multi-line PS1: bind -x's redisplay only repainted the LAST row of the
  # prompt block (the row that carried the cursor). Rows above are still
  # on screen, untouched. Keep only the segment after the final newline so
  # the redraw replaces the rewrite row alone, not the whole prompt block.
  _SB_LAST_PROMPT=${_SB_LAST_PROMPT##*$'\n'}
  # Push the original to readline history so up-arrow recalls it as typed.
  history -s -- "$line"
  # Quote-aware split: keep redirection / pipe / sequence in the tail so
  # bash parses it natively; @Q-quote only the command portion.
  __sb_split_redirect "$line"
  if [[ -n $_SB_SPLIT_TAIL ]]; then
    READLINE_LINE="__sb_dispatch ${_SB_SPLIT_CMD@Q} ${_SB_SPLIT_TAIL}"
  else
    READLINE_LINE="__sb_dispatch ${line@Q}"
  fi
  READLINE_POINT=${#READLINE_LINE}
}

# ---------------------------------------------------------------------------
# preexec hook - log original slash invocations to a cache file.
# ---------------------------------------------------------------------------

# Idempotent ensure-dir helper. Called lazily so sourcing the library has
# no filesystem side effects. Dir is created 0700 and the history file is
# created 0600 so /ask prompt args (recorded only when SB_LOG_ARGS is set)
# are not world-readable on a multi-user box.
_sb_ensure_history_dir() {
  local -- d=${_SB_HISTORY_FILE%/*}
  if [[ ! -d $d ]]; then
    mkdir -p -- "$d" && chmod 0700 -- "$d"
  fi
  if [[ ! -e $_SB_HISTORY_FILE ]]; then
    : > "$_SB_HISTORY_FILE" && chmod 0600 -- "$_SB_HISTORY_FILE"
  fi
}

# Append one TSV record per slash-command dispatch to the history file.
# Default payload is the command verb only (e.g. '/ask', '/kb') - prevents
# API keys, passwords, or PII pasted into /ask prompts from landing on
# disk in plaintext. Set SB_LOG_ARGS=1 to record the full original line
# (the legacy behaviour); the file is still 0600-mode in either case.
_sb_log_dispatch() {
  # bash-preexec passes the command from `history 1`, not BASH_COMMAND -
  # and __sb_intercept pushes the original `/cmd' line via `history -s'
  # so up-arrow recalls as typed. So $1 is the user-facing slash line,
  # NOT the rewritten "__sb_dispatch '...'" form. Gate purely on
  # _SB_LAST_ORIGINAL being set: __sb_intercept sets it only for lines
  # matching ^[[:space:]]*/ and this function clears it, so non-empty
  # means "the most recent dispatch was ours and has not been logged yet".
  [[ -n $_SB_LAST_ORIGINAL ]] || return 0
  _sb_ensure_history_dir
  local -- payload
  if [[ -n ${SB_LOG_ARGS:-} ]]; then
    payload=$_SB_LAST_ORIGINAL
  else
    payload=${_SB_LAST_ORIGINAL%% *}
  fi
  printf '%s\t%s\n' "$(_sb_iso_now)" "$payload" \
    >> "$_SB_HISTORY_FILE"
  _SB_LAST_ORIGINAL=''
  _SB_LAST_PROMPT=''
}

# Hide the dispatcher rewrite from the terminal. After accept-line submits
# the rewritten "__sb_dispatch '<original>'" form, the cursor is on the
# row below; move up, clear, and reprint the captured prompt + original
# /cmd so the user sees what they typed, not the chord-rewrite. Gated on
# DEBUG (same convention as the HISTIGNORE patch) so setting DEBUG=1
# keeps both the readline-history rewrite and the visible rewrite intact
# for debugging the chord trick.
_sb_redraw_original() {
  # See _sb_log_dispatch for why we gate on _SB_LAST_ORIGINAL rather than
  # matching $1 against "__sb_dispatch*": bash-preexec passes the history
  # form (the user's original "/cmd" line), never the rewritten dispatch.
  [[ -n $_SB_LAST_ORIGINAL ]] || return 0
  [[ -z ${DEBUG:-} ]] || return 0
  # \033[1A cursor up 1; \r column 0; \033[K erase to EOL. Write to
  # /dev/tty rather than stdout so a redirected dispatch like
  # "/help > file" still gets its prompt line restored - bash applies
  # the dispatch's redirection to the simple command, and at preexec
  # time fd 1 may already be the redirect target rather than the
  # terminal. The 2>/dev/null swallows the no-tty edge (interactive
  # guard at top of file makes this practically unreachable).
  printf '\033[1A\r\033[K%s%s\n' "$_SB_LAST_PROMPT" "$_SB_LAST_ORIGINAL" \
    > /dev/tty 2>/dev/null
}
# Order matters: redraw reads _SB_LAST_ORIGINAL, log clears it.
preexec_functions+=(_sb_redraw_original _sb_log_dispatch)

# ---------------------------------------------------------------------------
# Per-command handler files. Each handlers.d/*.bash file defines its
# _sb_cmd_<name> handler (and any colocated _sb_complete_<name>) and
# registers itself by appending to _SB_HANDLERS / _SB_HELP / _SB_COMPLETE.
# Convention is to prefix with `_` to keep handler files visually distinct
# from any future README/sidecar files.
# Glob is alphabetic - this is the implicit ordering contract for
# inter-handler dependencies (e.g. _systemprompt.bash reuses
# _sb_complete_agent from _agent.bash, and _agent.bash < _systemprompt.bash
# lexically). nullglob makes the loop a no-op when handlers.d/ is absent
# or empty - in that case _SB_HANDLERS stays empty, the validation pass
# below has nothing to iterate, and every /cmd dispatch reports
# "unknown slash command" until the directory is restored.
# ---------------------------------------------------------------------------

# TEST_SHIM_HANDLERS_BEGIN
# (The bats `source_slash_bash' shim strips this region: BASH_SOURCE[0]
# under process substitution resolves to /dev/fd/N rather than the real
# library path, so the glob below cannot find handlers.d/. The harness
# pre-sources handlers.d/_*.bash explicitly via $PROJECT_DIR, then runs
# the equivalent of the validation+derive blocks itself.)
declare -- _sb_handler_file
declare -i _sb_was_nullglob=0
shopt -q nullglob && _sb_was_nullglob=1
shopt -s nullglob
for _sb_handler_file in "${BASH_SOURCE[0]%/*}"/handlers.d/*.bash; do
  # shellcheck source=/dev/null
  source -- "$_sb_handler_file"
done
((_sb_was_nullglob)) || shopt -u nullglob
unset -v _sb_handler_file _sb_was_nullglob

# Validate the registry: every /cmd in _SB_HANDLERS must resolve to a
# defined function. Catches typos and missing-handler regressions at
# library-load time rather than at first /cmd dispatch.
declare -- _sb_cmd _sb_fn
for _sb_cmd in "${!_SB_HANDLERS[@]}"; do
  _sb_fn=${_SB_HANDLERS[$_sb_cmd]}
  declare -F -- "$_sb_fn" >/dev/null 2>&1 \
    || _warn "internal: ${_sb_cmd} -> ${_sb_fn@Q} not defined"
done
unset -v _sb_cmd _sb_fn

# Derive _SB_SLASH_CMDS from registered handlers (sorted, all aliases).
# This overwrites any prior value; site hooks that want completion-only
# entries should append to the array AFTER source completes (the site
# hook block at the end of this file runs after derive).
readarray -t _SB_SLASH_CMDS < <(printf '%s\n' "${!_SB_HANDLERS[@]}" | sort)
# TEST_SHIM_HANDLERS_END

# ---------------------------------------------------------------------------
# Key bindings - the chord trick.
#
#   \C-xs                 -> __sb_intercept (bind -x runs in live shell)
#   \C-m   (Enter)        -> macro "\C-xs\C-j"
#   \C-j                  -> default accept-line (untouched, so the macro
#                            does not recurse)
#
# Net effect: pressing Enter runs the interceptor, then accept-line submits
# whatever READLINE_LINE now contains.
# ---------------------------------------------------------------------------

bind -m emacs     -x '"\C-xs": __sb_intercept'
bind -m vi-insert -x '"\C-xs": __sb_intercept'
bind -m emacs        '"\C-m": "\C-xs\C-j"'
bind -m vi-insert    '"\C-m": "\C-xs\C-j"'

# ---------------------------------------------------------------------------
# Completion registration. `complete -I` (bash 5.0+) registers an "initial
# word" compspec that fires for the command-name position; this is the
# only way to override bash's built-in pathname completion for /-prefixed
# words. Per-command `complete -F` registrations are driven by
# _SB_COMPLETE (populated by handlers.d/_*.bash) so a new handler file
# wires up arg completion without touching this block.
# ---------------------------------------------------------------------------

complete -I -F _sb_complete_first
declare -- _sb_compspec_cmd
for _sb_compspec_cmd in "${!_SB_COMPLETE[@]}"; do
  complete -F "${_SB_COMPLETE[$_sb_compspec_cmd]}" -- "$_sb_compspec_cmd"
done
unset -v _sb_compspec_cmd

# Lazy bash_completion loader. The eager load is suppressed in
# .slash-bash-init via BASH_COMPLETION_VERSINFO=1 (saves ~586 ms at startup).
# This default compspec fires on the first TAB for any command without an
# explicit compspec; it sources bash_completion, removes itself, then
# returns 124 to tell readline "compspec changed, retry the completion" -
# the same dynamic-loader pattern bash_completion uses internally.
__sb_lazy_complete() {
  unset -v BASH_COMPLETION_VERSINFO
  if [[ -r /usr/share/bash-completion/bash_completion ]]; then
    # shellcheck source=/dev/null
    if source /usr/share/bash-completion/bash_completion; then
      # Source succeeded. bash_completion's own 'complete -D -F
      # _completion_loader' has already overwritten our stub in the
      # single -D slot. Do NOT issue 'complete -r -D' here - that
      # would strip the loader bash_completion just installed and
      # orphan ~1,029 per-command completions. Just drop our function
      # body and tell readline to retry; the retry finds the fresh
      # default compspec (_completion_loader) and dispatches.
      unset -f __sb_lazy_complete
      return 124
    fi
    _warn 'bash-completion source failed; default completion disabled'
  fi
  # Source unavailable or failed. Unregister stub so non-/-prefix TAB
  # falls through to bash's built-in pathname completion rather than
  # looping with no compspec installed (the original return-124-on-
  # failure bug). Slash-cmd's own /cmd compspecs are unaffected.
  complete -r -D 2>/dev/null
  unset -f __sb_lazy_complete
  return 0
}
complete -D -F __sb_lazy_complete

# Hide the rewritten dispatcher form from readline history; the original
# /command is still preserved by `history -s` inside __sb_intercept.
# Set DEBUG to any non-empty value to keep both forms visible (useful when
# debugging the intercept/accept-line chord).
if [[ -z ${DEBUG:-} ]]; then
  case ":${HISTIGNORE:-}:" in
    *":__sb_dispatch *:"*) ;;
    *) HISTIGNORE="${HISTIGNORE:+$HISTIGNORE:}__sb_dispatch *" ;;
  esac
fi

# ---------------------------------------------------------------------------
# Site-specific extension hook. Sourced after all built-in handlers, key
# bindings, and compspecs are in place, so it can:
#   - define new _sb_cmd_<name> handlers
#   - append to _SB_SLASH_CMDS for tab completion
#   - register `complete -F` compspecs
#   - override _SB_AGENT / _SB_MODEL / etc.
# Override location with SB_SITE_BASH=path. Default lives under
# $XDG_CONFIG_HOME (or ~/.config) so it round-trips with XDG-compliant
# dotfile managers.
# ---------------------------------------------------------------------------

declare -g -- _SB_SITE_BASH="${SB_SITE_BASH:-${XDG_CONFIG_HOME:-$HOME/.config}/slash-bash/site.bash}"
# ssh-style ownership/permissions guard. Refuse to source if not owned by
# $USER or if the file has group/other write bits - this prevents the
# standard bash dotfile confused-deputy trap on shared boxes (a careless
# `chmod -R g+w ~` would otherwise let any group member inject code into
# every slash-bash session).
if [[ -r $_SB_SITE_BASH ]]; then
  declare -- _sb_site_meta='' _sb_site_owner='' _sb_site_mode=''
  if _sb_site_meta=$(stat -c '%U %a' -- "$_SB_SITE_BASH" 2>/dev/null); then
    _sb_site_owner=${_sb_site_meta% *}
    _sb_site_mode=${_sb_site_meta##* }
    if [[ $_sb_site_owner != "$USER" ]]; then
      _warn "skipping ${_SB_SITE_BASH@Q}: owned by ${_sb_site_owner}, not ${USER}"
    elif (( 8#$_sb_site_mode & 8#022 )); then
      _warn "skipping ${_SB_SITE_BASH@Q}: group/other-writable (mode ${_sb_site_mode})"
    else
      # shellcheck source=/dev/null
      source -- "$_SB_SITE_BASH"
    fi
  else
    _warn "skipping ${_SB_SITE_BASH@Q}: stat failed"
  fi
  unset -v _sb_site_meta _sb_site_owner _sb_site_mode
fi

#fin
