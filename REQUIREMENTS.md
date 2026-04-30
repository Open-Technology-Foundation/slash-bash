# Requirements — Bash++ slash-bash (`/ai/scripts/claude/slash-bash/`)

## Context

This is an as-built requirements specification for the slash-bash project, captured after the BCS audit + 3 remediation passes landed in commit `7b066cd`. The doc serves three audiences: maintainers (what the contract is), contributors (what they must preserve when extending), and reviewers (what to check during regression).

slash-bash is a single-machine developer tool: an interactive bash launched as an "isolated shell" that intercepts `/cmd args` lines at the readline layer and dispatches to handler functions, while leaving normal bash command execution untouched. Repository: `github.com:Open-Technology-Foundation/slash-bash.git`. Status: 1.0.0 prototype, deployed only on `okusi`. Not packaged.

---

## 1. Functional Requirements

### 1.1 Slash-Command Interception

**FR-1.1.1** — Any line whose first non-whitespace character is `/` MUST be routed to the dispatcher (`__sb_dispatch`) instead of being executed as an external command.

**FR-1.1.2** — The interceptor MUST claim *all* `/`-prefixed lines: unknown commands print `unknown slash command: '/foo'` and return non-zero, never falling through to bash's `execve()` and never producing `bash: /foo: No such file or directory`.

**FR-1.1.3** — Non-slash lines MUST be passed through to bash unchanged. Normal commands, pipelines, scripts, etc., behave exactly as in vanilla bash.

**FR-1.1.4** — The interceptor MUST work in both `emacs` and `vi-insert` keymaps. The `vi-command` keymap is intentionally unbound (Enter in command mode submits whatever's on the line, which is fine because the chord only needs to fire while the user is typing).

### 1.2 Built-in Slash Commands

The following commands MUST be available out-of-the-box, with TAB completion for first-word and (where listed) for arguments:

| Command | Purpose | Arg completion |
|---|---|---|
| `/help`, `/?` | Show help | — |
| `/agents` | List available agents (from `claude.agent --list`) | — |
| `/agent [name]` | Show or set active agent (case-insensitive prefix match) | yes — agent names |
| `/models` | List available models | — |
| `/model [name]` | Show or set active model | yes — model names |
| `/kbs`, `/knowledgebases` | List discovered KBs under `$VECTORDBS` | — |
| `/kb [name]` | Show or set active KB; `off`/`none`/`clear` resets | yes — KB names + reset literals |
| `/maxtokens [N]` | Show or set max output tokens (positive integer) | — |
| `/ollama [model\|off]` | Toggle Ollama backend; arg becomes `OLLAMA_MODEL` | yes — `off`/`0`/`false` |
| `/ask <text>`, `/ <text>` | Send LLM query via `claude.agent` | — |
| `/systemprompt [agent]` | Show resolved system prompt for active or named agent (with `{{spacetime}}` substitution) | yes — agent names |
| `/history [N]`, `/h` | Show last N (default 20) slash invocations | — |
| `/sessions` | List Claude Code sessions for `$PWD` (TSV: mtime, uuid, title) | — |
| `/status` | Print bash-reusable env dump of current session state (round-trippable via `eval "$(/status)"` then `slash-bash`) | — |
| `/rebase [--force]` | Bind active conversation to `$PWD`'s most-recent JSONL (auto-pick); prompts before discarding a binding with recent `/ask` activity | yes — `--force` |
| `/exit`, `/quit`, `/q`, `/bye` | Exit slash-bash | — |

**FR-1.2.1** — Every command in the table above MUST be registered in `_SB_HANDLERS` (which drives both dispatch and first-word TAB completion). `_SB_SLASH_CMDS` is auto-derived from `${!_SB_HANDLERS[@]}` at end-of-init and remains declared (not deleted) so legacy site hooks can still append to it for completion-only entries.

**FR-1.2.2** — Input that crosses a security or correctness boundary MUST be regex-validated before use (KB name, model name, maxtokens, history count). Validation regex must be anchored (`^...$`).

### 1.3 History Logging

**FR-1.3.1** — Every dispatched `/cmd` MUST be logged with an ISO-8601 timestamp to `$SB_HISTORY_FILE` (default `${XDG_CACHE_HOME:-$HOME/.cache}/slash-bash/history`). The original (pre-rewrite) form of the command is logged, not the `__sb_dispatch '...'` form.

**FR-1.3.2** — The history directory MUST be created lazily on first write, not on library source. (Library purity — see §3.)

**FR-1.3.3** — The rewritten `__sb_dispatch *` form MUST be hidden from readline history via `HISTIGNORE`, while the original `/cmd` form is preserved (via `history -s` inside the interceptor). `DEBUG=1` disables this concealment.

### 1.4 Session Management (`claude-sessions`)

**FR-1.4.1** — The `/sessions` command (and the standalone `claude-sessions` CLI it delegates to) MUST list Claude Code session JSONL files under `~/.claude/projects/<encoded-cwd>/`, output as TSV (mtime, uuid, title), sorted reverse-chronological.

**FR-1.4.2** — The cwd-encoding scheme (`/` → `-`) is intentionally ambiguous and MUST mirror Claude Code's on-disk layout exactly. Do not "fix" the ambiguity unilaterally.

---

## 2. State and Configuration

### 2.1 Per-Session Globals

All start with `_SB_` prefix. Initial values come from like-named env vars (`SB_AGENT`, `SB_MODEL`, …) or hardcoded defaults. Mutable; `/cmd` handlers update them.

| Global | Default | Settable via |
|---|---|---|
| `_SB_AGENT` | `${SB_AGENT:-leet}` | `/agent` |
| `_SB_MODEL` | `${SB_MODEL:-claude-opus-4-7}` | `/model` |
| `_SB_KB` | `''` | `/kb` |
| `_SB_KB_ROOT` | `${VECTORDBS:-/var/lib/vectordbs}` | env only |
| `_SB_MAX_TOKENS` | `${SB_MAX_TOKENS:-32000}` | `/maxtokens` |
| `_SB_OLLAMA` | `${SB_OLLAMA:-0}` | `/ollama` |
| `_SB_HISTORY_FILE` | `${SB_HISTORY_FILE:-${XDG_CACHE_HOME:-$HOME/.cache}/slash-bash/history}` | env only |
| `_SB_SITE_BASH` | `${SB_SITE_BASH:-${XDG_CONFIG_HOME:-$HOME/.config}/slash-bash/site.bash}` | env only |
| `_SB_SESSION_CWD` | `${SB_SESSION_CWD:-$PWD}` (at source time) | `/rebase`; `/status` round-trip |
| `_SB_SESSION_UUID` | `${SB_SESSION_UUID:-}` (empty until first `/ask`) | auto via `/ask`; `/rebase`; `/status` round-trip |
| `_SB_SESSION_LAST_ASK` | `${SB_SESSION_LAST_ASK:-0}` | auto via `/ask`; `/status` round-trip |
| `_SB_DIRTY_WINDOW` | `${SB_DIRTY_WINDOW:-300}` | env only |

### 2.2 Env-Var Convention

**FR-2.2.1** — slash-bash-owned vars use the `SB_` prefix (`SB_AGENT`, `SB_MODEL`, `SB_MAX_TOKENS`, `SB_OLLAMA`, `SB_HISTORY_FILE`, `SB_SITE_BASH`, `SB_DIRTY_WINDOW`, `SB_SESSION_CWD`, `SB_SESSION_UUID`, `SB_SESSION_LAST_ASK`, `SB_KB_LIST`, `SB_MODEL_LIST`, `SB_CLAUDE_PROJECTS_DIR`, `SB_VERBOSE`, `SB_DEBUG`, `SB_LOG_ARGS`). Cross-project Okusi conventions are reused verbatim (`VECTORDBS`, `AGENTS_JSON`, `OLLAMA_MODEL`, `OLLAMA_HOST`). Behaviour with no env vars set MUST reproduce the original hardcoded defaults exactly. The `SB_SESSION_*` + `SB_DIRTY_WINDOW` quartet is the round-trip restore path: `eval "$(/status)"` then `slash-bash` MUST reproduce the conversation binding. `SB_LOG_ARGS` defaults to unset; the history logger then records only the command verb (e.g. `/ask`) — set `SB_LOG_ARGS=1` to log full original lines.

---

## 3. Architectural Invariants (load-bearing — do not violate)

**AI-3.1 — The chord trick is the *only* viable interception mechanism.** `command_not_found_handle` is rejected because bash runs `execve()` *before* the handler fires, so the user has already seen the cryptic `bash: /foo: No such file or directory`. The abandoned prototype `.gudang/process-llm-command` is preserved as historical evidence; it MUST NOT be revived. Implementation: bind `\C-xs` to `__sb_intercept`, bind `\C-m` (Enter) to the macro `\C-xs\C-j` so the interceptor mutates `READLINE_LINE` *before* bash's parser sees it. (`slash-bash.bash:557-560`.)

**AI-3.2 — Two-keymap binding (`emacs` + `vi-insert`) MUST NOT be collapsed.** The visible duplication is intentional — collapsing breaks vi-mode users.

**AI-3.3 — The library MUST be source-pure.** Sourcing `slash-bash.bash` only declares functions and state. No filesystem mutation, no network, no side effects. The history dir is created lazily on first write (`_sb_ensure_history_dir`, `slash-bash.bash:465-473`). Direct dependency `bash-preexec.sh` is existence-checked before sourcing (`slash-bash.bash:36-43`). (BCS0407.)

**AI-3.4 — The library MUST detect direct execution.** Running `bash slash-bash.bash` inside an interactive shell is a contributor footgun — the chord trick installs into the wrong shell. Source-detection guard at `slash-bash.bash:16-19` exits 1 with diagnostic. The interactive guard at `slash-bash.bash:24` is a *second* gate that makes non-interactive sourcing a no-op.

**AI-3.5 — The library MUST NOT enable `set -euo pipefail`.** It is sourced into the user's live interactive shell; errexit would kill the shell on any handler failure. Compensation: every handler uses explicit `|| return N` patterns. Comment at `slash-bash.bash:27-30` documents this and instructs maintainers not to "fix" it.

**AI-3.6 — The launcher MUST enable strict mode + `inherit_errexit`.** Distinct from AI-3.5 because the launcher (`slash-bash`) is a one-shot executable, not a sourceable library. (BCS0101.)

**AI-3.7 — The interceptor claims all `/` lines.** Unknown commands print `unknown slash command: ...`; never fall through to bash. This is by design (see CLAUDE.md and README.md).

**AI-3.8 — UUID adoption MUST be gated on `claude.agent` rc==0.** A non-zero rc commonly indicates shlock contention with a sibling `slash-bash` in the same cwd (upstream `claude.agent` wraps `claude.x` in `shlock`, non-blocking by default — see `claude.agent:354-375`); the newest JSONL in that case belongs to the *other* shell, and adopting it would silently rebind this conversation to the sibling's session. The gate at `handlers.d/_ask.bash:61-62` (the `(( rc == 0 )) && [[ -z $_SB_SESSION_UUID ]]` predicate before `_sb_pick_newest_uuid`) defends against this and emits an explicit retry hint on rc=1.

---

## 4. External Dependencies

### 4.1 Required for full function

| Tool | Used by | If absent |
|---|---|---|
| `claude.agent` | `/ask`, `/agents`, `/agent`, `/systemprompt` | those commands print "claude.agent not in PATH"; rest works |
| `jq` | `/systemprompt`, `claude-sessions` | `/systemprompt` graceful skip; `claude-sessions` returns 18 |

### 4.2 Required for fallback / hygiene

| Tool | Used by | Notes |
|---|---|---|
| `realpath` | launcher | resolves script path for `--init-file` |
| `date` | history logger | `-Iseconds` (GNU) with portable fallback |
| `mkdir`, `sed`, `awk`, `sort`, `head`, `cut` | misc | one or two callsites each |

### 4.3 Vendored

| File | Source | Coupling |
|---|---|---|
| `bash-preexec.sh` | rcaloras/bash-preexec, MIT | only `preexec_functions` array used; `precmd_functions` not used |

### 4.4 Configurable file paths

| Path | Override | Used by |
|---|---|---|
| `$VECTORDBS/<name>/<name>.cfg` | `VECTORDBS` | `/kb`, `/kbs`, `/ask` |
| `Agents.json` | `AGENTS_JSON` (default `/ai/scripts/claude/agents/Agents.json`) | `/systemprompt` |
| `~/.claude/projects/<encoded-cwd>/*.jsonl` | `SB_CLAUDE_PROJECTS_DIR` | `/sessions`, `claude-sessions` |
| `$_SB_HISTORY_FILE` | `SB_HISTORY_FILE` | history logger |
| `$_SB_SITE_BASH` | `SB_SITE_BASH` | end-of-init extension hook |

---

## 5. Extensibility

### 5.1 Adding a Built-in Slash Command

**FR-5.1.1** — A new `/cmd` is a single new file under `handlers.d/`. The library globs `handlers.d/_*.bash` at init time; each file:

1. Defines the `_sb_cmd_<name>` handler body.
2. Optionally defines `_sb_complete_<name>` (argument completer).
3. Registers itself by appending to the library's three associative-array maps:
   - `_SB_HANDLERS[/<name>]=_sb_cmd_<name>` — required; drives both dispatch and first-word TAB completion.
   - `_SB_HELP[/<name>]='one-line synopsis'` — required on the canonical alias only.
   - `_SB_COMPLETE[/<name>]=_sb_complete_<name>` — required only when step 2 was done.

Aliases are extra keys on `_SB_HANDLERS` (e.g. `_SB_HANDLERS[/h]=_sb_cmd_history`); `_SB_HELP` is keyed only on the canonical alias. `_SB_SLASH_CMDS` is auto-derived from `${!_SB_HANDLERS[@]}` at end-of-init, so first-word TAB completion picks up new commands without a separate edit.

**FR-5.1.2** — A library-load-time validation pass MUST warn if any `_SB_HANDLERS` entry resolves to an undefined function. This catches typos and missing-handler regressions at source time rather than at first dispatch.

**FR-5.1.3** — The `${#_SB_HANDLERS[@]} == 23` invariant (16 handler files contributing 23 registrations including aliases) is asserted by the test suite. Bare `/` is special-cased in `__sb_dispatch` as the documented `/ask` shorthand and is NOT a key.

### 5.2 Per-Host Site Extensions

**FR-5.2.1** — `_SB_SITE_BASH` (default `${XDG_CONFIG_HOME:-$HOME/.config}/slash-bash/site.bash`) MUST be sourced after all built-in handlers, key bindings, and compspecs are registered. The site file runs in the live interactive shell (not a subshell) and may:
- define new `_sb_cmd_<name>` handlers and register them via `_SB_HANDLERS[/<name>]=_sb_cmd_<name>` (preferred — same registry path as `handlers.d/`),
- append to `_SB_SLASH_CMDS` for completion-only entries (legacy; dispatch will report "unknown slash command" if no handler is bound),
- register `complete -F` compspecs (or append to `_SB_COMPLETE`),
- override default state (`_SB_AGENT`, `_SB_MODEL`, etc.),
- re-bind chord keys.

**FR-5.2.2** — Per-host commands MUST NOT live in `slash-bash.bash`. The site file is the canonical "I want a `/ticket` command on my laptop only" path.

---

## 6. Non-Functional Requirements

### 6.1 Platform

**NFR-6.1.1** — Bash 5.2+ exclusively. Modern features expected (e.g., `${var@Q}`, `complete -I`, `bind -m`). No POSIX compatibility layer.

**NFR-6.1.2** — Linux only (Ubuntu 24.04+ target). No macOS / BSD / Windows / WSL support promised. `date -Iseconds` portable fallback exists but is the only concession.

### 6.2 Code-Quality Gates

**NFR-6.2.1** — `shellcheck -x` MUST pass clean (exit 0) on all in-tree bash files: `slash-bash`, `slash-bash.bash`, `.slash-bash-init`, `claude-sessions`, and every file under `handlers.d/`. Documented suppressions only, each with an explanatory comment per BCS1202. Vendored `bash-preexec.sh` is exempt.

**NFR-6.2.2** — BCS conformance baseline (post-audit, see `AUDIT-BASH.md` regenerated via `make audit`; current health score 8.5/10, ~92% on confirmed findings):
- Core errors: zero outstanding. Two bcscheck-flagged `[ERROR]` findings (BCS0606 on the launcher's `die()` and on the library's `shopt -q nullglob && _sb_was_nullglob=1`) were verified to **not** trigger errexit — the launcher case was reproduced; the library case never runs under `set -e` because the library deliberately omits strict mode (Documented Exemption 1).
- Recommended/style warnings deferred with rationale in the audit file: BCS0405 (six unused colour-palette vars retained for `$SB_SITE_BASH` consumers), BCS0305 (intentional `printf` format with embedded sigil), BCS0407 (architectural — readline `bind`, `complete`, `preexec_functions+=`, `HISTIGNORE` are the library's purpose).
Re-run `make audit` after any modification; deviations from this baseline require an audit-doc update.

**NFR-6.2.3** — `claude-sessions` MUST stay shellcheck-clean (exposed via `.symlink` as a top-level CLI; some users invoke it independently of `slash-bash`).

### 6.3 Safety

**NFR-6.3.1** — The library MUST NOT crash the user's shell on a handler error. Errexit is forbidden in the library (AI-3.5). Each handler returns its own non-zero code; the dispatcher reports it without aborting.

**NFR-6.3.2** — Input validation regex MUST be anchored. Path components in particular (KB names) must reject `..`, `/`, and shell metacharacters before being concatenated into filesystem paths.

**NFR-6.3.3** — All error messages displaying user-supplied or path-derived strings MUST use `${var@Q}` (single-quote form, unambiguous), not `printf '%q'` (which may emit `$'...'` ANSI-C escapes confusing in logs). (BCS0306.)

### 6.4 Compatibility

**NFR-6.4.1** — `_sb_spacetime` MUST stay format-synced with `claude.agent`'s `spacetime_string` (lines 68-80 of that script). The sync comment at `slash-bash.bash:193-198` flags the dependency.

**NFR-6.4.2** — The cwd-encoding scheme used by `/sessions` MUST round-trip with whatever Claude Code itself writes to `~/.claude/projects/`. Independent encoding changes are forbidden.

---

## 7. Verification

### 7.1 Static + automated

```bash
shellcheck -x slash-bash slash-bash.bash .slash-bash-init claude-sessions handlers.d/*.bash
bcscheck slash-bash
bcscheck slash-bash.bash
make test                # bats Phase 1 (~234 cases)
make test-e2e            # bats Phase 2 — PTY-driven chord-trick verification
make check               # combined lint + test gate
```

Both `bcscheck` invocations should return exit 0 with no findings (modulo the style-tier deviations noted in NFR-6.2.2). The bats suite under `tests/` exercises every handler and the dispatcher; `tests/test_helper.bash` strips the three `TEST_SHIM_*` sentinel regions so handlers can be called directly without a real TTY.

### 7.2 Functional smoke (non-interactive — handlers callable directly)

```bash
[[ $- != *i* ]] && exec bash -i "$0" "$@"
source /ai/scripts/claude/slash-bash/slash-bash.bash 2>/dev/null
_sb_cmd_maxtokens 0           # expect: usage error, rc=1
_sb_cmd_ollama                # expect: model=<default>
_sb_cmd_kb '../../etc/passwd' # expect: invalid kb name, rc=1
```

### 7.3 Functional smoke (chord trick — TTY required)

```bash
slash-bash                # PS1 should show [<agent>]
[leet] $ /help             # built-in help text
[leet] $ /agents           # lists agents (or claude.agent diagnostic)
[leet] $ /maxtokens 16000  # 'maxtokens set to: 16000'
[leet] $ /history          # ≥ 4 lines from this session
[leet] $ /bogus            # 'unknown slash command: '/bogus''
[leet] $ /exit             # 'farewell', exit 0
```

The chord trick only fires under a real TTY; piping commands into stdin will not exercise the readline interception path.

### 7.4 Library purity (post-fix invariant)

```bash
TMPDIR=$(mktemp -d); export TMPDIR
SB_HISTORY_FILE=$TMPDIR/sub/history bash -i -c '
  source /ai/scripts/claude/slash-bash/slash-bash.bash
  [[ -d $TMPDIR/sub ]] && echo "FAIL: dir created on source" || echo "ok"
  _SB_LAST_ORIGINAL=/test
  _sb_log_dispatch "__sb_dispatch /test"
  [[ -d $TMPDIR/sub ]] && echo "ok: dir created on first write" || echo "FAIL"
'; rm -rf "$TMPDIR"
```

### 7.5 Direct-execution rejection

```bash
bash /ai/scripts/claude/slash-bash/slash-bash.bash; echo "expect 1, got $?"
```

### 7.6 Launcher arg parser

```bash
./slash-bash -V          # exit 0
./slash-bash -h          # exit 0
./slash-bash --bogus     # exit 22 (BCS canonical ERR_INVAL)
./slash-bash extraarg    # exit 2  (BCS canonical ERR_USAGE)
```

---

## 8. Out of Scope (explicit non-requirements)

- **No release automation.** Version is hardcoded in launcher (`VERSION=1.0.0`). No CHANGELOG, no git tags.
- **No multi-line input.** Each `/cmd` line is a single readline submission. README §"Future hooks" notes this as a possible enhancement.
- **No streaming output.** `/ask` returns once `claude.agent` exits. Streaming is README-future.
- **No persistent state across sessions.** Settings reset to env-var defaults each shell startup.
- **No portability beyond Linux.** `bash 5.2+` and Ubuntu 24.04+ are the only supported platform.
- **No Windows / macOS / BSD support.**

---

## 9. Files of Record

| File | Role | Lines |
|---|---|---|
| `slash-bash` | launcher | 88 |
| `slash-bash.bash` | sourceable library (the chord trick + registry-driven dispatcher) | ~656 |
| `.slash-bash-init` | rcfile sourced by `bash --init-file` | 71 |
| `handlers.d/_*.bash` | one file per slash-command handler (16 files; 23 registrations including aliases) | ~611 total |
| `bash-preexec.sh` | vendored MIT (preexec hooks) | 567 |
| `claude-sessions` | sibling CLI (`/sessions` delegates to it) | 82 |
| `Makefile` | dev workflow targets: `test`, `test-e2e`, `lint`, `audit`, `check` | 39 |
| `tests/*.bats` | bats suite (~234 cases across ~20 files; `e2e_chord.bats` runs only with `BATS_E2E=1`) | — |
| `.symlink` | declares which executables are exposed to PATH | 2 entries: `slash-bash`, `claude-sessions` |
| `README.md` | user-facing tour, "How to extend", limits | ~400 |
| `CLAUDE.md` | maintainer doc for Claude Code (gitignored) | — |
| `BASH-CODING-STANDARD.md` | symlink → `/usr/local/share/yatti/BCS/data/` (gitignored) | — |
| `.gudang/process-llm-command` | preserved abandoned prototype (do not revive) | 30 |

---

#fin
