import { describe, it, expect } from 'vitest';

// Pure function versions of the shuffle/queue logic (extracted for testability)

function shuffleArray(array) {
  const a = [...array];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

function getNextIndex(queue, queueIndex, playMode, shuffledQueue) {
  if (!queue.length) return -1;

  if (playMode === 'repeat-one') return queueIndex;

  if (playMode === 'shuffle') {
    const shuffled = shuffledQueue.length > 0 ? shuffledQueue : queue;
    const currentShuffledIdx = shuffled.findIndex(t => t.id === queue[queueIndex]?.id);
    if (currentShuffledIdx < shuffled.length - 1) {
      return queue.findIndex(t => t.id === shuffled[currentShuffledIdx + 1].id);
    }
    return queue.findIndex(t => t.id === shuffled[0].id);
  }

  // sequential
  return queueIndex < queue.length - 1 ? queueIndex + 1 : 0;
}

function getPrevIndex(queue, queueIndex, currentTime, playMode, shuffledQueue) {
  if (!queue.length) return -1;

  if (currentTime > 3) return queueIndex; // restart current track

  if (playMode === 'shuffle') {
    const shuffled = shuffledQueue.length > 0 ? shuffledQueue : queue;
    const currentShuffledIdx = shuffled.findIndex(t => t.id === queue[queueIndex]?.id);
    if (currentShuffledIdx > 0) {
      return queue.findIndex(t => t.id === shuffled[currentShuffledIdx - 1].id);
    }
    return queue.findIndex(t => t.id === shuffled[shuffled.length - 1].id);
  }

  return queueIndex > 0 ? queueIndex - 1 : queue.length - 1;
}

const tracks = [
  { id: 1, title: 'A' }, { id: 2, title: 'B' },
  { id: 3, title: 'C' }, { id: 4, title: 'D' },
];

describe('Sequential mode', () => {
  it('moves to next track', () => {
    expect(getNextIndex(tracks, 0, 'sequential', [])).toBe(1);
    expect(getNextIndex(tracks, 2, 'sequential', [])).toBe(3);
  });

  it('wraps to first track after last', () => {
    expect(getNextIndex(tracks, 3, 'sequential', [])).toBe(0);
  });

  it('goes to previous track', () => {
    expect(getPrevIndex(tracks, 2, 1, 'sequential', [])).toBe(1);
  });

  it('wraps to last track before first', () => {
    expect(getPrevIndex(tracks, 0, 1, 'sequential', [])).toBe(3);
  });

  it('restarts current track if >3s elapsed', () => {
    expect(getPrevIndex(tracks, 1, 4, 'sequential', [])).toBe(1);
  });
});

describe('Repeat-one mode', () => {
  it('stays on the same track', () => {
    expect(getNextIndex(tracks, 1, 'repeat-one', [])).toBe(1);
  });
});

describe('Shuffle mode', () => {
  it('returns a valid index within queue bounds', () => {
    const shuffled = shuffleArray(tracks);
    const nextIdx = getNextIndex(tracks, 0, 'shuffle', shuffled);
    expect(nextIdx).toBeGreaterThanOrEqual(0);
    expect(nextIdx).toBeLessThan(tracks.length);
  });

  it('prev returns valid index', () => {
    const shuffled = shuffleArray(tracks);
    const prevIdx = getPrevIndex(tracks, 1, 1, 'shuffle', shuffled);
    expect(prevIdx).toBeGreaterThanOrEqual(0);
    expect(prevIdx).toBeLessThan(tracks.length);
  });

  it('handles empty queue gracefully', () => {
    expect(getNextIndex([], 0, 'sequential', [])).toBe(-1);
    expect(getPrevIndex([], 0, 1, 'sequential', [])).toBe(-1);
  });
});
