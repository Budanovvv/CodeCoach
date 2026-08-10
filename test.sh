#!/bin/bash
set -euo pipefail

# Unit tests for CodeCoach.
#
# The test target compiles the pure-logic sources directly (no TEST_HOST), so
# the tests never launch the GUI and never depend on TCC state.

cd "$(dirname "$0")"

DD="$HOME/Library/Caches/CodeCoachBuild"
mkdir -p "$DD"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not found: brew install xcodegen" >&2
  exit 1
fi

echo "==> generating project"
xcodegen generate

echo "==> running tests"
# CODE_SIGNING_ALLOWED=NO on purpose: the test bundle needs no signature, and
# signing it can block on a Keychain dialog that opens behind other windows —
# the run then sits at 0% CPU forever with no visible cause.
set +e
xcodebuild \
  -project CodeCoach.xcodeproj \
  -scheme CodeCoach \
  -configuration Debug \
  -derivedDataPath "$DD" \
  CODE_SIGNING_ALLOWED=NO \
  test 2>&1 | tee "$DD/test.log" | grep -E "Test Case.*(passed|failed)|Executed .* tests|error:|\*\* TEST"
STATUS=${PIPESTATUS[0]}
set -e

if [[ "$STATUS" != "0" ]]; then
  echo "==> tests FAILED (full log: $DD/test.log)" >&2
  exit 1
fi
echo "==> tests passed"
