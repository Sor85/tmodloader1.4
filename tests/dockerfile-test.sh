#!/bin/bash

set -u

repoRoot=$(cd "$(dirname "$0")/.." && pwd)
dockerfile="$repoRoot/Dockerfile"
failures=0

assert_contains() {
  local expected="$1"
  local message="$2"

  if ! grep -q "$expected" "$dockerfile"; then
    echo "FAIL: $message"
    failures=$((failures + 1))
  fi
}

test_installs_dotnet_globalization_dependency() {
  assert_contains "libicu" "Dockerfile should install ICU for .NET globalization support."
}

test_installs_dotnet_globalization_dependency

if [ "$failures" -ne 0 ]; then
  exit 1
fi
