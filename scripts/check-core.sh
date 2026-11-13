#!/usr/bin/env bash
# Cheap local verification; deliberately does not invoke GitHub Actions.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v swiftc >/dev/null 2>&1; then
  echo "Swift compiler not found. Install Swift or Xcode Command Line Tools." >&2
  exit 2
fi

echo "Checking CleanJunkCore Swift sources without building the AppKit target..."
swiftc -swift-version 5 -module-name CleanJunkCore -typecheck Sources/CleanJunkCore/*.swift
echo "CleanJunkCore typecheck succeeded."

if [[ "${1:-}" == "--test" ]]; then
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Full app tests require macOS with Xcode 26." >&2
    exit 2
  fi
  swift test --parallel
fi
