#!/usr/bin/env bash
# session-start.sh — SessionStart hook entry point for cc-fresh
# Runs check-updates.sh, then decides whether to show a notification.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"

ensure_data_dir

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

# Run check-updates.sh and capture its JSON output
CACHE_JSON=$(bash "${SCRIPT_DIR}/check-updates.sh" 2>/dev/null) || true

if [ -z "$CACHE_JSON" ]; then
  exit 0
fi

# Use a temp file to pass the JSON to python3 safely
TMPWORK=$(mktemp -d)
trap 'rm -rf "$TMPWORK"' EXIT

echo "$CACHE_JSON" > "${TMPWORK}/cache.json"

# Count updates and build hash string
UPDATE_INFO=$(python3 - "${TMPWORK}/cache.json" << 'PYEOF'
import json, sys

cache_path = sys.argv[1]
with open(cache_path) as f:
    data = json.load(f)

updates = data.get("updates", [])
count = len(updates)

if count == 0:
    print("0")
    print("")
else:
    # Build sorted plugin@version strings joined with |
    entries = []
    for u in updates:
        name = u.get("name", "")
        ver = u.get("available_version", u.get("installed_version", ""))
        entries.append(f"{name}@{ver}")
    entries.sort()
    hash_input = "|".join(entries)
    print(count)
    print(hash_input)
PYEOF
)

UPDATE_COUNT=$(echo "$UPDATE_INFO" | head -1)
HASH_INPUT=$(echo "$UPDATE_INFO" | tail -1)

# No updates → clean up and exit
if [ "$UPDATE_COUNT" = "0" ] || [ -z "$UPDATE_COUNT" ]; then
  rm -f "$NOTIFY_STATE_FILE"
  exit 0
fi

# Compute hash of the update list
CURRENT_HASH=$(hash_string "$HASH_INPUT")

# Read existing notify-state.json if it exists
SHOULD_NOTIFY="no"

if [ ! -f "$NOTIFY_STATE_FILE" ]; then
  # First time seeing updates
  SHOULD_NOTIFY="yes"
else
  # Read last_notify_time and last_notify_hash
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
    # Hash changed → new updates
    SHOULD_NOTIFY="yes"
  else
    # Same hash → check cooldown
    NOW_MS=$(epoch_ms)
    ELAPSED=$((NOW_MS - PREV_TIME))
    if [ "$ELAPSED" -ge "$COOLDOWN_MS" ]; then
      SHOULD_NOTIFY="yes"
    fi
  fi
fi

if [ "$SHOULD_NOTIFY" = "yes" ]; then
  # Update notify-state.json
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

  # Output notification line
  echo "${UPDATE_COUNT} plugin(s) have updates. /cc-fresh:check"
fi

exit 0
