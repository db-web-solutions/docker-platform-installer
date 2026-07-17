#!/usr/bin/env bash
set -Eeuo pipefail

readonly TEST_TOKEN="github_pat_TEST_SECRET_123456789"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_dir="$(dirname -- "${script_dir}")"
suite_tmp="$(mktemp -d)"
passed=0

cleanup() {
  rm -rf -- "${suite_tmp}"
}
trap cleanup EXIT HUP INT TERM

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

pass() {
  passed=$((passed + 1))
  printf 'ok %d - %s\n' "${passed}" "$1"
}

assert_contains() {
  local file=$1
  local expected=$2
  local message=$3

  grep -Fq -- "${expected}" "${file}" ||
    fail "${message}: '${expected}' not found in ${file}"
}

assert_not_contains() {
  local file=$1
  local unexpected=$2
  local message=$3

  if grep -Fq -- "${unexpected}" "${file}"; then
    fail "${message}: '${unexpected}' found in ${file}"
  fi
}

assert_equal() {
  local expected=$1
  local actual=$2
  local message=$3

  [[ "${actual}" == "${expected}" ]] ||
    fail "${message}: expected '${expected}', got '${actual}'"
}

make_mocks() {
  local case_dir=$1
  local mock_bin="${case_dir}/bin"

  mkdir -p "${mock_bin}"

  cat >"${mock_bin}/curl" <<'MOCK_CURL'
#!/usr/bin/env bash
set -Eeuo pipefail

output=""
headers=""

printf '%s\n' "$@" >>"${MOCK_CURL_ARGS_LOG}"

while (($#)); do
  case "$1" in
    --output|--dump-header|--write-out)
      case "$1" in
        --output) output=$2 ;;
        --dump-header) headers=$2 ;;
      esac
      shift 2
      ;;
    --config)
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

url=""
authorization_seen=0
while IFS= read -r config_line; do
  case "${config_line}" in
    'url = "'*)
      url="${config_line#url = \"}"
      url="${url%\"}"
      ;;
    'header = "Authorization: Bearer '*)
      authorization_seen=1
      ;;
  esac
done

[[ "${authorization_seen}" -eq 1 ]] || exit 90
printf 'HTTP/2 200\r\nx-ratelimit-remaining: 100\r\n\r\n' >"${headers}"

status=200
case "${url}" in
  */repos/db-web-solutions/docker-platform)
    case "${MOCK_SCENARIO}" in
      authentication_failure) status=401 ;;
      missing_permission) status=404 ;;
      rate_limit)
        status=403
        printf 'HTTP/2 403\r\nx-ratelimit-remaining: 0\r\n\r\n' >"${headers}"
        ;;
    esac
    printf '{}\n' >"${output}"
    ;;
  */releases/latest)
    if [[ "${MOCK_SCENARIO}" == "latest_not_found" ]]; then
      status=404
      printf '{}\n' >"${output}"
    elif [[ "${MOCK_SCENARIO}" == "latest_prerelease" ]]; then
      printf '{"tag_name":"v1.5.0","draft":false,"prerelease":true}\n' >"${output}"
    else
      printf '{"tag_name":"v1.4.0","draft":false,"prerelease":false}\n' >"${output}"
    fi
    ;;
  */contents/install.sh?ref=*)
    if [[ "${MOCK_SCENARIO}" == "installer_download_failure" ]]; then
      exit 7
    fi
    if [[ "${MOCK_SCENARIO}" == "empty_installer" ]]; then
      : >"${output}"
    elif [[ "${MOCK_SCENARIO}" == "private_installer_failure" ]]; then
      printf '#!/usr/bin/env bash\nexit 42\n' >"${output}"
    else
      cat >"${output}" <<MOCK_PRIVATE_INSTALLER
#!/usr/bin/env bash
set -Eeuo pipefail
{
  printf 'ref=%s\n' "\${DOCKER_PLATFORM_REF:-}"
  printf 'archive=%s\n' "\${DOCKER_PLATFORM_ARCHIVE_FILE:-}"
  printf 'path=%s\n' "\${PATH:-}"
  env
} >>"${MOCK_PRIVATE_LOG}"
[[ -f "\${DOCKER_PLATFORM_ARCHIVE_FILE}" ]]
printf 'Installed mock docker-platform %s\n' "\${DOCKER_PLATFORM_REF}"
MOCK_PRIVATE_INSTALLER
    fi
    ;;
  */tarball/*)
    if [[ "${MOCK_SCENARIO}" == "archive_download_failure" ]]; then
      exit 6
    fi
    if [[ "${MOCK_SCENARIO}" == "signal_cleanup" ]]; then
      printf '%s\n' "$$" >"${MOCK_SIGNAL_CURL_PID}"
      : >"${MOCK_SIGNAL_READY}"
      while :; do
        :
      done
    elif [[ "${MOCK_SCENARIO}" == "empty_archive" ]]; then
      : >"${output}"
    elif [[ "${MOCK_SCENARIO}" == "invalid_archive" ]]; then
      printf 'not a gzip archive\n' >"${output}"
    else
      cp "${MOCK_ARCHIVE}" "${output}"
    fi
    ;;
  *)
    exit 91
    ;;
esac

printf '%s' "${status}"
MOCK_CURL

  cat >"${mock_bin}/sudo" <<'MOCK_SUDO'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$@" >>"${MOCK_SUDO_ARGS_LOG}"
exec "$@"
MOCK_SUDO

  cat >"${mock_bin}/docker-platform" <<'MOCK_RUNTIME'
#!/usr/bin/env bash
printf 'runtime invoked\n' >>"${MOCK_RUNTIME_LOG}"
MOCK_RUNTIME

  chmod 0755 "${mock_bin}/curl" "${mock_bin}/sudo" "${mock_bin}/docker-platform"
}

make_archive() {
  local case_dir=$1
  local fixture="${case_dir}/archive-source/docker-platform-fixture"

  mkdir -p "${fixture}"
  printf 'fixture\n' >"${fixture}/VERSION"
  tar -czf "${case_dir}/release.tar.gz" -C "${case_dir}/archive-source" docker-platform-fixture
}

prepare_case() {
  local name=$1
  local case_dir="${suite_tmp}/${name}"

  mkdir -p "${case_dir}/tmp"
  make_mocks "${case_dir}"
  make_archive "${case_dir}"

  : >"${case_dir}/curl.args"
  : >"${case_dir}/sudo.args"
  : >"${case_dir}/private.log"
  : >"${case_dir}/runtime.log"

  cat >"${case_dir}/runner" <<RUNNER
#!/usr/bin/env bash
printf '%s\n' "\$\$" >"${case_dir}/installer.pid"
exec bash "${repository_dir}/install.sh"
RUNNER
  chmod 0755 "${case_dir}/runner"

  printf '%s\n' "${case_dir}"
}

run_case() {
  local name=$1
  local scenario=$2
  local ref=$3
  local expected_status=$4
  local case_dir
  local status

  case_dir="$(prepare_case "${name}")"

  set +e
  {
    sleep 0.2
    printf '%s\n' "${TEST_TOKEN}"
  } 2>/dev/null |
    env \
      PATH="${case_dir}/bin:/usr/bin:/bin" \
      TMPDIR="${case_dir}/tmp" \
      DOCKER_PLATFORM_REF="${ref}" \
      MOCK_SCENARIO="${scenario}" \
      MOCK_ARCHIVE="${case_dir}/release.tar.gz" \
      MOCK_CURL_ARGS_LOG="${case_dir}/curl.args" \
      MOCK_SUDO_ARGS_LOG="${case_dir}/sudo.args" \
      MOCK_PRIVATE_LOG="${case_dir}/private.log" \
      MOCK_RUNTIME_LOG="${case_dir}/runtime.log" \
      MOCK_SIGNAL_READY="${case_dir}/signal.ready" \
      MOCK_SIGNAL_CURL_PID="${case_dir}/signal-curl.pid" \
      script -qefc "${case_dir}/runner" /dev/null \
      >"${case_dir}/output" 2>&1
  status=$?
  set -e

  if [[ "${expected_status}" == "success" && "${status}" -ne 0 ]]; then
    sed -n '1,160p' "${case_dir}/output" >&2
    fail "${name} unexpectedly failed with status ${status}"
  fi
  if [[ "${expected_status}" == "failure" && "${status}" -eq 0 ]]; then
    fail "${name} unexpectedly succeeded"
  fi

  printf '%s\n' "${case_dir}"
}

assert_cleaned() {
  local case_dir=$1

  if find "${case_dir}/tmp" -mindepth 1 -maxdepth 1 -name 'docker-platform-installer.*' |
    grep -q .; then
    fail "temporary bootstrap directory was not cleaned for ${case_dir}"
  fi
}

case_dir="$(run_case explicit_release success v1.4.0 success)"
assert_contains \
  "${case_dir}/output" \
  "Docker Platform Installer $(sed -n '1p' "${repository_dir}/VERSION")" \
  "installer identity"
assert_contains "${case_dir}/private.log" "ref=v1.4.0" "explicit release"
pass "explicit vMAJOR.MINOR.PATCH"

case_dir="$(run_case latest_release success "" success)"
assert_contains "${case_dir}/output" "Latest stable release: v1.4.0" "latest discovery"
assert_contains "${case_dir}/private.log" "ref=v1.4.0" "latest exact ref"
pass "automatic latest stable discovery"

for invalid_ref in main latest master develop v1 v1.2 v1.2.3.4 v1.2.x v1..3 v01.2.3; do
  safe_name="${invalid_ref//[^a-zA-Z0-9]/_}"
  case_dir="$(run_case "invalid_${safe_name}" success "${invalid_ref}" failure)"
  assert_contains "${case_dir}/output" "must be an exact release tag" "invalid ref rejection"
  [[ ! -s "${case_dir}/curl.args" ]] || fail "invalid ref reached GitHub: ${invalid_ref}"
done
pass "mutable, partial, and malformed refs rejected"

case_dir="$(run_case authentication authentication_failure v1.4.0 failure)"
assert_contains "${case_dir}/output" "GitHub authentication failed" "authentication error"
pass "authentication failure"

case_dir="$(run_case permission missing_permission v1.4.0 failure)"
assert_contains "${case_dir}/output" "Grant the token Contents: Read-only" "permission error"
pass "missing repository permission"

case_dir="$(run_case no_latest latest_not_found "" failure)"
assert_contains "${case_dir}/output" "no published stable GitHub Release" "missing latest"
pass "latest release not found"

case_dir="$(run_case prerelease latest_prerelease "" failure)"
assert_contains "${case_dir}/output" "was not a published stable release" "prerelease rejection"
pass "draft or prerelease cannot be selected as latest stable"

case_dir="$(run_case rate_limit rate_limit v1.4.0 failure)"
assert_contains "${case_dir}/output" "rate limit exceeded" "rate-limit error"
pass "API rate limit"

case_dir="$(run_case installer_network installer_download_failure v1.4.0 failure)"
assert_contains "${case_dir}/output" "network failure while performing private installer download" "installer download error"
pass "failed installer download"

case_dir="$(run_case archive_network archive_download_failure v1.4.0 failure)"
assert_contains "${case_dir}/output" "network failure while performing private release archive download" "archive download error"
pass "failed archive download"

case_dir="$(run_case empty_installer empty_installer v1.4.0 failure)"
assert_contains "${case_dir}/output" "private installer is not a non-empty regular file" "empty installer"
pass "empty installer rejected"

case_dir="$(run_case empty_archive empty_archive v1.4.0 failure)"
assert_contains "${case_dir}/output" "private release archive is not a non-empty regular file" "empty archive"
pass "empty archive rejected"

case_dir="$(run_case invalid_archive invalid_archive v1.4.0 failure)"
assert_contains "${case_dir}/output" "not a valid tar.gz file" "invalid archive"
pass "invalid archive rejected"

case_dir="$(run_case private_failure private_installer_failure v1.4.0 failure)"
assert_contains "${case_dir}/sudo.args" "DOCKER_PLATFORM_REF=v1.4.0" "sudo called before private failure"
pass "private installer failure propagated"

case_dir="$(run_case cleanup_success success v1.4.0 success)"
assert_cleaned "${case_dir}"
pass "temporary cleanup after success"

case_dir="$(run_case cleanup_failure invalid_archive v1.4.0 failure)"
assert_cleaned "${case_dir}"
pass "temporary cleanup after failure"

signal_dir="$(prepare_case signal_cleanup)"
set +e
{
  sleep 0.2
  printf '%s\n' "${TEST_TOKEN}"
} 2>/dev/null |
  env \
    PATH="${signal_dir}/bin:/usr/bin:/bin" \
    TMPDIR="${signal_dir}/tmp" \
    DOCKER_PLATFORM_REF=v1.4.0 \
    MOCK_SCENARIO=signal_cleanup \
    MOCK_ARCHIVE="${signal_dir}/release.tar.gz" \
    MOCK_CURL_ARGS_LOG="${signal_dir}/curl.args" \
    MOCK_SUDO_ARGS_LOG="${signal_dir}/sudo.args" \
    MOCK_PRIVATE_LOG="${signal_dir}/private.log" \
    MOCK_RUNTIME_LOG="${signal_dir}/runtime.log" \
    MOCK_SIGNAL_READY="${signal_dir}/signal.ready" \
    MOCK_SIGNAL_CURL_PID="${signal_dir}/signal-curl.pid" \
    script -qefc "${signal_dir}/runner" /dev/null \
    >"${signal_dir}/output" 2>&1 &
signal_job=$!
set -e

for _ in {1..100}; do
  [[ -f "${signal_dir}/signal.ready" && -f "${signal_dir}/installer.pid" ]] && break
  sleep 0.05
done
[[ -f "${signal_dir}/signal.ready" ]] || fail "signal test never reached the blocking download"
kill -TERM "$(sed -n '1p' "${signal_dir}/installer.pid")"
kill -TERM "$(sed -n '1p' "${signal_dir}/signal-curl.pid")"
set +e
wait "${signal_job}"
signal_status=$?
set -e
[[ "${signal_status}" -ne 0 ]] || fail "signal test unexpectedly succeeded"
assert_cleaned "${signal_dir}"
pass "temporary cleanup after signal"

case_dir="$(run_case secret_safety success v1.4.0 success)"
assert_not_contains "${case_dir}/output" "${TEST_TOKEN}" "token leaked to output"
assert_not_contains "${case_dir}/curl.args" "${TEST_TOKEN}" "token leaked to curl arguments"
assert_not_contains "${case_dir}/sudo.args" "${TEST_TOKEN}" "token leaked to sudo arguments"
assert_not_contains "${case_dir}/private.log" "${TEST_TOKEN}" "token leaked to root environment"
pass "token absent from output, curl arguments, and sudo environment"

assert_contains "${case_dir}/sudo.args" "-i" "sudo clean environment"
assert_contains "${case_dir}/sudo.args" "DOCKER_PLATFORM_REF=v1.4.0" "sudo exact ref"
assert_contains "${case_dir}/sudo.args" "DOCKER_PLATFORM_ARCHIVE_FILE=" "sudo local archive"
assert_not_contains "${case_dir}/private.log" "MOCK_SCENARIO=" "ambient environment reached private installer"
pass "sudo receives exact ref and local archive in a clean environment"

repeat_dir="$(run_case repeat_first success v1.4.0 success)"
repeat_second="$(run_case repeat_second success v1.4.0 success)"
assert_contains "${repeat_dir}/private.log" "ref=v1.4.0" "first installation"
assert_contains "${repeat_second}/private.log" "ref=v1.4.0" "repeated installation"
pass "repeated installation delegates safely"

case_dir="$(run_case previous_release success v1.3.0 success)"
assert_contains "${case_dir}/private.log" "ref=v1.3.0" "previous release"
pass "specific previous release installation"

[[ ! -s "${case_dir}/runtime.log" ]] || fail "bootstrap invoked docker-platform runtime"
pass "bootstrap does not start docker-platform runtime"

assert_equal \
  "Docker Platform Installer $(sed -n '1p' "${repository_dir}/VERSION")" \
  "$(bash "${repository_dir}/install.sh" --version)" \
  "installer VERSION metadata"
bash "${repository_dir}/install.sh" --help >"${suite_tmp}/help"
assert_contains "${suite_tmp}/help" "Usage:" "installer help"
assert_contains "${suite_tmp}/help" "DOCKER_PLATFORM_REF" "installer environment help"
if bash "${repository_dir}/install.sh" unknown >"${suite_tmp}/unknown" 2>&1; then
  fail "installer accepted an unknown argument"
fi
assert_contains "${suite_tmp}/unknown" "unknown argument" "unknown argument rejection"
pass "version, help, and argument contract"

for required_file in \
  README.md \
  CHANGELOG.md \
  VERSION \
  CONTRIBUTING.md \
  SECURITY.md \
  LICENSE \
  docs/architecture.md \
  docs/release-process.md; do
  [[ -s "${repository_dir}/${required_file}" ]] ||
    fail "required repository documentation is missing: ${required_file}"
done
pass "repository release and documentation metadata"

bash -n "${repository_dir}/install.sh"
git -C "${repository_dir}" diff --check
pass "shell syntax and git diff --check"

printf '\nAll %d bootstrap installer checks passed.\n' "${passed}"
