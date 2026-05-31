# Makefile - slash-bash dev workflow targets.
#
# Targets:
#   test           Run the bats suite (281 cases; the 4 PTY e2e cases skip
#                  unless BATS_E2E=1, which runs the chord-trick verification).
#   lint           shellcheck -x on every bash file in the project + tests/.
#   audit          bcscheck on the library (BCS, LLM-backed, slow).
#   check          lint + test (the default pre-merge gate).
#   install        System install: copies runtime files to $(APPDIR), creates
#                  symlinks in $(BINDIR). Honours PREFIX / DESTDIR.
#   uninstall      Remove the named files and symlinks created by 'install'.
#   check-install  Smoke test for an in-place install (skipped when DESTDIR set).
#
# The bash 5+ requirement is enforced by individual .bats files; the suite
# does not require a Makefile-level guard.

.PHONY: test test-e2e lint audit check help install uninstall check-install
.DEFAULT_GOAL := help

BASH_FILES = slash-bash.bash slash-bash .slash-bash-init claude-sessions \
             tests/test_helper.bash $(wildcard handlers.d/*.bash)

PREFIX   ?= /usr/local
BINDIR   ?= $(PREFIX)/bin
SHAREDIR ?= $(PREFIX)/share
APPDIR   := $(SHAREDIR)/slash-bash
DESTDIR  ?=

INSTALL         ?= install
INSTALL_PROGRAM ?= $(INSTALL) -m 755
INSTALL_DATA    ?= $(INSTALL) -m 644
INSTALL_DIR     ?= $(INSTALL) -d -m 755
LN_SF           ?= ln -sfn

HANDLER_FILES := $(wildcard handlers.d/_*.bash)

test:
	@bats tests/

test-e2e:
	@BATS_E2E=1 bats tests/e2e_chord.bats

lint:
	@shellcheck -x $(BASH_FILES) tests/mocks/*

audit:
	@bcscheck slash-bash.bash

check: lint test

install:
	$(INSTALL_DIR) $(DESTDIR)$(APPDIR) $(DESTDIR)$(APPDIR)/handlers.d $(DESTDIR)$(BINDIR)
	$(INSTALL_PROGRAM) slash-bash      $(DESTDIR)$(APPDIR)/slash-bash
	$(INSTALL_PROGRAM) claude-sessions $(DESTDIR)$(APPDIR)/claude-sessions
	$(INSTALL_DATA)    slash-bash.bash  $(DESTDIR)$(APPDIR)/slash-bash.bash
	$(INSTALL_DATA)    .slash-bash-init $(DESTDIR)$(APPDIR)/.slash-bash-init
	$(INSTALL_DATA)    bash-preexec.sh  $(DESTDIR)$(APPDIR)/bash-preexec.sh
	@for f in $(HANDLER_FILES); do \
	  $(INSTALL_DATA) "$$f" $(DESTDIR)$(APPDIR)/handlers.d/; \
	done
	$(LN_SF) $(APPDIR)/slash-bash      $(DESTDIR)$(BINDIR)/slash-bash
	$(LN_SF) $(APPDIR)/claude-sessions $(DESTDIR)$(BINDIR)/claude-sessions
	@echo "installed to $(DESTDIR)$(APPDIR); symlinks in $(DESTDIR)$(BINDIR)"

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/slash-bash $(DESTDIR)$(BINDIR)/claude-sessions
	rm -f $(DESTDIR)$(APPDIR)/slash-bash $(DESTDIR)$(APPDIR)/claude-sessions
	rm -f $(DESTDIR)$(APPDIR)/slash-bash.bash $(DESTDIR)$(APPDIR)/.slash-bash-init
	rm -f $(DESTDIR)$(APPDIR)/bash-preexec.sh
	rm -f $(DESTDIR)$(APPDIR)/handlers.d/*.bash
	rmdir $(DESTDIR)$(APPDIR)/handlers.d 2>/dev/null || true
	rmdir $(DESTDIR)$(APPDIR)            2>/dev/null || true
	@echo "uninstalled from $(DESTDIR)$(APPDIR) and $(DESTDIR)$(BINDIR)"

check-install:
	@if [ -n "$(DESTDIR)" ]; then echo "check-install: skipped (DESTDIR set)"; exit 0; fi
	@command -v slash-bash >/dev/null || { echo "FAIL: slash-bash not in PATH"; exit 1; }
	@slash-bash --version | grep -qE '[0-9]+\.[0-9]+\.[0-9]+' || { echo "FAIL: --version did not print version"; exit 1; }
	@command -v claude-sessions >/dev/null || { echo "FAIL: claude-sessions not in PATH"; exit 1; }
	@echo "check-install: ok"

help:
	@echo 'Targets:'
	@echo '  test           Run bats suite (281 cases; 4 e2e skip without BATS_E2E)'
	@echo '  test-e2e       Run BATS_E2E=1 PTY chord tests (needs expect)'
	@echo '  lint           shellcheck -x all bash files'
	@echo '  audit          bcscheck slash-bash.bash (slow, LLM-backed)'
	@echo '  check          lint + test'
	@echo '  install        Install to $(DESTDIR)$(APPDIR) + symlinks in $(DESTDIR)$(BINDIR)'
	@echo '  uninstall      Remove files installed by '\''install'\'''
	@echo '  check-install  Smoke-test an in-place install (skipped when DESTDIR set)'
	@echo
	@echo 'Install variables (override on command line):'
	@echo '  PREFIX=$(PREFIX)  BINDIR=$(BINDIR)  SHAREDIR=$(SHAREDIR)  DESTDIR=$(DESTDIR)'
