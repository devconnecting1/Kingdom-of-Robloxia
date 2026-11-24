#!/usr/bin/env bash
# Runs a check and, when it fails on GitHub Actions, also writes its output as an error annotation so the reason is
# visible on the pull request without opening the log.
# Usage: scripts/ci/run.sh "<title>" <command> [args...]
set -uo pipefail
title="$1"
shift
output=$("$@" 2>&1)
status=$?
printf '%s\n' "$output"
if [ "$status" -ne 0 ] && [ "${GITHUB_ACTIONS:-}" = "true" ]; then
  # Annotations hold about 4 KB each: send the first lines in chunks.
  printf '%s\n' "$output" | head -n 400 | split -l 40 - "${RUNNER_TEMP:-/tmp}/annot." 
  for part in "${RUNNER_TEMP:-/tmp}"/annot.*; do
    body=$(sed -e 's/%/%25/g' "$part" | awk '{printf "%s%%0A", $0}')
    echo "::error title=${title}::${body}"
  done
  rm -f "${RUNNER_TEMP:-/tmp}"/annot.*
fi
exit "$status"
