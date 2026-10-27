#!/usr/bin/env bash
# Send a fake, signed GitHub pull_request event to the EventListener.
# Prerequisite (see RUNBOOK.md 2.6):
#   kubectl port-forward svc/el-github-listener 8090:8080
# Run from inside your clone: the commit sha must exist in your GitHub repo.
set -euo pipefail

secret="1234567"                     # must match github-secret.yml
event="pull_request"
commit_sha=$(git rev-parse HEAD)
payload='{"action": "opened", "pull_request":{"head":{"sha": "'"${commit_sha}"'"}},"repository":{"clone_url": "https://github.com/nemcikjan/fri-uniza-onpk-cicd.git"}}'
hmac=$(printf '%s' "${payload}" | openssl sha1 -hmac "${secret}" | sed -e 's/^.* //')

curl -sS \
  -H "X-GitHub-Event: ${event}" \
  -H "X-Hub-Signature: sha1=${hmac}" \
  -H "Content-Type: application/json" \
  -d "${payload}" \
  http://localhost:8090
echo
