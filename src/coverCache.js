// Simple LRU cache for cover art base64 data URLs
const MAX_SIZE = 50;
const cache = new Map();

export function getCachedCover(coverPath) {
  if (!coverPath) return null;
  const entry = cache.get(coverPath);
  if (entry) {
    // Move to end (most recently used)
    cache.delete(coverPath);
    cache.set(coverPath, entry);
    return entry;
  }
  return null;
}

export function setCachedCover(coverPath, dataUrl) {
  if (!coverPath || !dataUrl) return;
  if (cache.has(coverPath)) {
    cache.delete(coverPath);
  } else if (cache.size >= MAX_SIZE) {
    // Evict oldest (first key)
    const firstKey = cache.keys().next().value;
    cache.delete(firstKey);
  }
  cache.set(coverPath, dataUrl);
}

export function clearCoverCache() {
  cache.clear();
}
