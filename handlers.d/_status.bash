#!/usr/bin/bash
#shellcheck shell=bash disable=SC2034
# handlers.d/_status.bash - /status
# Bash-reusable env dump. Output `source`s into a fresh slash-bash
# session to round-trip current state. Each line is `export
# SB_NAME=<@Q-quoted>` so the next interactive shell's library sees the
# same SB_* env vars that initialise the corresponding `_SB_*` internal
# globals.

_sb_cmd_status() {
  # AGENTS_JSON is intentionally NOT seeded here: the library and handlers
  # auto-derive the path from claude.agent in PATH (see
  # _sb_default_agents_json). If the user explicitly set AGENTS_JSON in
  # their env, the always-emitted loop below picks it up via [[ -v ]];
  # otherwise we let the next session re-run discovery.
  : "${SB_CLAUDE_PROJECTS_DIR:=$HOME/.claude/projects}"
  # Map: internal-var -> exported-env-var. Always-emitted vars first;
  # the tail (SB_KB_LIST, OLLAMA_MODEL) emit only when set.
  local -a always=(
    _SB_AGENT:SB_AGENT
    _SB_MODEL:SB_MODEL
    _SB_MAX_TOKENS:SB_MAX_TOKENS
    _SB_OLLAMA:SB_OLLAMA
    _SB_HISTORY_FILE:SB_HISTORY_FILE
    _SB_SITE_BASH:SB_SITE_BASH
    _SB_SESSION_CWD:SB_SESSION_CWD
    _SB_SESSION_UUID:SB_SESSION_UUID
    _SB_SESSION_LAST_ASK:SB_SESSION_LAST_ASK
    _SB_DIRTY_WINDOW:SB_DIRTY_WINDOW
    SB_CLAUDE_PROJECTS_DIR:SB_CLAUDE_PROJECTS_DIR
    VECTORDBS:VECTORDBS
    AGENTS_JSON:AGENTS_JSON
  )
  local -a optional=(SB_KB_LIST:SB_KB_LIST OLLAMA_MODEL:OLLAMA_MODEL)
  local -- pair src dst
  for pair in "${always[@]}"; do
    src=${pair%%:*}; dst=${pair#*:}
    [[ -v $src ]] || continue
    printf 'export %s=%s\n' "$dst" "${!src@Q}"
  done
  for pair in "${optional[@]}"; do
    src=${pair%%:*}; dst=${pair#*:}
    [[ -v $src && -n ${!src:-} ]] || continue
    printf 'export %s=%s\n' "$dst" "${!src@Q}"
  done
  return 0
}

_SB_HANDLERS[/status]=_sb_cmd_status
_SB_HELP[/status]='dump bash-reusable env (source the output to round-trip session state)'

#fin
