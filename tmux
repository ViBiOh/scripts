#!/usr/bin/env bash

TMUX_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

tmux_is_inside() {
  if [[ -z "${TMUX:-}" ]]; then
    printf "false"
  fi
  printf "true"
}

tmux_split_cmd() (
  source "${TMUX_SCRIPT_DIR}/meta" && meta_init "var"
  var_color

  if [[ $(tmux_is_inside) == "true" ]]; then
    printf "%bnot inside a tmux%b\n" "${RED}" "${RESET}"
    return 1
  fi

  var_read SCRIPT_DIR
  tmux split-window -hd -c "${SCRIPT_DIR}" -t "${TMUX_PANE}" "bash --rcfile <(echo '. ~/.bash_profile;${*}')" && tmux select-layout tiled
)
