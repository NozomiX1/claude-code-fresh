#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../plugin/scripts/helpers.sh"

PASS=0; FAIL=0
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"; PASS=$((PASS+1))
  else
    echo "  FAIL: $desc"; echo "    expected: $expected"; echo "    actual:   $actual"; FAIL=$((FAIL+1))
  fi
}

echo "=== Test: json_get ==="
test_json='{"name":"test","version":"1.0.0"}'
assert_eq "top-level string" "test" "$(echo "$test_json" | json_get 'name')"
assert_eq "version field" "1.0.0" "$(echo "$test_json" | json_get 'version')"
assert_eq "missing field" "" "$(echo "$test_json" | json_get 'missing')"

echo "=== Test: json_set ==="
result=$(echo '{"a":"1"}' | json_set 'a' '2')
assert_eq "set existing key" '2' "$(echo "$result" | json_get 'a')"

echo "=== Test: read_config (defaults) ==="
export CC_FRESH_DATA_DIR=$(mktemp -d)
config=$(read_config)
assert_eq "default policy" "check" "$(echo "$config" | json_get 'default')"
assert_eq "default cooldown" "24" "$(echo "$config" | json_get 'cooldown_hours')"

echo "=== Test: ensure_data_dir ==="
export CC_FRESH_DATA_DIR=$(mktemp -d)/new_subdir
ensure_data_dir
[ -d "$CC_FRESH_DATA_DIR" ] && assert_eq "data dir created" "yes" "yes" || assert_eq "data dir created" "yes" "no"
rm -rf "$CC_FRESH_DATA_DIR"

echo "=== Test: hash_string ==="
h1=$(hash_string "hello")
h2=$(hash_string "hello")
h3=$(hash_string "world")
assert_eq "same input same hash" "$h1" "$h2"
[ "$h1" != "$h3" ] && assert_eq "diff input diff hash" "yes" "yes" || assert_eq "diff input diff hash" "yes" "no"

echo "=== Test: epoch_ms ==="
ms=$(epoch_ms)
[ "$ms" -gt 1000000000000 ] && assert_eq "epoch_ms is milliseconds" "yes" "yes" || assert_eq "epoch_ms is milliseconds" "yes" "no"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
