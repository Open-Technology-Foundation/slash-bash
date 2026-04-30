#!/usr/bin/bash
#shellcheck shell=bash disable=SC2034
# test_helper.bash - shared utilities for the slash-bash bats suite.
#
# Provides:
#   - Isolated test env (mktemp HOME, scrubbed XDG, scrubbed SB_* env)
#   - source_slash_bash helper that bypasses the interactive guard so the
#     library loads in non-interactive bats subshells (see WHY below)
#   - Mock-injection helpers for claude.agent, jq, etc.
#   - Fixture builders (fake KBs, fake session JSONLs)
#
# WHY the guard-stripping shim:
#   slash-bash.bash:23 is `[[ $- == *i* ]] || return 0` - the library is a
#   no-op in non-interactive shells. bats spawns each test in a non-interactive
#   subshell even when bats itself is launched via `bash -i -c 'bats ...'`.
#   The shim strips that single line plus the BASH_SOURCE-relative
#   bash-preexec.sh source-block (lines 30-40), then pre-sources bash-preexec
#   manually so preexec_functions resolves correctly. Bind warnings on stderr
#   are tolerated (no TTY).

PROJECT_DIR="${BATS_TEST_DIRNAME}/.."
MOCK_DIR="${BATS_TEST_DIRNAME}/mocks"
FIXTURE_DIR="${BATS_TEST_DIRNAME}/fixtures"

# Load bats-support / bats-assert so individual .bats files don't have to.
load '/usr/local/lib/bats-support/load'
load '/usr/local/lib/bats-assert/load'

setup_test_env() {
  TEST_HOME=$(mktemp -d)
  export HOME="$TEST_HOME"
  export XDG_CACHE_HOME="$TEST_HOME/.cache"
  export XDG_CONFIG_HOME="$TEST_HOME/.config"
  # Library defaults are evaluated at source-time; HOME/XDG must be set first.
  export SB_HISTORY_FILE="$TEST_HOME/.cache/slash-bash/history"
  export SB_CLAUDE_PROJECTS_DIR="$TEST_HOME/projects"
  export VECTORDBS="$TEST_HOME/kbroot"
  export AGENTS_JSON="${FIXTURE_DIR}/Agents.json"
  export NO_COLOR=1
  # Unset all SB_* env vars - tests that want defaults must inherit them
  # from the library, not from the harness's outer shell.
  unset SB_AGENT SB_MODEL SB_MODEL_LIST SB_MAX_TOKENS SB_OLLAMA \
        SB_KB_LIST SB_SITE_BASH SB_DIRTY_WINDOW \
        SB_SESSION_CWD SB_SESSION_UUID SB_SESSION_LAST_ASK \
        OLLAMA_MODEL OLLAMA_HOST DEBUG
}

teardown_test_env() {
  if [[ -d ${TEST_HOME:-} ]]; then
    rm -rf "$TEST_HOME"
  fi
  if [[ -n ${_ORIG_PATH:-} ]]; then
    export PATH="$_ORIG_PATH"
    unset _ORIG_PATH
  fi
}

# Source slash-bash.bash into the current bats subshell. Strips the
# interactive guard and the bash-preexec source-block; pre-sources
# bash-preexec.sh manually. See WHY at top of file.
#
# CRITICAL: bats relies on `set -e` to detect test-command failures. We must
# disable it temporarily for the source (the lib's tail-end `bind` calls fail
# in non-TTY) and restore the caller's state before returning. Without this,
# `set +e` leaks into the test body and silently masks failures.
source_slash_bash() {
  # Capture caller's shell-options state (BCS-style flag tracking).
  # $-/$BASHOPTS would also work; using local flag vars keeps it explicit.
  # Note: avoid $() command substitution here - bats may have set
  # inherit_errexit, in which case `shopt -po errexit` exit-1-when-off
  # propagates through $() and trips set -e in the caller.
  local -i _was_e=0 _was_u=0 _was_p=0
  [[ $- == *e* ]] && _was_e=1
  [[ $- == *u* ]] && _was_u=1
  [[ -o pipefail ]] && _was_p=1
  set +euo pipefail
  shopt -u inherit_errexit 2>/dev/null || true
  # shellcheck source=/dev/null
  source "$PROJECT_DIR/bash-preexec.sh" 2>/dev/null
  # awk strips three regions delimited by sentinel comments in the
  # library:
  #   1. TEST_SHIM_GUARD_*    - interactive guard (no-op in non-TTY bats)
  #   2. TEST_SHIM_PREEXEC_*  - BASH_SOURCE-relative bash-preexec source
  #                              (would resolve to /dev/fd/bash-preexec.sh
  #                              under process substitution)
  #   3. TEST_SHIM_HANDLERS_* - source-glob loop + validation + derive.
  #                              Same /dev/fd issue as preexec; we
  #                              re-implement the equivalent below using
  #                              $PROJECT_DIR.
  # The markers are the explicit contract; the library can reword
  # anything inside them without breaking the harness.
  # shellcheck source=/dev/null
  source <(awk '
    /^# TEST_SHIM_GUARD_BEGIN/, /^# TEST_SHIM_GUARD_END/ { next }
    /^# TEST_SHIM_PREEXEC_BEGIN/, /^# TEST_SHIM_PREEXEC_END/ { next }
    /^# TEST_SHIM_HANDLERS_BEGIN/, /^# TEST_SHIM_HANDLERS_END/ { next }
    { print }
  ' "$PROJECT_DIR/slash-bash.bash") 2>/dev/null
  # Source handlers.d/_*.bash explicitly with the real project path. In
  # the live library this loop runs from inside the (sentinel-stripped)
  # block above; here we drive it from the harness so $PROJECT_DIR is
  # the real on-disk directory rather than /dev/fd. Sorted glob matches
  # the alphabetic-source contract documented in the library.
  local -- _sb_handler_file
  for _sb_handler_file in "$PROJECT_DIR"/handlers.d/_*.bash; do
    [[ -r $_sb_handler_file ]] || continue
    # shellcheck source=/dev/null
    source -- "$_sb_handler_file" 2>/dev/null
  done
  # Derive _SB_SLASH_CMDS the same way the library would (skip the
  # warn-on-undefined validation - in tests, missing handlers are
  # caught by individual @test cases).
  if (( ${#_SB_HANDLERS[@]} )); then
    readarray -t _SB_SLASH_CMDS < <(printf '%s\n' "${!_SB_HANDLERS[@]}" | sort)
    # Re-register per-cmd compspecs (the library's compspec-loop block
    # ran before _SB_COMPLETE was populated, since we sourced handlers
    # AFTER source_slash_bash's awk-stripped main body).
    local -- _sb_cmpcmd
    for _sb_cmpcmd in "${!_SB_COMPLETE[@]}"; do
      complete -F "${_SB_COMPLETE[$_sb_cmpcmd]}" -- "$_sb_cmpcmd" 2>/dev/null
    done
  fi
  # bash-preexec installs DEBUG trap + PROMPT_COMMAND that interfere with
  # bats `run`; clear them.
  trap - DEBUG 2>/dev/null
  PROMPT_COMMAND=
  # Restore caller's errexit / nounset / pipefail state. Order: restore
  # errexit LAST so the test body sees -e even if intermediate restore
  # commands fail. Explicit `return 0` so the lib's tail-end exit status
  # (e.g. `[[ -r $_SB_SITE_BASH ]]` failing when site.bash is absent)
  # doesn't leak through.
  ((_was_p)) && set -o pipefail
  ((_was_u)) && set -u
  ((_was_e)) && set -e
  return 0
}

enable_mocks() {
  _ORIG_PATH=$PATH
  export PATH="$MOCK_DIR:$TEST_HOME/bin:$PATH"
}

disable_mocks() {
  if [[ -n ${_ORIG_PATH:-} ]]; then
    export PATH="$_ORIG_PATH"
    unset _ORIG_PATH
  fi
}

# Configure the claude.agent mock. Accepts:
#   list-good     normal --list output (3 agents)
#   list-empty    --list returns no agents
#   list-noisy    ANSI-coloured + duplicate output (tests sed/sort -u)
#   fail          claude.agent itself returns 1 unconditionally
#   passthrough   echoes its args (used by /ask invocation tests)
mock_claude_agent() {
  export MOCK_CLAUDE_AGENT_KIND="${1:-list-good}"
  export MOCK_CLAUDE_AGENT_LOG="$TEST_HOME/agent.log"
  : > "$MOCK_CLAUDE_AGENT_LOG"
}

# Hide jq from PATH so `command -v jq` returns non-zero. We build a sanitised
# PATH by symlinking essential coreutils into a temp dir but deliberately
# omitting jq. Used by /systemprompt and claude-sessions jq-missing tests.
hide_jq() {
  _ORIG_PATH=${_ORIG_PATH:-$PATH}
  local -- d=$TEST_HOME/no_jq_bin
  mkdir -p "$d"
  local -- cmd src
  for cmd in mkdir rm ls cat cp mv tail head sort awk sed cut date \
             find grep printf chmod touch tr basename dirname stat \
             realpath uname env; do
    src=$(command -v "$cmd" 2>/dev/null) || continue
    ln -sf "$src" "$d/$cmd"
  done
  export PATH="$d"
}

# Create an empty KB cfg so /kb <name> succeeds.
make_fake_kb() {
  local -- name=$1
  mkdir -p "$VECTORDBS/$name"
  printf 'desc=%s\n' "$name" > "$VECTORDBS/$name/$name.cfg"
}

# Append a JSONL record to the encoded-cwd session dir for claude-sessions.
make_fake_session_jsonl() {
  local -- uuid=$1
  local -- record=$2
  local -- enc_dir=$SB_CLAUDE_PROJECTS_DIR/${PWD//\//-}
  mkdir -p "$enc_dir"
  printf '%s\n' "$record" >> "$enc_dir/$uuid.jsonl"
}

#fin
