#!/usr/bin/env bash

set -o nounset -o pipefail -o errexit

if [[ ${TRACE:-0} == "1" ]]; then
  set -o xtrace
fi

seal_content() {
  printf '%s' "${1}" | kubeseal --raw --from-file=/dev/stdin --namespace="${NAMESPACE}" --name="${NAME}" --scope='strict' --cert="${CERT_FILE}"
}

update_manifest() {
  yq eval "(select(.kind == \"${DESTINATION_RESOURCE_TYPE}\" and .metadata.namespace == \"${NAMESPACE}\" and .metadata.name == \"${NAME}\") | ${DESTINATION_YAML_PATH}[\"${1}\"] ) |= strenv(MANIFEST_VALUE)" --inplace "${MANIFEST_FILE}"
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

main() {
  source "$(script_dir)/meta" && meta_check "var"

  local MANIFEST_FILE
  var_shift_or_read MANIFEST_FILE "${1-}"
  shift || true

  local CERT_FILE
  var_shift_or_read CERT_FILE "${1-}"
  shift || true

  local DESTINATION_RESOURCE_TYPE
  var_shift_or_read DESTINATION_RESOURCE_TYPE "${1:-HelmRelease}"
  shift || true

  local DESTINATION_YAML_PATH
  var_shift_or_read DESTINATION_YAML_PATH "${1:-.spec.values.secrets}"
  shift || true

  for item in $(yq --no-doc eval "(select(.kind == \"${DESTINATION_RESOURCE_TYPE}\")) | .metadata | .namespace + \"/\" + .name" "${MANIFEST_FILE}"); do
    local NAMESPACE
    NAMESPACE="$(printf '%s' "${item}" | awk -F '/' '{ print $1 }')"
    local NAME
    NAME="$(printf '%s' "${item}" | awk -F '/' '{ print $2 }')"

    if [[ -z ${NAME-} ]]; then
      return 1
    fi

    kubectl get secrets --ignore-not-found --namespace "${NAMESPACE}" "${NAME}" --output json | jq --compact-output --raw-output '.data | .[] |= @base64d | to_entries[]' | while read -r secret; do
      MANIFEST_VALUE="$(seal_content "$(printf '%s' "${secret}" | jq --raw-output '.value')")" update_manifest "$(printf '%s' "${secret}" | jq --raw-output '.key')"
    done
  done
}

main "${@}"
