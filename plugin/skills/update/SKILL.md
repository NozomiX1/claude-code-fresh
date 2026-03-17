---
name: update
description: Execute pending plugin updates. Use when user wants to apply available plugin updates.
---

# Update Plugins

Execute the update script:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/do-update.sh"
```

Present the output to the user.

After completion, remind: "Run `/reload-plugins` to apply the changes to your current session."

If failures are reported, explain what went wrong and suggest running `/cc-fresh:check` to see current state.
