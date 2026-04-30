# slash-bash test suite

`bats-core` tests covering the four Bash files of the project (`slash-bash.bash`,
`slash-bash`, `.slash-bash-init`, `claude-sessions`) plus the chord-trick
behaviour and contractual invariants from `REQUIREMENTS.md` and `AUDIT-BASH.md`.

## Layout

| File | Cases | Concern |
|------|-------|---------|
| `source_invariants.bats`    | 11 | source-detection guard, interactive guard, source-time purity, default values, missing-dep diagnostics, dual-keymap binding |
| `handlers_basic.bats`       | 20 | `/help` `/agents` `/agent` `/models` `/model` `/maxtokens` |
| `handlers_kb.bats`          | 12 | `/kbs` `/kb` (incl. anchored regex traversal rejection) |
| `handlers_ollama.bats`      | 8  | `/ollama` regex acceptance/rejection |
| `handlers_ask.bats`         | 5  | `/ask` argv shape, KB cfg append, env passthrough |
| `handlers_systemprompt.bats`| 7  | jq presence, agent resolution, `{{spacetime}}` substitution |
| `handlers_history.bats`     | 5  | `/history`, lazy dir creation |
| `handlers_sessions.bats`    | 3  | wrapper delegation to `claude-sessions` |
| `handlers_status.bats`      | 7  | `/status` env dump, eval-safety, mutated-state round-trip |
| `completion.bats`           | 12 | `_sb_complete_*` (5 functions) |
| `intercept_dispatch.bats`   | 12 | `__sb_intercept` rewrite, `__sb_dispatch` routing |
| `lazy_loaders.bats`         | 8  | idempotency, ANSI strip, env override |
| `helpers.bats`              | 6  | `_sb_iso_now`, `_sb_spacetime`, agent resolve/key |
| `security.bats`             | 6  | `${var@Q}` quoting, traversal regex, HISTIGNORE |
| `launcher_slash_bash.bats` | 6  | exit codes 0/2/3/22 |
| `claude_sessions.bats`      | 7  | TSV format, exit codes 0/2/3/18, title fallback chain |
| `e2e_chord.bats`            | 2  | **optional** PTY-driven chord-trick verification (gated) |

Total: 137 cases (135 mandatory + 2 optional E2E).

## Running

```bash
# Phase 1 (the default - all tests except E2E):
bats tests/                # or: make test

# Single file:
bats tests/handlers_kb.bats

# Phase 2 (PTY chord tests). Requires `expect` from the `expect` package.
BATS_E2E=1 bats tests/e2e_chord.bats   # or: make test-e2e
```

The plan called for `bash -i -c 'bats tests/'` to satisfy the library's
interactive guard. That entry point still works, but the harness's
`source_slash_bash` shim strips the guard at source-time, so plain
`bats tests/` is sufficient.

## How the harness sources a "no-op in non-interactive shells" library

`slash-bash.bash:23` is `[[ $- == *i* ]] || return 0` - a hard guard that
makes the library a no-op outside interactive shells. `bats` runs each test in
a non-interactive subshell (it does not propagate `-i` from its parent shell),
so a naive `source slash-bash.bash` defines no handlers.

`tests/test_helper.bash:source_slash_bash` solves this by:

1. Pre-sourcing `bash-preexec.sh` from the project root (the library expects
   `preexec_functions` to exist and would otherwise resolve the path
   `BASH_SOURCE[0]%/*` to `/dev/fd` under process substitution).
2. Stripping the interactive guard line and the bash-preexec source-block via
   `awk`, then sourcing the rest from `<(...)`.
3. Saving and restoring the caller's `set -e/-u/pipefail` state - bats relies
   on `errexit` to detect test failures, and a leaked `set +e` would silently
   pass broken tests. The shim makes this air-tight.
4. Clearing the `DEBUG` trap and `PROMPT_COMMAND` that bash-preexec installs
   (they interfere with `bats run`).

## Mocks

Only `tests/mocks/claude.agent` is a runtime stub. It branches on
`$MOCK_CLAUDE_AGENT_KIND`:

| Kind | Behaviour |
|------|-----------|
| `list-good` (default) | Emits `leet\nhaiku\nopus\n` for `--list` |
| `list-empty`   | `--list` returns no agents |
| `list-noisy`   | ANSI-coloured + duplicate output (tests `sed`/`sort -u`) |
| `fail`         | Always exits 1 |
| `passthrough`  | Echoes argv (used by `/ask` argv-shape tests) |

`hide_jq()` (in `test_helper.bash`) builds a clean PATH containing only
coreutils, deliberately omitting `jq`. Used by the "missing jq" tests in
`/systemprompt` and `claude-sessions`.

## Adding a test

1. Pick the closest-fit `.bats` file (or create a new one if none fits).
2. Follow the `setup`/`teardown` boilerplate at the top of any existing file.
3. State mutations (`_SB_AGENT`, `_SB_KB`, etc.) must be observed via direct
   calls, **not** `run` - `run` spawns a subshell and the mutation is lost.
4. Use `${var@Q}` form in any assertion that targets diagnostic output (this
   is the project's BCS-NFR-6.3.3 quoting convention).

#fin
