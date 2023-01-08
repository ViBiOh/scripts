#!/usr/bin/env bash

sql_find_port() {
  local START_INDEX=3
  local POSSIBLE_PORTS="9876543"

  while nc -z "127.0.0.1" "${POSTGRES_PORT}" >/dev/null 2>&1; do
    if [[ ${START_INDEX} -lt 0 ]]; then
      return 1
    fi

    POSTGRES_PORT="${POSSIBLE_PORTS:START_INDEX:4}"

    START_INDEX=$((START_INDEX - 1))
  done
}
