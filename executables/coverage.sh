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

  (
    printf -- "%s\n" "${MODE}" >"${COVERAGE_OUTPUT}"

    for pkg in $(go list "${PACKAGES:-./...}"); do
      go test -count=1 -race -covermode="${COVER_MODE}" -coverprofile="${COVER_PROFILE}" "${pkg}"

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
