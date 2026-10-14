#!/bin/sh
# api-check-report.sh
#
# Turns the results of a scheduled API check run into GitHub issues. Run by
# the report job in .github/workflows/api-check.yml; needs gh and jq.
#
# Usage:
#   sh scripts/api-check-report.sh <results-dir>
#
# <results-dir> holds one directory per provider (the downloaded workflow
# artifacts), each containing the files provider, status, rc and output.txt
# written by the check job.
#
# Per provider:
#   rc 0  close any open issue for it
#   rc 1  ACTIVE / API_TESTED: open "API check failing: <provider>", or comment
#         on it if already open. Other statuses: nothing.
#   rc 2  nothing, unless the last three runs on the default branch were all
#         inconclusive, in which case open "API check unreachable: <provider>"
#
# Environment:
#   GH_TOKEN, GITHUB_REPOSITORY     required by gh
#   DEFAULT_BRANCH                  branch whose runs count towards the streak
#   GITHUB_SERVER_URL, GITHUB_RUN_ID  used to link the run
#   AC_REPORT_DRY_RUN               "true" prints what would be done instead

AC_RESULTS_DIR="${1:-}"
if [ -z "$AC_RESULTS_DIR" ] || [ ! -d "$AC_RESULTS_DIR" ]; then
	printf 'Usage: sh scripts/api-check-report.sh <results-dir>\n' >&2
	exit 1
fi

AC_LABEL="api-check"
AC_STREAK=3
AC_RUN_URL="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-}"
AC_BODY="$(mktemp)"
trap 'rm -f "$AC_BODY"' EXIT

# Runs a gh command that changes something, or prints it in a dry run.
_acr_gh(){
	if [ "${AC_REPORT_DRY_RUN:-}" = "true" ]; then
		printf '  [dry run] gh %s\n' "$*"
		return 0
	fi
	gh "$@"
}

# _acr_find_issue title → number of the open issue with exactly that title
_acr_find_issue(){
	gh issue list --state open --label "$AC_LABEL" --limit 100 --json number,title \
		| jq -r --arg t "$1" '.[] | select(.title==$t) | .number' | head -1
}

# _acr_write_body provider status intro output_file
_acr_write_body(){
	{
		printf '%s\n\n' "$3"
		printf -- '- Provider: `%s` (status `%s`)\n' "$1" "$2"
		printf -- '- Run: %s\n\n' "$AC_RUN_URL"
		printf '<details open><summary>Check output</summary>\n\n```\n'
		tail -c 50000 "$4" 2>/dev/null
		printf '\n```\n\n</details>\n'
	} > "$AC_BODY"
}

# _acr_raise title provider status intro output_file
_acr_raise(){
	_acr_write_body "$2" "$3" "$4" "$5"
	_acrr_issue="$(_acr_find_issue "$1")"
	if [ -n "$_acrr_issue" ]; then
		printf '%s: still failing — commenting on #%s\n' "$2" "$_acrr_issue"
		_acr_gh issue comment "$_acrr_issue" --body-file "$AC_BODY"
	else
		printf '%s: opening issue "%s"\n' "$2" "$1"
		_acr_gh issue create --title "$1" --label "$AC_LABEL" --body-file "$AC_BODY"
	fi
}

# _acr_resolve title provider
_acr_resolve(){
	_acrs_issue="$(_acr_find_issue "$1")"
	[ -n "$_acrs_issue" ] || return 0
	printf '%s: recovered — closing #%s\n' "$2" "$_acrs_issue"
	_acr_gh issue close "$_acrs_issue" --comment "The API check for \`$2\` passed again: $AC_RUN_URL"
}

# _acr_inconclusive_streak provider → 0 when the last $AC_STREAK results on the
# default branch were all inconclusive. The check job encodes its exit code in
# the artifact name (api-check-<provider>-rc<code>), so the history can be read
# from the artifact list without downloading anything.
_acr_inconclusive_streak(){
	_acri_recent="$(gh api "repos/${GITHUB_REPOSITORY}/actions/artifacts?per_page=100" \
		| jq -r --arg p "api-check-$1-rc" --arg b "${DEFAULT_BRANCH:-main}" --argjson n "$AC_STREAK" \
			'[.artifacts[] | select(.name | startswith($p)) | select(.workflow_run.head_branch==$b)]
			 | sort_by(.created_at) | reverse | .[:$n] | map(.name | sub($p; "")) | join(" ")')"
	[ "$(printf '%s' "$_acri_recent" | wc -w | tr -d ' ')" -eq "$AC_STREAK" ] || return 1
	for _acri_rc in $_acri_recent; do
		[ "$_acri_rc" = "2" ] || return 1
	done
	return 0
}

_acr_gh label create "$AC_LABEL" --force --color D93F0B \
	--description "Opened automatically when a provider's API check fails" >/dev/null

for _acr_dir in "$AC_RESULTS_DIR"/*/; do
	[ -f "${_acr_dir}rc" ] || continue
	_acr_provider="$(cat "${_acr_dir}provider")"
	_acr_status="$(cat "${_acr_dir}status")"
	_acr_rc="$(cat "${_acr_dir}rc")"
	_acr_failing="API check failing: $_acr_provider"
	_acr_unreachable="API check unreachable: $_acr_provider"

	case "$_acr_rc" in
		0)
			printf '%s: ok\n' "$_acr_provider"
			_acr_resolve "$_acr_failing" "$_acr_provider"
			_acr_resolve "$_acr_unreachable" "$_acr_provider"
			;;
		1)
			case "$_acr_status" in
				ACTIVE|API_TESTED)
					_acr_raise "$_acr_failing" "$_acr_provider" "$_acr_status" \
						"The scheduled API check found that an endpoint the \`$_acr_provider\` provider depends on no longer behaves as the provider expects. Routers using this provider may be unable to select a server or apply a config. If this cannot be fixed promptly, set the provider's \`# Status:\` to \`UNTESTED\`." \
						"${_acr_dir}output.txt"
					;;
				*)
					printf '%s: failing, but status is %s — no issue\n' "$_acr_provider" "$_acr_status"
					;;
			esac
			;;
		2)
			case "$_acr_status" in
				ACTIVE|API_TESTED)
					if _acr_inconclusive_streak "$_acr_provider"; then
						_acr_raise "$_acr_unreachable" "$_acr_provider" "$_acr_status" \
							"The last $AC_STREAK API check runs for \`$_acr_provider\` were all inconclusive: requests were blocked, rate limited, answered with server errors, or not answered at all. Either the provider is having a long outage or it is refusing requests from GitHub's runners, in which case this check can no longer see API changes and needs another place to run from." \
							"${_acr_dir}output.txt"
					else
						printf '%s: inconclusive — no issue yet\n' "$_acr_provider"
					fi
					;;
				*)
					printf '%s: inconclusive, status is %s — no issue\n' "$_acr_provider" "$_acr_status"
					;;
			esac
			;;
		*)
			printf '%s: check did not run cleanly (exit %s) — no issue\n' "$_acr_provider" "$_acr_rc"
			;;
	esac
done
