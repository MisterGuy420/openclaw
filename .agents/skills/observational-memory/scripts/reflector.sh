#!/usr/bin/env bash
# =============================================================================
# Observational Memory — Reflector
# =============================================================================
# Runs periodically (every 4 hours via cron). When the ## Observations section
# in MEMORY.md exceeds a character threshold, condenses observations via LLM:
#   🔴 Critical  — always preserved verbatim
#   🟡 Relevant  — merged / summarized where possible
#   🟢 Routine   — dropped unless still relevant
#
# Environment:
#   MINIMAX_API_KEY          — required
#   MEMORY_FILE              — override path (default: /data/.clawdbot/MEMORY.md)
#   REFLECTION_THRESHOLD     — char threshold (default: 10000)
# =============================================================================
set -euo pipefail

MEMORY_FILE="${MEMORY_FILE:-/data/.clawdbot/MEMORY.md}"
API_URL="https://api.minimax.io/anthropic/v1/messages"
MODEL="MiniMax-M2.5"
REFLECTION_THRESHOLD="${REFLECTION_THRESHOLD:-10000}"
TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M")

# ── Resolve API key ──────────────────────────────────────────────────────────
AUTH_JSON="/data/.clawdbot/agents/main/agent/auth.json"
if [ -f "$AUTH_JSON" ]; then
  RESOLVED_KEY=$(python3 -c "
import json
with open('$AUTH_JSON') as f:
    data = json.load(f)
print(data.get('minimax', {}).get('key', ''))
" 2>/dev/null)
  if [ -n "$RESOLVED_KEY" ]; then
    MINIMAX_API_KEY="$RESOLVED_KEY"
  fi
fi

if [ -z "${MINIMAX_API_KEY:-}" ]; then
  echo "reflector: no MiniMax API key found (checked auth.json + env), skipping" >&2
  exit 0
fi

if [ ! -f "$MEMORY_FILE" ]; then
  echo "reflector: MEMORY.md not found, skipping" >&2
  exit 0
fi

# ── Extract observations section ─────────────────────────────────────────────
TMPDIR_REF=$(mktemp -d)
trap 'rm -rf "$TMPDIR_REF"' EXIT

python3 - "$MEMORY_FILE" "$TMPDIR_REF/observations.txt" "$TMPDIR_REF/before.txt" "$TMPDIR_REF/after.txt" << 'PYEOF'
import sys

memory_path = sys.argv[1]
obs_out     = sys.argv[2]
before_out  = sys.argv[3]
after_out   = sys.argv[4]

with open(memory_path, "r") as f:
    content = f.read()

# Find ## Observations boundaries
obs_start = content.find("## Observations")
if obs_start == -1:
    sys.exit(0)

# Find the next ## header after Observations (typically ## Notes)
rest = content[obs_start + len("## Observations"):]
next_header = -1
for i, line in enumerate(rest.split("\n")):
    if line.startswith("## ") and i > 0:
        # Calculate position in `rest`
        pos = sum(len(l) + 1 for l in rest.split("\n")[:i])
        next_header = obs_start + len("## Observations") + pos
        break

if next_header == -1:
    # No next header — observations go to end of file
    before = content[:obs_start]
    obs_section = content[obs_start:]
    after = ""
else:
    before = content[:obs_start]
    obs_section = content[obs_start:next_header]
    after = content[next_header:]

# Strip the header and marker from observations, keep only the content
lines = obs_section.split("\n")
obs_lines = []
skip_header = True
for line in lines:
    if skip_header and (line.startswith("## Observations") or line.startswith("<!--") or not line.strip()):
        if line.startswith("<!--"):
            skip_header = False
        continue
    skip_header = False
    obs_lines.append(line)

obs_text = "\n".join(obs_lines).strip()

with open(obs_out, "w") as f:
    f.write(obs_text)
with open(before_out, "w") as f:
    f.write(before)
with open(after_out, "w") as f:
    f.write(after)
PYEOF

if [ ! -s "$TMPDIR_REF/observations.txt" ]; then
  echo "reflector: no observations to reflect on"
  exit 0
fi

OBS_SIZE=$(wc -c < "$TMPDIR_REF/observations.txt" | tr -d ' ')
echo "reflector: observations section is ${OBS_SIZE} chars (threshold: ${REFLECTION_THRESHOLD})"

if [ "$OBS_SIZE" -lt "$REFLECTION_THRESHOLD" ]; then
  echo "reflector: below threshold, no condensation needed"
  exit 0
fi

# ── Build condensation prompt ────────────────────────────────────────────────
CURRENT_OBS=$(cat "$TMPDIR_REF/observations.txt")

cat > "$TMPDIR_REF/prompt.txt" << PROMPT_EOF
You are the Observational Memory reflector. Your job is to condense accumulated
observations while preserving critical information.

## Priority Rules

🔴 Critical — ALWAYS preserve verbatim. These are decisions, commitments,
   important facts. Never drop or summarize these.

🟡 Relevant — Merge related observations into combined lines where possible.
   Keep the substance, reduce redundancy. Preserve technical details.

🟢 Routine — Drop unless still actively relevant. If a routine observation
   provides useful context for a 🔴 or 🟡 item, fold it in.

## Format

Output condensed observations in the same format:
- Each line starts with 🔴, 🟡, or 🟢
- Group by topic when it helps readability (use ### headers for groups)
- Preserve timestamps on 🔴 items
- For merged 🟡 items, use the most recent timestamp

## Current Observations (${OBS_SIZE} chars → condense to ~40-60%)

${CURRENT_OBS}

## Output

Write the condensed observations. Preserve all 🔴 items. Merge 🟡 items.
Drop most 🟢 items. No preamble — observations only.
PROMPT_EOF

# ── Call MiniMax API ─────────────────────────────────────────────────────────
python3 - "$TMPDIR_REF/prompt.txt" "$TMPDIR_REF/request.json" << 'PYEOF'
import json, sys

with open(sys.argv[1]) as f:
    prompt = f.read()

payload = {
    "model": "MiniMax-M2.5",
    "max_tokens": 4096,
    "messages": [{"role": "user", "content": prompt}],
}

with open(sys.argv[2], "w") as f:
    json.dump(payload, f)
PYEOF

HTTP_CODE=$(curl -s -o "$TMPDIR_REF/response.json" -w "%{http_code}" \
  -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $MINIMAX_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -d @"$TMPDIR_REF/request.json")

if [ "$HTTP_CODE" != "200" ]; then
  echo "reflector: API returned HTTP $HTTP_CODE" >&2
  cat "$TMPDIR_REF/response.json" >&2
  exit 1
fi

# ── Extract condensed observations ───────────────────────────────────────────
python3 - "$TMPDIR_REF/response.json" "$TMPDIR_REF/condensed.txt" << 'PYEOF'
import json, sys

with open(sys.argv[1]) as f:
    resp = json.load(f)

text_parts = []
for block in resp.get("content", []):
    if block.get("type") == "text":
        text_parts.append(block["text"])

text = "\n".join(text_parts).strip()
if not text:
    sys.exit(1)

with open(sys.argv[2], "w") as f:
    f.write(text)
PYEOF

if [ ! -s "$TMPDIR_REF/condensed.txt" ]; then
  echo "reflector: LLM returned empty condensation" >&2
  exit 1
fi

NEW_SIZE=$(wc -c < "$TMPDIR_REF/condensed.txt" | tr -d ' ')
echo "reflector: condensed ${OBS_SIZE} → ${NEW_SIZE} chars"

# ── Rewrite MEMORY.md ───────────────────────────────────────────────────────
CONDENSED=$(cat "$TMPDIR_REF/condensed.txt")
BEFORE=$(cat "$TMPDIR_REF/before.txt")
AFTER=$(cat "$TMPDIR_REF/after.txt")

# Backup current MEMORY.md (keep only 5 most recent)
cp "$MEMORY_FILE" "${MEMORY_FILE}.bak.$(date -u +%Y%m%d-%H%M%S)"
ls -1t "${MEMORY_FILE}.bak."* 2>/dev/null | awk 'NR>5' | xargs rm -f 2>/dev/null || true

cat > "$MEMORY_FILE" << MEMEOF
${BEFORE}## Observations

<!-- Managed by Observational Memory skill. Do not edit this section manually. -->

### [Reflected ${TIMESTAMP}]
${CONDENSED}

${AFTER}
MEMEOF

echo "reflector: MEMORY.md rewritten with condensed observations"
