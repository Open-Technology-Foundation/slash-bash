#!/usr/bin/bash
#shellcheck shell=bash disable=SC2034
# handlers.d/_kb.bash - /kb and /knowledgebase [<name>|off|none|clear]
# + colocated _sb_complete_kb. Validates name shape ([A-Za-z0-9_-]+) and
# requires <name>/<name>.cfg under $_SB_KB_ROOT.

_sb_cmd_kb() {
  local -- name=$*
  if [[ -z $name ]]; then
    printf 'current kb: %s\n' "${_SB_KB:-<none>}"
    return 0
  fi
  case ${name,,} in
    off|none|clear)
      _SB_KB=''
      printf 'kb cleared\n'
      return 0
      ;;
  esac
  if [[ ! $name =~ ^[A-Za-z0-9_-]+$ ]]; then
    _error "invalid kb name: ${name@Q}"
    return 1
  fi
  local -- kb_cfg=$_SB_KB_ROOT/$name/$name.cfg
  if [[ ! -f $kb_cfg ]]; then
    _error "unknown kb: ${name@Q} (no cfg at $kb_cfg)"
    return 1
  fi
  _SB_KB=$name
  printf 'kb switched to: %s\n' "$_SB_KB"
}

_sb_complete_kb() {
  local -- cur=${COMP_WORDS[COMP_CWORD]}
  COMPREPLY=()
  _sb_load_kb_list 2>/dev/null
  readarray -t COMPREPLY < <(compgen -W "${_SB_KB_LIST[*]} off none clear" -- "$cur")
}

_SB_HANDLERS[/kb]=_sb_cmd_kb
_SB_HANDLERS[/knowledgebase]=_sb_cmd_kb
_SB_HELP[/kb]='switch active knowledgebase (or off/none/clear to disable)'
_SB_COMPLETE[/kb]=_sb_complete_kb
_SB_COMPLETE[/knowledgebase]=_sb_complete_kb

#fin
