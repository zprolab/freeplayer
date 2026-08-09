import { useState, useEffect } from 'react';
import { getCachedCover, setCachedCover } from '../coverCache';

export function useCoverArt(track) {
  const [coverUrl, setCoverUrl] = useState(null);

  useEffect(() => {
    let stale = false;
    if (track && track.cover_path) {
      const cached = getCachedCover(track.cover_path);
      if (cached) {
        setCoverUrl(cached);
        return;
      }
      window.freeplayer.getCover(track.cover_path).then((url) => {
        if (!stale && url) {
          setCachedCover(track.cover_path, url);
          setCoverUrl(url);
        }
      });
    } else {
      setCoverUrl(null);
    }
    return () => { stale = true; };
  }, [track]);

  return coverUrl;
}
