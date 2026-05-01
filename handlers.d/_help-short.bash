#!/usr/bin/bash
#shellcheck shell=bash disable=SC2034
# handlers.d/_help-short.bash - the /? handler. Single hand-coded
# heredoc with one line per command (no descriptions); the verbose
# /help form lives in _help.bash.

_sb_cmd_help_short() {
  cat <<SLASH_CMD_HELP
Available slash commands:
  $_BOLD/?$_NC
  $_BOLD/help$_NC

  $_BOLD/ $_NC || $_BOLD/ask$_NC <text>

  $_BOLD/agents$_NC [--select|--list]
  $_BOLD/agent$_NC [<agent>]
  $_BOLD/models$_NC [--select|--list]
  $_BOLD/model$_NC [<name>]
  $_BOLD/kbs$_NC || $_BOLD/knowledgebases$_NC [--select|--list]
  $_BOLD/kb$_NC || $_BOLD/knowledgebase$_NC [<kbname>]

  $_BOLD/filemanager$_NC || $_BOLD/fm$_NC [<dirpath>]
  $_BOLD/history$_NC [<n>]
  $_BOLD/maxtokens$_NC [<n>]
  $_BOLD/ollama$_NC [model|off]
  $_BOLD/rebase$_NC [--force]
  $_BOLD/status$_NC
  $_BOLD/version$_NC
  $_BOLD/sessions$_NC
  $_BOLD/systemprompt$_NC [<agent>]

  $_BOLD/q$_NC || $_BOLD/exit$_NC
SLASH_CMD_HELP
}

_SB_HANDLERS['/?']=_sb_cmd_help_short
_SB_HELP['/?']='show short help (one line per command)'

#fin
