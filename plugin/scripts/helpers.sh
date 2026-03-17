#!/usr/bin/env bash
# helpers.sh — Shared utilities for cc-fresh scripts
# Sourced by other scripts, never run directly.

CC_FRESH_DATA_DIR="${CC_FRESH_DATA_DIR:-$HOME/.claude/cc-fresh}"
PLUGINS_DIR="${PLUGINS_DIR:-$HOME/.claude/plugins}"
INSTALLED_PLUGINS_FILE="${INSTALLED_PLUGINS_FILE:-$PLUGINS_DIR/installed_plugins.json}"
KNOWN_MARKETPLACES_FILE="${KNOWN_MARKETPLACES_FILE:-$PLUGINS_DIR/known_marketplaces.json}"
MARKETPLACES_DIR="${MARKETPLACES_DIR:-$PLUGINS_DIR/marketplaces}"
CACHE_DIR="${CACHE_DIR:-$PLUGINS_DIR/cache}"

log_info()  { echo "[cc-fresh] $*" >&2; }
log_warn()  { echo "[cc-fresh] WARN: $*" >&2; }
log_error() { echo "[cc-fresh] ERROR: $*" >&2; }

ensure_data_dir() {
  mkdir -p "$CC_FRESH_DATA_DIR"
}

# Read a top-level key from JSON on stdin
json_get() {
  local key="$1"
  python3 -c "
import sys, json
d = json.load(sys.stdin)
v = d.get('$key', '')
print(v if not isinstance(v, (dict, list)) else json.dumps(v))
"
}

# Set a top-level key in JSON on stdin, output modified JSON
json_set() {
  local key="$1" value="$2"
  python3 -c "
import sys, json
d = json.load(sys.stdin)
try:
    d['$key'] = json.loads('''\"$value\"''')
except:
    d['$key'] = '''$value'''
json.dump(d, sys.stdout)
"
}

# Read config, return defaults if file missing
read_config() {
  local config_file="${CC_FRESH_DATA_DIR}/config.json"
  if [ -f "$config_file" ]; then
    cat "$config_file"
  else
    echo '{"default":"check","cooldown_hours":24,"marketplaces":{}}'
  fi
}

# Get policy for a marketplace
get_marketplace_policy() {
  local marketplace_name="$1"
  local config
  config=$(read_config)
  python3 << PYEOF
import json
config = json.loads('''$config''')
mp = config.get('marketplaces', {})
default = config.get('default', 'check')
print(mp.get('$marketplace_name', default))
PYEOF
}

# List all marketplace names from known_marketplaces.json
get_known_marketplaces() {
  if [ ! -f "$KNOWN_MARKETPLACES_FILE" ]; then
    return
  fi
  python3 << PYEOF
import json
with open('$KNOWN_MARKETPLACES_FILE') as f:
    d = json.load(f)
for name in d:
    print(name)
PYEOF
}

# Get installed plugins for a marketplace
# Output: plugin_name\tversion\tgitCommitSha\tinstallPath (per line)
get_installed_plugins_for_marketplace() {
  local marketplace_name="$1"
  if [ ! -f "$INSTALLED_PLUGINS_FILE" ]; then
    return
  fi
  python3 << PYEOF
import json
with open('$INSTALLED_PLUGINS_FILE') as f:
    d = json.load(f)
plugins = d.get('plugins', {})
for key, entries in plugins.items():
    if '@' in key:
        pname, mkt = key.rsplit('@', 1)
        if mkt == '$marketplace_name':
            for e in entries:
                sha = e.get('gitCommitSha', '')
                print(f"{pname}\t{e['version']}\t{sha}\t{e.get('installPath','')}")
PYEOF
}

# Get marketplace install location directory path
get_marketplace_dir() {
  local marketplace_name="$1"
  if [ ! -f "$KNOWN_MARKETPLACES_FILE" ]; then
    return 1
  fi
  python3 << PYEOF
import json
with open('$KNOWN_MARKETPLACES_FILE') as f:
    d = json.load(f)
mp = d.get('$marketplace_name', {})
print(mp.get('installLocation', ''))
PYEOF
}

# Get plugin version from marketplace.json in a marketplace dir
get_marketplace_plugin_version() {
  local marketplace_dir="$1" plugin_name="$2"
  local mkt_json="${marketplace_dir}/.claude-plugin/marketplace.json"
  if [ ! -f "$mkt_json" ]; then
    return
  fi
  python3 << PYEOF
import json
with open('$mkt_json') as f:
    d = json.load(f)
plugins = d.get('plugins', [])
if isinstance(plugins, list):
    for p in plugins:
        if p.get('name') == '$plugin_name':
            print(p.get('version', ''))
            break
elif isinstance(plugins, dict):
    p = plugins.get('$plugin_name', {})
    print(p.get('version', ''))
PYEOF
}

# Get plugin source path from marketplace.json
# Returns relative path for local, "EXTERNAL:<url>" for external
get_marketplace_plugin_source() {
  local marketplace_dir="$1" plugin_name="$2"
  local mkt_json="${marketplace_dir}/.claude-plugin/marketplace.json"
  if [ ! -f "$mkt_json" ]; then
    return
  fi
  python3 << PYEOF
import json
with open('$mkt_json') as f:
    d = json.load(f)
plugins = d.get('plugins', [])
if isinstance(plugins, list):
    for p in plugins:
        if p.get('name') == '$plugin_name':
            src = p.get('source', '')
            if isinstance(src, str):
                print(src)
            elif isinstance(src, dict):
                print('EXTERNAL:' + src.get('url', ''))
            break
elif isinstance(plugins, dict):
    p = plugins.get('$plugin_name', {})
    src = p.get('source', '')
    if isinstance(src, str):
        print(src)
    elif isinstance(src, dict):
        print('EXTERNAL:' + src.get('url', ''))
PYEOF
}

# SHA256 hash of a string
hash_string() {
  echo -n "$1" | shasum -a 256 | cut -d' ' -f1
}

# Current epoch in milliseconds
epoch_ms() {
  python3 -c "import time; print(int(time.time() * 1000))"
}
