#!/usr/bin/env bash

set -o nounset -o pipefail

if [[ ${TRACE:-0} == "1" ]]; then
  set -o xtrace
fi

main() {
  # cloudflare
  if ping -c 4 "1.1.1.1"; then
    return 0
  fi

  # google
  if ping -c 4 "8.8.8.8"; then
    return 0
  fi

  local SMART_PLUG_ID="8ae318c4-e170-4ca0-ba7d-1cc85e343a1a"

  printf "Internet seems unreachable, turning off smart plug..."
  curl --disable --silent --show-error --location --max-time 30 --request POST "http://127.0.0.1/api/groups/${SMART_PLUG_ID}" --data state=off --data method=PATCH >/dev/null

  sleep 30

  printf "Turning on smart plug..."
  curl --disable --silent --show-error --location --max-time 30 --request POST "http://127.0.0.1/api/groups/${SMART_PLUG_ID}" --data state=off --data method=PATCH >/dev/null
}

main "${@}"
