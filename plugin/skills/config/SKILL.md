---
name: config
description: Configure cc-fresh update policies per marketplace. Use when user wants to change auto-update settings, notification cooldown, or marketplace update behavior.
---

# Configure cc-fresh

Read current config from `~/.claude/cc-fresh/config.json`. If missing, defaults are:
```json
{"default": "check", "cooldown_hours": 24, "marketplaces": {}}
```

Also read `~/.claude/plugins/known_marketplaces.json` to list all known marketplace names.

Present current configuration:

```
cc-fresh Configuration:

  Default policy: [current default]
  Notification cooldown: [N] hours

  Marketplace policies:
    1. marketplace-name    [explicit policy or "(default)"]
    2. marketplace-name    [explicit policy or "(default)"]
    ...

Available policies:
  auto   - Fetch, pull, and update plugin cache on session start
  check  - Only check for updates and notify (default)
  ignore - Skip entirely
```

Ask: "What would you like to change?"

When user responds, update `~/.claude/cc-fresh/config.json` using the Write tool. Confirm the change.
