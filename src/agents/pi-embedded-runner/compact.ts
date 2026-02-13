const originalCompact = `const result = await session.compact(params.customInstructions);
        // Flush pending tool results to disk before compaction to preserve recent messages
        // Fixes #15171: Compaction drops tail-end messages before compaction fires
        sessionManager.flushPendingToolResults?.();/a

        // Then notify incrementCompactionCount with updated token counts
        const result = await session.compact(params.customInstructions);/g
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
        return {
          ok: true,
          compacted: true,
          result: {
            summary: result.summary,
            firstKeptEntryId: result.firstKeptEntryId,
            tokensBefore: result.tokensBefore,
            tokensAfter,
            details: result.details,
          },
        };
      } finally {
        sessionManager.flushPendingToolResults?.();
        session.dispose();
      }
    } finally {
      restoreSkillEnv?.();
      process.chdir(prevCwd);
    }
  `;

const newCompact = `const result = await session.compact(params.customInstructions);
        // Flush pending tool results to disk before compaction to preserve recent messages
        // Fixes #15171: Compaction drops tail-end messages before compaction fires
        sessionManager.flushPendingToolResults?.();/a

        // Then notify incrementCompactionCount with updated token counts
        const result = await session.compact(params.customInstructions);/g
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
        const result = await session.compact(params.customInstructions);
        // Flush pending tool results to disk before compaction to preserve recent messages
        // Fixes #15171: Compaction drops tail-end messages before compaction fires
        sessionManager.flushPendingToolResults?.();/a

        // Then notify incrementCompactionCount with updated token counts
        const result = await session.compact(params.customInstructions);/g
