#!/usr/bin/env bash
#
# test-action.sh — Test harness for the Octozipo GitHub Action
#
# Runs the action entry script (src/action.sh) and through it the octozipo
# script (src/octozipo) against zip packages and bare "remote" repositories
# that are created on the fly. Octozipo talks to git@<host>:<org>/<repo>.git,
# so a git `url.<base>.insteadOf` rewrite sends those urls to the local bare
# repositories. No network access, git server or SSH key is needed.
#
# Usage:
#   bash tests/test-action.sh [path/to/src/action.sh]
#
# Exit codes:
#   0  All tests passed
#   1  One or more tests failed
#

set -Euo pipefail

# ──────────────────────────────────────────────
# Configuration
# ──────────────────────────────────────────────
ACTION_SCRIPT="${1:-./src/action.sh}"
OCTOZIPO_SCRIPT=""
TEST_HOST="git.test.local"
TEST_ORG="octoleo"
TEST_USER="Test Robot"
TEST_EMAIL="robot@test.local"

# Counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Scratch space — completely isolated from the real HOME
TEST_ROOT=""
REMOTES=""
REAL_HOME="${HOME}"

# Result of the last run_action call
RUN_EXIT=0
RUN_LOG=""
RUN_OUTPUT=""
RUN_SUMMARY=""

# ──────────────────────────────────────────────
# Logging / assertions
# ──────────────────────────────────────────────
_red()   { printf '\033[1;31m%s\033[0m' "$*"; }
_green() { printf '\033[1;32m%s\033[0m' "$*"; }
_bold()  { printf '\033[1m%s\033[0m' "$*"; }

log_section() {
	printf '\n%s\n' "── $(_bold "$*") ──"
}

pass() {
	((TESTS_RUN++)) || true
	((TESTS_PASSED++)) || true
	printf '  %s %s\n' "$(_green "PASS")" "$*"
}

fail_test() {
	((TESTS_RUN++)) || true
	((TESTS_FAILED++)) || true
	printf '  %s %s\n' "$(_red "FAIL")" "$*"
}

assert_eq() {
	local description="$1" expected="$2" actual="$3"
	if [[ "${expected}" == "${actual}" ]]; then
		pass "${description}"
	else
		fail_test "${description}"
		printf '         expected: %s\n' "${expected}"
		printf '         actual:   %s\n' "${actual}"
	fi
}

assert_file_exists() {
	local description="$1" filepath="$2"
	if [[ -f "${filepath}" ]]; then
		pass "${description}"
	else
		fail_test "${description} (file not found: ${filepath})"
	fi
}

assert_file_not_exists() {
	local description="$1" filepath="$2"
	if [[ ! -f "${filepath}" ]]; then
		pass "${description}"
	else
		fail_test "${description} (file should not exist: ${filepath})"
	fi
}

assert_dir_exists() {
	local description="$1" dirpath="$2"
	if [[ -d "${dirpath}" ]]; then
		pass "${description}"
	else
		fail_test "${description} (directory not found: ${dirpath})"
	fi
}

assert_dir_not_exists() {
	local description="$1" dirpath="$2"
	if [[ ! -d "${dirpath}" ]]; then
		pass "${description}"
	else
		fail_test "${description} (directory should not exist: ${dirpath})"
	fi
}

assert_file_contains() {
	local description="$1" filepath="$2" pattern="$3"
	if grep -qF -- "${pattern}" "${filepath}" 2>/dev/null; then
		pass "${description}"
	else
		fail_test "${description} (pattern '${pattern}' not found in ${filepath})"
	fi
}

assert_file_not_contains() {
	local description="$1" filepath="$2" pattern="$3"
	if grep -qF -- "${pattern}" "${filepath}" 2>/dev/null; then
		fail_test "${description} (pattern '${pattern}' found in ${filepath})"
	else
		pass "${description}"
	fi
}

# Assertions on the last run_action call
assert_exit() {
	local description="$1" expected="$2"
	if [[ "${RUN_EXIT}" == "${expected}" ]]; then
		pass "${description}"
	else
		fail_test "${description} (expected exit ${expected}, got ${RUN_EXIT})"
		printf '         log tail:\n'
		tail -n 15 "${RUN_LOG}" | sed 's/^/           /'
	fi
}

assert_log_contains() {
	assert_file_contains "$1" "${RUN_LOG}" "$2"
}

assert_log_not_contains() {
	assert_file_not_contains "$1" "${RUN_LOG}" "$2"
}

assert_output() {
	local description="$1" name="$2" expected="$3"
	assert_eq "${description}" "${expected}" "$(output_value "${name}")"
}

# ──────────────────────────────────────────────
# Test environment setup / teardown
# ──────────────────────────────────────────────
create_test_environment() {
	TEST_ROOT="$(mktemp -d)"
	REMOTES="${TEST_ROOT}/remotes"
	export HOME="${TEST_ROOT}/fakehome"
	export GNUPGHOME="${HOME}/.gnupg"
	mkdir -p "${HOME}" "${GNUPGHOME}" "${REMOTES}" "${TEST_ROOT}/workspace"
	chmod 700 "${GNUPGHOME}"

	# nothing from the real environment may leak into the runs
	unset GITHUB_ACTIONS GITHUB_OUTPUT GITHUB_STEP_SUMMARY GITHUB_WORKSPACE RUNNER_TEMP
	unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
	unset GIT_SIGNING_KEY GIT_GPG_SIGN GIT_SSH_KEY_PATH GIT_SSH_COMMAND
	unset GIT_EDITOR VISUAL EDITOR OCTOZIPO_BIN
	while IFS='=' read -r name _; do
		unset "${name}"
	done < <(env | grep -E '^(INPUT_|VDM_)' || true)

	git config --global user.name "${TEST_USER}"
	git config --global user.email "${TEST_EMAIL}"
	git config --global init.defaultBranch master
	# octozipo uses git@<host>:<org>/<repo>.git, send that to the local bare repositories
	git config --global url."${REMOTES}/".insteadOf "git@${TEST_HOST}:"
	git config --global --add url."${REMOTES}/".insteadOf "git@git.vdm.dev:"
}

# shellcheck disable=SC2317  # invoked through the EXIT trap
destroy_test_environment() {
	gpgconf --kill gpg-agent >/dev/null 2>&1 || true
	export HOME="${REAL_HOME}"
	if [[ -n "${TEST_ROOT}" && -d "${TEST_ROOT}" ]]; then
		rm -rf "${TEST_ROOT}"
	fi
}

# ──────────────────────────────────────────────
# Fixture helpers
# ──────────────────────────────────────────────

# make_remote <repo> [seed=true] [branch=master] [org=TEST_ORG]
# Creates a bare repository. A seeded repository gets a first commit on the
# branch (an existing repository), an unseeded one is empty (push-create).
make_remote() {
	local repo="$1" seed="${2:-true}" branch="${3:-master}" org="${4:-${TEST_ORG}}"
	local bare="${REMOTES}/${org}/${repo}.git"
	local work

	rm -rf "${bare}"
	mkdir -p "${REMOTES}/${org}"
	git init -q --bare "${bare}"

	if [[ "${seed}" == "true" ]]; then
		work="$(mktemp -d "${TEST_ROOT}/seed.XXXXXX")"
		(
			cd "${work}" \
				&& git init -q \
				&& printf 'seed\n' > README.md \
				&& git add . \
				&& git commit -q -m "seed" \
				&& git push -q "${bare}" "master:${branch}"
		)
		rm -rf "${work}"
	fi
}

# make_zip <dir> <zip name> <xml name> <version>
# Creates a zip package with an extension manifest, a changelog and a readme.
make_zip() {
	local dir="$1" zip="$2" name="$3" version="$4"
	local work

	work="$(mktemp -d "${TEST_ROOT}/zip.XXXXXX")"
	printf '<?xml version="1.0" encoding="utf-8"?>\n<extension type="component" method="upgrade">\n\t<name>%s</name>\n\t<version>%s</version>\n</extension>\n' \
		"${name}" "${version}" > "${work}/manifest.xml"
	printf '# v%s\n\n- Change for %s\n\n# v0.0.1\n\n- first\n' "${version}" "${version}" > "${work}/CHANGELOG.md"
	printf '%s %s\n' "${name}" "${version}" > "${work}/README.md"
	mkdir -p "${dir}"
	(cd "${work}" && zip -q -r "${dir}/${zip}" .)
	rm -rf "${work}"
}

# run_action <label> [NAME=value ...]
# Runs the action script as GitHub Actions would, with the given environment.
# Sets RUN_EXIT, RUN_LOG, RUN_OUTPUT and RUN_SUMMARY.
run_action() {
	local label="$1"
	shift
	local run_dir="${TEST_ROOT}/runs/${label}"

	mkdir -p "${run_dir}"
	RUN_LOG="${run_dir}/log.txt"
	RUN_OUTPUT="${run_dir}/output.txt"
	RUN_SUMMARY="${run_dir}/summary.md"
	: > "${RUN_OUTPUT}"
	: > "${RUN_SUMMARY}"

	RUN_EXIT=0
	env \
		"GITHUB_ACTIONS=true" \
		"GITHUB_OUTPUT=${RUN_OUTPUT}" \
		"GITHUB_STEP_SUMMARY=${RUN_SUMMARY}" \
		"GITHUB_WORKSPACE=${TEST_ROOT}/workspace" \
		"RUNNER_TEMP=${run_dir}" \
		"INPUT_ORG=${TEST_ORG}" \
		"INPUT_GIT_URL=${TEST_HOST}" \
		"$@" \
		bash "${ACTION_SCRIPT}" > "${RUN_LOG}" 2>&1 || RUN_EXIT=$?
}

# output_value <name>
# Prints the value of a step output written by the last run.
output_value() {
	grep -m1 "^$1=" "${RUN_OUTPUT}" 2>/dev/null | cut -d'=' -f2- || true
}

# Remote repository inspection
remote_dir() {
	printf '%s' "${REMOTES}/${2:-${TEST_ORG}}/$1.git"
}

remote_subjects() {
	git --git-dir="$(remote_dir "$1")" log --format='%s' "${2:-master}" 2>/dev/null || true
}

remote_head_subject() {
	remote_subjects "$1" "${2:-master}" | head -n 1
}

remote_commit_count() {
	git --git-dir="$(remote_dir "$1")" rev-list --count "${2:-master}" 2>/dev/null || printf '0'
}

remote_tags() {
	git --git-dir="$(remote_dir "$1")" tag -l 2>/dev/null | tr '\n' ' ' | sed 's/ $//'
}

remote_file() {
	git --git-dir="$(remote_dir "$1")" show "${3:-master}:$2" 2>/dev/null || true
}

# ──────────────────────────────────────────────
# TEST SUITES
# ──────────────────────────────────────────────

test_prerequisites() {
	log_section "Prerequisites"

	local tool
	for tool in git unzip zip; do
		if command -v "${tool}" >/dev/null 2>&1; then
			pass "${tool} is available"
		else
			fail_test "${tool} is available"
		fi
	done

	assert_file_exists "action script exists" "${ACTION_SCRIPT}"
	assert_file_exists "octozipo script exists" "${OCTOZIPO_SCRIPT}"

	if bash -n "${ACTION_SCRIPT}" 2>/dev/null; then
		pass "action script has valid syntax"
	else
		fail_test "action script has valid syntax"
	fi

	if bash -n "${OCTOZIPO_SCRIPT}" 2>/dev/null; then
		pass "octozipo script has valid syntax"
	else
		fail_test "octozipo script has valid syntax"
	fi

	local help
	help="$(bash "${OCTOZIPO_SCRIPT}" --help 2>&1)"
	if printf '%s' "${help}" | grep -qF -- '--report=<file>'; then
		pass "octozipo --help documents --report"
	else
		fail_test "octozipo --help documents --report"
	fi
}

test_input_validation() {
	log_section "Input validation"

	local zips="${TEST_ROOT}/packages/validation"
	mkdir -p "${zips}"

	run_action val-no-zip-dir "INPUT_ZIP_DIR="
	assert_exit "missing zip-dir fails" 1
	assert_log_contains "missing zip-dir names the input" "::error::Input 'zip-dir' is required"

	run_action val-no-org "INPUT_ZIP_DIR=${zips}" "INPUT_ORG="
	assert_exit "missing org fails" 1
	assert_log_contains "missing org names the input" "Input 'org' is required"

	run_action val-missing-dir "INPUT_ZIP_DIR=${TEST_ROOT}/does-not-exist"
	assert_exit "zip-dir that does not exist fails with 5" 5
	assert_log_contains "zip-dir that does not exist is reported" "does not exist"

	run_action val-bad-bool "INPUT_ZIP_DIR=${zips}" "INPUT_PUSH_CREATE=maybe"
	assert_exit "invalid boolean fails" 1
	assert_log_contains "invalid boolean is reported" "Input 'push-create' must be true or false, got 'maybe'"

	run_action val-bad-url "INPUT_ZIP_DIR=${zips}" "INPUT_GIT_URL=${TEST_HOST}/${TEST_ORG}"
	assert_exit "git-url with a path fails" 1
	assert_log_contains "git-url with a path is reported" "must be a host name only"

	run_action val-mapper "INPUT_ZIP_DIR=${zips}" "INPUT_MAPPER=${TEST_ROOT}/missing.mapper"
	assert_exit "mapper that does not exist fails" 1
	assert_log_contains "mapper that does not exist is reported" "Input 'mapper' points to a file that does not exist"

	run_action val-env-file "INPUT_ZIP_DIR=${zips}" "INPUT_ENV_FILE=${TEST_ROOT}/missing.env"
	assert_exit "env-file that does not exist fails" 1
	assert_log_contains "env-file that does not exist is reported" "Input 'env-file' points to a file that does not exist"

	run_action val-ssh-key "INPUT_ZIP_DIR=${zips}" "INPUT_SSH_KEY_PATH=${TEST_ROOT}/missing.key"
	assert_exit "ssh-key-path that does not exist fails" 1
	assert_log_contains "ssh-key-path that does not exist is reported" "Input 'ssh-key-path' points to a file that does not exist"
}

test_empty_directory() {
	log_section "Empty zip directory"

	local zips="${TEST_ROOT}/packages/empty"
	mkdir -p "${zips}"

	run_action empty "INPUT_ZIP_DIR=${zips}"
	assert_exit "empty directory fails with 6" 6
	assert_log_contains "empty directory is reported" "::error::No zip packages found"

	run_action empty-allowed "INPUT_ZIP_DIR=${zips}" "INPUT_ALLOW_EMPTY=true"
	assert_exit "empty directory passes with allow-empty" 0
	assert_log_contains "empty directory gives a warning" "::warning::No zip packages found"
	assert_output "processed output is 0" processed 0
	assert_output "repositories output is empty" repositories ""
	assert_output "report output is an empty array" report "[]"

	run_action empty-missing-allowed "INPUT_ZIP_DIR=${TEST_ROOT}/does-not-exist" "INPUT_ALLOW_EMPTY=yes"
	assert_exit "missing directory passes with allow-empty" 0
}

test_update_and_create() {
	log_section "Update an existing repository and create a new one"

	local zips="${TEST_ROOT}/packages/main"
	make_remote alpha true
	make_remote beta false
	make_zip "${zips}" alpha_v1.0.1.zip "Alpha" 1.0.1
	make_zip "${zips}" beta_v2.0.0.zip "Beta" 2.0.0

	run_action main "INPUT_ZIP_DIR=${zips}" "INPUT_PUSH_CREATE=true"
	assert_exit "run succeeds" 0
	assert_output "processed output" processed 2
	assert_output "created output" created 1
	assert_output "updated output" updated 1
	assert_output "unchanged output" unchanged 0
	assert_output "pending output" pending 0
	assert_output "skipped output" skipped 0
	assert_output "failed output" failed 0
	assert_output "dry-run output" dry-run 0
	assert_output "repositories output lists both repositories" repositories "${TEST_ORG}/alpha,${TEST_ORG}/beta"

	local report
	report="$(output_value report)"
	assert_eq "report output holds the updated package" \
		"{\"status\":\"updated\",\"zip\":\"alpha_v1.0.1.zip\",\"git_url\":\"${TEST_HOST}\",\"org\":\"${TEST_ORG}\",\"repo\":\"alpha\",\"branch\":\"master\",\"version\":\"1.0.1\"}" \
		"$(printf '%s' "${report}" | tr -d '[]' | cut -d'}' -f1)}"
	assert_file_contains "report output holds the created package" "${RUN_OUTPUT}" '"status":"created","zip":"beta_v2.0.0.zip"'

	local report_file
	report_file="$(output_value report-file)"
	assert_file_exists "report file exists" "${report_file}"
	assert_eq "report file has one line per package" 2 "$(wc -l < "${report_file}")"
	assert_file_contains "report file line" "${report_file}" "$(printf 'updated\talpha_v1.0.1.zip\t%s\t%s\talpha\tmaster\t1.0.1' "${TEST_HOST}" "${TEST_ORG}")"

	assert_eq "existing repository received the release commit" "Release of v1.0.1" "$(remote_head_subject alpha)"
	assert_eq "existing repository has two commits" 2 "$(remote_commit_count alpha)"
	assert_eq "existing repository was tagged" "v1.0.1" "$(remote_tags alpha)"
	assert_eq "existing repository holds the package files" "Alpha 1.0.1" "$(remote_file alpha README.md)"
	assert_eq "new repository received the first commit" "first commit - v2.0.0" "$(remote_head_subject beta)"
	assert_eq "new repository was tagged" "v2.0.0" "$(remote_tags beta)"
	assert_eq "new repository holds the manifest" "yes" "$([[ -n "$(remote_file beta manifest.xml)" ]] && echo yes || echo no)"

	assert_file_not_exists "processed zip was removed" "${zips}/alpha_v1.0.1.zip"
	assert_file_not_exists "created zip was removed" "${zips}/beta_v2.0.0.zip"
	assert_dir_not_exists "repository directory was removed" "${zips}/alpha"
	assert_dir_not_exists "new repository directory was removed" "${zips}/beta"

	assert_file_contains "summary has the heading" "${RUN_SUMMARY}" "### Octozipo v"
	assert_file_contains "summary counts the packages" "${RUN_SUMMARY}" "2 processed, 1 created, 1 updated"
	assert_file_contains "summary lists the updated package" "${RUN_SUMMARY}" "| updated | alpha_v1.0.1.zip | ${TEST_HOST}/${TEST_ORG}/alpha | master | 1.0.1 |"
	assert_log_contains "log is grouped" "::group::Octozipo v"
	assert_log_contains "log announces success" "Octozipo completed successfully"

	# the same package again: nothing changes
	make_zip "${zips}" alpha_v1.0.1.zip "Alpha" 1.0.1
	run_action rerun "INPUT_ZIP_DIR=${zips}"
	assert_exit "re-run succeeds" 0
	assert_output "re-run reports the repository as unchanged" unchanged 1
	assert_output "re-run updated nothing" updated 0
	assert_output "re-run lists no repositories" repositories ""
	assert_eq "re-run added no commit" 2 "$(remote_commit_count alpha)"
}

test_dry_run() {
	log_section "Dry run"

	local zips="${TEST_ROOT}/packages/dry"
	make_remote gamma true
	make_zip "${zips}" gamma_v1.1.0.zip "Gamma" 1.1.0

	run_action dry "INPUT_ZIP_DIR=${zips}" "INPUT_DRY_RUN=true"
	assert_exit "dry run succeeds" 0
	assert_output "dry run is counted" dry-run 1
	assert_output "dry run updated nothing" updated 0
	assert_output "dry run lists no repositories" repositories ""
	assert_log_contains "dry run shows the push it skipped" "[dry run] git push origin master"
	assert_eq "remote did not change" "seed" "$(remote_head_subject gamma)"
	assert_eq "remote was not tagged" "" "$(remote_tags gamma)"
	assert_dir_exists "repository directory is kept in a dry run" "${zips}/gamma"
}

test_pending_without_push_create() {
	log_section "New repository without push-create"

	local zips="${TEST_ROOT}/packages/pending"
	make_zip "${zips}" delta_v1.0.0.zip "Delta" 1.0.0

	run_action pending "INPUT_ZIP_DIR=${zips}"
	assert_exit "run succeeds" 0
	assert_output "repository is pending" pending 1
	assert_output "nothing was created" created 0
	assert_log_contains "unreachable remote is explained" "Remote repository (git@${TEST_HOST}:${TEST_ORG}/delta.git) is not available"
	assert_log_contains "pending repositories give a warning" "::warning::1 new repositories were prepared but not pushed"
	assert_file_exists "zip is kept for a pending repository" "${zips}/delta_v1.0.0.zip"
	assert_dir_exists "local repository is kept for a pending repository" "${zips}/delta/.git"
	assert_dir_not_exists "no remote was created" "$(remote_dir delta)"
}

test_push_failure() {
	log_section "Push failure"

	local zips="${TEST_ROOT}/packages/failure"
	make_zip "${zips}" epsilon_v1.0.0.zip "Epsilon" 1.0.0

	# push-create against a remote that does not exist at all
	run_action failure "INPUT_ZIP_DIR=${zips}" "INPUT_PUSH_CREATE=true"
	assert_exit "failed push fails the action with the octozipo exit code" 7
	assert_output "failed package is counted" failed 1
	assert_output "failed package is still processed" processed 1
	assert_log_contains "git error is shown" "[error] git push failed (exit 128)"
	assert_log_contains "git reason is shown" "does not appear to be a git repository"
	assert_log_contains "action error annotation" "::error::Octozipo failed with exit code 7"
	assert_file_contains "summary lists the failed package" "${RUN_SUMMARY}" "| failed | epsilon_v1.0.0.zip |"
}

test_broken_package() {
	log_section "Broken package"

	local zips="${TEST_ROOT}/packages/broken"
	make_remote zeta true
	make_zip "${zips}" zeta_v1.0.2.zip "Zeta" 1.0.2
	printf 'this is not a zip file\n' > "${zips}/broken.zip"

	run_action broken "INPUT_ZIP_DIR=${zips}"
	assert_exit "broken package does not fail the run" 0
	assert_output "broken package is skipped" skipped 1
	assert_output "good package is still updated" updated 1
	assert_log_contains "unzip failure is shown" "[error] unzip failed"
	assert_log_contains "skipped packages give a warning" "::warning::1 packages were skipped"
	assert_file_exists "broken package is left in place" "${zips}/broken.zip"
	assert_eq "no extraction folders are left behind" 0 "$(find "${zips}" -mindepth 1 -maxdepth 1 -type d | wc -l)"
}

test_relative_paths_and_env_fallbacks() {
	log_section "Relative paths and VDM_* environment fallbacks"

	local zips="${TEST_ROOT}/workspace/build/packages"
	make_remote eta true
	make_zip "${zips}" eta_v3.0.0.zip "Eta" 3.0.0

	# no INPUT_* values at all: everything comes from the environment
	run_action env-fallback \
		"INPUT_ZIP_DIR=" "INPUT_ORG=" "INPUT_GIT_URL=" \
		"VDM_ZIP_DIR=build/packages" "VDM_ORG=${TEST_ORG}" "VDM_GIT_URL=${TEST_HOST}" \
		"VDM_PUSH_CREATE=1" "VDM_KEEP_ZIP=on" "VDM_REPORT_FILE=reports/eta.tsv"
	assert_exit "run with environment settings succeeds" 0
	assert_log_contains "relative zip-dir is resolved against the workspace" "zip-dir:      ${zips}"
	assert_output "repository was updated" updated 1
	assert_file_exists "keep-zip from the environment keeps the zip" "${zips}/eta_v3.0.0.zip"
	assert_output "relative report-file is resolved against the workspace" report-file "${TEST_ROOT}/workspace/reports/eta.tsv"
	assert_file_exists "report file was written where asked" "${TEST_ROOT}/workspace/reports/eta.tsv"
	assert_eq "remote received the release" "Release of v3.0.0" "$(remote_head_subject eta)"
}

test_git_url_cleaning() {
	log_section "git-url cleaning"

	local zips="${TEST_ROOT}/packages/url"
	make_remote theta true
	make_zip "${zips}" theta_v1.0.0.zip "Theta" 1.0.0

	run_action url "INPUT_ZIP_DIR=${zips}" "INPUT_GIT_URL=https://git@${TEST_HOST}/"
	assert_exit "run with a full url succeeds" 0
	assert_log_contains "scheme, user and slashes are removed" "git-url:      ${TEST_HOST}"
	assert_output "repository was updated" updated 1
}

test_mapper_spacer_and_xml_name() {
	log_section "Mapper file, spacer and use-xml-name"

	local zips="${TEST_ROOT}/packages/mapper"
	local mapper="${TEST_ROOT}/workspace/octozipo.mapper"

	# mapper: package iota lives in repository iota-renamed on branch develop
	make_remote iota-renamed true develop
	make_zip "${zips}" iota_v1.0.0.zip "Iota" 1.0.0
	printf 'iota=iota-renamed\niota_branch=develop\n' > "${mapper}"

	run_action mapper "INPUT_ZIP_DIR=${zips}" "INPUT_MAPPER=octozipo.mapper"
	assert_exit "run with a mapper succeeds" 0
	assert_output "mapped repository was updated" updated 1
	assert_output "mapped repository name is reported" repositories "${TEST_ORG}/iota-renamed"
	assert_file_contains "mapped branch is reported" "${RUN_OUTPUT}" '"repo":"iota-renamed","branch":"develop"'
	assert_eq "mapped branch received the release" "Release of v1.0.0" "$(remote_head_subject iota-renamed develop)"

	# spacer: kappa_two stays kappa_two instead of kappa-two
	make_remote kappa_two true
	make_zip "${zips}" kappa_two_v1.0.0.zip "Kappa Two" 1.0.0

	run_action spacer "INPUT_ZIP_DIR=${zips}" "INPUT_SPACER=_"
	assert_exit "run with a spacer succeeds" 0
	assert_output "repository with the spacer was updated" repositories "${TEST_ORG}/kappa_two"

	# use-xml-name: the manifest name wins over the zip name
	make_remote lambda-extension true
	make_zip "${zips}" lambda_v1.0.0.zip "Lambda Extension" 1.0.0

	run_action xml-name "INPUT_ZIP_DIR=${zips}" "INPUT_USE_XML_NAME=true"
	assert_exit "run with use-xml-name succeeds" 0
	assert_output "repository named after the manifest was updated" repositories "${TEST_ORG}/lambda-extension"
}

test_env_file() {
	log_section "Environment file"

	local zips="${TEST_ROOT}/packages/env-file"
	local env_file="${TEST_ROOT}/workspace/.octozipo-env"

	# the environment file may override the inputs, here the organisation
	make_remote omicron true master otherorg
	make_zip "${zips}" omicron_v1.0.0.zip "Omicron" 1.0.0
	printf 'VDM_ORG="otherorg"\n' > "${env_file}"

	run_action env-file "INPUT_ZIP_DIR=${zips}" "INPUT_ENV_FILE=${env_file}"
	assert_exit "run with an environment file succeeds" 0
	assert_output "organisation from the environment file was used" repositories "otherorg/omicron"
	assert_eq "repository in the other organisation received the release" "Release of v1.0.0" "$(git --git-dir="$(remote_dir omicron otherorg)" log --format='%s' -1 master)"
}

test_git_identity_inputs() {
	log_section "Git identity inputs"

	local zips="${TEST_ROOT}/packages/identity"
	make_remote mu true
	make_zip "${zips}" mu_v1.0.0.zip "Mu" 1.0.0

	run_action identity "INPUT_ZIP_DIR=${zips}" "INPUT_GIT_USER=Other Robot" "INPUT_GIT_EMAIL=other@test.local"
	assert_exit "run with git identity inputs succeeds" 0
	assert_log_contains "author name is passed to octozipo" "Git author name set to: Other Robot"
	assert_eq "commit author comes from the inputs" "Other Robot <other@test.local>" \
		"$(git --git-dir="$(remote_dir mu)" log --format='%an <%ae>' -1 master)"
	assert_eq "commit committer comes from the inputs" "Other Robot <other@test.local>" \
		"$(git --git-dir="$(remote_dir mu)" log --format='%cn <%ce>' -1 master)"

	# an ssh key path is exported for the git commands (the local rewrite ignores it)
	printf 'not a real key\n' > "${TEST_ROOT}/workspace/deploy.key"
	make_zip "${zips}" mu_v1.0.1.zip "Mu" 1.0.1
	run_action ssh-key "INPUT_ZIP_DIR=${zips}" "INPUT_SSH_KEY_PATH=deploy.key"
	assert_exit "run with an ssh key path succeeds" 0
	assert_log_contains "ssh key path is passed to octozipo" "Git SSH key path set to: ${TEST_ROOT}/workspace/deploy.key"
}

test_quiet_and_debug() {
	log_section "Quiet and debug"

	local zips="${TEST_ROOT}/packages/quiet"
	make_remote xi true
	make_zip "${zips}" xi_v1.0.0.zip "Xi" 1.0.0
	printf 'this is not a zip file\n' > "${zips}/broken.zip"

	run_action debug "INPUT_ZIP_DIR=${zips}" "INPUT_DEBUG=true"
	assert_exit "debug run succeeds" 0
	assert_log_contains "debug run prints the configuration" "Options: VALUES"
	assert_output "debug run processes nothing" processed 0
	assert_file_exists "debug run leaves the packages alone" "${zips}/xi_v1.0.0.zip"

	run_action quiet "INPUT_ZIP_DIR=${zips}" "INPUT_QUIET=true"
	assert_exit "quiet run succeeds" 0
	assert_output "quiet run still updates" updated 1
	assert_log_not_contains "quiet run hides the info messages" "[info] Successfully unzipped"
	assert_log_contains "quiet run still shows errors" "[error] unzip failed"
}

test_signed_tags() {
	log_section "Signed commits and tags (git-user configuration)"

	if ! command -v gpg >/dev/null 2>&1; then
		printf '  SKIP gpg is not installed\n'
		return 0
	fi

	local key_id
	gpg --batch --quiet --gen-key <<EOF 2>/dev/null
%no-protection
Key-Type: eddsa
Key-Curve: ed25519
Key-Usage: sign
Name-Real: ${TEST_USER}
Name-Email: ${TEST_EMAIL}
Expire-Date: 0
%commit
EOF
	key_id="$(gpg --batch --with-colons --list-secret-keys "${TEST_EMAIL}" 2>/dev/null | awk -F: '/^sec/ { print $5; exit }')"
	if [[ -z "${key_id}" ]]; then
		fail_test "gpg key generation (cannot test signing)"
		return 0
	fi

	# the same global configuration octoleo/git-user writes
	git config --global user.signingkey "${key_id}"
	git config --global commit.gpgsign true
	git config --global tag.gpgSign true
	git config --global gpg.program gpg

	local zips="${TEST_ROOT}/packages/signed"
	make_remote nu true
	make_remote nu-new false
	make_zip "${zips}" nu_v1.0.0.zip "Nu" 1.0.0
	make_zip "${zips}" nu_new_v1.0.0.zip "Nu New" 1.0.0

	run_action signed "INPUT_ZIP_DIR=${zips}" "INPUT_PUSH_CREATE=true"
	assert_exit "run with signing enabled succeeds without a terminal" 0
	assert_output "signed update was pushed" updated 1
	assert_output "signed new repository was pushed" created 1
	assert_eq "commit is signed" "G" "$(git --git-dir="$(remote_dir nu)" log --format='%G?' -1 master)"
	assert_eq "tag is an annotated (signed) tag" "tag" "$(git --git-dir="$(remote_dir nu)" cat-file -t v1.0.0 2>/dev/null)"
	assert_eq "tag message is the commit message" "Release of v1.0.0" "$(git --git-dir="$(remote_dir nu)" tag -l --format='%(contents:subject)' v1.0.0)"
	if git --git-dir="$(remote_dir nu)" tag -v v1.0.0 >/dev/null 2>&1; then
		pass "tag signature verifies"
	else
		fail_test "tag signature verifies"
	fi
	assert_eq "first commit of the new repository is signed" "G" "$(git --git-dir="$(remote_dir nu-new)" log --format='%G?' -1 master)"
	assert_eq "new repository tag is signed" "tag" "$(git --git-dir="$(remote_dir nu-new)" cat-file -t v1.0.0 2>/dev/null)"

	# an unsigned run must still create lightweight tags
	git config --global --unset user.signingkey
	git config --global --unset commit.gpgsign
	git config --global --unset tag.gpgSign
	git config --global --unset gpg.program
	gpgconf --kill gpg-agent >/dev/null 2>&1 || true

	make_remote nu-plain true
	make_zip "${zips}" nu_plain_v1.0.0.zip "Nu Plain" 1.0.0
	run_action unsigned "INPUT_ZIP_DIR=${zips}"
	assert_exit "run without signing succeeds" 0
	assert_eq "tag without signing is a lightweight tag" "commit" "$(git --git-dir="$(remote_dir nu-plain)" cat-file -t v1.0.0 2>/dev/null)"
}

# ──────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────
main() {
	printf '%s\n' "$(_bold "Octozipo action — Test Suite")"
	printf 'Script under test: %s\n' "${ACTION_SCRIPT}"
	printf 'Date:              %s\n' "$(date -u '+%Y-%m-%d %H:%M:%S UTC')"

	ACTION_SCRIPT="$(cd "$(dirname "${ACTION_SCRIPT}")" && pwd)/$(basename "${ACTION_SCRIPT}")"
	OCTOZIPO_SCRIPT="$(dirname "${ACTION_SCRIPT}")/octozipo"

	create_test_environment
	trap destroy_test_environment EXIT

	test_prerequisites
	test_input_validation
	test_empty_directory
	test_update_and_create
	test_dry_run
	test_pending_without_push_create
	test_push_failure
	test_broken_package
	test_relative_paths_and_env_fallbacks
	test_git_url_cleaning
	test_mapper_spacer_and_xml_name
	test_env_file
	test_git_identity_inputs
	test_quiet_and_debug
	test_signed_tags

	# Summary
	printf '\n%s\n' "════════════════════════════════════════"
	printf 'Tests run:    %d\n' "${TESTS_RUN}"
	printf 'Passed:       %s\n' "$(_green "${TESTS_PASSED}")"
	if ((TESTS_FAILED > 0)); then
		printf 'Failed:       %s\n' "$(_red "${TESTS_FAILED}")"
		printf '\n%s\n' "$(_red "SOME TESTS FAILED")"
		exit 1
	else
		printf 'Failed:       0\n'
		printf '\n%s\n' "$(_green "ALL TESTS PASSED")"
		exit 0
	fi
}

main "$@"
