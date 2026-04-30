#!/usr/bin/bash
#shellcheck shell=bash disable=SC2034
# handlers.d/_sessions.bash - /sessions
# Thin wrapper around the standalone `claude-sessions` script. Logic
# lives there so the same listing is available as a top-level command
# in any shell. Resolves via the library's own dir so dev works
# pre-`symlink -S`.

_sb_cmd_sessions() {
  # SB_CLAUDE_SESSIONS_BIN overrides the resolved path; the default
  # walks one level up from this file's directory (handlers.d/) to find
  # the sibling claude-sessions script. The override exists primarily
  # for tests that need to drive the missing-script error path
  # deterministically.
  local -- script=${SB_CLAUDE_SESSIONS_BIN:-${BASH_SOURCE[0]%/*}/../claude-sessions}
  if [[ ! -x $script ]]; then
    _error "claude-sessions not found or not executable: $script"
    return 18
  fi
  "$script" "$@"
}

_SB_HANDLERS[/sessions]=_sb_cmd_sessions
_SB_HELP[/sessions]='list Claude Code sessions for the current cwd (TSV)'

#fin
