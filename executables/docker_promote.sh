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

dockerhub_auth() {
  var_read DOCKER_USER
  var_read DOCKER_PASS "" "secret"

  var_info "Getting token for pulling and pushing to ${1}..."

  http_request \
    --request GET \
    --user "${DOCKER_USER}:${DOCKER_PASS}" \
    "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${1}:pull,push"
  unset DOCKER_PASS

  if [[ ${HTTP_STATUS} != "200" ]]; then
    http_handle_error "Unable to retrieve token for ${1}"
    exit 1
  fi

  HTTP_CLIENT_ARGS+=("--header" "Authorization: Bearer $(jq --raw-output .token "${HTTP_OUTPUT}")")
  rm "${HTTP_OUTPUT}"
}

scw_login() {
  var_read SCW_ACCESS_KEY
  var_read SCW_SECRET_KEY "" "secret"
  var_read SCW_REGION "fr-par"

  var_info "Getting token for pulling and pushing to ${1}..."

  http_request \
    --request GET \
    --user "${SCW_ACCESS_KEY}:${SCW_SECRET_KEY}" \
    "https://api.scaleway.com/registry-internal/v1/regions/${SCW_REGION}/tokens?service=registry&scope=repository:${1}:pull,push"
  unset SCW_SECRET_KEY

  if [[ ${HTTP_STATUS} != "200" ]]; then
    http_handle_error "Unable to retrieve token for ${1}"
    exit 1
  fi

  HTTP_CLIENT_ARGS+=("--header" "Authorization: Bearer $(jq --raw-output .token "${HTTP_OUTPUT}")")
  rm "${HTTP_OUTPUT}"
}

promote() {
  local MANIFEST_ACCEPT=("application/vnd.oci.image.index.v1+json" "application/vnd.docker.distribution.manifest.list.v2+json" "application/vnd.docker.distribution.manifest.v2+json")

  for manifest in "${MANIFEST_ACCEPT[@]}"; do
    var_warning "Trying with manifest ${manifest}"

    # Getting manifest
    http_request --request GET "https://${DOCKER_REGISTRY}/v2/${DOCKER_IMAGE}/manifests/${IMAGE_VERSION}" --header "Accept: ${manifest}"
    if [[ ${HTTP_STATUS} != "200" ]]; then
      http_handle_error "Unable to retrieve manifest for https://${DOCKER_REGISTRY}/v2/${DOCKER_IMAGE}/manifests/${IMAGE_VERSION}"
      continue
    fi

    local MANIFEST_PAYLOAD
    MANIFEST_PAYLOAD="$(cat "${HTTP_OUTPUT}")"
    rm "${HTTP_OUTPUT}"

    # Promoting image
    http_request --request PUT "https://${DOCKER_REGISTRY}/v2/${DOCKER_IMAGE}/manifests/${VERSION_TARGET}" \
      --header "Content-Type: ${manifest}" \
      --data "${MANIFEST_PAYLOAD}"
    if [[ ${HTTP_STATUS} != "201" ]]; then
      http_handle_error "Unable to promote manifest for https://${DOCKER_REGISTRY}/v2/${DOCKER_IMAGE}/manifests/${VERSION_TARGET}"
      continue
    fi

    var_success "Image promoted to ${VERSION_TARGET}!"
    rm "${HTTP_OUTPUT}"

    if [[ -n ${DATE_VERSION-} ]]; then
      # Tagging image with timestamp
      http_request --request PUT "https://${DOCKER_REGISTRY}/v2/${DOCKER_IMAGE}/manifests/${DATE_VERSION}" \
        --header "Content-Type: ${manifest}" \
        --data "${MANIFEST_PAYLOAD}"
      if [[ ${HTTP_STATUS} != "201" ]]; then
        http_handle_error "Unable to tag date manifest for https://${DOCKER_REGISTRY}/v2/${DOCKER_IMAGE}/manifests/${DATE_VERSION}"
        continue
      fi

      var_success "Image tagged ${DATE_VERSION}!"
      rm "${HTTP_OUTPUT}"
    fi

    return
  done
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
      exit 1
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
    exit 1
  fi

  local DOCKER_IMAGE="${1}"
  shift
  local IMAGE_VERSION="${1}"
  shift
  local VERSION_TARGET="${1:-latest}"
  shift || true

  http_init_client

  var_info "Tagging image ${DOCKER_IMAGE} from ${IMAGE_VERSION} to ${VERSION_TARGET}..."

  var_read DOCKER_REGISTRY "registry-1.docker.io"

  if [[ ${DOCKER_REGISTRY} =~ docker.io ]]; then
    dockerhub_auth "${DOCKER_IMAGE}"
  elif [[ ${DOCKER_REGISTRY} =~ scw.cloud ]]; then
    scw_login "${DOCKER_IMAGE}"
  else
    var_red "Unhandled registry ${DOCKER_REGISTRY}"
    exit 1
  fi

  promote
}

main "${@}"
