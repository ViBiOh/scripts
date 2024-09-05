#!/usr/bin/env bash

set -o nounset -o pipefail -o errexit

if [[ ${TRACE:-0} == "1" ]]; then
  set -o xtrace
fi

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

main() {
  source "$(script_dir)/meta" && meta_check "var" "git"

  local BASE="${1:-main}"
  shift || true
  local HEAD="${1:-$(git branch --show-current)}"
  shift || true

  local UNCLEAR="false"
  IFS=$'\n'

  for commit in $(git log --pretty=format:'%s' "${BASE}..${HEAD}"); do
    printf -- "%bAnalyzing %b%s%b\n" "${BLUE}" "${YELLOW}" "${commit}" "${RESET}"

    if git_is_merge_commit "${commit}"; then
      var_warning "\tmerge commit, ignoring"
      continue
    fi

    if git_is_commit_wip "${commit}"; then
      var_red "\twip commit, please rebase"
      UNCLEAR="true"
      continue
    fi

    if ! git_is_conventional_commit "${commit}"; then
      printf -- "\t%bnot a conventional commit, please reword according to %bconventionalcommits.org/en/v1.0.0/%b\n" "${RED}" "${GREEN}" "${RESET}" 1>&2
      UNCLEAR="true"
    fi

    if ! git_is_valid_description "${commit}"; then
      printf -- "\t%btoo long, please reword below %b%s characters%b, currently %d%b\n" "${RED}" "${GREEN}" "${COMMIT_MAX_LENGTH:-70}" "${YELLOW}" "${#commit}" "${RESET}" 1>&2
      UNCLEAR="true"
    fi
  done

  if [[ ${UNCLEAR} == "true" ]]; then
    exit 1
  fi

  var_success "Everything looks fine!"
  exit 0
}

main "${@}"
