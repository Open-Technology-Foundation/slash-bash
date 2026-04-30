# Bash++ slash-bash

A working prototype of an interactive Bash shell that intercepts `/cmd args`
input at the readline layer and routes it to handler functions, while
leaving normal shell operation untouched. Single-machine dev demo on the
`okusi` workstation. Not packaged; not deployed.

```text
[leet] $ ls /tmp                  # ← normal bash
[leet] $ /agent claude            # ← slash command (intercepted)
agent set to: claude
[claude] $ /ask 'one-line haiku about bash'
...
```

## Goal (from `CLAUDE.md`)

> Initialise a bash shell sourced with functions that also run AI LLM
> commands. The shell should operate normally, except when a `/` char
> appears as the first char of a command line; when this happens, a
> dispatcher function should be called to see if it is a slash command:
>
> ```
> /ask
> /model
> /knowledgebase
> /...
> ```

## Why a normal `command_not_found_handle` will not work

Bash treats any token whose first char is `/` as an absolute path and runs
`execve()` immediately. The `command_not_found_handle` hook only fires
*after* `execve` fails — by which point the user has already seen
`bash: /foo: No such file or directory`. The earlier prototype
`.gudang/process-llm-command` used that hook and is preserved as a
historical record of an unsalvageable approach. **Do not revive it.**

## How it works — the chord trick

slash-bash intercepts the line at the readline layer, *before* bash parses
it for execution. Two key bindings cooperate:

| Binding | Effect |
|---------|--------|
| `\C-xs` (`bind -x`) | Runs `__sb_intercept` in the live shell. Reads `READLINE_LINE`; if it begins with `/`, rewrites it to `__sb_dispatch '<original>'` using `${line@Q}` for safe quoting. |
| `\C-m` (Enter) | Rebound to the macro `\C-xs\C-j` — interceptor first, then `\C-j` (the still-default `accept-line`) submits whatever the line now contains. |

By the time bash parses the line, it sees a normal function call rather
than a leading `/`. Lines that don't start with `/` pass through unchanged.

The `${line@Q}` quoting is the security boundary — it makes the dispatcher
immune to command injection via crafted input like `/foo'; rm -rf ~`.

`bash-preexec.sh` (vendored) provides `preexec_functions` so dispatched
commands can be logged to `~/.cache/slash-bash/history` without
re-implementing fragile DEBUG-trap plumbing.

## Install / run

```bash
cd /ai/scripts/claude/slash-bash
sudo symlink -S .          # exposes the launcher to /usr/local/bin
slash-bash                # opens an isolated interactive bash
```

The launcher `exec`s `bash --init-file .slash-bash-init -i`, so your
normal `~/.bashrc` is inherited but your outer shell is untouched. The
PS1 ends with `╱ <agent-name>` and updates live when you `/agent`, so
it is always obvious which agent is active. Examples below use the
shorthand `[leet] $` for readability — the actual rendered prompt is
multi-line and includes user@host, cwd, and the agent name after a
`╱` separator.

```bash
slash-bash --version       # 1.0.0
slash-bash --help
```

## Slash commands

| Command | Effect |
|---------|--------|
| `/help`, `/?` | Show inline help. |
| `/agents [--select\|--list]` | `--select` (default) presents a numbered picker via the bash `select` builtin and sets `_SB_AGENT` on choice; `q`/empty/`Ctrl-D` cancels. `--list` prints the legacy listing. Lazy-loads agents from `claude.agent --list` on first use. |
| `/agent <name>` | Set the active agent (case-insensitive exact match, then prefix match). No arg shows current. |
| `/models [--select\|--list]` | `--select` (default) presents a numbered picker via the bash `select` builtin and sets `_SB_MODEL` on choice. `--list` prints the legacy listing. |
| `/model [name]` | No arg: show current model. With arg: set it. |
| `/kbs`, `/knowledgebases [--select\|--list]` | `--select` (default) presents a numbered picker via the bash `select` builtin and sets `_SB_KB` on choice. `--list` prints the legacy listing. Both report "no knowledgebases found under …" if the root is empty. |
| `/kb <name>`, `/knowledgebase <name>` | Switch active KB (validated against `/var/lib/vectordbs/<name>/<name>.cfg`). `off`/`none`/`clear` to clear. No arg shows current. |
| `/maxtokens <n>` | Set `CLAUDE_CODE_MAX_OUTPUT_TOKENS` for subsequent `/ask` calls. No arg shows current. Positive integer. |
| `/ollama [model\|off]` | Toggle Ollama backend. Bare `/ollama` enables with default model; `<model>` enables and exports `OLLAMA_MODEL`; `off` disables. |
| `/ask <text>`, `/ <text>` | One-shot LLM call: `claude.agent -T <agent> --model <model> [-O] [--append-system-prompt-file <kb-cfg>] <text>` with `CLAUDE_CODE_MAX_OUTPUT_TOKENS` set. |
| `/systemprompt [agent]` | Show the system prompt for the active or named agent. Reads `Agents.json` (override path with `AGENTS_JSON` env var). Substitutes `{{spacetime}}` so the displayed prompt mirrors what the model actually sees. |
| `/history [n]` | Show the last `n` slash invocations from `~/.cache/slash-bash/history` (default 20). |
| `/status` | Print a bash-reusable env dump of current session state — one `export NAME='value'` line per `SB_*` knob (and the cross-project `VECTORDBS`, `AGENTS_JSON`, `OLLAMA_MODEL`, `SB_CLAUDE_PROJECTS_DIR`). Output is `eval`-safe; redirect to a file and `source` it before re-launching `slash-bash` to round-trip a saved session. |
| `/sessions` | List Claude Code sessions for the current `cwd` as TSV (`mtime`, `uuid`, `title`), newest first. UUIDs are accepted by `claude --resume`. Reads `~/.claude/projects/<encoded-cwd>/*.jsonl`. Thin wrapper that delegates to the standalone `claude-sessions` script (also available as a top-level command in any shell). |
| `/rebase [--force]` | Bind the active conversation to `$PWD`'s most-recent JSONL session (auto-pick — most recent by mtime). Subsequent `/ask` calls run inside the bound cwd and resume that UUID via `claude.agent --resume <uuid>`, regardless of where the user has `cd`'d. Default binding is the cwd at slash-bash entry; `_SB_SESSION_UUID` is empty until first `/ask` adopts the freshly-minted JSONL. If the current binding has recent `/ask` activity (within `SB_DIRTY_WINDOW` seconds — default 300), prompts before discarding; `--force` or non-TTY caller skips the prompt. No prior JSONL in the new cwd → next `/ask` starts a fresh conversation. |
| `/exit` | Leave slash-bash. |

Anything not starting with `/` is plain bash:

```text
[leet] $ ls /tmp
[leet] $ for i in 1 2 3; do echo "$i"; done
[leet] $ echo hello | wc -c
```

Anything that *starts* with `/` but isn't a known slash command prints
`unknown slash command: '/foo'` instead of the bash `No such file or
directory` error. The interceptor claims **all** lines that start with `/` —
there is no fallthrough to bash. This matches the CLAUDE.md goal of the
dispatcher being the single owner of `/`-prefixed input.

## Tab completion

First-word completion is wired via `complete -I` (Bash 5.0+, in this
project Bash 5.2+), which registers an "initial-word" compspec — the only
way to override bash's built-in pathname completion for `/`-prefixed words.
The completer (`_sb_complete_first`) reads keys from the `_SB_HANDLERS`
registry for tokens starting with `/`, and falls through to `compgen -c`
otherwise so non-slash commands tab-complete normally. `_SB_SLASH_CMDS`
is auto-derived from `${!_SB_HANDLERS[@]}` at end-of-init for legacy
site-hook compatibility but is not the source of truth.

Per-command argument completers are registered with the standard
`complete -F` path:

| Command(s) | Completer | Source |
|------------|-----------|--------|
| `/agent`, `/systemprompt` | `_sb_complete_agent` | `claude.agent --list` (lazy) |
| `/model` | `_sb_complete_model` | `_SB_MODEL_LIST` |
| `/kb`, `/knowledgebase` | `_sb_complete_kb` | `_SB_KB_LIST` plus `off`/`none`/`clear` |
| `/ollama` | `_sb_complete_ollama` | `off`/`0`/`false` |
| `/rebase` | `_sb_complete_rebase` | `--force` |

## Environment variables

slash-bash reads its initial state and filesystem layout from environment
variables. Every variable has a default that reproduces the workstation
layout on `okusi`, so unsetting all of them yields the original behaviour.

### Initial state (read once at library load)

| Variable | Default | Effect |
|----------|---------|--------|
| `SB_AGENT` | `leet` | Initial active agent. Overrides the library's default. |
| `SB_MODEL` | `claude-opus-4-7` | Initial active model. |
| `SB_MODEL_LIST` | `claude-opus-4-7 claude-opus-4-6 claude-sonnet-4-6 claude-haiku-4-6` | Space-separated menu shown by `/models` and `/model` tab-completion. |
| `SB_KB_LIST` | _(unset → discovered from `$VECTORDBS`)_ | Space-separated KB menu. Overrides discovery for a curated list. |
| `SB_MAX_TOKENS` | `32000` | Initial `CLAUDE_CODE_MAX_OUTPUT_TOKENS` for `/ask` calls. |
| `SB_OLLAMA` | `0` | Initial Ollama-on flag (`1` = on at start). |
| `SB_DIRTY_WINDOW` | `300` | Seconds since last `/ask` within which `/rebase` prompts before discarding the bound conversation. `0` disables the prompt. |
| `SB_SESSION_CWD` | `$PWD` at source time | Initial conversation-binding cwd. Restore path for `/status` round-trip. |
| `SB_SESSION_UUID` | _(empty — adopted on first `/ask`)_ | Initial conversation-binding JSONL UUID. Restore path for `/status` round-trip. |
| `SB_SESSION_LAST_ASK` | `0` | Initial EPOCHSECONDS of last `/ask`; gates `/rebase` dirty-prompt. Non-integer values coerce to `0` via `declare -ig`. Restore path for `/status` round-trip. |

### Filesystem locations

| Variable | Default | Effect |
|----------|---------|--------|
| `VECTORDBS` _(Okusi-wide convention)_ | `/var/lib/vectordbs` | Filesystem root holding `<name>/<name>.cfg` per KB. Read by `/kb`, `/kbs`, `/ask`. |
| `SB_HISTORY_FILE` | `${XDG_CACHE_HOME:-$HOME/.cache}/slash-bash/history` | Slash-invocation log path. Parent dir is auto-created. |
| `SB_CLAUDE_PROJECTS_DIR` | `$HOME/.claude/projects` | Where Claude Code stores per-cwd JSONL sessions. Read by `/sessions` and `claude-sessions`. |
| `SB_SITE_BASH` | `${XDG_CONFIG_HOME:-$HOME/.config}/slash-bash/site.bash` | Optional per-site extension file sourced at end of init. See [How to extend](#how-to-extend). |
| `AGENTS_JSON` | `/ai/scripts/claude/agents/Agents.json` | Path to the agent registry. Read by `/systemprompt`. |

### Pass-through to other tools

| Variable | Read by | Effect |
|----------|---------|--------|
| `OLLAMA_MODEL` | `/ollama`, `/ask` | Set by `/ollama <model>`; consumed by `claude.agent -O`. |
| `OLLAMA_HOST` | Ollama client | Honoured directly by Ollama; unused by slash-bash code. Set to `http://gpu-box:11434` etc. for a remote daemon. |
| `CLAUDE_CODE_MAX_OUTPUT_TOKENS` | `/ask` | Set per-invocation from `_SB_MAX_TOKENS`. |
| `TZ` | `/systemprompt` | Used to render the `{{spacetime}}` substitution. Falls back to `/etc/timezone`, then `UTC`. |
| `DEBUG` | library load time | If non-empty, the rewritten `__sb_dispatch …` form is *not* hidden from history (useful when debugging the chord trick). |
| `HISTIGNORE` | library load time | Patched (idempotently) to suppress `__sb_dispatch *` from history when `DEBUG` is unset. |
| `XDG_CACHE_HOME`, `XDG_CONFIG_HOME` | library load time | Standard XDG base-dir overrides for the history file and site hook defaults. |

## Portability

slash-bash ships with Okusi-workstation defaults but every machine-specific
path is overridable. Three recipes:

### Laptop without `/var/lib/vectordbs/`

Point `VECTORDBS` at a user-owned directory and drop a `<name>/<name>.cfg`
underneath:

```bash
export VECTORDBS=$HOME/kb
mkdir -p "$VECTORDBS/mykb"
printf 'You are a helpful assistant focused on X.\n' > "$VECTORDBS/mykb/mykb.cfg"
slash-bash
[leet] $ /kbs       # mykb appears
[leet] $ /kb mykb
```

The `VECTORDBS` env-var is the cross-project Okusi convention also honoured
by `claude.agent` and the vectordbs tooling — same redirect works
everywhere.

### Remote Ollama daemon

No code change. The Ollama client reads `OLLAMA_HOST` directly:

```bash
export OLLAMA_HOST=http://gpu-box:11434
slash-bash
[leet] $ /ollama llama3:70b
```

### Multi-site agent registry

```bash
export AGENTS_JSON=$HOME/.config/agents.json
slash-bash
[leet] $ /agents
```

### Fully self-contained "no /var, no /ai, no /etc" build

```bash
cat >>~/.bashrc <<'EOF'
export VECTORDBS=$HOME/kb
export AGENTS_JSON=$HOME/.config/agents.json
export SB_HISTORY_FILE=$HOME/.cache/slash-bash/history
export SB_SITE_BASH=$HOME/.config/slash-bash/site.bash
EOF
```

After that, the only system path slash-bash touches is the working
directory itself.

## Files

| File | Purpose |
|------|---------|
| `slash-bash` | Launcher — `exec`s an isolated bash (`bash --init-file .slash-bash-init -i`). |
| `.slash-bash-init` | rcfile companion — sources `~/.bashrc`, then the library, then sets `PS1` to embed the active agent name. |
| `slash-bash.bash` | Sourceable library — interceptor, dispatcher, handlers, completers, key bindings. |
| `claude-sessions` | Standalone CLI to list Claude Code sessions for the current `cwd`. Exposed via `.symlink`. The slash-bash `/sessions` handler delegates to it. |
| `bash-preexec.sh` | Vendored upstream (MIT) — `preexec`/`precmd` hooks. |
| `.symlink` | Maps the launcher and `claude-sessions` for `symlink -S` exposure. |
| `BASH-CODING-STANDARD.md` | Symlink → `/usr/local/share/yatti/BCS/data/BASH-CODING-STANDARD.md`. |
| `.gudang/process-llm-command` | Historical record of approach A (abandoned). |

`.gitignore` keeps `CLAUDE.md`, `.claude/`, the BCS symlink, and any
`AUDIT-*.md` out of version control per enterprise policy.

## Dependencies

### Required at runtime

| Dependency | Min version | Source / project | Notes |
|------------|-------------|------------------|-------|
| Bash       | **5.2+**    | https://www.gnu.org/software/bash/ | Chord trick uses `bind -x` and `\C-m` macro rebinding. `complete -I` requires 5.0+. `${var@Q}` requires 4.4+. We target 5.2+ exclusively. |
| coreutils | recent      | https://www.gnu.org/software/coreutils/ | `realpath`, `mkdir -p`, `sort`, `head`, `tail`, `cut`, `date -r`, `printf`. `date -Iseconds` is GNU-only but `_sb_iso_now` falls back to a portable `date +'%Y-%m-%dT%H:%M:%S%z'` invocation. `date -r FILE FORMAT` works on both GNU and BSD. |
| awk        | any POSIX   | https://www.gnu.org/software/gawk/ | Strips column 1 from `claude.agent --list`. |
| sed        | any POSIX   | https://www.gnu.org/software/sed/   | Strips ANSI color escapes from `claude.agent --list` output. |

### Vendored (in tree)

| File | Project | License | URL |
|------|---------|---------|-----|
| `bash-preexec.sh` | bash-preexec by @rcaloras (BCS-adapted copy) | MIT | https://github.com/rcaloras/bash-preexec |

### Optional — required only by specific slash commands

| Dependency | Used by | Source / project | Behaviour if absent |
|------------|---------|------------------|---------------------|
| `jq`           | `/systemprompt`, `/sessions` | https://github.com/jqlang/jq | `/systemprompt` prints `jq not in PATH` and returns 1. `/sessions` delegates to `claude-sessions`, which prints the same message and returns 18 (BCS `ERR_NODEP`). |
| `claude.agent` | `/ask`, `/agents`, `/agent`, `/systemprompt` | Okusi internal — `/ai/scripts/claude/agents/claude.agent` | Those commands print `claude.agent not in PATH`; the rest of the shell still works. |
| `claude-sessions` | `/sessions` | This project (sibling script in the slash-bash dir, also installed to PATH via `.symlink`) | `/sessions` prints `claude-sessions not found or not executable` and returns 18. |
| Claude Code CLI (`claude`) | `/sessions` (UUIDs are passed to `claude --resume`) | https://github.com/anthropics/claude-code | `/sessions` only *reads* `~/.claude/projects/<…>/*.jsonl`; running the CLI is left to the user. |
| Ollama | `/ollama`, `/ask -O` | https://github.com/ollama/ollama | Only invoked indirectly by `claude.agent -O`. Toggled-on but missing → `claude.agent` will report it. |
| `symlink` (Okusi tool) | install step | Okusi internal — `/usr/local/bin/symlink` | Replace with manual `ln -s` if absent. |

### Build / verification

| Tool | Source | URL | Notes |
|------|--------|-----|-------|
| ShellCheck | shellcheck | https://github.com/koalaman/shellcheck | `shellcheck -x` is mandatory and currently passes clean on all four bash files (`slash-bash`, `slash-bash.bash`, `.slash-bash-init`, `claude-sessions`). |
| bcscheck   | Okusi BCS toolchain | (internal) | LLM-backed BCS compliance check. ~10 minutes per script. Optional. |
| BCS data   | Bash Coding Standard | (internal — symlinked) | `/usr/local/share/yatti/BCS/data/`. |

## How to extend

Adding a `/cmd` is a **single new file** under `handlers.d/`. The
library globs `handlers.d/_*.bash` at init time; each handler file
defines its body, optional argument completer, and registers itself
into the `_SB_HANDLERS` / `_SB_HELP` / `_SB_COMPLETE` registry maps.

Worked example — drop this at `handlers.d/_weather.bash`:

```bash
#!/usr/bin/bash
#shellcheck shell=bash disable=SC2034
# handlers.d/_weather.bash - the /weather handler.

_sb_cmd_weather() {
  local -- arg=$*
  printf 'mock weather report (location: %s)\n' "${arg:-here}"
}

# Optional: argument completer. Omit if the command takes no args.
_sb_complete_weather() {
  local -- cur=${COMP_WORDS[COMP_CWORD]}
  COMPREPLY=()
  readarray -t COMPREPLY < <(compgen -W 'jakarta sydney london' -- "$cur")
}

# Registration (canonical position: end of file).
_SB_HANDLERS[/weather]=_sb_cmd_weather
_SB_HELP[/weather]='show mock weather for a city'
_SB_COMPLETE[/weather]=_sb_complete_weather

#fin
```

That's it. The dispatcher reads `_SB_HANDLERS` at runtime; `_SB_SLASH_CMDS`
is auto-derived from `${!_SB_HANDLERS[@]}` so first-word TAB completion
picks up the new command without any further edit. Aliases are extra keys
on `_SB_HANDLERS` (e.g. `_SB_HANDLERS[/w]=_sb_cmd_weather`).

### Per-host extension via the site hook

If you don't want to commit a handler upstream, drop a file at
`${XDG_CONFIG_HOME:-$HOME/.config}/slash-bash/site.bash` (or set
`SB_SITE_BASH` to point elsewhere). It's sourced at the end of the
library load, **after** `handlers.d/*.bash` and after key bindings /
compspecs are registered. Prefer the registry path:

```bash
# ~/.config/slash-bash/site.bash
_sb_cmd_ticket() {
  local -- arg=$*
  [[ -z $arg ]] && { >&2 printf 'usage: /ticket <text>\n'; return 1; }
  printf 'creating Linear ticket: %s\n' "$arg"
  # … your linear-cli call here …
}
_SB_HANDLERS[/ticket]=_sb_cmd_ticket
_SB_HELP[/ticket]='create a Linear ticket from the current shell'

# Override default agent for this host:
_SB_AGENT=claude
```

Legacy: `_SB_SLASH_CMDS+=(/ticket)` continues to work for completion-only
entries (no handler bound; dispatch will report "unknown slash command"
when invoked). The registry path is preferred for all new commands.

Future hooks (still out of scope):

- Streaming output via `coproc` so the prompt stays responsive during
  long LLM calls.
- Persistent state (active agent, model, KB) in
  `~/.config/slash-bash/state`.
- Multi-line input via PS2-aware intercept.

## Verification

```bash
shellcheck -x slash-bash slash-bash.bash .slash-bash-init claude-sessions handlers.d/*.bash
bcscheck slash-bash.bash      # full BCS, LLM-backed, slow (~10 min)
bcscheck claude-sessions       # ditto
make test                      # bats suite (~234 cases)
make test-e2e                  # PTY-driven chord-trick verification
make check                     # combined lint + test gate
```

Functional smoke test (must run under a real TTY — the chord trick won't
fire over piped stdin):

```bash
slash-bash
[leet] $ /help
[leet] $ /agents
[leet] $ /agent leet
[leet] $ /maxtokens 16000
[leet] $ /history
[leet] $ /exit
```

## Known limits

- Single-line input only — multi-line dispatch is not handled.
- `/ask`, `/agents`, `/agent`, `/systemprompt` require `claude.agent` in
  `PATH`. The agent list is loaded lazily on first use, so other commands
  still work without it.
- KB validation is path-based: a name is accepted only if
  `$VECTORDBS/<name>/<name>.cfg` exists (default
  `/var/lib/vectordbs`). `/kbs` discovers KB names by globbing that root;
  override the menu with `SB_KB_LIST="kb1 kb2"` or change the root with
  `VECTORDBS=…`.
- The interceptor claims **all** lines that start with `/`. There is no
  fallthrough to bash for unknown slash commands — by design (see Goal). If
  fallthrough is wanted, change the `*)` arm in `__sb_dispatch` (an
  `eval -- "$line"` would do it, with the obvious caveats).
- emacs and vi-insert keymaps are bound; vi-command keymap is not.
- `/sessions` encodes the cwd by replacing `/` with `-`, which is
  ambiguous (`/foo-bar` and `/foo/bar` collide). This mirrors Claude
  Code's own scheme and must stay in sync with it.

## Standards

- **BCS** (Bash Coding Standard) compliance: ~91%. The library deliberately
  omits `set -euo pipefail` because errexit in a sourced library would kill
  the live interactive shell on any handler failure; this is documented in
  the source. Run `make audit` (gitignored output → `AUDIT-BASH.md`) to
  reproduce the findings locally.
- ShellCheck: clean (`-x`) on all four bash files.
- Enterprise policy: `CLAUDE.md` and `.claude/` never committed
  (enforced by `.gitignore`).

#fin
