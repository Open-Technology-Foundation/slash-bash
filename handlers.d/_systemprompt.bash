#!/usr/bin/bash
#shellcheck shell=bash disable=SC2034
# handlers.d/_systemprompt.bash - /systemprompt [<agent>]
# Reuses _sb_complete_agent from _agent.bash for arg completion. The
# alphabetic glob in slash-bash.bash sources _agent.bash before this file
# (lexically _agent < _systemprompt), so the completion fn is defined
# by the time _SB_COMPLETE[/systemprompt] is set below.

_sb_cmd_systemprompt() {
  local -- name=$*
  [[ -z $name ]] && name=$_SB_AGENT
  if ! command -v jq >/dev/null; then
    _error 'jq not in PATH'
    return 1
  fi
  if ! _sb_load_agent_list; then
    _error 'claude.agent not in PATH'
    return 1
  fi
  local -- short=''
  if ! short=$(_sb_resolve_agent_name "$name"); then
    _error "unknown agent: ${name@Q}"
    return 1
  fi
  local -- key=''
  key=$(_sb_agent_key "$short") ||:
  if [[ -z $key ]]; then
    _error "agent not found in Agents.json: ${short@Q}"
    return 1
  fi
  local -r agents_json=${AGENTS_JSON:-$(_sb_default_agents_json)}
  local -- prompt=''
  prompt=$(jq -r --arg k "$key" '.[$k].systemprompt // empty' "$agents_json")
  if [[ -z $prompt ]]; then
    _error "agent has no systemprompt: ${key@Q}"
    return 1
  fi
  local -- spacetime=''
  spacetime=$(_sb_spacetime)
  prompt=${prompt//\{\{spacetime\}\}/$spacetime}
  printf '# agent: %s\n' "$key"
  printf '# spacetime: %s\n' "$spacetime"
  printf '%s\n' "$prompt"
}

_SB_HANDLERS[/systemprompt]=_sb_cmd_systemprompt
_SB_HELP[/systemprompt]='show system prompt for the active or named agent'
# _sb_complete_agent comes from _agent.bash (sourced earlier in the
# alphabetic glob). Cross-file dependency documented at top of file.
_SB_COMPLETE[/systemprompt]=_sb_complete_agent

#fin
