---
name: observational-memory
description: "Automatic observation capture and reflection for long-term agent memory"
homepage: https://gist.github.com/DevvGwardo/725a5f1467ef898a04a95bd126222d2a
metadata:
  openclaw:
    emoji: "🧠"
    install:
      - id: manual
        kind: manual
        label: "Deployed to .agents/skills/observational-memory"
---

# Observational Memory (OM)

Captures and maintains agent observations automatically, without requiring
explicit memory queries. Adapted from the Mastra pattern for OpenClaw.

## Components

### Observer (`scripts/observer.sh`)

Triggered by the `memoryFlush` hook when a session transcript nears the
compaction threshold (~6K tokens). The observer:

1. Finds the most-recently-modified active session transcript
2. Extracts the last ~25 user/assistant messages
3. Calls MiniMax M2.5 to compress them into emoji-prioritized observations
4. Appends the observations to `## Observations` in `MEMORY.md`

Runs **before** transcript compaction, preserving critical details that would
otherwise be lost to lossy summarization.

### Reflector (`scripts/reflector.sh`)

Runs periodically (every 4 hours via cron). When the `## Observations` section
exceeds 10K characters:

1. Reads the accumulated observations
2. Calls MiniMax M2.5 to condense them:
   - 🔴 Critical — preserved verbatim
   - 🟡 Relevant — merged where possible
   - 🟢 Routine — dropped unless still relevant
3. Rewrites the observations section with the condensed version
4. Creates a backup of the previous MEMORY.md

## Priority Emoji Guide

| Emoji | Level    | Meaning                                        | Lifecycle          |
| ----- | -------- | ---------------------------------------------- | ------------------ |
| 🔴    | Critical | Decisions, commitments, must-remember facts    | Always preserved   |
| 🟡    | Relevant | Useful context, preferences, technical details | Merged on reflect  |
| 🟢    | Routine  | General activity, minor details                | Dropped on reflect |

## Configuration

In `openclaw.json`:

```json
{
  "agents": {
    "defaults": {
      "compaction": {
        "memoryFlush": {
          "enabled": true,
          "softThresholdTokens": 6000,
          "prompt": "Run the observer now: bash /data/workspace/.agents/skills/observational-memory/scripts/observer.sh\nReply with NO_REPLY after completion.",
          "systemPrompt": "Session nearing compaction. Run the Observational Memory observer..."
        }
      }
    }
  },
  "skills": {
    "entries": {
      "observational-memory": {
        "enabled": true,
        "config": {
          "observationThresholdTokens": 30000,
          "reflectionThresholdTokens": 40000,
          "observerModel": "minimax/MiniMax-M2.5"
        }
      }
    }
  }
}
```

## Environment Variables

| Variable               | Required | Default                     | Description                     |
| ---------------------- | -------- | --------------------------- | ------------------------------- |
| `MINIMAX_API_KEY`      | Yes      | —                           | MiniMax API key                 |
| `MEMORY_FILE`          | No       | `/data/.clawdbot/MEMORY.md` | Path to MEMORY.md               |
| `SESSIONS_BASE`        | No       | `/data/.clawdbot/agents`    | Root of agent session dirs      |
| `MAX_MESSAGES`         | No       | `25`                        | Messages to sample per run      |
| `REFLECTION_THRESHOLD` | No       | `10000`                     | Chars before triggering reflect |

## Storage

- `MEMORY.md` lives on the persistent volume at `/data/.clawdbot/MEMORY.md`
- Auto-injected into agent context on every session via AGENTS.md instructions
- Observations accumulate between reflector runs with timestamped headers
- Backups created before each reflection: `MEMORY.md.bak.YYYYMMDD-HHMMSS`
