#!/bin/zsh
# Bridge-independent escalation fallback. Used when a task is marked blocked, so
# an escalation still reaches the phone if Remote Control push is down.
curl -s -d "ESCALATION: ${1:-unknown task} - ${2:-no reason given}" \
  "ntfy.sh/${NTFY_TOPIC:-__NTFY_TOPIC__}" >/dev/null || true
