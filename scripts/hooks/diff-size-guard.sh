#!/bin/zsh
# Scope-creep tripwire. Large diffs are usually a worker exceeding its spec.
set -uo pipefail
MAX="${MAX_DIFF_LINES:-600}"
N="$(git diff --cached --numstat 2>/dev/null | awk '{a+=$1+$2} END {print a+0}')"
if (( N > MAX )); then
  echo "BLOCKED: staged diff is $N lines (limit $MAX)." >&2
  echo "If this is genuinely one change, split it or raise MAX_DIFF_LINES for this task." >&2
  exit 1
fi
exit 0
