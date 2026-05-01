# SMOKE-rebase.md — `/rebase` live round-trip recipe

The bats suite (`handlers_rebase.bats`) mocks `claude.agent` and verifies
argv shape, but cannot prove that **the real upstream `claude` CLI**
honours `claude.agent --resume <uuid>` keyed by uuid alone, with cwd
determining which `~/.claude/projects/<encoded>/<uuid>.jsonl` gets
written to.

This recipe verifies that round-trip end-to-end. It requires:
- a real TTY (the chord trick only fires interactively),
- a working `claude.agent` in `$PATH` with credentials,
- ~3 minutes wall clock.

Everything is read-only on the user's `$HOME` apart from new JSONL
files under `~/.claude/projects/-ai-scripts-slash-bash/` and
`~/.claude/projects/-tmp/` — no production data touched.

## Placeholder convention

`$UUID_A` and `$UUID_T` in this recipe are **operator-set shell
variables** captured from `_SB_SESSION_UUID` after each `/ask`.
The library already populates `_SB_SESSION_UUID` in the live shell as
part of the `/ask` handler, so the recipe captures it directly:

```bash
UUID_A=$_SB_SESSION_UUID
```

No `/status` parsing required — the global is the authoritative source
inside the same slash-bash shell. The capture step is folded into the
recipe (steps 5 and 12) so it cannot be skipped.

If the recipe is ever run from a different terminal that only has the
exported `SB_SESSION_*` env vars (post-`source save.sh`), substitute:

```bash
UUID_A=$SB_SESSION_UUID
```

## Recipe

```text
1.  cd <slash-bash repo>
2.  slash-bash                                # PS1 becomes "[<agent>] $ "
3.  /status                                  # _SB_SESSION_CWD=$PWD,
                                             # _SB_SESSION_UUID=''
4.  /ask 'reply with the literal token CWD-A'
5.  UUID_A=$_SB_SESSION_UUID; echo "$UUID_A" # capture; must be non-empty
6.  ls ~/.claude/projects/-ai-scripts-slash-bash/"$UUID_A".jsonl
                                             # exists
7.  cd /tmp
8.  /ask 'reply with token CWD-B'            # subshell cd writes JSONL
                                             # back to -ai-scripts-slash-bash/
9.  ls -lt ~/.claude/projects/-ai-scripts-slash-bash/"$UUID_A".jsonl
                                             # mtime bumped
10. /rebase --force                          # rebinds to /tmp;
                                             # _SB_SESSION_UUID may reset
11. /ask 'reply with token CWD-tmp'          # writes new JSONL
                                             # under -tmp/
12. UUID_T=$_SB_SESSION_UUID; echo "$UUID_T" # capture; non-empty, != UUID_A
13. cd -                                     # back to slash-bash repo
14. /rebase                                  # may warn dirty;
                                             # picks $UUID_A
15. /ask 'recall my first token'             # should reply CWD-A
16. /exit
```

## Pass criteria

| Step | Expectation                                                    |
|------|----------------------------------------------------------------|
| 6    | JSONL exists under the encoded `-ai-scripts-slash-bash` dir.    |
| 9    | Only the original `$UUID_A` JSONL grew — subshell `cd` worked. |
| 11   | A new JSONL appears under `~/.claude/projects/-tmp/`.          |
| 14   | `_sb_pick_newest_uuid` selects `$UUID_A` (newest under cwd).   |
| 15   | Model recalls `CWD-A`, proving `--resume` round-tripped.       |

## Failure handling

If step 15 returns a generic "I don't have that context" reply, the
contract `claude.agent --resume <uuid>` does **not** key resume by uuid
alone — `/rebase` then needs revisiting before further work proceeds.
Capture the failing transcript verbatim under "## Last run" below and
stop.

## Last run

| Field         | Value                                                  |
|---------------|--------------------------------------------------------|
| Date          | 2026-04-30                                             |
| Operator      | Biksu-Okusi (`sysadmin@okusi`)                         |
| `claude.agent` version | `claude.agent 1.1.0` (`claude.x 1.4.1`, `claude 2.1.123`) |
| Step 6 pass   | ✓ JSONL exists under `~/.claude/projects/-ai-scripts-slash-bash/fd061b03-…` |
| Step 9 pass   | ✓ same UUID_A JSONL grew to 1039155 bytes after step-8 `/ask` from `/tmp` (subshell `cd` confirmed) |
| Step 11 pass  | ✓ new UUID_T `4ac26e59-c06f-4e9b-b901-2c35a6c2728f` written under `-tmp/` |
| Step 14 pass  | ✓ dirty prompt fired ("47s ago"), `_sb_pick_newest_uuid` selected UUID_A |
| Step 15 pass  | ✓ model recalled `CWD-A` — `claude.agent --resume <uuid>` round-tripped end-to-end |

## Round-trip restoration

Verifies `/status` (dump) → `eval` → `slash-bash` (restore) reproduces the
conversation binding across shell exits. Bats covers the env-var seed
path; this recipe proves the upstream `claude.agent --resume <uuid>`
honours the restored UUID end-to-end.

### Recipe

```text
1.  cd <slash-bash repo>
2.  slash-bash
3.  /ask 'reply with the literal token ROUNDTRIP-OK'
4.  /status > /tmp/sc-state.sh
5.  /exit
6.  cat /tmp/sc-state.sh             # confirm SB_SESSION_UUID=<uuid> present
7.  source /tmp/sc-state.sh          # SB_SESSION_* now in env
8.  slash-bash                        # fresh shell, lib seeds from env
9.  /status                          # SB_SESSION_UUID matches step-3 UUID
10. /ask 'recall the token'          # model replies ROUNDTRIP-OK
11. /exit
```

### Pass criteria

| Step | Expectation                                                  |
|------|--------------------------------------------------------------|
| 6    | `/tmp/sc-state.sh` contains `export SB_SESSION_UUID='<uuid>'`. |
| 9    | UUID in fresh `/status` matches step-3 UUID.                 |
| 10   | Model recalls `ROUNDTRIP-OK`, proving `--resume` round-tripped via env-var path. |

### Last run

| Field         | Value                                            |
|---------------|--------------------------------------------------|
| Date          | _pending — recipe needs live execution under TTY_ |
| Operator      | _pending_                                        |
| Step 6 pass   | _pending_                                        |
| Step 9 pass   | _pending_                                        |
| Step 10 pass  | _pending_                                        |

#fin
