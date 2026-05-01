# handlers.d/

Registry-driven extension point for slash-bash. **One file per slash
command.** The library globs `handlers.d/*.bash` at source time, sources
each in lex order, and validates every entry in `_SB_HANDLERS` resolves
to a defined function. Adding a command is a single-file change — no
edits to `slash-bash.bash` and no coordinated touches to a dispatcher
case arm or a sidecar list.

For broader context (chord trick, lazy completion, session binding)
see `../README.md` and `../CLAUDE.md`. This file is the contributor's
local cheat-sheet.

## Skeleton

```bash
#!/usr/bin/bash
#shellcheck shell=bash disable=SC2034
# handlers.d/_ticket.bash - the /ticket handler.

_sb_cmd_ticket() {
  local -- arg=$*
  printf 'ticket arg: %s\n' "$arg"
}

_sb_complete_ticket() {
  local -- cur=${COMP_WORDS[COMP_CWORD]}
  COMPREPLY=()
  readarray -t COMPREPLY < <(compgen -W 'open closed' -- "$cur")
}

_SB_HANDLERS[/ticket]=_sb_cmd_ticket
_SB_HELP[/ticket]='show or set a ticket'
_SB_COMPLETE[/ticket]=_sb_complete_ticket

#fin
```

Drop the file, start a fresh `slash-bash`, and `/ticket` works.

## Conventions

| Item | Rule |
|---|---|
| Filename | `_<name>.bash` — leading underscore keeps the glob predictable; lex order is load-order (see §Inter-handler dependencies). |
| Shebang | `#!/usr/bin/bash` |
| Pragma | `#shellcheck shell=bash disable=SC2034` — registration assignments look unused because the dispatcher reads the maps indirectly. |
| Handler name | `_sb_cmd_<name>` |
| Completer name | `_sb_complete_<name>` (optional) |
| End marker | `#fin` (BCS convention) |

## Registration — three maps

| Map | Required? | Purpose | Aliases? |
|---|---|---|---|
| `_SB_HANDLERS[/cmd]=_sb_cmd_<name>` | yes | dispatch + first-word TAB completion | one entry per alias |
| `_SB_HELP[/cmd]='one-line synopsis'` | canonical alias only | introspection | not aliased |
| `_SB_COMPLETE[/cmd]=_sb_complete_<name>` | only if a completer is defined | per-command `complete -F` registration | one entry per alias |

Bare `/` is special-cased in `__sb_dispatch` as the `/ask` shorthand —
it is **not** a registry key, do not register it.

## Globals

### Settings (handlers may read or write)

| Var | Purpose |
|---|---|
| `_SB_AGENT` | active agent short-name |
| `_SB_MODEL` | active model alias |
| `_SB_KB` | active knowledgebase name (or empty) |
| `_SB_KB_ROOT` | filesystem root for KB cfgs (read-only) |
| `_SB_MAX_TOKENS` | token cap passed to `claude.agent` |
| `_SB_OLLAMA` | ollama model override (or empty) |
| `_SB_SESSION_CWD` | bound directory for `/ask` JSONL writes |
| `_SB_SESSION_UUID` | active conversation UUID (auto-adopted on first `/ask`) |
| `_SB_SESSION_LAST_ASK` | epoch of last `/ask` (rebase-safety) |
| `_SB_DIRTY_WINDOW` | rebase-safety threshold (read-only, seconds) |
| `_SB_HISTORY_FILE` | preexec log path (read-only) |

### Lazy lists

Call the loader before reading:

| Var | Loader |
|---|---|
| `_SB_AGENT_LIST` | `_sb_load_agent_list` |
| `_SB_KB_LIST` | `_sb_load_kb_list` |
| `_SB_MODEL_LIST` | (eager-loaded at source time; just read) |

### Registry maps (your handler appends to these)

`_SB_HANDLERS`, `_SB_HELP`, `_SB_COMPLETE`. `_SB_SLASH_CMDS` is derived
from `_SB_HANDLERS` at end-of-init — do not write to it (the legacy
completion-only path `_SB_SLASH_CMDS+=(/myticket)` still works for site
hooks but is discouraged for new in-tree handlers).

### Colour palette

TTY-conditional; empty strings on non-TTY so they are always safe to
expand: `_RED`, `_GREEN`, `_YELLOW`, `_CYAN`, `_BOLD`, `_NC`, plus the
retained-but-currently-unused `_BLUE`, `_MAGENTA`, `_DIM`, `_ITALIC`,
`_UNDERLINE`, `_REVERSE`. Prefer the messaging primitives below — they
already wrap the palette.

## Helpers worth reusing

| Helper | Use when | Defined |
|---|---|---|
| `_sb_load_agent_list` | before reading `_SB_AGENT_LIST` | `slash-bash.bash:160` |
| `_sb_load_kb_list` | before reading `_SB_KB_LIST` | `slash-bash.bash:188` |
| `_sb_resolve_agent_name` | match user input case-insensitive then prefix | `slash-bash.bash:278` |
| `_sb_agent_key` | look up the long key in `Agents.json` | `slash-bash.bash:292` |
| `_sb_pick_newest_uuid OUTVAR CWD [MIN_MTIME]` | find newest JSONL session for a cwd | `slash-bash.bash:308` |
| `_sb_print_list LABEL VARNAME ITEMS…` | render an `available <label>s:` listing | `slash-bash.bash:236` |
| `_sb_select_from_list LABEL VARNAME ITEMS…` | numbered picker via the `select` builtin | `slash-bash.bash:249` |
| `_sb_iso_now` | ISO-8601 timestamp (portable fallback) | `slash-bash.bash:206` |
| `_sb_spacetime` | hour-granular spacetime string (matches `claude.agent`) | `slash-bash.bash:216` |

## Messaging primitives

Use these instead of raw `printf` to stderr — they prefix the active
agent name and a sigil, and they no-op cleanly on non-TTY (palette is
empty).

| Primitive | When | Gating |
|---|---|---|
| `_error MSG…` | fatal / user-correctable | always emits |
| `_warn  MSG…` | non-fatal advisory | always emits |
| `_info  MSG…` | progress note | `_VERBOSE` / `SB_VERBOSE` |
| `_success MSG…` | post-action confirmation | `_VERBOSE` / `SB_VERBOSE` |
| `_debug MSG…` | trace | `_DEBUG` / `SB_DEBUG` |
| `_die N MSG…` | print error then `return N` (NOT `exit`) | always |

`_die` uses `return`, not `exit`, because the library is sourced into
the user's live interactive shell — see `../slash-bash.bash:27-30` for
the no-`set -e` rationale.

## Aliases

One handler, multiple keys. `_kb.bash` is the canonical example:

```bash
_SB_HANDLERS[/kb]=_sb_cmd_kb
_SB_HANDLERS[/knowledgebase]=_sb_cmd_kb
_SB_HELP[/kb]='switch active knowledgebase'   # canonical alias only
_SB_COMPLETE[/kb]=_sb_complete_kb
_SB_COMPLETE[/knowledgebase]=_sb_complete_kb
```

`_SB_HELP` is keyed on the canonical alias only. `_SB_COMPLETE` is
keyed on every alias that should accept TAB completion. See also
`_history.bash` (`/history`, `/h`) and `_exit.bash` (`/bye`, `/quit`,
`/q`, `/exit`). `/help` and `/?` look like aliases but live in
separate files (`_help.bash`, `_help-short.bash`) because they render
distinct help bodies.

## Inter-handler dependencies — beware lex order

The library globs `handlers.d/*.bash` alphabetically. Any reuse across
files depends on this. Currently:

- `_systemprompt.bash` references `_sb_complete_agent`, defined in
  `_agent.bash`. `_agent` < `_systemprompt` lexically, so it works.
  Renaming either file in a way that breaks lex order silently breaks
  completion for `/systemprompt`.

If your handler defines a helper another handler will reuse, name your
file so it lex-sorts earlier — or move the helper into
`../slash-bash.bash` proper.

## Validation

End-of-init runs a pass that walks `_SB_HANDLERS` and emits
`_warn 'internal: /foo -> _sb_cmd_foo not defined'` for any entry whose
function is missing. Typos and copy-paste errors surface at source
time, not at first dispatch.

The bats suite asserts `${#_SB_HANDLERS[@]} == 26` as a guard against
silent drift. A new handler bumps that count — update the assertion in
`../tests/` in lockstep with the new file.

## Per-host vs in-tree

Handlers you intend to share with other slash-bash users belong here.
Handlers private to one machine belong in `$SB_SITE_BASH` (default
`${XDG_CONFIG_HOME:-$HOME/.config}/slash-bash/site.bash`). The site
file is sourced **after** `handlers.d/`, so it can override or extend
anything declared here. See `../README.md` §"Per-host extension via
the site hook" for the ownership/permissions gating.

#fin
