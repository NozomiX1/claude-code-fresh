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

# Cache the remote marketplace.json per marketplace (avoid repeated git show)
# Sets REMOTE_MKT_JSON_FILE to the cached file path
cache_remote_marketplace_json() {
  local mkt_dir="$1" remote_ref="$2" mkt_name="$3"
  REMOTE_MKT_JSON_FILE="${TMPDIR_WORK}/remote_mkt_${mkt_name}.json"
  if [ ! -f "$REMOTE_MKT_JSON_FILE" ]; then
    git -C "$mkt_dir" show "${remote_ref}:.claude-plugin/marketplace.json" > "$REMOTE_MKT_JSON_FILE" 2>/dev/null || return 1
  fi
}

# Check if plugin exists in remote marketplace.json and get its version + source
# Output: "FOUND:<version>:<source_path>" if found, "NOTFOUND" if not found
# source_path is the local directory path (e.g., "./plugins/context7") or empty for external
get_remote_plugin_info() {
  local mkt_json_file="$1" plugin_name="$2"
  python3 - "$mkt_json_file" "$plugin_name" << 'PYEOF'
import json, sys
mkt_path = sys.argv[1]
plugin_name = sys.argv[2]
with open(mkt_path) as f:
    d = json.load(f)
plugins = d.get('plugins', [])

def get_source_path(p):
    src = p.get('source', '')
    if isinstance(src, str):
        return src
    return ''  # external URL source

if isinstance(plugins, list):
    for p in plugins:
        if p.get('name') == plugin_name:
            ver = p.get('version', '')
            src = get_source_path(p)
            print(f"FOUND:{ver}:{src}")
            sys.exit()
elif isinstance(plugins, dict):
    if plugin_name in plugins:
        p = plugins[plugin_name]
        ver = p.get('version', '')
        src = get_source_path(p)
        print(f"FOUND:{ver}:{src}")
        sys.exit()
print("NOTFOUND")
PYEOF
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

  # Cache remote marketplace.json once per marketplace
  if ! cache_remote_marketplace_json "$mkt_dir" "$remote_ref" "$mkt_name"; then
    echo "{\"marketplace\": \"${mkt_name}\", \"message\": \"could not read remote marketplace.json\"}" >> "$ERRORS_FILE"
    continue
  fi

  # Check each installed plugin from this marketplace
  get_installed_plugins_for_marketplace "$mkt_name" | while IFS="	" read -r pname pver psha ppath; do
    [ -z "$pname" ] && continue

    # Check if plugin exists in remote marketplace.json and get version
    plugin_info=$(get_remote_plugin_info "$REMOTE_MKT_JSON_FILE" "$pname")

    if [ "$plugin_info" = "NOTFOUND" ]; then
      echo "{\"marketplace\": \"${mkt_name}\", \"message\": \"plugin ${pname} not found in marketplace.json\"}" >> "$ERRORS_FILE"
      continue
    fi

    # Extract version and source path from "FOUND:<version>:<source_path>"
    plugin_info_body="${plugin_info#FOUND:}"
    new_ver="${plugin_info_body%%:*}"
    plugin_source="${plugin_info_body#*:}"

    # Case 1: Both have version strings and they differ → version update
    if [ -n "$new_ver" ] && [ "$new_ver" != "$pver" ]; then
      echo "{\"name\": \"${pname}\", \"marketplace\": \"${mkt_name}\", \"installed_version\": \"${pver}\", \"available_version\": \"${new_ver}\"}" >> "$UPDATES_FILE"
      continue
    fi

    # Case 2: Check commit SHA for behind-commits detection
    if [ -n "$psha" ]; then
      remote_sha=$(git -C "$mkt_dir" rev-parse "$remote_ref" 2>/dev/null || echo "")
      if [ -n "$remote_sha" ] && [ "$remote_sha" != "$psha" ]; then
        # Scope commit count to plugin's directory (not entire marketplace repo)
        if [ -n "$plugin_source" ]; then
          commits_behind=$(git -C "$mkt_dir" rev-list --count "${psha}..${remote_sha}" -- "$plugin_source" 2>/dev/null || echo "0")
        else
          # External plugin or unknown source — count all commits
          commits_behind=$(git -C "$mkt_dir" rev-list --count "${psha}..${remote_sha}" 2>/dev/null || echo "0")
        fi
        if [ "$commits_behind" -gt 0 ] 2>/dev/null; then
          if [ -n "$new_ver" ] && [ "$new_ver" != "$pver" ]; then
            # Version actually changed (e.g., 10.5.6 → 10.6.0)
            display_old="${pver}"
            display_new="$new_ver"
          else
            # No version change — show commit SHAs for both
            display_old="${psha:0:12}"
            if [ -n "$plugin_source" ]; then
              latest_plugin_sha=$(git -C "$mkt_dir" rev-list -1 "$remote_ref" -- "$plugin_source" 2>/dev/null || echo "")
              display_new="${latest_plugin_sha:+${latest_plugin_sha:0:12}}"
              display_new="${display_new:-${display_old}}"
            else
              display_new="${display_old}"
            fi
          fi
          echo "{\"name\": \"${pname}\", \"marketplace\": \"${mkt_name}\", \"installed_version\": \"${display_old}\", \"available_version\": \"${display_new}\", \"installed_sha\": \"${psha}\", \"remote_sha\": \"${remote_sha}\", \"commits_behind\": ${commits_behind}}" >> "$UPDATES_FILE"
        else
          echo "{\"name\": \"${pname}\", \"marketplace\": \"${mkt_name}\", \"version\": \"${pver}\"}" >> "$UPTODATE_FILE"
        fi
      else
        echo "{\"name\": \"${pname}\", \"marketplace\": \"${mkt_name}\", \"version\": \"${pver}\"}" >> "$UPTODATE_FILE"
      fi
    else
      # No SHA, same/matching version → up to date
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
