---
description: Generate an image with Antigravity CLI (uses agy's built-in generate_image tool — Imagen under the hood)
argument-hint: "[--name <slug>] [--output <path>] [--model <model>] <description>"
allowed-tools: Bash(bash:*)
---

Ask `agy` to generate an image. The Antigravity CLI ships a native
`generate_image` tool (Imagen under the hood) that triggers automatically
when the prompt asks for an image — the wrapper builds the right prompt and
extracts the saved file path.

The user's request:

```
$ARGUMENTS
```

## How to invoke

Parse the user's request:

- `--name <slug>` — optional. Filename slug `agy` should save the image
  under (no extension).
- `--output <path>` — optional. Local path the wrapper should copy the
  generated file to after `agy` finishes.
- `--model <model>` — optional. Model to use (id or display label, see `/agy:models`).
- The remaining text — the description of what to generate.

Feed the description to the wrapper via stdin using a single-quoted heredoc
(`<<'PROMPT_EOF2'`) to prevent shell expansions:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/agy-run.sh" image [--name <slug>] [--output <path>] [--model <model>] <<'PROMPT_EOF2'
<description text, verbatim>
PROMPT_EOF2
```

## How the wrapper finds the saved path

The wrapper builds a prompt that asks `agy` to end its reply with a single
line:

```
IMAGE_PATH: <absolute path to the generated image>
```

This is the **primary contract**. If `agy` honors it, the wrapper picks the
path up deterministically and (when `--output` is set) copies the file
there. As a fallback, the wrapper also scrapes any absolute `*.png/.jpg/.jpeg/.webp`
path that appears in `agy`'s reply.

If neither is found, the wrapper prints a clear warning so the user knows the
file wasn't located. Generated files normally live under
`~/.gemini/antigravity-cli/brain/<uuid>/<name>.<ext>`.

## Notes

- Return Antigravity's full text response verbatim so the user can see the
  generated path.
- If the user did not provide any description, ask what they want to
  generate.
- If the wrapper reports `agy is not installed` or `not authenticated`,
  stop and tell the user to run `/agy:setup`.
