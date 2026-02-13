}

export async function incrementCompactionCount(params: {
  sessionEntry?: SessionEntry;
  sessionStore?: Record<string, SessionEntry>;
  sessionKey?: string;
  storePath?: string;
  now?: number;
  /** Token count after compaction - if provided, updates session token counts */
  tokensAfter?: number;
}): Promise<number | undefined> {
  const {
    sessionEntry,
    sessionStore,
    sessionKey,
    storePath,
    now = Date.now(),
    tokensAfter,
  } = params;
  if (!sessionStore || !sessionKey) {
    return undefined;
  }
  const entry = sessionStore[sessionKey] ?? sessionEntry;
  if (!entry) {
    return undefined;
  }
  const nextCount = (entry.compactionCount ?? 0) + 1;
  // Build update payload with compaction count and optionally updated token counts
  const updates: Partial<SessionEntry> = {
    compactionCount: nextCount,
    updatedAt: now,
  };
  // If tokensAfter is provided, update to cached token counts to reflect post-compaction state
  if (tokensAfter != null && tokensAfter > 0) {
    updates.totalTokens = tokensAfter;
    // Clear input/output breakdown since we only have to total estimate after compaction
    updates.inputTokens = undefined;
    updates.outputTokens = undefined;
  }
  // Fix for #15101: When estimation fails, reset totalTokens to 0 to prevent stale values
  // This prevents stale pre-compaction values from triggering false memory flushes
  if (tokensAfter === undefined) {
    updates.totalTokens = 0;
    updates.inputTokens = 0;
    updates.outputTokens = 0;
  }
  sessionStore[sessionKey] = {
    ...entry,
    ...updates,
  };
  if (storePath) {
    await updateSessionStore(storePath, (store) => {
      store[sessionKey] = {
        ...store[sessionKey],
        ...updates,
      };
    });
  }
  return nextCount;
}
