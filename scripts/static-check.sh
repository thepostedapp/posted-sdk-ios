#!/usr/bin/env bash
# Static gate — ios-detour. LINT-ONLY: the dev host's Swift 5.7.2 is older than this code targets
# and false-fails valid syntax, so iOS *correctness* is verified in CI (newer Xcode), not here.
set -euo pipefail
echo "▶ correctness: Package.swift resolves (BLOCKING)"
swift package resolve
echo "▶ lint/format (non-blocking)"
swiftlint lint --quiet || echo "::warn:: swiftlint findings (non-blocking)"
swiftformat --lint . || echo "::warn:: swiftformat diffs (non-blocking)"
echo "▶ doc API drift check (non-blocking, cheap pre-check)"
# README/CHANGELOG embed Swift snippets for these public symbols; warn if they disappear from
# Sources/. This only catches symbol removal/rename, not signature drift (e.g. a renamed
# parameter label) — Tests/PostedSDKTests/DocAPISnippetTests.swift is the compile-checked
# authority for that: it reproduces the doc snippets verbatim and fails to build in the `test`
# CI job if any of these 3 symbols' shapes change (POS-171).
doc_api_symbols=("resolveAppLaunch" "LaunchContext" "resetSession")
drift=0
for sym in "${doc_api_symbols[@]}"; do
  if ! grep -rq "func ${sym}\|enum ${sym}\|struct ${sym}\|var ${sym}" Sources/; then
    echo "::warn:: doc API drift: '${sym}' not found in Sources/ — update README/CHANGELOG if renamed"
    drift=1
  fi
done
[ "$drift" -eq 0 ] && echo "  ✓ doc symbols present in Sources/"
echo "✓ static gate passed (correctness verified in CI)"
