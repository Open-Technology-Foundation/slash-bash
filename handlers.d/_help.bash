#!/usr/bin/bash
#shellcheck shell=bash disable=SC2034
# handlers.d/_help.bash - the /help (and /?) handler. Hand-coded heredoc
# is intentional: auto-generation from _SB_HELP would alphabetise the
# output and lose the current grouping (settings -> ask -> introspection
# -> exit).

_sb_cmd_help() {
  cat <<SLASH_CMD_HELP
Available slash commands:
  $_BOLD/?$_NC     Short help
  $_BOLD/help$_NC  This help

  $_BOLD/ask$_NC <text>
                   Send a LLM query to claude code agent
  $_BOLD/$_NC <text>
                   Shorthand for /ask <text>

  $_BOLD/agents$_NC [--select|--list]
                   --select (default) picks via numbered menu; --list prints.
  $_BOLD/agent$_NC [<agent>]
                   Set an agent (case-insensitive prefix match)

  $_BOLD/models$_NC [--select|--list]
                   --select (default) picks via numbered menu; --list prints.
  $_BOLD/model$_NC [<name>]
                   Show or set the current model

  $_BOLD/kbs$_NC || $_BOLD/knowledgebases$_NC [--select|--list]
                   --select (default) picks via numbered menu; --list prints.
  $_BOLD/kb$_NC || $_BOLD/knowledgebase$_NC [<kbname>]
                   Switch the active default knowledge base

  $_BOLD/maxtokens$_NC [<n>]
                   Set max output tokens (positive integer)

  $_BOLD/ollama$_NC [model|off]
                   Toggle ollama backend; <model> exports OLLAMA_MODEL,
                   off disables, no arg enables with the default model.

  $_BOLD/history$_NC [<n>]
                   Show the last n slash invocations; default 20
  $_BOLD/status$_NC
                   Print bash-reusable env dump of current session state
                   (\`source\` the output to round-trip into a fresh session)
  $_BOLD/sessions$_NC
                   List Claude Code sessions for the current cwd
                   (TSV: mtime, uuid, title). UUID is \`claude --resume\`-able.
  $_BOLD/filemanager$_NC || $_BOLD/fm$_NC [<dirpath>]
                   Launch file manager on dirpath or \$PWD. Auto-detect:
                   GUI (xdg-open, detached) when \$DISPLAY/\$WAYLAND_DISPLAY
                   set, else TUI (\$SB_FILEMANAGER, mc, ranger, nnn, lf, vifm).
                   -g/--gui / -t/--tui force the mode; -n/--dry-run prints
                   what would launch.
  $_BOLD/rebase$_NC [--force]
                   Bind active conversation to \$PWD's most-recent JSONL
                   (auto-pick). Prompts if current binding has recent /ask
                   activity; --force or non-TTY skips the prompt.

  $_BOLD/systemprompt$_NC [<agent>]
                   Show system prompt for the active or named agent
  $_BOLD/q$_NC || $_BOLD/exit$_NC
                   Exit the slash-bash
SLASH_CMD_HELP
}

_SB_HANDLERS[/help]=_sb_cmd_help
#_SB_HANDLERS['/?']=_sb_cmd_help
_SB_HELP[/help]='show this help'

#fin
