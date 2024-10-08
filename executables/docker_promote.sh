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

  local DATE_VERSION

  OPTIND=0

  while getopts ":d:" option; do
    case "${option}" in
    d)
      DATE_VERSION="${OPTARG}"
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

  if [[ ${#} -lt 2 ]]; then
    var_red "Usage: ${0} DOCKER_IMAGE IMAGE_VERSION [VERSION_TARGET]"
    return 1
  fi

  local DOCKER_IMAGE="${1}"
  shift
  local IMAGE_VERSION="${1}"
  shift
  local VERSION_TARGET="${1:-latest}"
  shift || true

  var_read DOCKER_REGISTRY "https://registry-1.docker.io/v2"
  var_read DOCKER_AUTH_TOKEN "https://auth.docker.io/token?service=registry.docker.io"
  var_read DOCKER_USER
  var_read DOCKER_PASS "" "secret"

  http_init_client

  var_info "Getting token from ${DOCKER_AUTH_TOKEN} for pulling and pushing to ${DOCKER_IMAGE}..."

  http_request --request GET "${DOCKER_AUTH_TOKEN}&scope=repository:${DOCKER_IMAGE}:pull,push" --user "${DOCKER_USER}:${DOCKER_PASS}"
  unset DOCKER_PASS

  if [[ ${HTTP_STATUS} != "200" ]]; then
    http_handle_error "Unable to retrieve token for ${DOCKER_IMAGE}"
    return 1
  fi

  HTTP_CLIENT_ARGS+=("--header" "Authorization: Bearer $(jq --raw-output .token "${HTTP_OUTPUT}")")
  rm "${HTTP_OUTPUT}"

  var_info "Tagging image ${DOCKER_IMAGE} from ${IMAGE_VERSION} to ${VERSION_TARGET}..."

  local MANIFEST_ACCEPT=("application/vnd.oci.image.index.v1+json" "application/vnd.docker.distribution.manifest.list.v2+json" "application/vnd.docker.distribution.manifest.v2+json")
  for manifest in "${MANIFEST_ACCEPT[@]}"; do
    var_warning "Trying with manifest ${manifest}"

    # Getting manifest
    http_request --request GET "${DOCKER_REGISTRY}/${DOCKER_IMAGE}/manifests/${IMAGE_VERSION}" --header "Accept: ${manifest}"
    if [[ ${HTTP_STATUS} != "200" ]]; then
      http_handle_error "Unable to retrieve manifest for ${DOCKER_IMAGE}"
      continue
    fi

    local MANIFEST_PAYLOAD
    MANIFEST_PAYLOAD="$(cat "${HTTP_OUTPUT}")"
    rm "${HTTP_OUTPUT}"

    # Promoting image
    http_request --request PUT "${DOCKER_REGISTRY}/${DOCKER_IMAGE}/manifests/${VERSION_TARGET}" \
      --header "Content-Type: ${manifest}" \
      --data "${MANIFEST_PAYLOAD}"
    if [[ ${HTTP_STATUS} != "201" ]]; then
      http_handle_error "Unable to promote manifest for ${DOCKER_IMAGE}"
      continue
    fi

    var_success "Image promoted to ${VERSION_TARGET}!"
    rm "${HTTP_OUTPUT}"

    if [[ -n ${DATE_VERSION-} ]]; then
      # Tagging image with timestamp
      http_request --request PUT "${DOCKER_REGISTRY}/${DOCKER_IMAGE}/manifests/${DATE_VERSION}" \
        --header "Content-Type: ${manifest}" \
        --data "${MANIFEST_PAYLOAD}"
      if [[ ${HTTP_STATUS} != "201" ]]; then
        http_handle_error "Unable to tag date manifest for ${DOCKER_IMAGE}"
        continue
      fi

      var_success "Image tagged ${DATE_VERSION}!"
      rm "${HTTP_OUTPUT}"
    fi

    return
  done

  var_error "Manifest not found!"
  return 1
}

main "${@}"
