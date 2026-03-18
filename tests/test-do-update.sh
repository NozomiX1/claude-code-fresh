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

######################################################################
# --auto-only tests
######################################################################

# --- Test A: --auto-only with "check" policy → skips update ---
echo ""
echo "=== Test A: --auto-only with 'check' policy (default) → skips ==="

TEST_DIR_A=$(bash "${SCRIPT_DIR}/setup-test-env.sh")
export PLUGINS_DIR="${TEST_DIR_A}"
export INSTALLED_PLUGINS_FILE="${TEST_DIR_A}/installed_plugins.json"
export KNOWN_MARKETPLACES_FILE="${TEST_DIR_A}/known_marketplaces.json"
export MARKETPLACES_DIR="${TEST_DIR_A}/marketplaces"
export CACHE_DIR="${TEST_DIR_A}/cache"
export CC_FRESH_DATA_DIR="${TEST_DIR_A}/cc-fresh-data"

# config.json with default="check", no marketplace override
cat > "${CC_FRESH_DATA_DIR}/config.json" << 'CFGJSON'
{"default":"check","cooldown_hours":24,"marketplaces":{}}
CFGJSON

bash "${SCRIPT_DIR}/../plugin/scripts/check-updates.sh" >/dev/null 2>&1
OUTPUT_A=$(bash "${SCRIPT_DIR}/../plugin/scripts/do-update.sh" --auto-only 2>/dev/null)

# Should report 0 succeeded (plugin skipped due to "check" policy)
assert_contains "--auto-only check: 0 succeeded" "$OUTPUT_A" "0 succeeded"
# installed_plugins.json should still have 1.0.0
INSTALLED_A=$(cat "$INSTALLED_PLUGINS_FILE")
assert_contains "--auto-only check: still at 1.0.0" "$INSTALLED_A" '"version": "1.0.0"'
# cache.json should be preserved (--auto-only never deletes it)
assert_eq "--auto-only check: cache.json preserved" "yes" "$([ -f "${CC_FRESH_DATA_DIR}/cache.json" ] && echo yes || echo no)"

rm -rf "$TEST_DIR_A"

# --- Test B: --auto-only with "auto" policy → updates plugin ---
echo ""
echo "=== Test B: --auto-only with 'auto' policy → updates ==="

TEST_DIR_B=$(bash "${SCRIPT_DIR}/setup-test-env.sh")
export PLUGINS_DIR="${TEST_DIR_B}"
export INSTALLED_PLUGINS_FILE="${TEST_DIR_B}/installed_plugins.json"
export KNOWN_MARKETPLACES_FILE="${TEST_DIR_B}/known_marketplaces.json"
export MARKETPLACES_DIR="${TEST_DIR_B}/marketplaces"
export CACHE_DIR="${TEST_DIR_B}/cache"
export CC_FRESH_DATA_DIR="${TEST_DIR_B}/cc-fresh-data"

# config.json with test-marketplace set to "auto"
cat > "${CC_FRESH_DATA_DIR}/config.json" << 'CFGJSON2'
{"default":"check","cooldown_hours":24,"marketplaces":{"test-marketplace":"auto"}}
CFGJSON2

bash "${SCRIPT_DIR}/../plugin/scripts/check-updates.sh" >/dev/null 2>&1
OUTPUT_B=$(bash "${SCRIPT_DIR}/../plugin/scripts/do-update.sh" --auto-only 2>/dev/null)

# Should update successfully
assert_contains "--auto-only auto: 1 succeeded" "$OUTPUT_B" "1 succeeded"
# installed_plugins.json should have 1.1.0
INSTALLED_B=$(cat "$INSTALLED_PLUGINS_FILE")
assert_contains "--auto-only auto: updated to 1.1.0" "$INSTALLED_B" '"version": "1.1.0"'
# cache.json should be preserved (--auto-only never deletes it)
assert_eq "--auto-only auto: cache.json preserved" "yes" "$([ -f "${CC_FRESH_DATA_DIR}/cache.json" ] && echo yes || echo no)"
# cache.json updates array should be empty (moved to up_to_date)
CACHE_UPDATES_B=$(python3 -c "import json; d=json.load(open('${CC_FRESH_DATA_DIR}/cache.json')); print(len(d.get('updates',[])))")
assert_eq "--auto-only auto: updates array empty" "0" "$CACHE_UPDATES_B"

rm -rf "$TEST_DIR_B"

# --- Test C: --auto-only with "ignore" policy → skips update ---
echo ""
echo "=== Test C: --auto-only with 'ignore' policy → skips ==="

TEST_DIR_C=$(bash "${SCRIPT_DIR}/setup-test-env.sh")
export PLUGINS_DIR="${TEST_DIR_C}"
export INSTALLED_PLUGINS_FILE="${TEST_DIR_C}/installed_plugins.json"
export KNOWN_MARKETPLACES_FILE="${TEST_DIR_C}/known_marketplaces.json"
export MARKETPLACES_DIR="${TEST_DIR_C}/marketplaces"
export CACHE_DIR="${TEST_DIR_C}/cache"
export CC_FRESH_DATA_DIR="${TEST_DIR_C}/cc-fresh-data"

# config.json with test-marketplace set to "ignore"
cat > "${CC_FRESH_DATA_DIR}/config.json" << 'CFGJSON3'
{"default":"check","cooldown_hours":24,"marketplaces":{"test-marketplace":"ignore"}}
CFGJSON3

bash "${SCRIPT_DIR}/../plugin/scripts/check-updates.sh" >/dev/null 2>&1
OUTPUT_C=$(bash "${SCRIPT_DIR}/../plugin/scripts/do-update.sh" --auto-only 2>/dev/null)

assert_contains "--auto-only ignore: all up to date" "$OUTPUT_C" "All plugins are up to date"
INSTALLED_C=$(cat "$INSTALLED_PLUGINS_FILE")
assert_contains "--auto-only ignore: still at 1.0.0" "$INSTALLED_C" '"version": "1.0.0"'

rm -rf "$TEST_DIR_C"

# --- Test D: --auto-only with default="auto" → updates via default ---
echo ""
echo "=== Test D: --auto-only with default='auto' → updates via default ==="

TEST_DIR_D=$(bash "${SCRIPT_DIR}/setup-test-env.sh")
export PLUGINS_DIR="${TEST_DIR_D}"
export INSTALLED_PLUGINS_FILE="${TEST_DIR_D}/installed_plugins.json"
export KNOWN_MARKETPLACES_FILE="${TEST_DIR_D}/known_marketplaces.json"
export MARKETPLACES_DIR="${TEST_DIR_D}/marketplaces"
export CACHE_DIR="${TEST_DIR_D}/cache"
export CC_FRESH_DATA_DIR="${TEST_DIR_D}/cc-fresh-data"

# config.json with default="auto", no marketplace override
cat > "${CC_FRESH_DATA_DIR}/config.json" << 'CFGJSON4'
{"default":"auto","cooldown_hours":24,"marketplaces":{}}
CFGJSON4

bash "${SCRIPT_DIR}/../plugin/scripts/check-updates.sh" >/dev/null 2>&1
OUTPUT_D=$(bash "${SCRIPT_DIR}/../plugin/scripts/do-update.sh" --auto-only 2>/dev/null)

assert_contains "--auto-only default=auto: 1 succeeded" "$OUTPUT_D" "1 succeeded"
INSTALLED_D=$(cat "$INSTALLED_PLUGINS_FILE")
assert_contains "--auto-only default=auto: updated to 1.1.0" "$INSTALLED_D" '"version": "1.1.0"'

rm -rf "$TEST_DIR_D"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
