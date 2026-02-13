const originalCompact = \`const result = await session.compact(params.customInstructions);
        // Calculate tokens after compaction by summing token estimates for remaining messages
        let tokensAfter: number | undefined;
        try {
          tokensAfter = 0;
          for (const message of session.messages) {
            tokensAfter += estimateTokens(message);
          }
          // Sanity check: tokensAfter should be less than tokensBefore
          if (tokensAfter > result.tokensBefore) {
            tokensAfter = undefined; // Don't trust the estimate
          }
        } catch {
          // If estimation fails, leave tokensAfter undefined
          tokensAfter = undefined;
        }
\`;

const newCompact = \`const result = await session.compact(params.customInstructions);
        // Calculate tokens after compaction by summing token estimates for remaining messages
        let tokensAfter: number | undefined;
        try {
          tokensAfter = 0;
          for (const message of session.messages) {
            tokensAfter += estimateTokens(message);
          }
          // Sanity check: tokensAfter should be less than tokensBefore
          if (tokensAfter > result.tokensBefore) {
            tokensAfter = undefined; // Don't trust the estimate
          }
        } catch {
          // If estimation fails, leave tokensAfter undefined
          tokensAfter = undefined;
        }

        // Flush pending tool results to disk before compaction to preserve recent messages
        // Fixes #15171: Compaction drops tail-end messages before compaction fires
        sessionManager.flushPendingToolResults?.();

        // Then notify incrementCompactionCount with updated token counts
        await incrementCompactionCount({
          sessionEntry: params.sessionEntry,
          sessionStore: params.sessionStore,
          sessionKey: params.sessionKey,
          storePath: params.storePath,
          tokensAfter: finalTokensAfter,
        });
\`;

const compactFileContent = originalCompact.replace(originalCompact, newCompact);

const compactFixContent = compactFileContent.replace(
  /const result = await session.compact\\(params.customInstructions\\);/,
  /const result = await session.compact\\(params.customInstructions\\);\\n        sessionManager.flushPendingToolResults\\?.\\(\\);/
);

if (compactFixContent === compactFileContent) {
  console.error("Fix failed - content matches");
  process.exit(1);
}

console.log(compactFixContent);
