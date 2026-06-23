#!/usr/bin/env bash
# Static gate — ios-detour. LINT-ONLY: the dev host's Swift 5.7.2 is older than this code targets
# and false-fails valid syntax, so iOS *correctness* is verified in CI (newer Xcode), not here.
set -euo pipefail
echo "▶ correctness: Package.swift resolves (BLOCKING)"
swift package resolve
echo "▶ lint/format (non-blocking)"
swiftlint lint --quiet || echo "::warn:: swiftlint findings (non-blocking)"
swiftformat --lint . || echo "::warn:: swiftformat diffs (non-blocking)"
echo "✓ static gate passed (correctness verified in CI)"
