#!/usr/bin/env bash
# session-start.sh — SessionStart hook entry point for cc-fresh
# Runs check-updates.sh, then decides whether to show a notification.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"

ensure_data_dir

# Create default config.json if missing
CONFIG_FILE="${CC_FRESH_DATA_DIR}/config.json"
if [ ! -f "$CONFIG_FILE" ]; then
  echo '{"default":"check","cooldown_hours":24,"marketplaces":{}}' > "$CONFIG_FILE"
fi

NOTIFY_STATE_FILE="${CC_FRESH_DATA_DIR}/notify-state.json"
COOLDOWN_HOURS=24

# Read cooldown_hours from config
COOLDOWN_HOURS=$(python3 -c "
import json, sys
try:
    config = json.loads('''$(read_config)''')
    print(config.get('cooldown_hours', 24))
except:
    print(24)
")

COOLDOWN_MS=$((COOLDOWN_HOURS * 3600 * 1000))

CACHE_FILE="${CC_FRESH_DATA_DIR}/cache.json"
CACHE_MAX_AGE_MS=$((1 * 3600 * 1000))  # 1 hour

# Check if cache is fresh (< 1 hour old)
CACHE_FRESH="no"
if [ -f "$CACHE_FILE" ]; then
  CACHE_AGE=$(python3 -c "
import json, time
try:
    with open('${CACHE_FILE}') as f:
        d = json.load(f)
    age = int(time.time() * 1000) - d.get('checked_at', 0)
    print(age)
except:
    print(999999999999)
")
  if [ "$CACHE_AGE" -lt "$CACHE_MAX_AGE_MS" ]; then
    CACHE_FRESH="yes"
  fi
fi

# Only run check if cache is stale or missing
if [ "$CACHE_FRESH" = "no" ]; then
  bash "${SCRIPT_DIR}/check-updates.sh" >/dev/null 2>&1 || true
fi

if [ ! -f "$CACHE_FILE" ]; then
  exit 0
fi

# Run auto-updates for "auto" policy marketplaces (updates cache.json in place)
AUTO_OUTPUT=""
if [ "$CACHE_FRESH" = "no" ]; then
  AUTO_OUTPUT=$(bash "${SCRIPT_DIR}/do-update.sh" --auto-only 2>/dev/null) || true
fi

# Count auto-updated and remaining updates
NOTIFY_INFO=$(python3 - "$CACHE_FILE" << 'PYEOF'
import json, sys

with open(sys.argv[1]) as f:
    data = json.load(f)

updates = data.get("updates", [])
check_count = len(updates)

# Build hash for cooldown
if check_count == 0:
    print("0")
    print("")
else:
    entries = []
    for u in updates:
        name = u.get("name", "")
        ver = u.get("available_version", u.get("installed_version", ""))
        entries.append(f"{name}@{ver}")
    entries.sort()
    print(check_count)
    print("|".join(entries))
PYEOF
)

CHECK_COUNT=$(echo "$NOTIFY_INFO" | head -1)
HASH_INPUT=$(echo "$NOTIFY_INFO" | tail -1)

# Count how many were auto-updated
AUTO_COUNT=0
if [ -n "$AUTO_OUTPUT" ]; then
  AUTO_COUNT=$(echo "$AUTO_OUTPUT" | grep -c "^\\[OK\\]" || true)
fi

# Nothing happened at all → clean up
if [ "$CHECK_COUNT" = "0" ] && [ "$AUTO_COUNT" = "0" ]; then
  rm -f "$NOTIFY_STATE_FILE"
  exit 0
fi

# Build notification message
MESSAGES=""

if [ "$AUTO_COUNT" -gt 0 ]; then
  MESSAGES="${AUTO_COUNT} plugin(s) auto-updated. Run /reload-plugins to apply."
fi

if [ "$CHECK_COUNT" -gt 0 ]; then
  if [ -n "$MESSAGES" ]; then
    MESSAGES="${MESSAGES} ${CHECK_COUNT} more plugin(s) have updates. /cc-fresh:check"
  else
    MESSAGES="${CHECK_COUNT} plugin(s) have updates. /cc-fresh:check"
  fi
fi

if [ -z "$MESSAGES" ]; then
  exit 0
fi

# Cooldown check
CURRENT_HASH=$(hash_string "${AUTO_COUNT}:${HASH_INPUT}")
SHOULD_NOTIFY="no"

if [ ! -f "$NOTIFY_STATE_FILE" ]; then
  SHOULD_NOTIFY="yes"
else
  PREV_STATE=$(python3 - "$NOTIFY_STATE_FILE" << 'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
print(d.get("last_notify_time", 0))
print(d.get("last_notify_hash", ""))
PYEOF
  )

  PREV_TIME=$(echo "$PREV_STATE" | head -1)
  PREV_HASH=$(echo "$PREV_STATE" | tail -1)

  if [ "$CURRENT_HASH" != "$PREV_HASH" ]; then
    SHOULD_NOTIFY="yes"
  else
    NOW_MS=$(epoch_ms)
    ELAPSED=$((NOW_MS - PREV_TIME))
    if [ "$ELAPSED" -ge "$COOLDOWN_MS" ]; then
      SHOULD_NOTIFY="yes"
    fi
  fi
fi

if [ "$SHOULD_NOTIFY" = "yes" ]; then
  NOW_MS=$(epoch_ms)
  python3 - "$NOTIFY_STATE_FILE" "$NOW_MS" "$CURRENT_HASH" << 'PYEOF'
import json, sys
path = sys.argv[1]
now_ms = int(sys.argv[2])
current_hash = sys.argv[3]
state = {"last_notify_time": now_ms, "last_notify_hash": current_hash}
with open(path, "w") as f:
    json.dump(state, f)
PYEOF

  echo "$MESSAGES"
fi

exit 0
