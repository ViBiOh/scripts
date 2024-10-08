#!/usr/bin/env bash

set -o nounset -o pipefail -o errexit

if [[ ${TRACE:-0} == "1" ]]; then
  set -o xtrace
fi

main() {
  local REMOTE_DEPENDENCIES_URL="https://raw.githubusercontent.com/ViBiOh/scripts/main/"
  local SCRIPTS_PATH="./scripts"

  printf -- "Bootstrapping to %s\n" "${SCRIPTS_PATH}"

  local SCRIPTS_CLEAN

  OPTIND=0
  while getopts ":c" option; do
    case "${option}" in
    c)
      SCRIPTS_CLEAN="true"
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

  if [[ ${SCRIPTS_CLEAN:-} == "true" ]]; then
    rm -rf "${SCRIPTS_PATH}"
  fi

  mkdir -p "${SCRIPTS_PATH}"

  (
    cd "${SCRIPTS_PATH}"

    curl --disable --silent --show-error --location --max-time 30 --output "./meta" -- "${REMOTE_DEPENDENCIES_URL}/functions/meta"
    source "./meta" && meta_init "${@}"
  )
}

shift $((OPTIND - 1))

main "${@}"
