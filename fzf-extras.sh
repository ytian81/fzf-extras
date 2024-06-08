#!/usr/bin/env bash


# -----------------------------------------------------------------------------
# directory
# -----------------------------------------------------------------------------

# fzf --preview command for file and directory
if type bat >/dev/null 2>&1; then
    FZF_PREVIEW_CMD='bat --color=always --plain --line-range :$FZF_PREVIEW_LINES {}'
elif type pygmentize >/dev/null 2>&1; then
    FZF_PREVIEW_CMD='head -n $FZF_PREVIEW_LINES {} | pygmentize -g'
else
    FZF_PREVIEW_CMD='head -n $FZF_PREVIEW_LINES {}'
fi

# zdd - cd to selected directory
zdd() {
  local dir
  dir="$(
    find "${1:-.}" -path '*/\.*' -prune -o -type d -print 2> /dev/null \
      | fzf +m \
          --preview='tree -C {} | head -n $FZF_PREVIEW_LINES' \
          --preview-window='right:wrap' \
          --bind=ctrl-v:toggle-preview \
          --bind=ctrl-x:toggle-sort \
          --header='(view:ctrl-v) (sort:ctrl-x)' \
  )" || return
  cd "$dir" || return
}

# zda - including hidden directories
zda() {
  local dir
  dir="$(
    find "${1:-.}" -type d 2> /dev/null \
      | fzf +m \
          --preview='tree -C {} | head -n $FZF_PREVIEW_LINES' \
          --preview-window='right:wrap' \
          --bind=ctrl-v:toggle-preview \
          --bind=ctrl-x:toggle-sort \
          --header='(view:ctrl-v) (sort:ctrl-x)' \
  )" || return
  cd "$dir" || return
}

# zdr - cd to selected parent directory
zdr() {
  local dirs=()
  local parent_dir

  get_parent_dirs() {
    if [[ -d "$1" ]]; then dirs+=("$1"); else return; fi
    if [[ "$1" == '/' ]]; then
      for _dir in "${dirs[@]}"; do echo "$_dir"; done
    else
      get_parent_dirs "$(dirname "$1")"
    fi
  }

  parent_dir="$(
    get_parent_dirs "$(realpath "${1:-$PWD}")" \
      | fzf +m \
          --preview 'tree -C {} | head -n $FZF_PREVIEW_LINES' \
          --preview-window='right:wrap' \
          --bind=ctrl-v:toggle-preview \
          --bind=ctrl-x:toggle-sort \
          --header='(view:ctrl-v) (sort:ctrl-x)' \
  )" || return

  cd "$parent_dir" || return
}

# zst - cd into the directory from stack
zst() {
  local dir
  dir="$(
    dirs \
      | sed 's#\s#\n#g' \
      | uniq \
      | sed "s#^~#$HOME#" \
      | fzf +s +m -1 -q "$*" \
            --preview='tree -C {} | head -n $FZF_PREVIEW_LINES' \
            --preview-window='right:wrap' \
            --bind=ctrl-v:toggle-preview \
            --bind=ctrl-x:toggle-sort \
            --header='(view:ctrl-v) (sort:ctrl-x)' \
  )"
  # check $dir exists for Ctrl-C interrupt
  # or change directory to $HOME (= no value cd)
  if [[ -d "$dir" ]]; then
    cd "$dir" || return
  fi
}

# zdf - cd into the directory of the selected file
zdf() {
  local file
  file="$(fzf +m -q "$*" \
           --preview="${FZF_PREVIEW_CMD}" \
           --preview-window='right:wrap' \
           --bind=ctrl-v:toggle-preview \
           --bind=ctrl-x:toggle-sort \
           --header='(view:ctrl-v) (sort:ctrl-x)' \
       )"
  cd "$(dirname "$file")" || return
}

# zz - selectable cd to frecency directory
zz() {
  local dir

  dir="$(
    fasd -dl | rg $PWD \
      | fzf \
          --tac \
          --reverse \
          --select-1 \
          --no-sort \
          --no-multi \
          --tiebreak=index \
          --bind=ctrl-x:toggle-sort \
          --query "$*" \
          --preview='tree -C {} | head -n $FZF_PREVIEW_LINES' \
          --preview-window='right:hidden:wrap' \
          --bind=ctrl-v:toggle-preview \
          --bind=ctrl-x:toggle-sort \
          --header='(view:ctrl-v) (sort:ctrl-x)' \
  )" || return

  cd "$dir" || return
}

# zd - cd into selected directory with options
# The super function of zdd, zda, zdr, zst, zdf, zz
zd() {
  read -r -d '' helptext <<EOF
usage: zd [OPTIONS]
  zd: cd to selected options below
OPTIONS:
  -d [path]: Directory (default)
  -a [path]: Directory included hidden
  -r [path]: Parent directory
  -s [query]: Directory from stack
  -f [query]: Directory of the selected file
  -z [query]: Frecency directory
  -h: Print this usage
EOF

  usage() {
    echo "$helptext"
  }

  if [[ -z "$1" ]]; then
    # no arg
    zdd
  elif [[ "$1" == '..' ]]; then
    # arg is '..'
    shift
    zdr "$1"
  elif [[ "$1" == '-' ]]; then
    # arg is '-'
    shift
    zst "$*"
  elif [[ "${1:0:1}" != '-' ]]; then
    # first string is not -
    zdd "$(realpath "$1")"
  else
    # args is start from '-'
    while getopts darfszh OPT; do
      case "$OPT" in
        d) shift; zdd  "$1";;
        a) shift; zda "$1";;
        r) shift; zdr "$1";;
        s) shift; zst "$*";;
        f) shift; zdf "$*";;
        z) shift; zz  "$*";;
        h) usage; return 0;;
        *) usage; return 1;;
      esac
    done
  fi
}

zle -N zdd
bindkey '^g' zdd

# -----------------------------------------------------------------------------
# file
# -----------------------------------------------------------------------------

# e - open 'frecency' files in $VISUAL editor
e() {
  local IFS=$'\n'
  local files=()

  files=(
  "$(
    fasd -fl | rg $PWD \
      | fzf \
          --tac \
          --reverse -1 \
          --no-sort \
          --multi \
          --tiebreak=index \
          --bind=ctrl-x:toggle-sort \
          --query "$*" \
          --preview="${FZF_PREVIEW_CMD}" \
          --preview-window='right:hidden:wrap' \
          --bind=ctrl-v:toggle-preview \
          --bind=ctrl-x:toggle-sort \
          --header='(view:ctrl-v) (sort:ctrl-x)' \
      )"
  ) || return

  "${EDITOR:-vim}" "${files[@]}"
}

# fe [FUZZY PATTERN] - Open the selected file with the default editor
#   - Bypass fuzzy finder if there's only one match (--select-1)
#   - Exit if there's no match (--exit-0)
fe() {
  local IFS=$'\n'
  local files=()
  files=(
    "$(rg --files --follow --ignore-vcs > /dev/null 2>&1 | fzf \
          --query="$1" \
          --multi \
          --select-1 \
          --exit-0 \
          --preview="bat --style=numbers --color=always --line-range :500 {}" \
          --preview-window='right:nohidden:nowrap' \
    )"
  ) || return
  "${EDITOR:-vim}" "${files[@]}"
}

zle -N fe
bindkey '^f' fe

# fo - Modified version of fe() where you can press
#   - CTRL-O to open with $OPENER,
#   - CTRL-E or Enter key to open with $EDITOR
fo() {
  local IFS=$'\n'
  local out=()
  local key
  local file

  out=(
    "$(
        fzf \
          --query="$1" \
          --exit-0 \
          --expect=ctrl-o,ctrl-e
    )"
  )
  key="$(head -1 <<< "${out[@]}")"
  file="$(head -2 <<< "${out[@]}" | tail -1)" || return

  if [[ "$key" == ctrl-o ]]; then
    "${OPENER:-xdg-open}" "$file"
  else
    "${EDITOR:-vim}" "$file"
  fi
}

# v - open files in ~/.viminfo
v() {
  local files
  files="$(
    grep '^>' "$HOME/.viminfo" \
      | cut -c3- \
      | while read -r line; do
          [[ -f "${line/\~/$HOME}" ]] && echo "$line"
        done \
      | fzf -m -0 -1 -q "$*"
  )"
  "${EDITOR:-vim}" "${files/\~/$HOME}"
}

# -----------------------------------------------------------------------------
# history
# -----------------------------------------------------------------------------

# runcmd - utility function used to run the command in the shell
runcmd() {
  perl -e 'ioctl STDOUT, 0x5412, $_ for split //, <>'
}

# fh - repeat history
fh() {
  ([[ -n "$ZSH_NAME" ]] && fc -l 1 || history) \
    | fzf +s --tac \
    | sed -re 's/^\s*[0-9]+\s*//' \
    | runcmd
}

# writecmd - utility function used to write the command in the shell
writecmd() {
  perl -e 'ioctl STDOUT, 0x5412, $_ for split //, do { chomp($_ = <>); $_ }'
}

# fhe - repeat history edit
fhe() {
  ([[ -n "$ZSH_NAME" ]] && fc -l 1 || history) \
    | fzf +s --tac \
    | sed -re 's/^\s*[0-9]+\s*//' \
    | writecmd
}


# -----------------------------------------------------------------------------
# pid
# -----------------------------------------------------------------------------

# fkill - kill process
fkill() {
  local pid

  pid="$(
    ps -ef \
      | sed 1d \
      | fzf -m \
      | awk '{print $2}'
  )" || return

  kill -"${1:-9}" "$pid"
}


# -----------------------------------------------------------------------------
# tags
# -----------------------------------------------------------------------------

# ftags - search ctags
ftags() {
  local line

  [[ -e 'tags' ]] || return

  line="$(
    awk 'BEGIN { FS="\t" } !/^!/ {print toupper($4)"\t"$1"\t"$2"\t"$3}' tags \
      | cut -c1-"$COLUMNS" \
      | fzf --nth=2 --tiebreak=begin
  )" || return

  "${EDITOR:-vim}" "$(cut -f3 <<< "$line")" \
    -c 'set nocst' \
    -c "silent tag \"$(cut -f2 <<< "$line")\""
}


# -----------------------------------------------------------------------------
# tmux
# -----------------------------------------------------------------------------

# fs [FUZZY PATTERN] - Select selected tmux session
#   - Bypass fuzzy finder if there's only one match (--select-1)
#   - Exit if there's no match (--exit-0)
fs() {
  local session

  session="$(
    tmux list-sessions -F "#{session_name}" \
      | fzf \
          -p \
          --query="$1" \
          --select-1 \
          --exit-0
  )" || return

  if [[ -z "$TMUX" ]]; then
      tmux attach -t "$session"
  else 
      tmux switch-client -t "$session"
  fi
}

zle -N fs
bindkey '^s' fs

# ftpane - switch pane (@george-b)
ftpane() {
  local panes
  local current_window
  local current_pane
  local target
  local target_window
  local target_pane

  panes="$(
    tmux list-panes \
      -s \
      -F '#I:#P - #{pane_current_path} #{pane_current_command}'
  )"
  current_pane="$(tmux display-message -p '#I:#P')"
  current_window="$(tmux display-message -p '#I')"

  target="$(
    echo "$panes" \
      | grep -v "$current_pane" \
      | fzf +m --reverse
  )" || return

  target_window="$(
    echo "$target" \
      | awk 'BEGIN{FS=":|-"} {print$1}'
  )"

  target_pane="$(
    echo "$target" \
      | awk 'BEGIN{FS=":|-"} {print$2}' \
      | cut -c 1
  )"

  if [[ "$current_window" -eq "$target_window" ]]; then
    tmux select-pane -t "$target_window.$target_pane"
  else
    tmux select-pane -t "$target_window.$target_pane" \
      && tmux select-window -t "$target_window"
  fi
}

# vim: set filetype=sh foldmethod=marker foldlevel=0:
