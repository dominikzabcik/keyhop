#!/usr/bin/env bash
# Runs the Swift tests and, on GitHub, turns each failed assertion into an annotation, so a red
# run says which test failed without opening its log.
set -o pipefail
swift test "$@" 2>&1 | tee swift-test.log
status=$?
if [ "$status" -ne 0 ] && [ -n "${GITHUB_ACTIONS:-}" ]; then
  grep -E ': error: |Fatal error|Test Case .* failed' swift-test.log | head -40 | while IFS= read -r line; do
    echo "::error title=swift test::${line}"
  done
fi
exit "$status"
