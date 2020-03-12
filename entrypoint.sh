#!/bin/bash
set -e

cd "${GO_WORKING_DIR:-.}"

# Build ignored directories
IGNORED_DIRS=""
if [ -n "${GO_IGNORE_DIRS}" ]; then
  IGNORE_DIRS_ARR=($GO_IGNORE_DIRS)
  for DIR in "${IGNORE_DIRS_ARR[@]}"; do
    # If the directory doesn't end in "/*", add it
    if [[ ! "${DIR}" =~ .*\/\*$ ]]; then
      DIR="${DIR}/*"
    fi
    # Append to our list of directories to ignore
    IGNORED_DIRS+=" -not -path \"${DIR}\""
  done
fi

# Use an eval to avoid glob expansion
FIND_EXEC="find . -type f -iname '*.go' ${IGNORED_DIRS}"

# Get a list of files that we are interested in
CHECK_FILES=$(eval ${FIND_EXEC})

# Check if any files are not formatted.
set +e
test -z "$(gofmt -l -d -e ${CHECK_FILES})"
SUCCESS=$?
set -e

# Exit if `go fmt` passes.
if [ $SUCCESS -eq 0 ]; then
  exit 0
fi

# Get list of unformatted files.
# set +e
# ISSUE_FILES=$(gofmt -l ${CHECK_FILES})
# echo "${ISSUE_FILES}"
# set -e

# Iterate through each unformatted file.
# OUTPUT=""
# for FILE in $ISSUE_FILES; do
# DIFF=$(gofmt -d -e "${FILE}")
# OUTPUT="$OUTPUT
# \`${FILE}\`

# \`\`\`diff
# $DIFF
# \`\`\`
# "
# done

# Post results back as comment.
# COMMENT="#### \`go fmt\`
# $OUTPUT
# "
# PAYLOAD=$(echo '{}' | jq --arg body "$COMMENT" '.body = $body')
# COMMENTS_URL=$(cat /github/workflow/event.json | jq -r .pull_request.comments_url)

# if [ "COMMENTS_URL" != null ]; then
#   curl -s -S -H "Authorization: token $GITHUB_TOKEN" --header "Content-Type: application/json" --data "$PAYLOAD" "$COMMENTS_URL" > /dev/null
# fi

PR_NUMBER=$(jq -r ".issue.number" "$GITHUB_EVENT_PATH")
echo "Collecting information about PR #$PR_NUMBER of $GITHUB_REPOSITORY..."

if [[ -z "$GITHUB_TOKEN" ]]; then
  echo "Set the GITHUB_TOKEN env variable."
  exit 1
fi

URI=https://api.github.com
API_HEADER="Accept: application/vnd.github.v3+json"
AUTH_HEADER="Authorization: token $GITHUB_TOKEN"

pr_resp=$(curl -X GET -s -H "${AUTH_HEADER}" -H "${API_HEADER}" \
          "${URI}/repos/$GITHUB_REPOSITORY/pulls/$PR_NUMBER")

BASE_REPO=$(echo "$pr_resp" | jq -r .base.repo.full_name)
BASE_BRANCH=$(echo "$pr_resp" | jq -r .base.ref)

USER_LOGIN=$(jq -r ".comment.user.login" "$GITHUB_EVENT_PATH")

user_resp=$(curl -X GET -s -H "${AUTH_HEADER}" -H "${API_HEADER}" \
            "${URI}/users/${USER_LOGIN}")

USER_NAME=$(echo "$user_resp" | jq -r ".name")
if [[ "$USER_NAME" == "null" ]]; then
  USER_NAME=$USER_LOGIN
fi
USER_NAME="${USER_NAME} (Rebase PR Action)"

USER_EMAIL=$(echo "$user_resp" | jq -r ".email")
if [[ "$USER_EMAIL" == "null" ]]; then
  USER_EMAIL="$USER_LOGIN@users.noreply.github.com"
fi

# if [[ "$(echo "$pr_resp" | jq -r .rebaseable)" != "true" ]]; then
#   echo "GitHub doesn't think that the PR is rebaseable!"
#   exit 1
# fi

if [[ -z "$BASE_BRANCH" ]]; then
  echo "Cannot get base branch information for PR #$PR_NUMBER!"
  echo "API response: $pr_resp"
  exit 1
fi

# HEAD_REPO=$(echo "$pr_resp" | jq -r .head.repo.full_name)
# HEAD_BRANCH=$(echo "$pr_resp" | jq -r .head.ref)
HEAD_REPO=$(jq -r ".pull_request.head.repo.full_name" "$GITHUB_EVENT_PATH")
HEAD_BRANCH=$(jq -r ".pull_request.head.ref" "$GITHUB_EVENT_PATH")

echo "Base branch for PR #$PR_NUMBER is $BASE_BRANCH"

USER_TOKEN=${USER_LOGIN}_TOKEN
COMMITTER_TOKEN=${!USER_TOKEN:-$GITHUB_TOKEN}

git remote set-url origin https://x-access-token:$COMMITTER_TOKEN@github.com/$GITHUB_REPOSITORY.git
git config --global user.email "$USER_EMAIL"
git config --global user.name "$USER_NAME"

git remote add fork https://x-access-token:$COMMITTER_TOKEN@github.com/$HEAD_REPO.git

set -o xtrace

# # make sure branches are up-to-date
# git fetch origin $BASE_BRANCH
# git fetch fork $HEAD_BRANCH

# # do the rebase
# git checkout -b $HEAD_BRANCH fork/$HEAD_BRANCH
# git rebase origin/$BASE_BRANCH
gofmt -w .
git commit -a -m"go format code"

# push back
git checkout -b $HEAD_BRANCH
git push fork $HEAD_BRANCH


exit $SUCCESS
