#!/usr/bin/bash
#shellcheck shell=bash disable=SC2034
# handlers.d/_version.bash - the /version handler.

_sb_cmd_version() {
  [[ -n $* ]] && { _error "/version takes no arguments"; return 2; }
  printf 'slash-bash %s\n' "${_SB_VERSION:-unknown}"
}

_SB_HANDLERS[/version]=_sb_cmd_version
_SB_HELP[/version]='print slash-bash version'

#fin
