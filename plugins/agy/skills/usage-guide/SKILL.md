---
name: usage-guide
description: Use when deciding whether to delegate a task to the agy plugin (Google Antigravity CLI) instead of handling it directly, or when picking which agy command or model to use.
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
- **Tasks requiring conversation history**: `agy:runner` is a stateless, one-shot forwarder with zero memory of prior chat turns; keep tasks that rely on recent conversational context within Claude Code.
- **Tight iterative workflows**: Tasks requiring step-by-step clarification or frequent back-and-forth steering should remain in the primary session.

## Command-to-task mapping
| Command | Task Shape |
| :--- | :--- |
| `/agy:ask` | One-shot Q&A, conceptual questions, and quick second opinions. |
| `/agy:delegate` | Discrete, self-contained coding, refactoring, or debugging tasks. |
| `/agy:research` | Structured codebase and topic investigations, with optional background support. |
| `/agy:review` | Independent diff review across staged or unstaged git changes. |
| `/agy:image` | Prompt-based image and visual asset generation via Imagen. |
| `/agy:models` | Inspect live available models with curated use-case blurbs. |
| `/agy:help` | Command reference, invocation syntax, and flag documentation. |

## Model-selection strategy
Run `/agy:models` as the live source of truth for available models. Rule of thumb:
- **Fast lookups & simple edits**: Flash tier (`gemini-3.8-flash-high` / `-medium` / `-low`) for low-latency, low-cost tasks.
- **Hard multi-step & architecture**: `gemini-3.1-pro-high` or `claude-opus-4-6-thinking` for deep reasoning and complex debugging.
- **Everyday coding & review**: `claude-sonnet-4-6` for balanced speed, code quality, and diff evaluation.
- **Second opinions**: `gpt-oss-120b-medium` for open-weight diversity checks and alternative reasoning angles.

See `/agy:help` for full flag syntax and `/agy:models` for the live model list.
