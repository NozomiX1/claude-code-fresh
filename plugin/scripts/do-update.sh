#!/usr/bin/env bash
# do-update.sh — Execute pending plugin updates from cache.json
# Reads update cache written by check-updates.sh, pulls repos, copies files.
# Usage: do-update.sh [--auto-only]
#   --auto-only: Only update plugins from marketplaces with "auto" policy
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"

ensure_data_dir

AUTO_ONLY="no"
if [ "${1:-}" = "--auto-only" ]; then
  AUTO_ONLY="yes"
fi

CACHE_FILE="${CC_FRESH_DATA_DIR}/cache.json"

if [ ! -f "$CACHE_FILE" ]; then
  echo "No update cache found. Run /cc-fresh:check first."
  exit 0
fi

# Extract updates into a temp file using python3
TMPDIR_WORK=$(mktemp -d)
trap 'rm -rf "$TMPDIR_WORK"' EXIT

UPDATES_LIST="${TMPDIR_WORK}/updates_list.txt"
python3 - "$CACHE_FILE" "$UPDATES_LIST" << 'PYEOF'
import json, sys

cache_path = sys.argv[1]
out_path = sys.argv[2]

with open(cache_path) as f:
    data = json.load(f)

updates = data.get("updates", [])

with open(out_path, "w") as out:
    for u in updates:
        name = u.get("name", "")
        marketplace = u.get("marketplace", "")
        installed_ver = u.get("installed_version", "")
        available_ver = u.get("available_version", "")
        out.write(f"{name}\t{marketplace}\t{installed_ver}\t{available_ver}\n")
PYEOF

if [ ! -s "$UPDATES_LIST" ]; then
  echo "All plugins are up to date."
  exit 0
fi

# Process each update
RESULTS_FILE="${TMPDIR_WORK}/results.txt"
UPDATED_PLUGINS="${TMPDIR_WORK}/updated_plugins.txt"
touch "$RESULTS_FILE" "$UPDATED_PLUGINS"

OK_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

while IFS="	" read -r plugin_name marketplace_name current_version new_version; do
  [ -z "$plugin_name" ] && continue

  label="${plugin_name}@${marketplace_name}"

  # Filter by policy if --auto-only
  if [ "$AUTO_ONLY" = "yes" ]; then
    policy=$(get_marketplace_policy "$marketplace_name")
    if [ "$policy" != "auto" ]; then
      continue
    fi
  fi

  # Get marketplace dir
  marketplace_dir=$(get_marketplace_dir "$marketplace_name")
  if [ -z "$marketplace_dir" ] || [ ! -d "$marketplace_dir" ]; then
    echo "FAIL	${label}	marketplace directory not found" >> "$RESULTS_FILE"
    FAIL_COUNT=$((FAIL_COUNT+1))
    continue
  fi

  # Git pull --ff-only
  if ! git -C "$marketplace_dir" pull --ff-only >/dev/null 2>&1; then
    echo "FAIL	${label}	git pull --ff-only failed" >> "$RESULTS_FILE"
    FAIL_COUNT=$((FAIL_COUNT+1))
    continue
  fi

  # Get plugin source path
  plugin_source=$(get_marketplace_plugin_source "$marketplace_dir" "$plugin_name")

  # Check for external source
  case "$plugin_source" in
    EXTERNAL:*)
      echo "SKIP	${label}	external URL plugin, cannot update this way" >> "$RESULTS_FILE"
      SKIP_COUNT=$((SKIP_COUNT+1))
      continue
      ;;
  esac

  # Resolve local source path
  local_source="${marketplace_dir}/${plugin_source}"
  if [ ! -d "$local_source" ]; then
    echo "FAIL	${label}	source directory not found: ${plugin_source}" >> "$RESULTS_FILE"
    FAIL_COUNT=$((FAIL_COUNT+1))
    continue
  fi

  # Create new cache directory
  new_cache_dir="${CACHE_DIR}/${marketplace_name}/${plugin_name}/${new_version}"
  mkdir -p "$new_cache_dir"

  # Copy plugin files
  cp -r "${local_source}/." "${new_cache_dir}/"

  # Mark old cache dir with .orphaned_at
  old_cache_dir="${CACHE_DIR}/${marketplace_name}/${plugin_name}/${current_version}"
  if [ -d "$old_cache_dir" ] && [ "$old_cache_dir" != "$new_cache_dir" ]; then
    epoch_ms > "${old_cache_dir}/.orphaned_at"
  fi

  # Get git commit SHA and ISO timestamp
  new_sha=$(git -C "$marketplace_dir" rev-parse HEAD 2>/dev/null || echo "")
  iso_now=$(python3 -c "import datetime; print(datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'))")

  # Update installed_plugins.json
  python3 - "$INSTALLED_PLUGINS_FILE" "$plugin_name" "$marketplace_name" "$new_version" "$new_cache_dir" "$new_sha" "$iso_now" << 'PYEOF'
import json, sys

installed_path = sys.argv[1]
plugin_name = sys.argv[2]
marketplace_name = sys.argv[3]
new_version = sys.argv[4]
new_install_path = sys.argv[5]
new_sha = sys.argv[6]
iso_now = sys.argv[7]

with open(installed_path) as f:
    data = json.load(f)

key = f"{plugin_name}@{marketplace_name}"
plugins = data.get("plugins", {})

if key in plugins:
    entries = plugins[key]
    for entry in entries:
        entry["version"] = new_version
        entry["installPath"] = new_install_path
        entry["gitCommitSha"] = new_sha
        entry["lastUpdated"] = iso_now

with open(installed_path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PYEOF

  echo "OK	${label}	${current_version} -> ${new_version}" >> "$RESULTS_FILE"
  echo "${plugin_name}	${marketplace_name}	${new_version}" >> "$UPDATED_PLUGINS"
  OK_COUNT=$((OK_COUNT+1))

done < "$UPDATES_LIST"

# Print summary
echo "Update complete: ${OK_COUNT} succeeded, ${FAIL_COUNT} failed."

while IFS="	" read -r status label detail; do
  [ -z "$status" ] && continue
  echo "[${status}] ${label} — ${detail}"
done < "$RESULTS_FILE"

if [ "$OK_COUNT" -gt 0 ]; then
  echo "Run /reload-plugins to apply changes."
fi

# Move successfully updated plugins from "updates" to "up_to_date" in cache.json
if [ -s "$UPDATED_PLUGINS" ] && [ -f "$CACHE_FILE" ]; then
  python3 - "$CACHE_FILE" "$UPDATED_PLUGINS" << 'PYEOF'
import json, sys

cache_path = sys.argv[1]
updated_path = sys.argv[2]

with open(cache_path) as f:
    cache = json.load(f)

# Read updated plugin keys
updated_keys = set()
with open(updated_path) as f:
    for line in f:
        parts = line.strip().split("\t")
        if len(parts) >= 2:
            updated_keys.add((parts[0], parts[1]))

remaining_updates = []
for u in cache.get("updates", []):
    key = (u.get("name", ""), u.get("marketplace", ""))
    if key in updated_keys:
        new_ver = u.get("available_version", u.get("installed_version", ""))
        cache.setdefault("up_to_date", []).append({
            "name": u["name"],
            "marketplace": u["marketplace"],
            "version": new_ver
        })
    else:
        remaining_updates.append(u)

cache["updates"] = remaining_updates

with open(cache_path, "w") as f:
    json.dump(cache, f, indent=2)
    f.write("\n")
PYEOF
fi

# Delete cache.json so next check gets fresh state (only for full runs, not --auto-only)
if [ "$AUTO_ONLY" = "no" ]; then
  rm -f "$CACHE_FILE"
fi
