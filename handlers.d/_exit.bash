#!/usr/bin/bash
#shellcheck shell=bash disable=SC2034
# handlers.d/_exit.bash - /bye /quit /q /exit
# `exit` (not `return`) is intentional - terminates the slash-bash
# session.

_sb_cmd_exit() {
  exit 0
}

_SB_HANDLERS[/bye]=_sb_cmd_exit
_SB_HANDLERS[/quit]=_sb_cmd_exit
_SB_HANDLERS[/q]=_sb_cmd_exit
_SB_HANDLERS[/exit]=_sb_cmd_exit
_SB_HELP[/exit]='exit the slash-bash session'

#fin
