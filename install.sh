#!/usr/bin/env bash
set -Eeuo pipefail

readonly PROGRAM_NAME="Docker Platform Installer"
readonly VERSION="1.0.0-dev"
readonly REPOSITORY="db-web-solutions/docker-platform"
readonly API_ROOT="https://api.github.com"

tmp_dir=""
github_token=""

cleanup() {
  local exit_code=$?

  github_token=""
  unset github_token

  if [[ -n "${tmp_dir}" && -d "${tmp_dir}" ]]; then
    rm -rf -- "${tmp_dir}"
  fi

  return "${exit_code}"
}

trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  install.sh
  install.sh --help
  install.sh --version

Install the latest published stable Docker Platform release:
  curl -fsSL \
    https://raw.githubusercontent.com/db-web-solutions/docker-platform-installer/v1.0.0/install.sh \
    | bash

Install or reactivate an exact Docker Platform release:
  curl -fsSL \
    https://raw.githubusercontent.com/db-web-solutions/docker-platform-installer/v1.0.0/install.sh \
    | DOCKER_PLATFORM_REF=v1.4.0 bash

Environment:
  DOCKER_PLATFORM_REF  Optional exact private release tag in the form
                       vMAJOR.MINOR.PATCH. If omitted, the latest published
                       stable release is selected.

The installer prompts for a GitHub token through /dev/tty. The token needs
read-only Contents access to db-web-solutions/docker-platform.
EOF
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 is required."
}

preflight() {
  [[ "$(uname -s 2>/dev/null || true)" == "Linux" ]] ||
    fail "this installer supports Linux only."

  require_command bash
  require_command curl
  require_command tar
  require_command mktemp
  require_command sudo

  [[ -r /dev/tty && -w /dev/tty ]] ||
    fail "/dev/tty must be available for interactive GitHub authentication."
}

validate_ref() {
  local ref=$1

  [[ "${ref}" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] ||
    fail "DOCKER_PLATFORM_REF must be an exact release tag in the form vMAJOR.MINOR.PATCH: ${ref}"
}

prompt_for_token() {
  # A caller may have tracing enabled before starting this script. Disable it
  # before the secret exists and never enable it again.
  { set +x; } 2>/dev/null

  printf 'GitHub token: ' >/dev/tty
  IFS= read -r -s github_token </dev/tty ||
    fail "could not read the GitHub token from /dev/tty."
  printf '\rGitHub token: ********\n' >/dev/tty

  [[ -n "${github_token}" ]] || fail "the GitHub token must not be empty."
  [[ "${github_token}" =~ ^[A-Za-z0-9_-]+$ ]] ||
    fail "the GitHub token has an invalid format."
}

http_error() {
  local purpose=$1
  local status=$2
  local headers_file=$3
  local header_line

  case "${status}" in
    401)
      fail "GitHub authentication failed. Create a valid fine-grained token and try again."
      ;;
    403)
      while IFS= read -r header_line; do
        header_line="${header_line%$'\r'}"
        if [[ "${header_line,,}" =~ ^x-ratelimit-remaining:[[:space:]]*0[[:space:]]*$ ]]; then
          fail "GitHub API rate limit exceeded. Wait for the limit to reset and try again."
        fi
      done <"${headers_file}"
      fail "GitHub denied ${purpose}. Verify that the token has Contents: Read-only access to ${REPOSITORY}."
      ;;
    404)
      case "${purpose}" in
        "repository access")
          fail "the private repository is unavailable. Grant the token Contents: Read-only access to ${REPOSITORY}."
          ;;
        "latest stable release discovery")
          fail "no published stable GitHub Release was found for ${REPOSITORY}."
          ;;
        *)
          fail "${purpose} was not found for the selected release."
          ;;
      esac
      ;;
    *)
      fail "GitHub returned HTTP ${status:-unknown} while performing ${purpose}."
      ;;
  esac
}

github_get() {
  local url=$1
  local destination=$2
  local accept=$3
  local purpose=$4
  local partial="${destination}.partial"
  local headers="${destination}.headers"
  local errors="${destination}.errors"
  local status
  local curl_status

  rm -f -- "${partial}" "${headers}" "${errors}"

  set +e
  status="$(
    printf '%s\n' \
      'silent' \
      'show-error' \
      'location' \
      'proto = "=https"' \
      'tlsv1.2' \
      'request = "GET"' \
      "url = \"${url}\"" \
      "header = \"Accept: ${accept}\"" \
      "header = \"Authorization: Bearer ${github_token}\"" \
      'header = "X-GitHub-Api-Version: 2022-11-28"' |
      curl --config - \
        --output "${partial}" \
        --dump-header "${headers}" \
        --write-out '%{http_code}' \
        2>"${errors}"
  )"
  curl_status=$?
  set -e

  if [[ "${curl_status}" -ne 0 ]]; then
    fail "network failure while performing ${purpose}."
  fi

  if [[ ! "${status}" =~ ^2[0-9][0-9]$ ]]; then
    http_error "${purpose}" "${status}" "${headers}"
  fi

  [[ -f "${partial}" ]] || fail "${purpose} produced no download."
  mv -- "${partial}" "${destination}"
  rm -f -- "${headers}" "${errors}"
}

clear_token() {
  github_token=""
  unset github_token
}

case "$#" in
  0)
    ;;
  1)
    case "$1" in
      --help|-h)
        usage
        exit 0
        ;;
      --version|-V)
        printf '%s %s\n' "${PROGRAM_NAME}" "${VERSION}"
        exit 0
        ;;
      *)
        fail "unknown argument: $1"
        ;;
    esac
    ;;
  *)
    fail "this installer accepts no positional arguments."
    ;;
esac

preflight

printf '%s %s\n\n' "${PROGRAM_NAME}" "${VERSION}"
printf 'Repository: %s\n' "${REPOSITORY}"

requested_ref="${DOCKER_PLATFORM_REF:-}"
if [[ -n "${requested_ref}" ]]; then
  validate_ref "${requested_ref}"
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/docker-platform-installer.XXXXXXXX")"
chmod 0700 "${tmp_dir}"

prompt_for_token

github_get \
  "${API_ROOT}/repos/${REPOSITORY}" \
  "${tmp_dir}/repository.json" \
  "application/vnd.github+json" \
  "repository access"

selected_ref="${requested_ref}"
if [[ -z "${selected_ref}" ]]; then
  latest_json=""
  tag_pattern='"tag_name"[[:space:]]*:[[:space:]]*"([^"]*)"'
  stable_draft_pattern='"draft"[[:space:]]*:[[:space:]]*false'
  stable_prerelease_pattern='"prerelease"[[:space:]]*:[[:space:]]*false'

  github_get \
    "${API_ROOT}/repos/${REPOSITORY}/releases/latest" \
    "${tmp_dir}/latest-release.json" \
    "application/vnd.github+json" \
    "latest stable release discovery"

  latest_json="$(<"${tmp_dir}/latest-release.json")"
  [[ "${latest_json}" =~ ${tag_pattern} ]] ||
    fail "GitHub returned an invalid latest release response."
  selected_ref="${BASH_REMATCH[1]}"
  [[ -n "${selected_ref}" ]] ||
    fail "GitHub returned an invalid latest release response."
  [[ "${latest_json}" =~ ${stable_draft_pattern} &&
    "${latest_json}" =~ ${stable_prerelease_pattern} ]] ||
    fail "GitHub latest release response was not a published stable release."
  validate_ref "${selected_ref}"

  printf '\nLatest stable release: %s\n' "${selected_ref}"
fi

printf 'Selected release:      %s\n\n' "${selected_ref}"

installer_file="${tmp_dir}/install.sh"
archive_file="${tmp_dir}/docker-platform-${selected_ref}.tar.gz"

printf 'Downloading private installer...\n'
github_get \
  "${API_ROOT}/repos/${REPOSITORY}/contents/install.sh?ref=${selected_ref}" \
  "${installer_file}" \
  "application/vnd.github.raw+json" \
  "private installer download"

printf 'Downloading private release archive...\n'
github_get \
  "${API_ROOT}/repos/${REPOSITORY}/tarball/${selected_ref}" \
  "${archive_file}" \
  "application/vnd.github+json" \
  "private release archive download"

clear_token

[[ -f "${installer_file}" && ! -L "${installer_file}" && -s "${installer_file}" ]] ||
  fail "the downloaded private installer is not a non-empty regular file."

[[ -f "${archive_file}" && ! -L "${archive_file}" && -s "${archive_file}" ]] ||
  fail "the downloaded private release archive is not a non-empty regular file."

archive_listing="${tmp_dir}/archive.list"
tar -tzf "${archive_file}" >"${archive_listing}" 2>/dev/null ||
  fail "the downloaded private release archive is not a valid tar.gz file."
[[ -s "${archive_listing}" ]] ||
  fail "the downloaded private release archive is empty."

printf 'Download complete.\n\n'
printf 'Installing docker-platform %s...\n' "${selected_ref}"

sudo env \
  -i \
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  DOCKER_PLATFORM_REF="${selected_ref}" \
  DOCKER_PLATFORM_ARCHIVE_FILE="${archive_file}" \
  bash "${installer_file}"
