---
name: usage-guide
description: Use when deciding whether to delegate a task to the agy plugin (Google Antigravity CLI) instead of handling it directly, or when picking which agy command, model, or flag (--effort, --conversation, --print-timeout, --base, --json-schema) to use.
---

# agy Usage Guide

Decision aid for delegating tasks from Claude Code to Google Antigravity CLI (`agy`).

## When to reach for agy
- **Independent code review**: Run `/agy:review` to get an un-anchored, second-opinion code review on your local diff from a different model family before committing.
- **Image generation**: Use `/agy:image` to create assets, diagrams, or UI mockups via Google Imagen (this plugin's only image-generation path).
- **Model diversity & sanity checks**: Delegate difficult debugging problems, math/logic proofs, or architecture validation to Gemini or GPT-OSS models via `/agy:ask` or `/agy:delegate`.
- **Background research**: Offload deep investigations and exploration with `/agy:research --background` to continue local development without blocking this session.
- **Multimodal reasoning**: Analyze screenshots, UI layouts, or visual artifacts by passing image paths to Gemini's native multimodal context.

## When NOT to delegate
- **Trivial edits & quick lookups**: Simple file reads, regex searches, small typos, or single-line fixes are faster to execute directly in-session without CLI handoff latency.
- **Tasks requiring Claude's conversation history**: agy cannot see this Claude Code conversation; keep tasks that rely on recent conversational context here, or spell that context out in the prompt.
- **Tight iterative workflows**: Tasks requiring step-by-step clarification or frequent back-and-forth steering should remain in the primary session.

## Follow-ups
Every `/agy:ask`, `/agy:delegate`, `/agy:research` and `/agy:review` run ends with `[agy] conversation: <id>`. Pass `--conversation <id>` on the next call to continue that agy conversation with its full history ("now also fix the tests", "expand section 2") instead of re-sending context.

## Command-to-task mapping
| Command | Task Shape |
| :--- | :--- |
| `/agy:ask` | One-shot Q&A, conceptual questions, and quick second opinions. |
| `/agy:delegate` | Discrete, self-contained coding, refactoring, or debugging tasks. |
| `/agy:research` | Structured codebase and topic investigations, with optional background support. |
| `/agy:review` | Independent review of uncommitted changes (incl. untracked files), or a whole branch with `--base main`. |
| `/agy:image` | Prompt-based image and visual asset generation via Imagen. |
| `/agy:models` | Inspect live available models with curated use-case blurbs. |
| `/agy:help` | Command reference, invocation syntax, and flag documentation. |

## Model-selection strategy
Run `/agy:models` as the live source of truth for available models. Use `--effort low|medium|high|xhigh|max` to tune reasoning depth on any call. Rule of thumb:
- **Fast lookups & simple edits**: Flash tier (`gemini-3.8-flash-high` / `-medium` / `-low`) for low-latency, low-cost tasks.
- **Hard multi-step & architecture**: `gemini-3.1-pro-high` or `claude-opus-4-6-thinking` for deep reasoning and complex debugging.
- **Everyday coding & review**: `claude-sonnet-4-6` for balanced speed, code quality, and diff evaluation.
- **Second opinions**: `gpt-oss-120b-medium` for open-weight diversity checks and alternative reasoning angles.

## Flag-selection rules
Flags go before the prompt text; the wrapper forwards them to `agy`. A compact version of these rules is also injected into every session by the plugin's SessionStart hook (`AGY_NO_SESSION_GUIDE=1` turns it off).

| Situation | Use | Avoid |
| :--- | :--- | :--- |
| Follow-up on earlier agy work ("now also…", "fix what you found") | `--conversation <id>` from the previous `[agy] conversation:` line | `-c` / `--continue` (resumes the user's latest agy conversation, possibly their own terminal session); re-sending all context |
| Lookup, trivial edit, quick sanity check | `--effort low`, a flash model | `--effort max` |
| Hard debugging, architecture, research, review of risky code | `--effort high` (or `xhigh`) | — |
| Ordinary task | omit `--effort` and `--model` | guessing model ids — check `/agy:models` |
| Delegation that must not run unbounded | `--print-timeout 20m` (review defaults to 15m, image to 10m, others unlimited) | — |
| Review a whole branch, not just uncommitted edits | `/agy:review --base main` | — |
| Need machine-readable output | `--json-schema '<object schema>'` (wrapper prints the structured object) | parsing free text |
| Task needs files outside the repo | `--add-dir <path>` | — |
| "Plan only, don't edit" | say so in the prompt | `--mode plan` (ignored headless; agy may still edit) |
| User asked for restricted / unattended execution | `--sandbox` / `--dangerously-skip-permissions` | either one unprompted |
| Long task, user wants to keep working | `--background` on `/agy:delegate` or `/agy:research` | — |

## Handling results
- Relay agy's output verbatim, including the `[agy] conversation:` line.
- Exit `3`: model/agent error (e.g. no capacity). Relay the `[agy] error:` line; retry once or suggest another `--model`.
- Exit `124`: print timeout hit; the reply is partial. Continue with `--conversation <id>` or retry with a longer `--print-timeout`.
- Exit `1` "not authenticated" or `127`: tell the user to run `/agy:setup`.

See `/agy:help` for full flag syntax and `/agy:models` for the live model list.
