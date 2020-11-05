#!/usr/bin/env bash

TMUX_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

tmux_is_inside() {
  if [[ -z ${TMUX:-} ]]; then
    return 1
  fi

  return 0
}

tmux_split_cmd() (
  source "${TMUX_SCRIPT_DIR}/meta" && meta_init "var"
  var_color

  if ! tmux_is_inside; then
    var_warning "not inside a tmux"
    return 1
  fi

  var_read SCRIPT_DIR
  tmux split-window -hd -c "${SCRIPT_DIR}" -t "${TMUX_PANE}" "bash --rcfile <(echo '. ~/.bash_profile;${*}')" && tmux select-layout tiled
)
