#!/usr/bin/env bash

set -o nounset -o pipefail -o errexit

if [[ ${TRACE:-0} == "1" ]]; then
  set -o xtrace
fi

release_clean() {
  var_info "Cleaning ${OUTPUT_DIR}"

  rm -rf "${OUTPUT_DIR:?}"
  mkdir "${OUTPUT_DIR}"
}

golang_build() {
  if ! command -v go >/dev/null 2>&1; then
    var_error "go not found"
    return 1
  fi

  local SOURCE_DIR
  SOURCE_DIR="${ROOT_DIR}/..."

  (
    cd "${ROOT_DIR}"

    local OUTPUT_BINARIES
    mapfile -t OUTPUT_BINARIES < <(go list -f '{{ .Dir }} {{ .Name }}' "${SOURCE_DIR}" | grep "main" | awk '{print $1}')

    local GO_ARCHS="${GO_ARCHS:-linux/amd64 linux/arm linux/arm64 darwin/amd64 darwin/arm64}"

    for main in "${OUTPUT_BINARIES[@]}"; do
      local EXTENSION

      local NAME
      NAME="$(basename "${main}")"

      if [[ -n ${DD_API_KEY:-} ]] && [[ -n ${DD_APP_KEY:-} ]] && [[ -n ${DD_SERVICE:-} ]] && [[ -n ${DD_ENV:-} ]] && [[ ${PGO_NAME:-} == "${NAME}" ]]; then
        var_info "Using PGO for 'service:${DD_SERVICE} env:${DD_ENV}'"
        go run "github.com/DataDog/datadog-pgo@latest" "service:${DD_SERVICE} env:${DD_ENV}" "${main}/default.pgo"
      fi

      local LDFLAGS="-s -w"
      if [[ -n ${GIT_TAG-} ]] && [[ -n ${GO_VERSION_PATH-} ]]; then
        LDFLAGS+=" -X '${GO_VERSION_PATH}=${GIT_TAG}'"
      fi

      for OS_ARCH in ${GO_ARCHS[*]}; do
        local BUILD_GOOS
        BUILD_GOOS="$(printf '%s' "${OS_ARCH}" | awk -F '/' '{ print $1 }')"
        local BUILD_GOARCH
        BUILD_GOARCH="$(printf '%s' "${OS_ARCH}" | awk -F '/' '{ print $2 }')"

        (
          export GOOS="${BUILD_GOOS}"
          export GOARCH="${BUILD_GOARCH}"
          export CGO_ENABLED="0"

          if [[ ${GOOS} == "windows" ]]; then
            EXTENSION=".exe"
          else
            EXTENSION=""
          fi

          var_info "Building binary ${NAME}_${GOOS}_${GOARCH} to ${OUTPUT_DIR}"
          go build "-ldflags=${LDFLAGS}" -installsuffix nocgo -o "${OUTPUT_DIR}/${NAME}_${GOOS}_${GOARCH}${EXTENSION}" "${main}"

          if [[ -n ${GPG_FINGERPRINT-} ]]; then
            gpg --no-tty --batch --detach-sign --armor --local-user "${GPG_FINGERPRINT}" "${OUTPUT_DIR}/${NAME}_${GOOS}_${GOARCH}${EXTENSION}"
          fi
        )
      done
    done
  )
}

docker_dependencies() {
  docker run -v "$(pwd):/tmp/" --rm "alpine" /bin/sh -c 'apk --update add tzdata ca-certificates zip && cd /usr/share/zoneinfo/ && zip -q -r -0 /tmp/zoneinfo.zip . && cp /etc/ssl/certs/ca-certificates.crt /tmp/ca-certificates.crt'

  if [[ ${RELEASE_NEED_WAIT-} == "true" ]]; then
    # renovate: datasource=github-releases depName=ViBiOh/wait
    local WAIT_VERSION="v0.1.0"

    for platform in ${DOCKER_ARCHS:-linux/amd64 linux/arm linux/arm64}; do
      local BUILD_GOOS
      BUILD_GOOS="$(printf '%s' "${platform}" | awk -F '/' '{ print $1 }')"
      local BUILD_GOARCH
      BUILD_GOARCH="$(printf '%s' "${platform}" | awk -F '/' '{ print $2 }')"

      local WAIT_BINARY_NAME="wait_${BUILD_GOOS}_${BUILD_GOARCH}"

      curl \
        --disable \
        --silent \
        --show-error \
        --location \
        --max-time 300 \
        --output "${WAIT_BINARY_NAME}" \
        "https://github.com/ViBiOh/wait/releases/download/v${WAIT_VERSION}/${WAIT_BINARY_NAME}"
      chmod +x "${WAIT_BINARY_NAME}"
    done
  fi
}

docker_build() {
  if ! command -v docker >/dev/null 2>&1; then
    var_error "docker not found"
    return 1
  fi

  local DOCKER_PLATFORMS
  DOCKER_PLATFORMS="${DOCKER_ARCHS:-linux/amd64 linux/arm linux/arm64}"
  DOCKER_PLATFORMS="${DOCKER_PLATFORMS// /,}"

  local BUILT_IMAGE="${DOCKER_IMAGE}:${IMAGE_VERSION}"

  var_read DOCKER_IMAGE
  var_read IMAGE_VERSION
  var_read GIT_SHA
  var_read DOCKERFILE "Dockerfile"

  export DOCKER_CLI_EXPERIMENTAL="enabled"
  export DOCKER_BUILDKIT="1"

  var_info "Building and pushing image ${BUILT_IMAGE} for ${DOCKER_PLATFORMS}"
  docker buildx build \
    --push \
    --platform "${DOCKER_PLATFORMS}" \
    --file "${DOCKERFILE}" \
    --tag "${BUILT_IMAGE}" \
    --build-arg "VERSION=${IMAGE_VERSION}" \
    --build-arg "GIT_SHA=${GIT_SHA}" \
    -o "type=registry,oci-mediatypes=true,compression=estargz,force-compression=true" \
    .
}

release_upload() {
  if ! [[ -d ${OUTPUT_DIR} ]]; then
    var_warning "Nothing to upload!"
  fi

  http_init_client --header "Authorization: token ${GITHUB_TOKEN}"
  HTTP_CLIENT_ARGS+=("--max-time" "120")

  var_read GIT_TAG
  http_request --header "Content-Type: application/json" "https://api.github.com/repos/${GITHUB_REPOSITORY}/releases/tags/${GIT_TAG}"
  if [[ ${HTTP_STATUS} != "200" ]]; then
    http_handle_error "Unable to get release"
    return 1
  fi

  local RESPONSE_URL
  RESPONSE_URL="$(jq --raw-output .upload_url "${HTTP_OUTPUT}" | sed 's|{.*||')"
  rm "${HTTP_OUTPUT}"

  for asset in "${OUTPUT_DIR}"/*; do
    var_info "Uploading asset ${asset}"

    http_request --header "Content-Type: application/x-executable" --request POST "${RESPONSE_URL}?name=$(basename "${asset}")" --data-binary "@${asset}"
    if [[ ${HTTP_STATUS} != "201" ]]; then
      http_handle_error "Unable to upload asset ${asset}"
      return 1
    fi

    rm "${HTTP_OUTPUT}"
  done
}

release_usage() {
  printf -- "Usage of %s\n" "${0}"
  printf -- "clean\n\tClean output dir %s\n" "${OUTPUT_DIR}"
  printf -- "build\n\tBuild artifacts\n"
  printf -- "docker\n\tBuild docker images\n"
  printf -- "assets\n\tUpload output dir content to GitHub release\n"
  printf -- "clea,\n\tClean created output directory\n"
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
  source "$(script_dir)/meta" && meta_check "var" "git" "github" "http" "pass" "version"

  local ROOT_DIR
  ROOT_DIR="$(git_root)"

  local OUTPUT_DIR="${ROOT_DIR}/release"

  for arg in "${@}"; do
    case "${arg}" in
    "build")
      release_clean

      if [[ -f "${ROOT_DIR}/go.mod" ]]; then
        golang_build
      fi
      ;;

    "make")
      make build
      ;;

    "docker")
      docker_dependencies
      docker_build
      ;;

    "assets")
      release_upload
      ;;

    "clean")
      release_clean
      ;;

    *)
      release_usage
      ;;
    esac
  done
}

DEFAULT_ARGS=("release" "build" "assets" "clean")
main "${@:-${DEFAULT_ARGS[@]}}"
