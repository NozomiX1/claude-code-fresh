---
name: check
description: Check for available Claude Code plugin updates. Use when user wants to see which plugins have updates, or asks about plugin versions.
---

# Check Plugin Updates

Read the cache file at `~/.claude/cc-fresh/cache.json`.

If the file doesn't exist or is older than 1 hour, run the check script first:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-updates.sh"
```

Then read `~/.claude/cc-fresh/cache.json` and present results:

**Updates available:**
For each entry in `updates`, show: `  plugin_name    current_version -> new_version    (marketplace)`
If `commits_behind` is non-empty, append `(N commits behind)`.

**Up to date:**
List names from `up_to_date` on one line, comma-separated.

**Ignored:**
List names from `ignored` with marketplace name.

**Errors:**
Show marketplace and error for any entries in `errors`.

If updates exist, end with: "Run `/cc-fresh:update` to apply updates."
Always end with: "Run `/cc-fresh:config` to change update policies."
