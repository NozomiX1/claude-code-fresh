#!/usr/bin/env bash
# check-updates.sh — Detect available plugin updates across marketplaces
# Fetches latest from remotes, compares versions, outputs JSON report.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"

ensure_data_dir

# Temp files for collecting results
TMPDIR_WORK=$(mktemp -d)
trap 'rm -rf "$TMPDIR_WORK"' EXIT

UPDATES_FILE="${TMPDIR_WORK}/updates.jsonl"
UPTODATE_FILE="${TMPDIR_WORK}/uptodate.jsonl"
ERRORS_FILE="${TMPDIR_WORK}/errors.jsonl"
IGNORED_FILE="${TMPDIR_WORK}/ignored.jsonl"

touch "$UPDATES_FILE" "$UPTODATE_FILE" "$ERRORS_FILE" "$IGNORED_FILE"

# Get the remote tracking branch for a marketplace dir
get_remote_branch() {
  local mkt_dir="$1"
  local branch
  branch=$(git -C "$mkt_dir" symbolic-ref --short HEAD 2>/dev/null || echo "main")
  echo "origin/${branch}"
}

# Read plugin version from the remote ref's marketplace.json (after git fetch)
get_remote_plugin_version() {
  local mkt_dir="$1" plugin_name="$2" remote_ref="$3"
  local tmp_mkt_json
  tmp_mkt_json="${TMPDIR_WORK}/remote_mkt_$$.json"
  git -C "$mkt_dir" show "${remote_ref}:.claude-plugin/marketplace.json" > "$tmp_mkt_json" 2>/dev/null || return
  python3 - "$tmp_mkt_json" "$plugin_name" << 'PYEOF'
import json, sys
mkt_path = sys.argv[1]
plugin_name = sys.argv[2]
with open(mkt_path) as f:
    d = json.load(f)
plugins = d.get('plugins', [])
if isinstance(plugins, list):
    for p in plugins:
        if p.get('name') == plugin_name:
            print(p.get('version', ''))
            break
elif isinstance(plugins, dict):
    p = plugins.get(plugin_name, {})
    print(p.get('version', ''))
PYEOF
  rm -f "$tmp_mkt_json"
}

# Iterate over known marketplaces
get_known_marketplaces | while IFS= read -r mkt_name; do
  [ -z "$mkt_name" ] && continue

  # Check policy
  policy=$(get_marketplace_policy "$mkt_name")

  if [ "$policy" = "ignore" ]; then
    # Collect all plugin names for this marketplace into ignored list
    get_installed_plugins_for_marketplace "$mkt_name" | while IFS="	" read -r pname pver psha ppath; do
      echo "{\"name\": \"${pname}\", \"marketplace\": \"${mkt_name}\"}" >> "$IGNORED_FILE"
    done
    continue
  fi

  # Get marketplace dir
  mkt_dir=$(get_marketplace_dir "$mkt_name")
  if [ -z "$mkt_dir" ] || [ ! -d "$mkt_dir" ]; then
    echo "{\"marketplace\": \"${mkt_name}\", \"message\": \"marketplace directory not found\"}" >> "$ERRORS_FILE"
    continue
  fi

  # Git fetch
  if ! git -C "$mkt_dir" fetch origin >/dev/null 2>&1; then
    echo "{\"marketplace\": \"${mkt_name}\", \"message\": \"git fetch failed\"}" >> "$ERRORS_FILE"
    continue
  fi

  # Determine remote branch ref
  remote_ref=$(get_remote_branch "$mkt_dir")

  # Auto policy: also pull
  if [ "$policy" = "auto" ]; then
    if ! git -C "$mkt_dir" pull --ff-only origin HEAD >/dev/null 2>&1; then
      log_warn "git pull --ff-only failed for marketplace '$mkt_name'"
    fi
  fi

  # Check each installed plugin from this marketplace
  get_installed_plugins_for_marketplace "$mkt_name" | while IFS="	" read -r pname pver psha ppath; do
    [ -z "$pname" ] && continue

    # Read version from remote ref (fetched content, not local working tree)
    new_ver=$(get_remote_plugin_version "$mkt_dir" "$pname" "$remote_ref")

    if [ -z "$new_ver" ]; then
      echo "{\"marketplace\": \"${mkt_name}\", \"message\": \"plugin ${pname} not found in marketplace.json\"}" >> "$ERRORS_FILE"
      continue
    fi

    if [ "$new_ver" != "$pver" ]; then
      # Version changed - update available
      echo "{\"name\": \"${pname}\", \"marketplace\": \"${mkt_name}\", \"installed_version\": \"${pver}\", \"available_version\": \"${new_ver}\"}" >> "$UPDATES_FILE"
    elif [ -n "$psha" ]; then
      # Same version, check commit SHA against remote HEAD
      remote_sha=$(git -C "$mkt_dir" rev-parse "$remote_ref" 2>/dev/null || echo "")
      if [ -n "$remote_sha" ] && [ "$remote_sha" != "$psha" ]; then
        commits_behind=$(git -C "$mkt_dir" rev-list --count "${psha}..${remote_sha}" 2>/dev/null || echo "0")
        echo "{\"name\": \"${pname}\", \"marketplace\": \"${mkt_name}\", \"installed_version\": \"${pver}\", \"available_version\": \"${pver}\", \"installed_sha\": \"${psha}\", \"remote_sha\": \"${remote_sha}\", \"commits_behind\": ${commits_behind}}" >> "$UPDATES_FILE"
      else
        echo "{\"name\": \"${pname}\", \"marketplace\": \"${mkt_name}\", \"version\": \"${pver}\"}" >> "$UPTODATE_FILE"
      fi
    else
      echo "{\"name\": \"${pname}\", \"marketplace\": \"${mkt_name}\", \"version\": \"${pver}\"}" >> "$UPTODATE_FILE"
    fi
  done
done

# Build final JSON using python3, reading from temp files
result=$(python3 << PYEOF
import json, time, os

def read_jsonl(path):
    items = []
    if os.path.exists(path):
        with open(path) as f:
            for line in f:
                line = line.strip()
                if line:
                    items.append(json.loads(line))
    return items

updates = read_jsonl("${UPDATES_FILE}")
up_to_date = read_jsonl("${UPTODATE_FILE}")
errors = read_jsonl("${ERRORS_FILE}")
ignored = read_jsonl("${IGNORED_FILE}")

result = {
    "checked_at": int(time.time() * 1000),
    "updates": updates,
    "up_to_date": up_to_date,
    "errors": errors,
    "ignored": ignored
}

print(json.dumps(result, indent=2))
PYEOF
)

# Write cache
echo "$result" > "${CC_FRESH_DATA_DIR}/cache.json"

# Output to stdout
echo "$result"
