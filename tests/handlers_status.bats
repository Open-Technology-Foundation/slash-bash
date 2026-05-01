#!/usr/bin/env bats
#shellcheck shell=bats
# handlers_status.bats - /status handler.
#
# Asserts that the bash-reusable env dump:
#   - emits exactly the always-emitted lines under default state
#   - is `eval`-safe (round-trips through `eval` into a fresh subshell)
#   - reflects mutated state from /agent /maxtokens /ollama
#   - conditionally emits OLLAMA_MODEL only when set
#   - preserves embedded whitespace / metacharacters via ${var@Q} quoting

load test_helper

setup() {
  setup_test_env
  enable_mocks
  source_slash_bash
}

teardown() {
  disable_mocks
  teardown_test_env
}

# ----------------------------------------------------------------------------
# Default-state shape
# ----------------------------------------------------------------------------

@test "/status: defaults emit exactly 13 export lines, all valid form" {
  run _sb_cmd_status
  assert_success
  # Always-emitted set: SB_AGENT, SB_MODEL, SB_MAX_TOKENS, SB_OLLAMA,
  # SB_HISTORY_FILE, SB_SITE_BASH, SB_SESSION_CWD, SB_SESSION_UUID,
  # SB_SESSION_LAST_ASK, SB_DIRTY_WINDOW, SB_CLAUDE_PROJECTS_DIR,
  # VECTORDBS, AGENTS_JSON. Optional (skipped under defaults): SB_KB_LIST,
  # OLLAMA_MODEL.
  (( ${#lines[@]} == 13 ))
  local -- ln
  for ln in "${lines[@]}"; do
    # Each line: `export NAME=<single-quoted-or-empty-quoted-value>`
    [[ $ln =~ ^export\ [A-Z_]+=.* ]] || { printf 'bad line: %s\n' "$ln" >&2; false; }
  done
}

@test "/status: includes the four /rebase session vars by default" {
  run _sb_cmd_status
  assert_success
  assert_output --partial "export SB_SESSION_CWD="
  assert_output --partial "export SB_SESSION_UUID="
  assert_output --partial "export SB_SESSION_LAST_ASK="
  assert_output --partial "export SB_DIRTY_WINDOW="
}

# ----------------------------------------------------------------------------
# Eval-safety round-trip
# ----------------------------------------------------------------------------

@test "/status: output is eval-safe (round-trips defaults via eval)" {
  local -- captured
  captured=$(_sb_cmd_status)
  local -- agent model
  agent=$(eval "$captured"; printf '%s' "$SB_AGENT")
  model=$(eval "$captured"; printf '%s' "$SB_MODEL")
  [[ $agent == 'leet' ]]
  [[ $model == 'claude-opus-4-7' ]]
}

# ----------------------------------------------------------------------------
# Mutated state survives the round-trip
# ----------------------------------------------------------------------------

@test "/status: emits mutated SB_AGENT after /agent <name>" {
  mock_claude_agent list-good
  _sb_cmd_agent haiku >/dev/null
  run _sb_cmd_status
  assert_success
  assert_output --partial "export SB_AGENT='haiku'"
}

@test "/status: emits mutated SB_MAX_TOKENS after /maxtokens <n>" {
  _sb_cmd_maxtokens 8192 >/dev/null
  run _sb_cmd_status
  assert_success
  assert_output --partial "export SB_MAX_TOKENS='8192'"
}

@test "/status: emits SB_OLLAMA=1 + OLLAMA_MODEL after /ollama <model>" {
  _sb_cmd_ollama 'llama3.1:8b' >/dev/null
  run _sb_cmd_status
  assert_success
  assert_output --partial "export SB_OLLAMA='1'"
  assert_output --partial "export OLLAMA_MODEL='llama3.1:8b'"
}

# ----------------------------------------------------------------------------
# Conditional emit
# ----------------------------------------------------------------------------

@test "/status: omits OLLAMA_MODEL line when not set" {
  run _sb_cmd_status
  assert_success
  refute_output --partial "OLLAMA_MODEL"
}

@test "/status: omits AGENTS_JSON when unset (next session auto-derives)" {
  # Previously _sb_cmd_status seeded AGENTS_JSON to a hardcoded path so
  # it was always emitted. The new contract: emit only if the user has
  # AGENTS_JSON set externally, otherwise omit and let the next session's
  # _sb_default_agents_json discover from claude.agent in PATH.
  unset AGENTS_JSON
  run _sb_cmd_status
  assert_success
  refute_output --partial "export AGENTS_JSON"
  # Sanity: the rest of the always-emitted set still appears.
  assert_output --partial "export SB_AGENT="
  assert_output --partial "export VECTORDBS="
}

# ----------------------------------------------------------------------------
# @Q quoting round-trips embedded whitespace
# ----------------------------------------------------------------------------

@test "/status: @Q quoting round-trips spaces and metacharacters" {
  _SB_AGENT='weird name; $(echo bad)'
  local -- captured
  captured=$(_sb_cmd_status)
  local -- round_tripped
  round_tripped=$(eval "$captured"; printf '%s' "$SB_AGENT")
  [[ $round_tripped == 'weird name; $(echo bad)' ]]
}

#fin
