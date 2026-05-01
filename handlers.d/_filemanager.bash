#!/usr/bin/bash
#shellcheck shell=bash disable=SC2034
# handlers.d/_filemanager.bash - /filemanager [options] [<dirpath>]
# + /fm alias. Launches the user's default GUI file manager (via
# xdg-open) on <dirpath>, defaulting to $PWD when omitted. The launch
# is detached (nohup + & + disown) so the GUI lives independently of
# the slash-bash session.

_sb_cmd_filemanager() {
  # __sb_dispatch passes the entire arg string as a single $1; re-split
  # so we can parse "-n /path" without inline string surgery. Trailing
  # word(s) are re-joined as the dirpath (preserves whitespace as well
  # as the rest of the codebase does, which is "the input was already
  # space-joined when it arrived").
  local -a tokens=()
  read -ra tokens <<<"${1:-}"

  local -i dry_run=0 want_help=0
  while ((${#tokens[@]})); do
    case ${tokens[0]} in
      -h|--help) want_help=1 ;;
      -n|--dry-run) dry_run=1 ;;
      --) tokens=("${tokens[@]:1}"); break ;;
      -*) _error "unknown option: ${tokens[0]@Q}"; return 22 ;;
      *) break ;;
    esac
    tokens=("${tokens[@]:1}")
  done

  if ((want_help)); then
    cat <<'USAGE'
/filemanager [-h|--help] [-n|--dry-run] [--] [<dirpath>]
  alias: /fm

  Launch the default GUI file manager (via xdg-open) on <dirpath>, or
  $PWD if omitted. The GUI is detached - control returns immediately.

Options:
  -h, --help     show this help
  -n, --dry-run  print what would launch, do not run it
  --             end of options (paths starting with '-' need this)
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
  if ! command -v xdg-open >/dev/null; then
    _error 'xdg-open not in PATH (install xdg-utils)'
    return 1
  fi
  if [[ -z ${DISPLAY:-}${WAYLAND_DISPLAY:-} ]]; then
    _error 'no display detected (DISPLAY and WAYLAND_DISPLAY both unset)'
    return 1
  fi

  if ((dry_run)); then
    printf 'would run: xdg-open %q\n' "$dir"
    return 0
  fi

  # nohup detaches from the controlling terminal; & runs in background;
  # disown removes it from the shell's job table so an `exit` won't
  # trigger SIGHUP. Stdout/stderr to /dev/null so xdg-open chatter
  # doesn't pollute the prompt line.
  nohup xdg-open "$dir" >/dev/null 2>&1 &
  disown
  printf 'launched file manager at: %s\n' "$dir"
}

_sb_complete_filemanager() {
  local -- cur=${COMP_WORDS[COMP_CWORD]}
  COMPREPLY=()
  if [[ $cur == -* ]]; then
    readarray -t COMPREPLY < <(compgen -W '-h --help -n --dry-run --' -- "$cur")
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
_SB_HELP[/filemanager]='launch GUI file manager on <dirpath> (default: $PWD)'
_SB_COMPLETE[/filemanager]=_sb_complete_filemanager
_SB_COMPLETE[/fm]=_sb_complete_filemanager

#fin
