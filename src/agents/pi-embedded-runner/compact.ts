// Reload session from disk to ensure latest messages are included
// Fixes #15171: Compaction drops tail-end messages before compaction fires
// This ensures that when session.compact() reads session.messages,
// all messages including most recent ones that were just persisted are included

const latestEntries = sessionManager.getEntries();
const sessionContext = session.agent.buildSessionContext(latestEntries);
const prior = await sanitizeSessionHistory({
  messages: sessionContext.messages,
  modelApi: model.api,
  modelId,
  provider,
  sessionManager,
  sessionId: params.sessionId,
  policy: transcriptPolicy,
});
