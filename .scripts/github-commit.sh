#!/usr/bin/env bash
# Create a GitHub-signed commit using GitHub's native GraphQL API.

set -euo pipefail

TARGET_DIR="${1:-www-client/google-chrome}"
COMMIT_MSG="${2:-www-client/google-chrome: update from gentoo-mirror}"

# Check for modified, added, or deleted files in target directory
status_output="$(git status --porcelain "${TARGET_DIR}")"
if [[ -z "${status_output}" ]]; then
	echo "No changes detected in ${TARGET_DIR}."
	exit 0
fi

REPO="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner \
	--jq .nameWithOwner 2>/dev/null || true)}"
BRANCH="${GITHUB_REF_NAME:-$(git branch --show-current)}"
HEAD_OID="$(git rev-parse HEAD)"

if [[ -z "${REPO}" || -z "${BRANCH}" || -z "${HEAD_OID}" ]]; then
	echo "Error: Missing repository, branch, or HEAD OID context." >&2
	exit 1
fi

additions=""
deletions=""

while IFS= read -r line; do
	[[ -z "${line}" ]] && continue
	status="${line:0:2}"
	file="${line:3}"
	file="${file#\"}"
	file="${file%\"}"

	if [[ "${status}" =~ D ]] || [[ ! -e "${file}" ]]; then
		[[ -n "${deletions}" ]] && deletions+=","
		deletions+="{\"path\":\"${file}\"}"
	else
		b64="$(base64 --wrap=0 "${file}")"
		[[ -n "${additions}" ]] && additions+=","
		additions+="{\"path\":\"${file}\",\"contents\":\"${b64}\"}"
	fi
done <<< "${status_output}"

query='mutation($input: CreateCommitOnBranchInput!) { '
query+='createCommitOnBranch(input: $input) { commit { oid } } }'

payload="{\"query\":\"${query}\",\"variables\":{\"input\":{"
payload+="\"branch\":{\"repositoryNameWithOwner\":\"${REPO}\","
payload+="\"branchName\":\"${BRANCH}\"},"
payload+="\"message\":{\"headline\":\"${COMMIT_MSG}\"},"
payload+="\"expectedHeadOid\":\"${HEAD_OID}\","
payload+="\"fileChanges\":{"
payload+="\"additions\":[${additions}],"
payload+="\"deletions\":[${deletions}]}}}}"

echo "Creating GitHub-signed commit on ${REPO}@${BRANCH}..."
gh api graphql --input - <<< "${payload}"
echo "Successfully pushed signed commit."
