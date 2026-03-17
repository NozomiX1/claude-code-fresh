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

echo "=== Test: session-start.sh ==="
echo "  Test dir: $TEST_DIR"

# Override environment variables
export PLUGINS_DIR="${TEST_DIR}"
export INSTALLED_PLUGINS_FILE="${TEST_DIR}/installed_plugins.json"
export KNOWN_MARKETPLACES_FILE="${TEST_DIR}/known_marketplaces.json"
export MARKETPLACES_DIR="${TEST_DIR}/marketplaces"
export CACHE_DIR="${TEST_DIR}/cache"
export CC_FRESH_DATA_DIR="${TEST_DIR}/cc-fresh-data"

SESSION_SCRIPT="${SCRIPT_DIR}/../plugin/scripts/session-start.sh"

echo ""
echo "--- Test 1: First run with updates → should notify ---"
OUTPUT=$(bash "$SESSION_SCRIPT" 2>/dev/null)
assert_contains "output contains 'updates'" "$OUTPUT" "updates"
assert_contains "output contains '/cc-fresh:check'" "$OUTPUT" "/cc-fresh:check"
assert_eq "notify-state.json exists" "yes" "$([ -f "${CC_FRESH_DATA_DIR}/notify-state.json" ] && echo yes || echo no)"

echo ""
echo "--- Test 2: Immediate second run → should be silent (cooldown) ---"
OUTPUT2=$(bash "$SESSION_SCRIPT" 2>/dev/null)
assert_eq "output is empty (silent)" "" "$OUTPUT2"

echo ""
echo "--- Test 3: Expired cooldown → should notify again ---"
# Manually set last_notify_time to 0 (far in the past)
python3 -c "
import json
with open('${CC_FRESH_DATA_DIR}/notify-state.json') as f:
    d = json.load(f)
d['last_notify_time'] = 0
with open('${CC_FRESH_DATA_DIR}/notify-state.json', 'w') as f:
    json.dump(d, f)
"
OUTPUT3=$(bash "$SESSION_SCRIPT" 2>/dev/null)
assert_contains "output contains 'updates' after cooldown" "$OUTPUT3" "updates"
assert_contains "output contains '/cc-fresh:check' after cooldown" "$OUTPUT3" "/cc-fresh:check"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
