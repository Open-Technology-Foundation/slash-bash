#!/usr/bin/bash
#shellcheck shell=bash disable=SC2034
# handlers.d/_filemanager.bash - /filemanager [options] [<dirpath>]
# + /fm alias. Launches a file manager on <dirpath> (default $PWD).
#
# Mode auto-detection:
#   GUI when $DISPLAY or $WAYLAND_DISPLAY is set: nohup xdg-open <dir>
#     & disown (detached, GUI lives past this shell).
#   TUI otherwise (or with -t/--tui): probes $SB_FILEMANAGER, mc,
#     ranger, nnn, lf, vifm in that order; first found wins. Foreground
#     - the TUI takes over the terminal, slash-bash regains control
#     when the user quits it.
#
# Override flags: -g/--gui forces GUI; -t/--tui forces TUI. Useful
# under SSH-with-X-forwarding (display set but user prefers in-term).

# Resolve a launchable file manager binary for the requested mode.
# Echoes the binary name on success, returns 1 with empty stdout on
# failure. SB_FILEMANAGER (if set & non-empty) preempts the built-in
# TUI list, matching the `SB_*` env-override convention used by
# SB_AGENT / SB_MODEL elsewhere in the library.
_sb_resolve_filemanager() {
  local -- mode=$1
  if [[ $mode == gui ]]; then
    command -v xdg-open >/dev/null && { printf 'xdg-open\n'; return 0; }
    return 1
  fi
  local -- candidate
  for candidate in "${SB_FILEMANAGER:-}" mc ranger nnn lf vifm; do
    [[ -z $candidate ]] && continue
    command -v "$candidate" >/dev/null && { printf '%s\n' "$candidate"; return 0; }
  done
  return 1
}

_sb_cmd_filemanager() {
  # __sb_dispatch passes the entire arg string as a single $1; re-split
  # so we can parse "-n /path" without inline string surgery. Trailing
  # word(s) are re-joined as the dirpath (preserves whitespace as well
  # as the rest of the codebase does, which is "the input was already
  # space-joined when it arrived").
  local -a tokens=()
  read -ra tokens <<<"${1:-}"

  local -i dry_run=0 want_help=0 force_gui=0 force_tui=0
  while ((${#tokens[@]})); do
    case ${tokens[0]} in
      -h|--help)    want_help=1 ;;
      -n|--dry-run) dry_run=1 ;;
      -g|--gui)     force_gui=1 ;;
      -t|--tui)     force_tui=1 ;;
      --) tokens=("${tokens[@]:1}"); break ;;
      -*) _error "unknown option: ${tokens[0]@Q}"; return 22 ;;
      *) break ;;
    esac
    tokens=("${tokens[@]:1}")
  done

  if ((force_gui && force_tui)); then
    _error '-g/--gui and -t/--tui are mutually exclusive'
    return 22
  fi

  if ((want_help)); then
    cat <<'USAGE'
/filemanager [-h|--help] [-n|--dry-run] [-g|--gui|-t|--tui] [--] [<dirpath>]
  alias: /fm

  Launch a file manager on <dirpath>, or $PWD if omitted.

  Mode auto-detect:
    GUI when $DISPLAY or $WAYLAND_DISPLAY is set (uses xdg-open,
      detached - returns to the shell immediately).
    TUI otherwise. Probes $SB_FILEMANAGER, mc, ranger, nnn, lf, vifm
      in that order; runs in the foreground until quit.

Options:
  -h, --help     show this help
  -n, --dry-run  print what would launch, do not run it
  -g, --gui      force GUI mode (fails if no xdg-open or no display)
  -t, --tui      force TUI mode (fails if no TUI tool found)
  --             end of options (paths starting with '-' need this)

Environment:
  SB_FILEMANAGER  preferred TUI binary; tried before mc/ranger/...
USAGE
    return 0
  fi

  local -- dir
  if ((${#tokens[@]} == 0)); then
    dir=$PWD
  elif ((${#tokens[@]} == 1)); then
    dir=${tokens[0]}
  else
    dir="${tokens[*]}"
  fi

  if [[ ! -d $dir ]]; then
    _error "not a directory: ${dir@Q}"
    return 1
  fi

  # Mode selection: explicit flag > display detection > TUI fallback.
  local -- mode
  if ((force_gui)); then
    mode=gui
  elif ((force_tui)); then
    mode=tui
  elif [[ -n ${DISPLAY:-}${WAYLAND_DISPLAY:-} ]]; then
    mode=gui
  else
    mode=tui
  fi

  local -- bin
  if ! bin=$(_sb_resolve_filemanager "$mode"); then
    case $mode in
      gui) _error 'GUI file manager unavailable (xdg-open not in PATH; install xdg-utils)' ;;
      tui) _error 'no TUI file manager found (searched: SB_FILEMANAGER, mc, ranger, nnn, lf, vifm)' ;;
    esac
    return 1
  fi

  if ((dry_run)); then
    printf 'would run: %s %q (mode=%s)\n' "$bin" "$dir" "$mode"
    return 0
  fi

  case $mode in
    gui)
      # nohup blocks SIGHUP propagation when the shell exits; & puts it
      # in the background; disown removes it from the shell's job table.
      # All three needed for true detach-and-forget.
      nohup "$bin" "$dir" >/dev/null 2>&1 &
      disown
      printf 'launched %s at: %s\n' "$bin" "$dir"
      ;;
    tui)
      # Foreground - TUI owns the terminal until the user quits.
      # No status print after; the TUI's own teardown is the user's
      # cue that control has returned.
      "$bin" "$dir"
      ;;
  esac
}

_sb_complete_filemanager() {
  local -- cur=${COMP_WORDS[COMP_CWORD]}
  COMPREPLY=()
  if [[ $cur == -* ]]; then
    readarray -t COMPREPLY < <(compgen -W '-h --help -n --dry-run -g --gui -t --tui --' -- "$cur")
  else
    # Directory completion with trailing slash for nicer chained tab use.
    readarray -t COMPREPLY < <(compgen -d -- "$cur")
    local -i i
    for i in "${!COMPREPLY[@]}"; do
      COMPREPLY[i]+=/
    done
  fi
}

_SB_HANDLERS[/filemanager]=_sb_cmd_filemanager
_SB_HANDLERS[/fm]=_sb_cmd_filemanager
# shellcheck disable=SC2016
_SB_HELP[/filemanager]='launch file manager on <dirpath> (auto GUI/TUI; default: $PWD)'
_SB_COMPLETE[/filemanager]=_sb_complete_filemanager
_SB_COMPLETE[/fm]=_sb_complete_filemanager

#fin
