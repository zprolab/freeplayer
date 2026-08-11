// Pure queue-navigation helpers shared by usePlayback (and its tests).
// Extracted from the hook so the next/prev index logic is testable as the
// real code path instead of a drift-prone copy. Semantics match the
// original inline logic exactly, including the shuffle wrap-around which
// re-rolls the queue and hands the fresh order back for the caller to
// persist (SET_SHUFFLED_QUEUE).

export function shuffleArray(array) {
  const a = [...array];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

// nextIdx: index into `queue` of the track to play; -1 when the queue can't
// be navigated (empty queue, or the shuffled order no longer matches the
// queue — the caller should skip, not play queue[-1]).
// reshuffled: fresh shuffle order on wrap-around, null otherwise.
export function computeNextIndex({ queue, queueIndex, playMode, shuffledQueue }) {
  if (!queue.length) return { nextIdx: -1, reshuffled: null };

  if (playMode === 'shuffle') {
    const shuffled = shuffledQueue.length > 0 ? shuffledQueue : queue;
    const currentShuffledIdx = shuffled.findIndex(t => t.id === queue[queueIndex]?.id);
    if (currentShuffledIdx < shuffled.length - 1) {
      return {
        nextIdx: queue.findIndex(t => t.id === shuffled[currentShuffledIdx + 1].id),
        reshuffled: null,
      };
    }
    const reshuffled = shuffleArray(queue);
    return { nextIdx: queue.findIndex(t => t.id === reshuffled[0].id), reshuffled };
  }

  return { nextIdx: queueIndex < queue.length - 1 ? queueIndex + 1 : 0, reshuffled: null };
}

// prevIdx: index into `queue`; equals queueIndex when the current track
// should be restarted instead (more than 3s elapsed).
export function computePrevIndex({ queue, queueIndex, currentTime, playMode, shuffledQueue }) {
  if (!queue.length) return { prevIdx: -1 };

  if (currentTime > 3) return { prevIdx: queueIndex };

  if (playMode === 'shuffle') {
    const shuffled = shuffledQueue.length > 0 ? shuffledQueue : queue;
    const currentShuffledIdx = shuffled.findIndex(t => t.id === queue[queueIndex]?.id);
    if (currentShuffledIdx > 0) {
      return { prevIdx: queue.findIndex(t => t.id === shuffled[currentShuffledIdx - 1].id) };
    }
    return { prevIdx: queue.findIndex(t => t.id === shuffled[shuffled.length - 1].id) };
  }

  return { prevIdx: queueIndex > 0 ? queueIndex - 1 : queue.length - 1 };
}
