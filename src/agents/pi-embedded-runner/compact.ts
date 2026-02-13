      applySystemPromptOverrideToSession(session, systemPromptOverride());

      // Reload session from disk to ensure latest messages are included
      // Fixes #15171: Compaction drops tail-end messages before compaction fires
      // This ensures that when session.compact() reads session.messages,
      // all messages including most recent ones that were just persisted are included

      try {
        // Reload session from disk to ensure latest messages are included
        // Fixes #15171: Compaction drops tail-end messages before compaction fires
        const latestEntries = sessionManager.getEntries();
        const sessionContext = session.agent.buildSessionContext(latestEntries);
        const prior = await sanitizeSessionHistory({
          messages: sessionContext.messages,