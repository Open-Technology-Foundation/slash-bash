#!/usr/bin/env bats
#shellcheck shell=bats
# launcher_slash_bash.bats - the slash-bash launcher (BCS exit codes).

load test_helper

setup() {
  setup_test_env
}

teardown() {
  teardown_test_env
}

@test "launcher: --version prints VERSION and exits 0" {
  run "$PROJECT_DIR/slash-bash" --version
  assert_success
  assert_output --partial "slash-bash"
  assert_output --partial "1.0.0"
}

@test "launcher: -V short form prints VERSION and exits 0" {
  run "$PROJECT_DIR/slash-bash" -V
  assert_success
  assert_output --partial "1.0.0"
}

@test "launcher: --help prints usage and exits 0" {
  run "$PROJECT_DIR/slash-bash" --help
  assert_success
  assert_output --partial "Usage:"
  assert_output --partial "Behaviour:"
  assert_output --partial "Exit codes:"
}

@test "launcher: unexpected arg exits 2 (BCS ERR_USAGE)" {
  run "$PROJECT_DIR/slash-bash" some-positional-arg
  assert_failure 2
  assert_output --partial "unexpected argument"
}

@test "launcher: invalid -X option exits 22 (BCS ERR_INVAL)" {
  run "$PROJECT_DIR/slash-bash" -X
  assert_failure 22
  assert_output --partial "invalid option"
}

@test "launcher: missing init file exits 3" {
  # Copy launcher to temp dir without the init file.
  local -- d=$TEST_HOME/launcher
  mkdir -p "$d"
  cp "$PROJECT_DIR/slash-bash" "$d/slash-bash"
  run "$d/slash-bash" --help
  # --help short-circuits before init check, so it should still exit 0.
  assert_success
  # Now invoke without args (would normally exec into the init file).
  # This must exit 3 because $d has no .slash-bash-init.
  run "$d/slash-bash"
  assert_failure 3
  assert_output --partial "init file missing"
}

#fin
