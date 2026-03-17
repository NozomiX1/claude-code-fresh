#!/usr/bin/env bash
# setup-test-env.sh — Create a mock Claude plugins environment for testing
# Usage: bash setup-test-env.sh [test-dir]
# Prints the test directory path to stdout.
set -euo pipefail

TEST_DIR="${1:-$(mktemp -d)}"
mkdir -p "$TEST_DIR"

# Directories
BARE_REPO="${TEST_DIR}/bare-repo.git"
MARKETPLACE_DIR="${TEST_DIR}/marketplaces/test-marketplace"
CACHE_DIR="${TEST_DIR}/cache/test-marketplace/hello-plugin/1.0.0"
DATA_DIR="${TEST_DIR}/cc-fresh-data"

mkdir -p "$DATA_DIR"

# 1. Create bare git repo as "remote"
git init --bare "$BARE_REPO" >/dev/null 2>&1

# 2. Clone it to simulate marketplace install location
git clone "$BARE_REPO" "$MARKETPLACE_DIR" >/dev/null 2>&1

# 3. Populate with marketplace.json containing hello-plugin 1.0.0
mkdir -p "${MARKETPLACE_DIR}/.claude-plugin"
cat > "${MARKETPLACE_DIR}/.claude-plugin/marketplace.json" << 'MKJSON'
{
  "name": "test-marketplace",
  "plugins": [
    {
      "name": "hello-plugin",
      "version": "1.0.0",
      "source": "./plugins/hello-plugin"
    }
  ]
}
MKJSON

# 4. Create plugin directory with plugin.json and SKILL.md
mkdir -p "${MARKETPLACE_DIR}/plugins/hello-plugin"
cat > "${MARKETPLACE_DIR}/plugins/hello-plugin/plugin.json" << 'PJSON'
{
  "name": "hello-plugin",
  "version": "1.0.0",
  "description": "A test plugin"
}
PJSON
cat > "${MARKETPLACE_DIR}/plugins/hello-plugin/SKILL.md" << 'SKILL'
# Hello Plugin
This is version 1.0.0 of the hello plugin.
SKILL

# 5. Commit and push to bare repo
(
  cd "$MARKETPLACE_DIR"
  git add -A >/dev/null 2>&1
  git commit -m "Initial commit: hello-plugin 1.0.0" >/dev/null 2>&1
  git push origin HEAD >/dev/null 2>&1
)

# 6. Record initial commit SHA
INITIAL_SHA=$(cd "$MARKETPLACE_DIR" && git rev-parse HEAD)

# 7. Create mock installed_plugins.json
cat > "${TEST_DIR}/installed_plugins.json" << IPJSON
{
  "plugins": {
    "hello-plugin@test-marketplace": [
      {
        "version": "1.0.0",
        "gitCommitSha": "${INITIAL_SHA}",
        "installPath": "${CACHE_DIR}"
      }
    ]
  }
}
IPJSON

# 8. Create mock known_marketplaces.json
cat > "${TEST_DIR}/known_marketplaces.json" << KMJSON
{
  "test-marketplace": {
    "installLocation": "${MARKETPLACE_DIR}"
  }
}
KMJSON

# 9. Create mock plugin cache directory
mkdir -p "$CACHE_DIR"

# 10. Simulate upstream update: bump to 1.1.0
TMPCLONE="${TEST_DIR}/tmp-clone"
git clone "$BARE_REPO" "$TMPCLONE" >/dev/null 2>&1
(
  cd "$TMPCLONE"

  # Update marketplace.json version
  cat > ".claude-plugin/marketplace.json" << 'MKJSON2'
{
  "name": "test-marketplace",
  "plugins": [
    {
      "name": "hello-plugin",
      "version": "1.1.0",
      "source": "./plugins/hello-plugin"
    }
  ]
}
MKJSON2

  # Update plugin.json version
  cat > "plugins/hello-plugin/plugin.json" << 'PJSON2'
{
  "name": "hello-plugin",
  "version": "1.1.0",
  "description": "A test plugin"
}
PJSON2

  # Update SKILL.md
  cat > "plugins/hello-plugin/SKILL.md" << 'SKILL2'
# Hello Plugin
This is version 1.1.0 of the hello plugin with new features.
SKILL2

  git add -A >/dev/null 2>&1
  git commit -m "Bump hello-plugin to 1.1.0" >/dev/null 2>&1
  git push origin HEAD >/dev/null 2>&1
)
rm -rf "$TMPCLONE"

echo "$TEST_DIR"
