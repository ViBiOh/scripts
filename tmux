#!/usr/bin/env bash

tmux_is_inside() {
  if [[ -z ${TMUX:-} ]]; then
    return 1
  fi

  return 0
}

tmux_split_cmd() (
  if ! tmux_is_inside; then
    printf "not inside a tmux\n"
    return 1
  fi

  tmux split-window -hd -t "${TMUX_PANE}" "bash --rcfile <(echo '. ~/.bash_profile;${*}')" && tmux select-layout tiled
)
