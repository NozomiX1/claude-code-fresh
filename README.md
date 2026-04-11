# cc-fresh

[中文文档](./README.zh-CN.md)

**Auto-update plugin for Claude Code** — keeps your plugins up to date with zero effort.

cc-fresh runs silently on every session start, checks all your installed marketplaces for plugin updates, applies auto-updates where configured, and notifies you about the rest. No more manually checking if your plugins are outdated.

## Features

- **Automatic update detection** — Fetches and compares remote marketplace state against your installed plugins on every session start
- **Per-plugin scoped diffing** — Counts only commits that affect each specific plugin directory, not the entire marketplace repo
- **Smart notifications** — Configurable cooldown (default 24h) prevents repeated alerts for the same pending updates
- **Auto-update mode** — Marketplaces set to `auto` policy pull and apply updates without any interaction
- **Cache optimization** — Results are cached (default 12 hours, configurable) to avoid redundant git operations across rapid session restarts
- **Version + SHA tracking** — Works with semantic versioned plugins and versionless (commit-based) plugins alike

## Requirements

- **bash** 3.2+ (macOS default works)
- **python3** (for JSON manipulation)
- **git** (for fetching marketplace updates)

## Installation

```bash
# 1. Add this repository as a marketplace
/plugin marketplace add NozomiX1/claude-code-fresh

# 2. Install the plugin
/plugin install cc-fresh@claude-code-fresh
```

After installation, cc-fresh activates automatically on your next Claude Code session.

## How It Works

### Session Start Flow

When you start a new Claude Code session, cc-fresh runs the following pipeline:

```
Session Start
    │
    ▼
[Cache fresh?] ── yes ──► Use cached results ──► [Auto policy?] ── yes ──► Apply updates
    │ no                       │                       │ no
    ▼                          ▼                       ▼
Fork git fetch               Read cache            [Cooldown expired?] ── yes ──► Print notification
to background                                         │ no
(non-blocking)                                        ▼
    │                                               (silent)
    ▼
Updates cache for
next session
```

1. **Cache check** — If `cache.json` exists and is within `cache_ttl_hours` (default 12h), use cached results. Otherwise, fork `check-updates.sh` to the background (non-blocking).
2. **Update detection** — For each installed plugin, compare the installed version/SHA against the remote marketplace state. Commit counts are scoped to each plugin's subdirectory.
3. **Auto-updates** — Plugins from marketplaces with `auto` policy are pulled and installed immediately (only when cache is fresh). The cache is updated in-place so subsequent checks remain fast.
4. **Notification** — If there are pending updates, a single notification line is printed synchronously, subject to cooldown rules. The background fetch updates the cache for the next session.

### Notification Cooldown

cc-fresh tracks a hash of the pending update list. Notifications fire when:
- It's the first time updates are detected, **or**
- The set of pending updates has changed (new plugin, new version), **or**
- The cooldown period (default 24 hours) has elapsed since the last notification

This means you won't see the same "3 plugins have updates" message every time you open a session.

## Commands

| Command | Description |
|---|---|
| `/cc-fresh:check` | Check all marketplaces for available plugin updates and display results |
| `/cc-fresh:update` | Apply all pending updates found by the last check |
| `/cc-fresh:config` | View and modify update policies, cooldown, and per-marketplace settings |

### `/cc-fresh:check`

Displays a summary of all plugin states:

```
Updates available:
  context7       1.0.0 → 1.1.0     (official-marketplace)    2 commits behind
  my-tool        a1b2c3d4e5f6 → f6e5d4c3b2a1  (community)   5 commits behind

Up to date:
  plugin-a, plugin-b, plugin-c

Ignored:
  experimental-plugin (test-marketplace)

Run /cc-fresh:update to apply updates.
Run /cc-fresh:config to change update policies.
```

### `/cc-fresh:update`

Pulls the latest from each marketplace repository, copies updated plugin files into your local plugin directory, and updates `installed_plugins.json` with new version/SHA records.

After updating, run `/reload-plugins` to apply changes to the current session.

### `/cc-fresh:config`

Interactive configuration management. Shows all known marketplaces with their current policy and lets you change them:

```
cc-fresh Configuration:

  Default policy: check
  Notification cooldown: 24 hours

  Marketplace policies:
    1. official-marketplace    auto
    2. community-plugins       (default)
    3. test-marketplace        ignore

Available policies:
  auto   - Fetch, pull, and apply updates on session start
  check  - Only check for updates and notify (default)
  ignore - Skip this marketplace entirely
```

## Configuration

Config file location: `~/.claude/cc-fresh/config.json`

This file is created automatically on first session start with the following defaults:

```json
{
  "default": "check",
  "cooldown_hours": 24,
  "cache_ttl_hours": 12,
  "marketplaces": {}
}
```

### Fields

| Field | Type | Default | Description |
|---|---|---|---|
| `default` | string | `"check"` | Default policy for marketplaces without an explicit override |
| `cooldown_hours` | number | `24` | Hours between repeated notifications for the same set of updates |
| `cache_ttl_hours` | number | `12` | Hours before cached check results expire and trigger a background refresh |
| `marketplaces` | object | `{}` | Per-marketplace policy overrides (sparse — only explicit overrides are stored) |

### Policies

| Policy | Behavior |
|---|---|
| `auto` | Fetch remote state, pull changes, and apply updates automatically on session start |
| `check` | Fetch remote state and notify about available updates, but don't apply them |
| `ignore` | Skip this marketplace entirely — no fetch, no notification |

### Example: Enable auto-update for a trusted marketplace

```json
{
  "default": "check",
  "cooldown_hours": 24,
  "marketplaces": {
    "official-marketplace": "auto"
  }
}
```

Or interactively via `/cc-fresh:config`.

## File Layout

```
cc-fresh/
├── plugin/
│   ├── .claude-plugin/
│   │   └── plugin.json          # Plugin metadata
│   ├── hooks/
│   │   └── hooks.json           # SessionStart hook definition
│   ├── scripts/
│   │   ├── helpers.sh           # Shared utilities (JSON, config, marketplace)
│   │   ├── session-start.sh     # Entry point — orchestrates check + auto-update
│   │   ├── check-updates.sh     # Core detection — git fetch + version comparison
│   │   └── do-update.sh         # Applies updates — git pull + file copy
│   └── commands/
│       ├── check.md             # /cc-fresh:check command
│       ├── update.md            # /cc-fresh:update command
│       └── config.md            # /cc-fresh:config command
├── tests/
│   ├── setup-test-env.sh        # Test fixture generator
│   ├── test-helpers.sh          # Unit tests for helpers.sh
│   ├── test-check-updates.sh    # Integration tests for update detection
│   ├── test-do-update.sh        # Integration tests for update execution
│   └── test-session-start.sh    # Integration tests for session hook
├── README.md
└── LICENSE
```

## Running Tests

All tests are self-contained bash scripts that create temporary mock environments:

```bash
# Run all tests
bash tests/test-helpers.sh
bash tests/test-check-updates.sh
bash tests/test-session-start.sh
bash tests/test-do-update.sh

# Or run them all at once
for t in tests/test-*.sh; do echo "--- $t ---"; bash "$t"; echo; done
```

Tests create isolated temp directories with mock git repos and marketplace structures, so they don't touch your real plugin installation.

## Data Files

cc-fresh stores runtime data in `~/.claude/cc-fresh/`:

| File | Purpose |
|---|---|
| `config.json` | User configuration (policies, cooldown) |
| `cache.json` | Cached update check results (TTL: configurable, default 12h) |
| `notify-state.json` | Last notification timestamp and hash (for cooldown) |

## License

MIT
