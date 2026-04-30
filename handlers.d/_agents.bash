#!/usr/bin/bash
#shellcheck shell=bash disable=SC2034
# handlers.d/_agents.bash - /agents [--select|--list]
# Lazy-loads _SB_AGENT_LIST from claude.agent --list. Selection mutates
# _SB_AGENT via _sb_select_from_list (nameref-bound).

_sb_cmd_agents() {
  local -- mode=${1:-}
  [[ $mode == *' '* ]] && { _error "unexpected arguments: ${mode#* }"; return 1; }
  if ! _sb_load_agent_list; then
    _error 'claude.agent not in PATH'
    return 1
  fi
  ((${#_SB_AGENT_LIST[@]})) || { _error 'no agents found'; return 1; }
  case $mode in
    ''|--select) _sb_select_from_list agent _SB_AGENT "${_SB_AGENT_LIST[@]}" ;;
    --list)      _sb_print_list       agent _SB_AGENT "${_SB_AGENT_LIST[@]}" ;;
    *)           _error "unknown option: ${mode@Q} (expected --select or --list)"; return 1 ;;
  esac
}

_SB_HANDLERS[/agents]=_sb_cmd_agents
_SB_HELP[/agents]='list / select an agent (--select default, --list prints)'

#fin
