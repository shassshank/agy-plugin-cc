---
description: Verify the Antigravity CLI (`agy`) is installed and authenticated; offer to install it if missing
allowed-tools: Bash(bash:*), Bash(curl:*), AskUserQuestion
---

Run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/agy-run.sh" check
```

Then interpret the JSON output:

- If `installed: false`, use `AskUserQuestion` once to offer installation.
  Options:
  - `Install agy now (Recommended)` — run the official installer:
    ```bash
    curl -fsSL https://antigravity.google/cli/install.sh | bash
    ```
    Then re-run the check.
  - `Skip for now` — explain that `/agy:ask`, `/agy:delegate`,
    `/agy:research`, `/agy:review`, `/agy:image`, and `/agy:models` will
    fail until `agy` is installed.

- If `installed: true` but `auth: missing`, tell the user to either:
  - run `!agy` once interactively to sign in (stored in the OS keychain),
    **or**
  - export `GEMINI_API_KEY` (a Gemini API key) in their shell rc and reload it.

- If `installed: true` and `auth` is `api-key`, `adc` or `oauth`, report that
  everything is ready — one short status line is enough.
- If `auth` is `unknown`, agy could not be asked (e.g. no network); say the
  sign-in could not be verified and that the next `/agy:*` call will tell.
- If `warning` is non-empty, relay it (it suggests `agy update` for an agy
  older than the plugin is tested on).
