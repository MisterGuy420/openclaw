      applySystemPromptOverrideToSession(session, systemPromptOverride());

      // Flush pending tool results to disk before compaction to preserve recent messages
      // Fixes #15171: Compaction drops tail-end messages before compaction fires
      // This ensures that when session.compact() reads session.messages,
      // all messages including those sent right before compaction triggered are included
      // in the summary.

      const prior = await sanitizeSessionHistory({
          messages: session.messages,