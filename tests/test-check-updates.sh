#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

PASS=0; FAIL=0
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"; PASS=$((PASS+1))
  else
    echo "  FAIL: $desc"; echo "    expected: $expected"; echo "    actual:   $actual"; FAIL=$((FAIL+1))
  fi
}
assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -q "$needle"; then
    echo "  PASS: $desc"; PASS=$((PASS+1))
  else
    echo "  FAIL: $desc (needle '$needle' not found)"; FAIL=$((FAIL+1))
  fi
}

# Setup test environment
TEST_DIR=$(bash "${SCRIPT_DIR}/setup-test-env.sh")
trap 'rm -rf "$TEST_DIR"' EXIT

echo "=== Test: check-updates.sh ==="
echo "  Test dir: $TEST_DIR"

# Override environment variables
export PLUGINS_DIR="${TEST_DIR}"
export INSTALLED_PLUGINS_FILE="${TEST_DIR}/installed_plugins.json"
export KNOWN_MARKETPLACES_FILE="${TEST_DIR}/known_marketplaces.json"
export MARKETPLACES_DIR="${TEST_DIR}/marketplaces"
export CACHE_DIR="${TEST_DIR}/cache"
export CC_FRESH_DATA_DIR="${TEST_DIR}/cc-fresh-data"

# Run check-updates.sh
OUTPUT=$(bash "${SCRIPT_DIR}/../plugin/scripts/check-updates.sh" 2>/dev/null)

echo "=== Verify output content ==="
assert_contains "output contains hello-plugin" "$OUTPUT" "hello-plugin"
assert_contains "output contains old version 1.0.0" "$OUTPUT" "1.0.0"
assert_contains "output contains new version 1.1.0" "$OUTPUT" "1.1.0"

echo "=== Verify cache.json ==="
assert_eq "cache.json exists" "yes" "$([ -f "${CC_FRESH_DATA_DIR}/cache.json" ] && echo yes || echo no)"

CACHE_CONTENT=$(cat "${CC_FRESH_DATA_DIR}/cache.json")
assert_contains "cache.json contains hello-plugin" "$CACHE_CONTENT" "hello-plugin"
assert_contains "cache.json has checked_at" "$CACHE_CONTENT" "checked_at"
assert_contains "cache.json has updates array" "$CACHE_CONTENT" '"updates"'

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
