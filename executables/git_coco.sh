#!/usr/bin/env bash

set -o nounset -o pipefail -o errexit

if [[ ${TRACE:-0} == "1" ]]; then
  set -o xtrace
fi

guess_component() {
  local COMPONENTS=()

  add_part() {
    local WORDS=()
    read -r -a WORDS <<<"$(printf -- "%s" "${1}" | sed 's|_| |g;s|-| |g;s|\.| |g')"

    COMPONENTS=("${COMPONENTS[@]}" "${WORDS[@]}")
  }

  for file in $(git diff --name-only --cached); do
    add_part "$(basename "${file%.*}")"

    local FILE_DIR
    FILE_DIR="$(dirname "${file}")"

    while [[ ${FILE_DIR} != "." ]]; do
      add_part "$(basename "${FILE_DIR}")"
      FILE_DIR="$(dirname "${FILE_DIR}")"
    done
  done

  printf -- "%s\n" "${COMPONENTS[@]}" | sort | uniq
}

is_github() {
  local GIT_REMOTE
  GIT_REMOTE="$(git remote show | head -1)"

  if [[ -z ${GIT_REMOTE:-} ]]; then
    return 1
  fi

  if [[ "$(git remote get-url --push "${GIT_REMOTE}")" =~ ^.*@github.com:(.*)/(.*)$ ]]; then
    return 0
  else
    return 1
  fi
}

get_issue() {
  http_request "https://api.github.com/repos/$(git_remote_repository)/issues?per_page=100"

  if [[ ${HTTP_STATUS} != "200" ]]; then
    http_handle_error "Unable to list issues"
    return
  fi

  if [[ $(jq --raw-output '[.[] | select(.pull_request | not)] | length' "${HTTP_OUTPUT}") -eq 0 ]]; then
    rm "${HTTP_OUTPUT}"
    return
  fi

  ISSUES="$(cat <(printf -- "None\n") <(jq --raw-output '.[] | select(.pull_request | not) | "#" + (.number | tostring) + " " + .title' "${HTTP_OUTPUT}") | fzf --height=20 --ansi --reverse --multi --prompt='Closes> ' | awk '{printf("%s", $1)}')"
  rm "${HTTP_OUTPUT}"

  if [[ ${ISSUES} != "None" ]]; then
    printf -- "\n\nCloses %s" "${ISSUES}"
  fi
}

get_co_author() {
  http_request "https://api.github.com/repos/$(git_remote_repository)/contributors?per_page=100"

  if [[ ${HTTP_STATUS} != "200" ]]; then
    http_handle_error "Unable to list contributors"
    return
  fi

  if [[ $(jq --raw-output 'length' "${HTTP_OUTPUT}") -eq 0 ]]; then
    rm "${HTTP_OUTPUT}"
    return
  fi

  local CO_AUTHOR=""
  CO_AUTHOR="$(cat <(printf -- "None\nOther\n") <(jq --raw-output '.[] | .login' "${HTTP_OUTPUT}") | fzf --height=20 --ansi --reverse --prompt='Co-Author>')"
  rm "${HTTP_OUTPUT}"

  if [[ ${CO_AUTHOR} == "None" ]]; then
    return
  fi

  if [[ ${CO_AUTHOR} == "Other" ]]; then
    var_read "CO_AUTHOR"
  fi

  http_request "https://api.github.com/users/${CO_AUTHOR}/events?per_page=100"
  if [[ ${HTTP_STATUS} != "200" ]]; then
    http_handle_error "Unable to get user's events"
    return
  fi

  CO_AUTHOR_EMAIL="$(jq --raw-output '.[] | select(.type == "PushEvent") | .payload.commits[] | .author.name + "<" + .author.email + ">"' "${HTTP_OUTPUT}" | sort | uniq | grep -v '\[bot\]' | fzf --height=20 --ansi --reverse --prompt='Email> ')"
  rm "${HTTP_OUTPUT}"

  if [[ -n ${CO_AUTHOR_EMAIL} ]]; then
    printf -- "\n\nCo-authored-by: %s" "${CO_AUTHOR_EMAIL}"
  fi
}

script_dir() {
  local FILE_SOURCE="${BASH_SOURCE[0]}"

  if [[ -L ${FILE_SOURCE} ]]; then
    dirname "$(readlink "${FILE_SOURCE}")"
  else
    (
      cd "$(dirname "${FILE_SOURCE}")" && pwd
    )
  fi
}

init_github_client() {
  http_init_client

  local GITHUB_TOKEN
  GITHUB_TOKEN="$(github_token)"

  if [[ -n ${GITHUB_TOKEN} ]]; then
    HTTP_CLIENT_ARGS+=("--header" "Authorization: token ${GITHUB_TOKEN}")
  fi
}

main() {
  source "$(script_dir)/meta" && meta_check "var" "git" "github" "http"

  if ! git_is_inside; then
    var_error "not inside a git tree"
    return 1
  fi

  git_is_valid_description "value"

  local REMAINING_LENGTH=$((COMMIT_MAX_LENGTH - 1))

  local SCOPE
  SCOPE="$(for i in "${!CONVENTIONAL_COMMIT_SCOPES[@]}"; do printf -- "%b%s%b %s\n" "${GREEN}" "${i}" "${RESET}" "${CONVENTIONAL_COMMIT_SCOPES[${i}]}"; done | fzf --height=20 --ansi --reverse --prompt "Scope: " | awk '{printf("%s", $1)}')"

  if [[ -z ${SCOPE} ]]; then
    return 1
  fi

  printf -- "SCOPE=%s\n" "${SCOPE}"
  REMAINING_LENGTH=$((REMAINING_LENGTH - ${#SCOPE}))

  local COMPONENT=""
  COMPONENT="$(cat <(guess_component) <(printf -- "None") | fzf --height=20 --ansi --reverse --prompt='Component:')"

  if [[ ${COMPONENT} == "None" ]]; then
    COMPONENT=""
  else
    printf -v COMPONENT -- "(%s)" "${COMPONENT}"
  fi
  printf -- "COMPONENT=%s\n" "${COMPONENT}"
  REMAINING_LENGTH=$((REMAINING_LENGTH - ${#COMPONENT}))

  local SKIP_CI=""
  if var_confirm "Skip CI"; then
    SKIP_CI="[skip ci] "
    REMAINING_LENGTH=$((REMAINING_LENGTH - ${#SKIP_CI}))
  fi

  local BREAKING=""
  if var_confirm "Contains breaking changes"; then
    BREAKING="!"
    REMAINING_LENGTH=$((REMAINING_LENGTH - ${#BREAKING}))
  fi

  local MESSAGE=""
  printf -- "%d characters remaining\n" "${REMAINING_LENGTH}"
  var_read MESSAGE

  local ISSUES_STRING=""
  local CO_AUTHOR_STRING=""

  if is_github; then
    if var_confirm "Link issue"; then
      init_github_client
      ISSUES_STRING="$(get_issue)"
    fi

    if var_confirm "Define co-author"; then
      init_github_client
      CO_AUTHOR_STRING="$(get_co_author)"
    fi
  fi

  var_print_and_run git commit --signoff --message \""$(printf -- "%s%s%s: %s%b%b%b" "${SCOPE}" "${COMPONENT}" "${BREAKING}" "${SKIP_CI}" "${MESSAGE}" "${ISSUES_STRING}" "${CO_AUTHOR_STRING}")"\" "${@}"
}

main "${@}"
