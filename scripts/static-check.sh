#!/usr/bin/env bash
# Static gate — PostedSDK iOS. LINT-ONLY: iOS *correctness* is verified in CI (xcodebuild on a
# newer Xcode), not here.
set -euo pipefail
echo "▶ correctness: Package.swift resolves (BLOCKING)"
swift package resolve
echo "▶ lint/format (non-blocking)"
swiftlint lint --quiet || echo "::warn:: swiftlint findings (non-blocking)"
swiftformat --lint . || echo "::warn:: swiftformat diffs (non-blocking)"
echo "▶ doc API drift check (non-blocking, cheap pre-check)"
# README/CHANGELOG embed Swift snippets for these public symbols; warn if they disappear from
# Sources/. This only catches symbol removal/rename, not signature drift —
# Tests/PostedSDKTests/DocAPISnippetTests.swift is the compile-checked authority for that.
doc_api_symbols=("reportInstall" "PostedConfig")
drift=0
for sym in "${doc_api_symbols[@]}"; do
  if ! grep -rq "func ${sym}\|enum ${sym}\|struct ${sym}\|var ${sym}" Sources/; then
    echo "::warn:: doc API drift: '${sym}' not found in Sources/ — update README/CHANGELOG if renamed"
    drift=1
  fi
done
[ "$drift" -eq 0 ] && echo "  ✓ doc symbols present in Sources/"
# Guard: reject stale references to the old GitHub org (postedapp); correct org is thepostedapp.
# The search pattern does not appear in thepostedapp URLs so there are no false positives.
echo "▶ org-url guard: no stale old-org references (BLOCKING)"
STALE_PATTERN='github\.com/postedapp'
if MATCHES=$(git grep -n -- "$STALE_PATTERN" -- ':!scripts/static-check.sh'); then
  echo "✗ stale old-org URL found — update to github.com/thepostedapp:"
  echo "$MATCHES"
  exit 1
fi
echo "✓ static gate passed (correctness verified in CI)"
