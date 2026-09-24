#!/usr/bin/env bash
#
# src/action.sh — GitHub Actions entry point for Octozipo.
#
# Reads the action inputs (INPUT_*), falls back to the matching VDM_* environment
# variables (so every setting can also be set with a workflow or job `env:` block),
# builds the octozipo command line, runs it, and publishes the result of every
# package as step outputs and as a job summary.
#
# Usage (normally called by action.yml):
#   INPUT_ZIP_DIR=/path/to/zips INPUT_ORG=joomla ./src/action.sh
#
# Environment:
#   INPUT_*              the action inputs (see action.yml)
#   VDM_*                fallback values for the inputs (see resolve_settings)
#   OCTOZIPO_BIN         the octozipo script to run (default: octozipo next to this file)
#   GITHUB_WORKSPACE     base directory for relative paths (default: current directory)
#   GITHUB_OUTPUT        file that receives the step outputs (optional)
#   GITHUB_STEP_SUMMARY  file that receives the job summary (optional)
#   RUNNER_TEMP          directory of the default report file (default: mktemp)
#
# Exit codes:
#   0     all packages were processed
#   1     invalid input or environment
#   5-8   octozipo error (see the octozipo script)
#   17    octozipo option error
#

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

OCTOZIPO_BIN="${OCTOZIPO_BIN:-${SCRIPT_DIR}/octozipo}"

# ──────────────────────────────────────────────
# Settings (filled by resolve_settings)
# ──────────────────────────────────────────────
ZIP_DIR=""
ORG=""
GIT_URL=""
MAPPER=""
ENV_FILE=""
SPACER=""
GIT_DATE=""
REPORT_FILE=""
PUSH_CREATE=false
KEEP_REPO=false
KEEP_ZIP=false
USE_XML_NAME=false
DRY_RUN=false
QUIET=false
DEBUG=false
ALLOW_EMPTY=false
GIT_USER=""
GIT_EMAIL=""
GIT_SIGNING_KEY=""
GIT_GPG_SIGN=""
SSH_KEY_PATH=""

# Result counters (filled by publish_results)
declare -a OCTOZIPO_ARGS=()

# ──────────────────────────────────────────────
# Logging helpers
#
# Inside GitHub Actions the messages use workflow commands, so that errors
# and warnings show up as annotations on the workflow run.
# ──────────────────────────────────────────────
in_github_actions() {
	[[ "${GITHUB_ACTIONS:-}" == "true" ]]
}

log_info() {
	printf '[INFO]  %s\n' "$*"
}

log_warn() {
	if in_github_actions; then
		printf '::warning::%s\n' "$*"
	else
		printf '[WARN]  %s\n' "$*" >&2
	fi
}

log_error() {
	if in_github_actions; then
		printf '::error::%s\n' "$*"
	else
		printf '[ERROR] %s\n' "$*" >&2
	fi
}

fail() {
	log_error "$*"
	exit 1
}

group_start() {
	if in_github_actions; then
		printf '::group::%s\n' "$*"
	else
		printf '\n── %s ──\n' "$*"
	fi
}

group_end() {
	if in_github_actions; then
		printf '::endgroup::\n'
	fi
}

# ──────────────────────────────────────────────
# Value helpers
# ──────────────────────────────────────────────

# set_bool <variable> <input name> <value> <default>
# Sets the variable to "true" or "false". An empty value gives the default,
# anything that is not a recognised boolean fails the action with a clear message.
set_bool() {
	local variable="$1" name="$2" value="${3,,}" default="$4"
	case "${value}" in
		'') printf -v "${variable}" '%s' "${default}" ;;
		true | 1 | yes | y | on) printf -v "${variable}" 'true' ;;
		false | 0 | no | n | off) printf -v "${variable}" 'false' ;;
		*) fail "Input '${name}' must be true or false, got '${3}'." ;;
	esac
}

# resolve_path <path>
# Prints an absolute path. Relative paths are resolved against the workspace.
resolve_path() {
	local path="$1"
	if [[ "${path}" != /* ]]; then
		path="${GITHUB_WORKSPACE:-${PWD}}/${path}"
	fi
	printf '%s' "${path}"
}

# clean_git_url <url>
# Octozipo builds SSH urls (git@host:org/repo.git), so only a host name is
# accepted. A scheme, a git@ prefix and trailing slashes are removed.
clean_git_url() {
	local url="$1"
	url="${url#*://}"
	url="${url#git@}"
	url="${url%%/}"
	url="${url%%/}"
	printf '%s' "${url}"
}

# json_string <value>
# Prints the value as a JSON string literal.
json_string() {
	local value="$1"
	value="${value//\\/\\\\}"
	value="${value//\"/\\\"}"
	value="${value//$'\t'/\\t}"
	value="${value//$'\n'/\\n}"
	value="${value//$'\r'/\\r}"
	printf '"%s"' "${value}"
}

# set_output <name> <value>
# Publishes a step output (when running inside GitHub Actions) and logs it.
set_output() {
	local name="$1" value="$2"
	if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
		if [[ "${value}" == *$'\n'* ]]; then
			printf '%s<<OCTOZIPO_EOF\n%s\nOCTOZIPO_EOF\n' "${name}" "${value}" >> "${GITHUB_OUTPUT}"
		else
			printf '%s=%s\n' "${name}" "${value}" >> "${GITHUB_OUTPUT}"
		fi
	fi
	log_info "output ${name}=${value}"
}

# octozipo_version
# Prints the version of the octozipo script that will be run.
octozipo_version() {
	local version
	version="$(grep -m1 '^PROGRAM_VERSION=' "${OCTOZIPO_BIN}" 2>/dev/null | cut -d'"' -f2 || true)"
	printf '%s' "${version:-unknown}"
}

# ──────────────────────────────────────────────
# Settings
# ──────────────────────────────────────────────

# Every input falls back to an environment variable, so a workflow can either
# pass the values as `with:` inputs or set them once in an `env:` block.
resolve_settings() {
	ZIP_DIR="${INPUT_ZIP_DIR:-${VDM_ZIP_DIR:-}}"
	ORG="${INPUT_ORG:-${VDM_ORG:-}}"
	GIT_URL="${INPUT_GIT_URL:-${VDM_GIT_URL:-git.vdm.dev}}"
	MAPPER="${INPUT_MAPPER:-${VDM_MAPPER_FILE_PATH:-}}"
	ENV_FILE="${INPUT_ENV_FILE:-${VDM_ENV_FILE_PATH:-}}"
	SPACER="${INPUT_SPACER:-${VDM_SPACER:-}}"
	GIT_DATE="${INPUT_GIT_DATE:-${VDM_GIT_DATE:-}}"
	REPORT_FILE="${INPUT_REPORT_FILE:-${VDM_REPORT_FILE:-}}"

	set_bool PUSH_CREATE push-create "${INPUT_PUSH_CREATE:-${VDM_PUSH_CREATE:-}}" false
	set_bool KEEP_REPO keep-repo "${INPUT_KEEP_REPO:-${VDM_KEEP_REPO:-}}" false
	set_bool KEEP_ZIP keep-zip "${INPUT_KEEP_ZIP:-${VDM_KEEP_ZIP:-}}" false
	set_bool USE_XML_NAME use-xml-name "${INPUT_USE_XML_NAME:-${VDM_USE_XML_NAME:-}}" false
	set_bool DRY_RUN dry-run "${INPUT_DRY_RUN:-${VDM_DRY_RUN:-}}" false
	set_bool QUIET quiet "${INPUT_QUIET:-${VDM_QUIET:-}}" false
	set_bool DEBUG debug "${INPUT_DEBUG:-${VDM_DEBUG:-}}" false
	set_bool ALLOW_EMPTY allow-empty "${INPUT_ALLOW_EMPTY:-${VDM_ALLOW_EMPTY:-}}" false

	GIT_USER="${INPUT_GIT_USER:-${GIT_AUTHOR_NAME:-}}"
	GIT_EMAIL="${INPUT_GIT_EMAIL:-${GIT_AUTHOR_EMAIL:-}}"
	GIT_SIGNING_KEY="${INPUT_GIT_SIGNING_KEY:-${GIT_SIGNING_KEY:-}}"
	GIT_GPG_SIGN="${INPUT_GIT_GPG_SIGN:-${GIT_GPG_SIGN:-}}"
	SSH_KEY_PATH="${INPUT_SSH_KEY_PATH:-${GIT_SSH_KEY_PATH:-}}"
	if [[ -n "${GIT_GPG_SIGN}" ]]; then
		set_bool GIT_GPG_SIGN git-gpg-sign "${GIT_GPG_SIGN}" false
	fi
}

validate_settings() {
	[[ -f "${OCTOZIPO_BIN}" ]] || fail "The octozipo script was not found at ${OCTOZIPO_BIN}."

	for tool in git unzip curl awk sed; do
		command -v "${tool}" >/dev/null 2>&1 || fail "Octozipo needs '${tool}', but it is not installed on this runner."
	done

	[[ -n "${ZIP_DIR}" ]] || fail "Input 'zip-dir' is required (or set VDM_ZIP_DIR): the directory that holds the zip packages."
	[[ -n "${ORG}" ]] || fail "Input 'org' is required (or set VDM_ORG): the organisation/user that owns the repositories."

	GIT_URL="$(clean_git_url "${GIT_URL}")"
	[[ -n "${GIT_URL}" ]] || fail "Input 'git-url' must be the host name of the git server, for example git.vdm.dev."
	[[ "${GIT_URL}" != */* ]] || fail "Input 'git-url' must be a host name only (no path), got '${GIT_URL}'."

	ZIP_DIR="$(resolve_path "${ZIP_DIR}")"

	if [[ -n "${MAPPER}" ]]; then
		MAPPER="$(resolve_path "${MAPPER}")"
		[[ -f "${MAPPER}" ]] || fail "Input 'mapper' points to a file that does not exist: ${MAPPER}"
	fi

	if [[ -n "${ENV_FILE}" ]]; then
		ENV_FILE="$(resolve_path "${ENV_FILE}")"
		[[ -f "${ENV_FILE}" ]] || fail "Input 'env-file' points to a file that does not exist: ${ENV_FILE}"
	fi

	if [[ -n "${SSH_KEY_PATH}" ]]; then
		SSH_KEY_PATH="$(resolve_path "${SSH_KEY_PATH}")"
		[[ -f "${SSH_KEY_PATH}" ]] || fail "Input 'ssh-key-path' points to a file that does not exist: ${SSH_KEY_PATH}"
	fi

	if [[ -z "${REPORT_FILE}" ]]; then
		if [[ -n "${RUNNER_TEMP:-}" && -d "${RUNNER_TEMP}" ]]; then
			REPORT_FILE="${RUNNER_TEMP}/octozipo-report.tsv"
		else
			REPORT_FILE="$(mktemp "${TMPDIR:-/tmp}/octozipo-report.XXXXXX")"
		fi
	else
		REPORT_FILE="$(resolve_path "${REPORT_FILE}")"
		mkdir -p "$(dirname "${REPORT_FILE}")"
	fi
	# the report always describes this run only
	: > "${REPORT_FILE}"
}

show_settings() {
	log_info "Octozipo v$(octozipo_version) (${OCTOZIPO_BIN})"
	log_info "zip-dir:      ${ZIP_DIR}"
	log_info "org:          ${ORG}"
	log_info "git-url:      ${GIT_URL}"
	log_info "mapper:       ${MAPPER:-<none>}"
	log_info "env-file:     ${ENV_FILE:-<auto>}"
	log_info "spacer:       ${SPACER:-<default>}"
	log_info "git-date:     ${GIT_DATE:-<now>}"
	log_info "push-create:  ${PUSH_CREATE}"
	log_info "use-xml-name: ${USE_XML_NAME}"
	log_info "keep-repo:    ${KEEP_REPO}"
	log_info "keep-zip:     ${KEEP_ZIP}"
	log_info "dry-run:      ${DRY_RUN}"
	log_info "quiet:        ${QUIET}"
	log_info "debug:        ${DEBUG}"
	log_info "allow-empty:  ${ALLOW_EMPTY}"
	log_info "git-user:     ${GIT_USER:-<git config>}"
	log_info "git-email:    ${GIT_EMAIL:-<git config>}"
	log_info "signing-key:  ${GIT_SIGNING_KEY:-<git config>}"
	log_info "gpg-sign:     ${GIT_GPG_SIGN:-<git config>}"
	log_info "ssh-key-path: ${SSH_KEY_PATH:-<git config>}"
	log_info "report-file:  ${REPORT_FILE}"
}

# ──────────────────────────────────────────────
# Git identity
#
# Normally the git user, signing and SSH access are configured before this
# action runs (for example with octoleo/git-user). These inputs are only
# exported when given, so an existing configuration is left untouched.
# ──────────────────────────────────────────────
prepare_git_environment() {
	if [[ -n "${GIT_USER}" ]]; then
		export GIT_AUTHOR_NAME="${GIT_USER}"
		export GIT_COMMITTER_NAME="${GIT_USER}"
	fi
	if [[ -n "${GIT_EMAIL}" ]]; then
		export GIT_AUTHOR_EMAIL="${GIT_EMAIL}"
		export GIT_COMMITTER_EMAIL="${GIT_EMAIL}"
	fi
	if [[ -n "${GIT_SIGNING_KEY}" ]]; then
		export GIT_SIGNING_KEY
	fi
	if [[ -n "${GIT_GPG_SIGN}" ]]; then
		export GIT_GPG_SIGN
	fi
	if [[ -n "${SSH_KEY_PATH}" ]]; then
		export GIT_SSH_KEY_PATH="${SSH_KEY_PATH}"
		# the remote checks and clones happen before octozipo configures the
		# repository, so the key must also be used by those git commands
		if [[ -z "${GIT_SSH_COMMAND:-}" ]]; then
			export GIT_SSH_COMMAND="ssh -i ${SSH_KEY_PATH} -o IdentitiesOnly=yes"
		fi
	fi
}

# ──────────────────────────────────────────────
# Octozipo command line
# ──────────────────────────────────────────────
build_arguments() {
	OCTOZIPO_ARGS=(
		--zip-dir "${ZIP_DIR}"
		--org "${ORG}"
		--git-url "${GIT_URL}"
		--report "${REPORT_FILE}"
	)

	if [[ -n "${MAPPER}" ]]; then
		OCTOZIPO_ARGS+=(--mapper "${MAPPER}")
	fi
	if [[ -n "${ENV_FILE}" ]]; then
		OCTOZIPO_ARGS+=(--env "${ENV_FILE}")
	fi
	if [[ -n "${SPACER}" ]]; then
		OCTOZIPO_ARGS+=(--spacer "${SPACER}")
	fi
	if [[ -n "${GIT_DATE}" ]]; then
		OCTOZIPO_ARGS+=(--git-date "${GIT_DATE}")
	fi
	if [[ "${PUSH_CREATE}" == "true" ]]; then
		OCTOZIPO_ARGS+=(--push-create)
	fi
	if [[ "${USE_XML_NAME}" == "true" ]]; then
		OCTOZIPO_ARGS+=(--use-xml-name)
	fi
	if [[ "${KEEP_REPO}" == "true" ]]; then
		OCTOZIPO_ARGS+=(--keep-repo)
	fi
	if [[ "${KEEP_ZIP}" == "true" ]]; then
		OCTOZIPO_ARGS+=(--keep-zip)
	fi
	if [[ "${DRY_RUN}" == "true" ]]; then
		OCTOZIPO_ARGS+=(--dry)
	fi
	if [[ "${QUIET}" == "true" ]]; then
		OCTOZIPO_ARGS+=(--quiet)
	fi
	if [[ "${DEBUG}" == "true" ]]; then
		OCTOZIPO_ARGS+=(--debug)
	fi
}

# count_packages
# Prints the number of zip files found directly inside the zip directory.
count_packages() {
	local -a packages=()
	if [[ -d "${ZIP_DIR}" ]]; then
		shopt -s nullglob
		packages=("${ZIP_DIR}"/*.zip)
		shopt -u nullglob
	fi
	printf '%d' "${#packages[@]}"
}

# ──────────────────────────────────────────────
# Results
#
# Octozipo writes one tab separated line per package to the report file:
#   status  zip  git url  org  repo  branch  version
# These are turned into step outputs and a job summary.
# ──────────────────────────────────────────────
publish_results() {
	local processed=0 created=0 updated=0 unchanged=0 pending=0 skipped=0 failed=0 dry=0
	local -a repositories=()
	local -a rows=()
	local -a summary=()
	local line status zip git_url org repo branch version
	local separator=$'\x1f'

	if [[ -f "${REPORT_FILE}" ]]; then
		while IFS= read -r line || [[ -n "${line}" ]]; do
			[[ -n "${line}" ]] || continue
			# tabs are IFS whitespace, so empty columns would collapse; use a
			# non whitespace separator to keep every column in place
			line="${line//$'\t'/${separator}}"
			IFS="${separator}" read -r status zip git_url org repo branch version <<< "${line}"
			processed=$((processed + 1))
			case "${status}" in
				created)
					created=$((created + 1))
					repositories+=("${org}/${repo}")
					;;
				updated)
					updated=$((updated + 1))
					repositories+=("${org}/${repo}")
					;;
				unchanged) unchanged=$((unchanged + 1)) ;;
				pending) pending=$((pending + 1)) ;;
				skipped) skipped=$((skipped + 1)) ;;
				failed) failed=$((failed + 1)) ;;
				dry-run) dry=$((dry + 1)) ;;
			esac
			rows+=("{\"status\":$(json_string "${status}"),\"zip\":$(json_string "${zip}"),\"git_url\":$(json_string "${git_url}"),\"org\":$(json_string "${org}"),\"repo\":$(json_string "${repo}"),\"branch\":$(json_string "${branch}"),\"version\":$(json_string "${version}")}")
			summary+=("| ${status} | ${zip} | ${git_url}/${org}/${repo} | ${branch} | ${version} |")
		done < "${REPORT_FILE}"
	fi

	local repositories_csv="" rows_json=""
	if ((${#repositories[@]} > 0)); then
		repositories_csv="$(IFS=,; printf '%s' "${repositories[*]}")"
	fi
	if ((${#rows[@]} > 0)); then
		rows_json="$(IFS=,; printf '%s' "${rows[*]}")"
	fi

	set_output processed "${processed}"
	set_output created "${created}"
	set_output updated "${updated}"
	set_output unchanged "${unchanged}"
	set_output pending "${pending}"
	set_output skipped "${skipped}"
	set_output failed "${failed}"
	set_output dry-run "${dry}"
	set_output repositories "${repositories_csv}"
	set_output report "[${rows_json}]"
	set_output report-file "${REPORT_FILE}"

	if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
		{
			printf '### Octozipo v%s\n\n' "$(octozipo_version)"
			printf 'Packages: %d processed, %d created, %d updated, %d unchanged, %d pending, %d skipped, %d failed, %d dry-run\n\n' \
				"${processed}" "${created}" "${updated}" "${unchanged}" "${pending}" "${skipped}" "${failed}" "${dry}"
			if ((${#summary[@]} > 0)); then
				printf '| Status | Package | Repository | Branch | Version |\n'
				printf '| --- | --- | --- | --- | --- |\n'
				printf '%s\n' "${summary[@]}"
			fi
		} >> "${GITHUB_STEP_SUMMARY}"
	fi

	if ((pending > 0)); then
		log_warn "${pending} new repositories were prepared but not pushed, set push-create: true to create them."
	fi
	if ((skipped > 0)); then
		log_warn "${skipped} packages were skipped because they could not be unzipped."
	fi
}

# ──────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────
main() {
	resolve_settings
	validate_settings
	show_settings
	prepare_git_environment
	build_arguments

	local packages
	packages="$(count_packages)"
	if ((packages == 0)); then
		if [[ "${ALLOW_EMPTY}" == "true" ]]; then
			log_warn "No zip packages found in ${ZIP_DIR}, nothing to do."
			publish_results
			exit 0
		fi
		if [[ ! -d "${ZIP_DIR}" ]]; then
			log_error "The zip directory does not exist: ${ZIP_DIR}"
			exit 5
		fi
		log_error "No zip packages found in ${ZIP_DIR} (set allow-empty: true to allow this)."
		exit 6
	fi
	log_info "Found ${packages} zip package(s) in ${ZIP_DIR}"

	local code=0
	group_start "Octozipo v$(octozipo_version)"
	bash "${OCTOZIPO_BIN}" "${OCTOZIPO_ARGS[@]}" || code=$?
	group_end

	publish_results

	if ((code != 0)); then
		log_error "Octozipo failed with exit code ${code}, see the log above for the reason."
		exit "${code}"
	fi

	log_info "Octozipo completed successfully."
}

main "$@"
