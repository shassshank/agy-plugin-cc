---
description: Delegate a thorough research investigation to the agy:runner subagent
argument-hint: "[--background] [--model <model>] <topic or question>"
allowed-tools: Agent
---

Hand a deep-research task to the `agy:runner` subagent
(`subagent_type: "agy:runner"`).

Wrap the user's topic in a research-oriented preamble so `agy` treats it as
a structured investigation rather than a quick Q&A.

Raw user request:
$ARGUMENTS

## How to forward

Build the research prompt for the subagent as:

```
[--model <model>] Conduct a thorough research investigation on the following topic. Look up
authoritative sources, summarize the current state of knowledge, surface
disagreements or open questions, and structure the response with clear
sections (Background, Key findings, Caveats, Sources).

Topic: <topic text here>
```

(Strip only the `--background` flag. If `--model <name>` is present in the
request, preserve `--model <name>` at the very front of the prompt text handed
to `agy:runner` so runner can extract and forward it. Strip `--model` from the
`<topic text here>` section.)

Then invoke the `agy:runner` subagent with that prompt as
`subagent_type: "agy:runner"`.

## Routing rules

- If the request contains `--background`, launch the subagent with
  `run_in_background: true`. Research is often long-running — prefer
  background unless the user explicitly asked for foreground. Strip
  `--background` from the forwarded prompt text.
- Do NOT strip `--model <name>`. Preserve `--model <name>` at the front of the
  prompt text handed to the `agy:runner` subagent so runner can forward it to
  the wrapper script. If no model is given, omit `--model` entirely and let
  `agy` use its own default (a reasoning-strong model like `gemini-3.1-pro-high`
  or `claude-opus-4-6-thinking` works well for research).

Models can be specified by exact id (e.g. `claude-opus-4-6-thinking`,
`gemini-3.1-pro-high`) or canonical display label (e.g.
`"Claude Opus 4.6 (Thinking)"`). Run `/agy:models` to see available models and
recommendations.

## Response style

Return the subagent's output verbatim — no extra commentary before or
after.

If the user did not supply a topic, ask what they want researched.
