# cc-fresh

Auto-update detection and management for Claude Code plugins.

## What it does

- Detects available updates across all installed marketplaces on session start
- Smart notifications with cooldown to avoid repeated alerts for the same updates
- One-command updates via `/cc-fresh:update` — pulls latest, copies plugin files, updates install records

## Install

```
/plugin marketplace add <your-github>/cc-fresh
/plugin install cc-fresh@cc-fresh-marketplace
```

## Commands

| Command           | Description                                          |
|-------------------|------------------------------------------------------|
| `/cc-fresh:check` | Check all marketplaces for available plugin updates  |
| `/cc-fresh:update`| Apply pending updates found by the last check        |
| `/cc-fresh:config`| View and change update policies and cooldown setting |

## Configuration

Config file: `~/.claude/cc-fresh/config.json`

```json
{
  "default": "check",
  "cooldown_hours": 24,
  "marketplaces": {
    "my-marketplace": "auto"
  }
}
```

Policies:

- `auto` — Fetch, pull, and update plugin cache automatically on session start
- `check` — Check for updates and notify (default)
- `ignore` — Skip this marketplace entirely

`cooldown_hours` controls how often the same pending updates trigger a notification.
The default is 24 hours. A new set of updates always notifies immediately.

## Requirements

- git
- python3
- bash 3.2+
