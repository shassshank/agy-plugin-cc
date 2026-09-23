#!/usr/bin/env python3
"""Annotate the live `agy models` list with recommendations.

Reads tab-separated "<model-id>\t<display-label>" lines on stdin (the
raw output of `agy models`) and prints a table with a curated-looking
"recommended use" column. Nothing here hardcodes a specific model id or
version number: descriptions are inferred from each id's naming pattern
(family / tier / version) and from comparing versions that are actually
present in the live list, so a new model release or a retired one is
picked up automatically the next time `agy models` runs.
"""
import re
import sys

TIER_WORDS = {"low", "medium", "high", "thinking"}


def parse(model_id):
    """Split a model id into (family, version, tier).

    family: the non-version, non-tier tokens, e.g. "gemini-flash".
    version: a tuple of ints for ordering, or None if none was found.
    tier: one of TIER_WORDS, or None.
    """
    tokens = model_id.split("-")

    tier = None
    if tokens and tokens[-1] in TIER_WORDS:
        tier = tokens.pop()

    # A dotted version token, e.g. "3.8" -> one token consumed.
    version = None
    version_idx = None
    version_token_count = 0
    for i, tok in enumerate(tokens):
        if re.fullmatch(r"\d+\.\d+", tok):
            version = tuple(int(p) for p in tok.split("."))
            version_idx = i
            version_token_count = 1
            break

    if version is None:
        # A run of trailing bare-digit tokens, e.g. "4", "6" -> (4, 6),
        # consuming one token per digit group.
        digit_run = []
        i = len(tokens) - 1
        while i >= 0 and tokens[i].isdigit():
            digit_run.append(int(tokens[i]))
            i += -1
        if digit_run:
            digit_run.reverse()
            version = tuple(digit_run)
            version_idx = i + 1
            version_token_count = len(digit_run)

    family_tokens = list(tokens)
    if version_idx is not None:
        del family_tokens[version_idx:version_idx + version_token_count]
    family = "-".join(family_tokens)

    return family, version, tier


def family_label(family):
    parts = family.split("-")
    out = []
    for p in parts:
        if p.lower() in ("gpt", "oss"):
            out.append(p.upper())
        else:
            out.append(p.capitalize())
    return " ".join(out)


def build_blurb(family, tier, is_latest, latest_id):
    label = family_label(family)

    if not is_latest:
        return f"Older-generation build of this tier. Prefer {latest_id} unless you need this exact version."

    fam_lower = family.lower()
    reasoning_family = "pro" in fam_lower or "opus" in fam_lower
    oss_family = "oss" in fam_lower

    oss_prefix = "Open-weight model. " if oss_family else ""

    if tier == "low":
        if reasoning_family:
            return "Deeper reasoning than the fast tier at lower effort. Good for moderately complex tasks."
        return f"{oss_prefix}Fastest, cheapest tier in the {label} line. Good for simple lookups, quick edits, low-stakes work."
    if tier == "medium":
        return f"{oss_prefix}Balanced speed and quality in the {label} line. Good default for everyday tasks."
    if tier == "high":
        if reasoning_family:
            return "Strongest reasoning tier here. Best for hard, multi-step problems, architecture decisions, deep research."
        return f"{oss_prefix}Strongest tier in the {label} line. Good default for most agentic coding tasks."
    if tier == "thinking":
        return f"Extended-thinking mode of the {label} line. Best for the hardest debugging, design, and coding tasks."

    if oss_family:
        return "Open-weight model. Useful for a second opinion / diversity check, or open-source-friendly workflows."
    return f"General-purpose model in the {label} line. See `agy models` / Antigravity's docs for details."


def main():
    rows = []
    for line in sys.stdin:
        line = line.rstrip("\n")
        if not line.strip():
            continue
        parts = line.split("\t")
        if len(parts) < 2:
            continue
        model_id, label = parts[0], parts[1]
        rows.append((model_id, label))

    parsed = {model_id: parse(model_id) for model_id, _ in rows}

    latest_in_group = {}
    for model_id, (family, version, tier) in parsed.items():
        key = (family, tier)
        if version is None:
            latest_in_group.setdefault(key, model_id)
            continue
        current = latest_in_group.get(key)
        if current is None or parsed[current][1] is None or version > parsed[current][1]:
            latest_in_group[key] = model_id

    print(f"{'MODEL ID':<26} {'DISPLAY LABEL':<30} RECOMMENDED USE")
    print(f"{'--------':<26} {'-------------':<30} ---------------")
    for model_id, label in rows:
        family, version, tier = parsed[model_id]
        key = (family, tier)
        latest_id = latest_in_group[key]
        is_latest = latest_id == model_id
        blurb = build_blurb(family, tier, is_latest, latest_id)
        print(f"{model_id:<26} {label:<30} {blurb}")


if __name__ == "__main__":
    main()
