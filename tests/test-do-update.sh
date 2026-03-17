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

echo "=== Test: do-update.sh ==="
echo "  Test dir: $TEST_DIR"

# Override environment variables
export PLUGINS_DIR="${TEST_DIR}"
export INSTALLED_PLUGINS_FILE="${TEST_DIR}/installed_plugins.json"
export KNOWN_MARKETPLACES_FILE="${TEST_DIR}/known_marketplaces.json"
export MARKETPLACES_DIR="${TEST_DIR}/marketplaces"
export CACHE_DIR="${TEST_DIR}/cache"
export CC_FRESH_DATA_DIR="${TEST_DIR}/cc-fresh-data"

# Step 1: Run check-updates.sh to populate cache
echo "=== Step 1: Run check-updates.sh ==="
bash "${SCRIPT_DIR}/../plugin/scripts/check-updates.sh" >/dev/null 2>&1
assert_eq "cache.json exists after check" "yes" "$([ -f "${CC_FRESH_DATA_DIR}/cache.json" ] && echo yes || echo no)"

# Step 2: Run do-update.sh
echo "=== Step 2: Run do-update.sh ==="
UPDATE_OUTPUT=$(bash "${SCRIPT_DIR}/../plugin/scripts/do-update.sh" 2>/dev/null)
echo "  Output: $UPDATE_OUTPUT"

# Step 3: Verify new cache dir exists
echo "=== Step 3: Verify new cache directory ==="
NEW_CACHE="${TEST_DIR}/cache/test-marketplace/hello-plugin/1.1.0"
assert_eq "new cache dir exists" "yes" "$([ -d "$NEW_CACHE" ] && echo yes || echo no)"
assert_eq "new cache has plugin.json" "yes" "$([ -f "${NEW_CACHE}/plugin.json" ] && echo yes || echo no)"

# Step 4: Verify installed_plugins.json updated
echo "=== Step 4: Verify installed_plugins.json ==="
INSTALLED=$(cat "$INSTALLED_PLUGINS_FILE")
assert_contains "installed_plugins has version 1.1.0" "$INSTALLED" '"version": "1.1.0"'

# Step 5: Verify old cache dir has .orphaned_at
echo "=== Step 5: Verify old cache orphaned ==="
OLD_CACHE="${TEST_DIR}/cache/test-marketplace/hello-plugin/1.0.0"
assert_eq "old cache .orphaned_at exists" "yes" "$([ -f "${OLD_CACHE}/.orphaned_at" ] && echo yes || echo no)"

# Step 6: Verify output contains reload message
echo "=== Step 6: Verify output messages ==="
assert_contains "output contains reload-plugins" "$UPDATE_OUTPUT" "Run /reload-plugins"
assert_contains "output contains success count" "$UPDATE_OUTPUT" "1 succeeded"

# Step 7: Verify cache.json deleted after update
echo "=== Step 7: Verify cache.json cleaned up ==="
assert_eq "cache.json deleted" "no" "$([ -f "${CC_FRESH_DATA_DIR}/cache.json" ] && echo yes || echo no)"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
