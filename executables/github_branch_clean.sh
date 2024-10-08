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
  source "$(script_dir)/meta" && meta_check "var" "http"

  local dryRun="true"

  OPTIND=0
  while getopts ":a" option; do
    case "${option}" in
    a)
      dryRun="false"
      ;;
    :)
      printf -- "option -%s requires a value\n" "${OPTARG}" >&2
      return 1
      ;;
    \?)
      printf -- "option -%s is invalid\n" "${OPTARG}" >&2
      return 2
      ;;
    esac
  done

  shift $((OPTIND - 1))

  if [[ ${#} -lt 1 ]]; then
    var_red "Usage: ${0} [-d for dry run] ORGANIZATION PAGE?"
    return 1
  fi

  local ORGANIZATION=${1}
  shift

  local GITHUB_TOKEN
  GITHUB_TOKEN="$(github_token)"

  http_init_client --header "Authorization: token ${GITHUB_TOKEN}" -H "Accept: application/vnd.github.v3+json"

  http_request "https://api.github.com/user"
  if [[ ${HTTP_STATUS} != "200" ]]; then
    http_handle_error "Unable to get user details"
    return 1
  fi

  local USER
  USER="$(jq --raw-output '.login' "${HTTP_OUTPUT}")"
  rm "${HTTP_OUTPUT}"

  local pr_page=${1-}
  local pr_page_size=100
  local pr_count="${pr_page_size}"

  while [[ pr_count -eq ${pr_page_size} ]]; do
    pr_page=$((pr_page + 1))

    var_info "Fetching page ${pr_page} of pull-requests"

    http_request "https://api.github.com/search/issues" -G --data-urlencode "q=is:pr author:${USER} archived:false is:closed user:${ORGANIZATION}" --data-urlencode "per_page=${pr_page_size}" --data-urlencode "page=${pr_page}"
    if [[ ${HTTP_STATUS} != "200" ]]; then
      http_handle_error "Unable to list pull-requests on page ${pr_page}"
      return 1
    fi

    pr_count="$(jq --raw-output '.items | length' "${HTTP_OUTPUT}")"
    if [[ ${pr_count} -eq 0 ]]; then
      rm "${HTTP_OUTPUT}"
      break
    fi

    local PULL_REQUESTS
    mapfile -t PULL_REQUESTS < <(jq --raw-output '.items[].pull_request.url' "${HTTP_OUTPUT}")
    rm "${HTTP_OUTPUT}"

    for PR in "${PULL_REQUESTS[@]}"; do
      http_request "${PR}"
      if [[ ${HTTP_STATUS} != "200" ]]; then
        http_handle_error "Unable to fetch pull-request ${PR}"
        return 1
      fi

      local BRANCH
      BRANCH="$(jq --raw-output '.head.ref' "${HTTP_OUTPUT}")"
      local REPO
      REPO="$(jq --raw-output '.head.repo.full_name' "${HTTP_OUTPUT}")"
      rm "${HTTP_OUTPUT}"

      http_request "https://api.github.com/repos/${REPO}/branches/${BRANCH}"
      if [[ ${HTTP_STATUS} != "404" ]]; then
        if [[ ${dryRun} == "true" ]]; then
          var_warning "Branches can be cleaned here https://github.com/${REPO}/branches/yours"
          continue
        fi

        var_warning "Deleting branch ${BRANCH} on ${REPO}..."

        http_request --request DELETE "https://api.github.com/repos/${REPO}/git/refs/heads/${BRANCH}"
        if [[ ${HTTP_STATUS} != "204" ]]; then
          http_handle_error "Unable to delete branch"
          return 1
        fi

        rm "${HTTP_OUTPUT}"
      fi
    done
  done
}

main "${@}"
