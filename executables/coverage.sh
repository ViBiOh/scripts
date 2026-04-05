#!/usr/bin/env bash

set -o nounset -o pipefail -o errexit

if [[ ${TRACE:-0} == "1" ]]; then
  set -o xtrace
fi

main() {
  local COVERAGE_OUTPUT="coverage.txt"
  local COVER_PROFILE="profile.out"
  local COVER_MODE="atomic"
  local MODE="mode: ${COVER_MODE}"

  local TEST_OPTIONS=("-covermode=${COVER_MODE}" "-coverprofile=${COVER_PROFILE}")

  if [[ ${GO_TEST_NO_RACE:-} != "true" ]]; then
    TEST_OPTIONS+=("-race")
  fi

  (
    printf -- "%s\n" "${MODE}" >"${COVERAGE_OUTPUT}"

    printf -- "Running tests for '%s' with options\n" "${PACKAGES:-./...}" >/dev/stderr
    printf -- "\t%s\n" "${TEST_OPTIONS[@]}" >/dev/stderr

    for pkg in $(go list "${PACKAGES:-./...}"); do
      go test -count=1 "${TEST_OPTIONS[@]}" "${pkg}"

      if [[ -f ${COVER_PROFILE} ]]; then
        grep --invert-match "${MODE}" "${COVER_PROFILE}" >>"${COVERAGE_OUTPUT}" || true
        rm "${COVER_PROFILE}"
      fi
    done

    if [[ $(wc -l <"${COVERAGE_OUTPUT}") -ne 1 ]]; then
      go tool cover -func="${COVERAGE_OUTPUT}"
    fi
  )
}

main
