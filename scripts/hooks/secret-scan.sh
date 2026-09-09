#!/bin/zsh
# Blocks commits containing obvious secrets. Staged diff only.
set -uo pipefail
# Two escape hatches, both necessary in practice:
#  - exclude the scanner itself, which contains every pattern it looks for;
#  - drop any line marked `allowlist-secret`, so docs and tests can quote a
#    pattern without tripping it. Use the marker sparingly and never on a
#    line that holds a real credential.
DIFF="$(git diff --cached -U0 -- . ':(exclude)*secret-scan.sh' 2>/dev/null \
        | grep -v 'allowlist-secret')" || exit 0
[[ -z "$DIFF" ]] && exit 0

PATTERNS=(
  'sk-ant-[A-Za-z0-9_-]{20,}'
  'gh[pousr]_[A-Za-z0-9]{30,}'
  'AKIA[0-9A-Z]{16}'
  'eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.'
  '[A-Z_]*(SECRET|SERVICE_ROLE|PRIVATE)_KEY[[:space:]]*=[[:space:]]*[A-Za-z0-9]'
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'
)
for p in "${PATTERNS[@]}"; do
  if echo "$DIFF" | grep -qE -- "$p"; then
    echo "BLOCKED: staged diff matches secret pattern: $p" >&2
    exit 1
  fi
done
# Never allow env files through, whatever their content.
if git diff --cached --name-only | grep -qE '(^|/)\.env(\.|$)'; then
  echo "BLOCKED: attempting to commit a .env file" >&2
  exit 1
fi
exit 0
