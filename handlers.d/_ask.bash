#!/usr/bin/bash
#shellcheck shell=bash disable=SC2034
# handlers.d/_ask.bash - /ask <text>
# Assembles claude.agent argv from _SB_AGENT / _SB_MODEL / _SB_OLLAMA /
# _SB_SESSION_UUID / _SB_KB and runs it inside _SB_SESSION_CWD so
# claude.x writes the JSONL to the right ~/.claude/projects/<encoded>/
# regardless of the user's $PWD. Adopts the freshly-minted JSONL UUID
# on rc==0; gates on rc==0 to avoid hijacking a sibling shell's JSONL
# when an upstream shlock contention causes claude.agent to fail.

_sb_cmd_ask() {
  local -- prompt=$*
  if [[ -z $prompt ]]; then
    _error 'usage: /ask <text>'
    return 1
  fi
  if ! command -v claude.agent >/dev/null; then
    _error 'claude.agent not in PATH'
    return 1
  fi
  local -a cmd=(claude.agent -T "$_SB_AGENT")
  [[ -n $_SB_MODEL ]] && cmd+=(--model "$_SB_MODEL")
  ((_SB_OLLAMA))      && cmd+=(-O) ||:
  [[ -n $_SB_SESSION_UUID ]] && cmd+=(--resume "$_SB_SESSION_UUID")
  if [[ -n $_SB_KB ]]; then
    local -- kb_cfg=$_SB_KB_ROOT/$_SB_KB/$_SB_KB.cfg
    if [[ -f $kb_cfg ]]; then
      cmd+=(--append-system-prompt-file "$kb_cfg")
    else
      _warn "kb cfg missing, skipping ${kb_cfg@Q}"
    fi
  fi
  local -i rc=0
  # Record a pre-call high-resolution timestamp in the same format that
  # find's `%T@` emits (epoch.nanosec). _sb_pick_newest_uuid filters
  # JSONLs against this cutoff so a sibling shell's same-second write
  # cannot win the tiebreaker against our own. `date +%s.%N` is GNU-
  # date specific; the integer EPOCHSECONDS fallback degrades to
  # 1-second resolution but stays correctness-safe (only files strictly
  # newer than `before_ask` are considered, so a sibling's write at
  # second T is filtered when before_ask=T).
  local -- before_ask
  before_ask=$(date +%s.%N 2>/dev/null) || before_ask=${EPOCHSECONDS:-$(date +%s)}
  if [[ -d $_SB_SESSION_CWD ]]; then
    ( cd -- "$_SB_SESSION_CWD" \
      && VERBOSE=0 CLAUDE_CODE_MAX_OUTPUT_TOKENS=$_SB_MAX_TOKENS "${cmd[@]}" "$prompt" )
    rc=$?
  else
    _warn "session cwd vanished: ${_SB_SESSION_CWD@Q} - using \$PWD"
    VERBOSE=0 CLAUDE_CODE_MAX_OUTPUT_TOKENS=$_SB_MAX_TOKENS "${cmd[@]}" "$prompt"
    rc=$?
  fi
  _SB_SESSION_LAST_ASK=${EPOCHSECONDS:-$(date +%s)}
  # First /ask after rebase to a fresh cwd: claude.x just minted a JSONL
  # - adopt it so subsequent /ask calls resume it. Gate on rc==0: if the
  # claude.agent run failed (most commonly because a sibling slash-bash
  # in the same cwd holds the upstream shlock - see
  # claude.agent:354-375), the newest JSONL belongs to the OTHER shell.
  # Adopting it would silently rebind this conversation to the
  # sibling's session.
  if (( rc == 0 )) && [[ -z $_SB_SESSION_UUID ]]; then
    _sb_pick_newest_uuid _SB_SESSION_UUID "$_SB_SESSION_CWD" "$before_ask"
  fi
  if (( rc == 1 )); then
    _warn "claude.agent exited 1; if a sibling slash-bash is active in"
    _warn "  ${_SB_SESSION_CWD@Q}, wait for it to finish and retry"
  fi
  return $rc
}

_SB_HANDLERS[/ask]=_sb_cmd_ask
_SB_HELP[/ask]='send a query to the active claude.agent (resumes session UUID if set)'

#fin
