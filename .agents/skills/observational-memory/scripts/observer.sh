#!/usr/bin/env bash
# =============================================================================
# Observational Memory — Observer
# =============================================================================
# Triggered by memoryFlush when a session transcript nears compaction.
# Reads recent messages, compresses into emoji-prioritized observations via
# MiniMax M2.5, and appends to the ## Observations section in MEMORY.md.
#
# Environment:
#   MINIMAX_API_KEY  — required
#   MEMORY_FILE      — override MEMORY.md path (default: /data/.clawdbot/MEMORY.md)
#   SESSIONS_BASE    — override sessions root  (default: /data/.clawdbot/agents)
#   MAX_MESSAGES     — messages to sample       (default: 25)
# =============================================================================
set -euo pipefail

MEMORY_FILE="${MEMORY_FILE:-/data/.clawdbot/MEMORY.md}"
SESSIONS_BASE="${SESSIONS_BASE:-/data/.clawdbot/agents}"
API_URL="https://api.minimax.io/anthropic/v1/messages"
MODEL="MiniMax-M2.5"
MAX_MESSAGES="${MAX_MESSAGES:-25}"
TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M")

# ── Resolve API key ──────────────────────────────────────────────────────────
# Try auth.json first (stored by OpenClaw onboarding), fall back to env var
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
  echo "observer: no MiniMax API key found (checked auth.json + env), skipping" >&2
  exit 0
fi

if [ ! -f "$MEMORY_FILE" ]; then
  echo "observer: MEMORY.md not found at $MEMORY_FILE, skipping" >&2
  exit 0
fi

# ── Extract recent messages from the most-recent active session ──────────────
TMPDIR_OBS=$(mktemp -d)
trap 'rm -rf "$TMPDIR_OBS"' EXIT

python3 - "$SESSIONS_BASE" "$MAX_MESSAGES" "$TMPDIR_OBS/messages.txt" << 'PYEOF'
import json, os, sys, glob

sessions_base = sys.argv[1]
max_messages  = int(sys.argv[2])
out_path      = sys.argv[3]

# Gather session files across all agent directories
patterns = [
    os.path.join(sessions_base, "*/sessions/*.jsonl"),
]
files = []
for pat in patterns:
    files.extend(glob.glob(pat))

# Filter out deleted / reset files
files = [f for f in files if ".deleted." not in f and ".reset." not in f]
if not files:
    sys.exit(0)

# Most-recently-modified first
files.sort(key=os.path.getmtime, reverse=True)
latest = files[0]

messages = []
with open(latest) as f:
    for line in f:
        try:
            entry = json.loads(line.strip())
            if entry.get("type") != "message":
                continue
            msg = entry.get("message", {})
            role = msg.get("role", "")
            if role not in ("user", "assistant"):
                continue
            content = msg.get("content")
            if not content:
                continue
            if isinstance(content, list):
                text = next(
                    (c.get("text", "") for c in content if c.get("type") == "text"), ""
                )
            else:
                text = str(content)
            # Skip slash commands and empty
            if not text or text.startswith("/"):
                continue
            # Truncate very long messages to save tokens
            if len(text) > 600:
                text = text[:600] + "…"
            messages.append(f"{role}: {text}")
        except Exception:
            pass

# Keep only the tail
messages = messages[-max_messages:]
if not messages:
    sys.exit(0)

with open(out_path, "w") as f:
    f.write("\n".join(messages))
PYEOF

if [ ! -s "$TMPDIR_OBS/messages.txt" ]; then
  echo "observer: no messages to observe"
  exit 0
fi

RECENT_MESSAGES=$(cat "$TMPDIR_OBS/messages.txt")

# ── Build prompt ─────────────────────────────────────────────────────────────
cat > "$TMPDIR_OBS/prompt.txt" << PROMPT_EOF
You are the Observational Memory observer for a personal AI agent. Analyze the
following recent conversation and extract key observations.

Format each observation as a single line with an emoji priority prefix:
🔴 Critical — decisions, commitments, important facts that MUST be remembered
🟡 Relevant — useful context, preferences, technical details worth keeping
🟢 Routine — general activity, minor details (may be dropped during reflection)

Rules:
- One line per observation, concise (~80-120 chars max)
- Focus on NEW information not already obvious from context
- Capture: decisions made, problems solved, user preferences, plans stated,
  errors encountered, tools/services mentioned, people/contacts referenced
- Skip: greetings, acknowledgements, raw tool output, code dumps, pleasantries
- Every line starts with the emoji, no numbering

Recent conversation:
---
${RECENT_MESSAGES}
---

Output ONLY the observation lines. No preamble, no summary.
PROMPT_EOF

# ── Call MiniMax API ─────────────────────────────────────────────────────────
python3 - "$TMPDIR_OBS/prompt.txt" "$TMPDIR_OBS/request.json" << 'PYEOF'
import json, sys

with open(sys.argv[1]) as f:
    prompt = f.read()

payload = {
    "model": "MiniMax-M2.5",
    "max_tokens": 2048,
    "messages": [{"role": "user", "content": prompt}],
}

with open(sys.argv[2], "w") as f:
    json.dump(payload, f)
PYEOF

HTTP_CODE=$(curl -s -o "$TMPDIR_OBS/response.json" -w "%{http_code}" \
  -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $MINIMAX_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -d @"$TMPDIR_OBS/request.json")

if [ "$HTTP_CODE" != "200" ]; then
  echo "observer: API returned HTTP $HTTP_CODE" >&2
  cat "$TMPDIR_OBS/response.json" >&2
  exit 1
fi

# ── Extract observations from response ───────────────────────────────────────
python3 - "$TMPDIR_OBS/response.json" "$TMPDIR_OBS/observations.txt" << 'PYEOF'
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

# Keep only lines that start with an emoji priority marker
lines = []
for line in text.splitlines():
    stripped = line.strip()
    if stripped and any(stripped.startswith(e) for e in ("🔴", "🟡", "🟢")):
        lines.append(stripped)

if not lines:
    # Fallback: keep all non-empty lines
    lines = [l.strip() for l in text.splitlines() if l.strip()]

with open(sys.argv[2], "w") as f:
    f.write("\n".join(lines))
PYEOF

if [ ! -s "$TMPDIR_OBS/observations.txt" ]; then
  echo "observer: LLM returned no usable observations" >&2
  exit 1
fi

OBSERVATIONS=$(cat "$TMPDIR_OBS/observations.txt")
OBS_COUNT=$(echo "$OBSERVATIONS" | wc -l | tr -d ' ')

# ── Append to MEMORY.md ─────────────────────────────────────────────────────
python3 - "$MEMORY_FILE" "$TMPDIR_OBS/observations.txt" "$TIMESTAMP" << 'PYEOF'
import sys

memory_path = sys.argv[1]
obs_path    = sys.argv[2]
timestamp   = sys.argv[3]

with open(memory_path, "r") as f:
    content = f.read()

with open(obs_path, "r") as f:
    observations = f.read().strip()

# ── Hard cap: prevent unbounded growth if reflector is failing ────────────
HARD_CAP = 30000
TRUNCATION_THRESHOLD = 20000

obs_header = "## Observations"
notes_header_check = "## Notes"
obs_start = content.find(obs_header)
if obs_start != -1:
    obs_end_check = content.find(notes_header_check, obs_start)
    if obs_end_check == -1:
        obs_end_check = len(content)
    obs_size = obs_end_check - obs_start

    if obs_size > HARD_CAP:
        print(f"observer: REFUSING to append — observations at {obs_size} chars (hard cap: {HARD_CAP})", file=sys.stderr)
        sys.exit(1)

    if obs_size > TRUNCATION_THRESHOLD:
        # Emergency truncation: drop all green (routine) lines to reclaim space
        obs_section = content[obs_start:obs_end_check]
        lines = obs_section.split("\n")
        kept = [l for l in lines if not l.strip().startswith("\U0001f7e2")]
        trimmed = "\n".join(kept)
        content = content[:obs_start] + trimmed + content[obs_end_check:]
        print(f"observer: emergency truncation — dropped routine observations ({obs_size} -> ~{len(trimmed)} chars)", file=sys.stderr)

# Prepend timestamp to the observation block
block = f"\n### [{timestamp}]\n{observations}\n"

# Strategy: insert before ## Notes (or at end of ## Observations section)
marker = "<!-- Managed by Observational Memory skill. Do not edit this section manually. -->"
notes_header = "## Notes"

if marker in content:
    # Insert after the marker, before ## Notes
    marker_end = content.index(marker) + len(marker)
    # Find where to insert — before ## Notes if it exists
    if notes_header in content[marker_end:]:
        notes_pos = content.index(notes_header, marker_end)
        new_content = (
            content[:notes_pos].rstrip()
            + "\n"
            + block
            + "\n"
            + content[notes_pos:]
        )
    else:
        new_content = (
            content[:marker_end]
            + block
            + content[marker_end:]
        )
elif "## Observations" in content:
    obs_pos = content.index("## Observations")
    obs_end = obs_pos + len("## Observations")
    nl = content.index("\n", obs_end)
    if notes_header in content[nl:]:
        notes_pos = content.index(notes_header, nl)
        new_content = (
            content[:notes_pos].rstrip()
            + "\n"
            + block
            + "\n"
            + content[notes_pos:]
        )
    else:
        new_content = content[:nl+1] + block + content[nl+1:]
else:
    new_content = content.rstrip() + "\n\n## Observations\n" + block + "\n"

with open(memory_path, "w") as f:
    f.write(new_content)
PYEOF

echo "observer: appended $OBS_COUNT observations to MEMORY.md [$TIMESTAMP]"
