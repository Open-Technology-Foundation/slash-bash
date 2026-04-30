#!/usr/bin/bash
#shellcheck shell=bash disable=SC2034
# handlers.d/_agent.bash - /agent [<name>] + colocated _sb_complete_agent.
# Empty arg prints current; non-empty resolves via case-insensitive
# exact-then-prefix match against _SB_AGENT_LIST (see
# _sb_resolve_agent_name in slash-bash.bash).
#
# IMPORTANT: defines _sb_complete_agent which is reused by
# _systemprompt.bash. Alphabetic glob ordering ensures _agent.bash sources
# before _systemprompt.bash; do not rename either file in a way that
# breaks the lex order without also moving the completion fn.

_sb_cmd_agent() {
  local -- name=$*
  if [[ -z $name ]]; then
    printf 'current agent: %s\n' "$_SB_AGENT"
    return 0
  fi
  if ! _sb_load_agent_list; then
    _error 'claude.agent not in PATH'
    return 1
  fi
  local -- match=''
  if ! match=$(_sb_resolve_agent_name "$name"); then
    _error "unknown agent: ${name@Q}"
    return 1
  fi
  _SB_AGENT=$match
  printf 'agent set to: %s\n' "$_SB_AGENT"
}

# Arg completion for /agent and /systemprompt. Lazy-loads _SB_AGENT_LIST
# on first invocation; silently returns empty COMPREPLY if claude.agent
# is not in PATH.
_sb_complete_agent() {
  local -- cur=${COMP_WORDS[COMP_CWORD]}
  COMPREPLY=()
  _sb_load_agent_list 2>/dev/null || return 0
  readarray -t COMPREPLY < <(compgen -W "${_SB_AGENT_LIST[*]}" -- "$cur")
}

_SB_HANDLERS[/agent]=_sb_cmd_agent
_SB_HELP[/agent]='set the active agent (case-insensitive prefix match)'
_SB_COMPLETE[/agent]=_sb_complete_agent

#fin
