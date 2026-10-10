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

// Build the play order for shuffle mode with `currentTrackId` first and every
// other track exactly once behind it. Keeping the *current* track at the head
// (rather than wherever the shuffle put it) is what makes one pass through the
// order cover the whole queue exactly once: previously the head was swapped
// with the clicked track, which left the old head inside the tail and made it
// play twice in a cycle while another track never played at all.
export function buildShuffleOrder(trackList, currentTrackId) {
  const rest = trackList.filter(t => t.id !== currentTrackId);
  const first = trackList.find(t => t.id === currentTrackId);
  const shuffledRest = shuffleArray(rest);
  return first ? [first, ...shuffledRest] : shuffledRest;
}

// nextIdx: index into `queue` of the track to play; -1 when the queue can't
// be navigated (empty queue, or the shuffled order no longer matches the
// queue — the caller should skip, not play queue[-1]).
// reshuffled: kept for the caller's dispatch; always null now that the order
// is seeded on mode change / track click instead of being re-rolled mid-cycle.
export function computeNextIndex({ queue, queueIndex, playMode, shuffledQueue }) {
  if (!queue.length) return { nextIdx: -1, reshuffled: null };

  if (playMode === 'shuffle') {
    const shuffled = shuffledQueue.length > 0 ? shuffledQueue : queue;
    const currentShuffledIdx = shuffled.findIndex(t => t.id === queue[queueIndex]?.id);
    // -1 means the stored order no longer describes this queue (the queue was
    // replaced). Advancing from -1 used to land on shuffled[1] and silently
    // play the wrong track; bail out and let the caller keep playing instead.
    if (currentShuffledIdx < 0) return { nextIdx: -1, reshuffled: null };
    // Wrap to the head of the same order instead of re-rolling: a re-roll mid
    // transition both repeated the track just played and skipped others, and
    // one pass now covers the queue exactly once.
    const nextShuffledIdx = (currentShuffledIdx + 1) % shuffled.length;
    return {
      nextIdx: queue.findIndex(t => t.id === shuffled[nextShuffledIdx].id),
      reshuffled: null,
    };
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
    if (currentShuffledIdx < 0) return { prevIdx: -1 };
    if (currentShuffledIdx > 0) {
      return { prevIdx: queue.findIndex(t => t.id === shuffled[currentShuffledIdx - 1].id) };
    }
    return { prevIdx: queue.findIndex(t => t.id === shuffled[shuffled.length - 1].id) };
  }

  return { prevIdx: queueIndex > 0 ? queueIndex - 1 : queue.length - 1 };
}
