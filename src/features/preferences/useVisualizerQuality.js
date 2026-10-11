import { useCallback, useEffect, useState } from 'react';
import { audioEngine } from '@/features/playback/audio.js';
import * as client from '@/core/client.js';

// ── Analysis quality tiers ──
// One knob trades frequency resolution against time resolution (inversely
// proportional for any window: df ~ 1/T). The window column is what the
// smearing/sync feel depends on; the bin column is what the bass detail
// depends on. Persisted under the `visualizer_quality` setting.
export const QUALITY_TIERS = [
  {
    id: 'reactive',
    fftSize: 2048,
    label: 'Reactive',
    hint: 'Responsive, but the bass is coarse',
    detail: '46 ms window · 21.5 Hz bins',
  },
  {
    id: 'balanced',
    fftSize: 8192,
    label: 'Balanced',
    hint: 'Bass detail without much smearing',
    detail: '186 ms window · 5.4 Hz bins',
  },
  {
    id: 'precise',
    fftSize: 16384,
    label: 'Precise',
    hint: 'Sharpest bass, slower to react',
    detail: '371 ms window · 2.7 Hz bins',
  },
];
export const DEFAULT_QUALITY = 'balanced';
export const SETTING_KEY = 'visualizer_quality';

export function tierFor(id) {
  return QUALITY_TIERS.find((t) => t.id === id) || QUALITY_TIERS.find((t) => t.id === DEFAULT_QUALITY);
}

// Applies a tier to the live analyser. The caller is responsible for dropping
// any spectrogram history sized for the previous bin count.
export function applyQualityTier(id) {
  const tier = tierFor(id);
  audioEngine.setFftSize(tier.fftSize);
  return tier;
}

// Single source of truth for the analysis quality preference, shared by the
// Settings page and the visualizer's inline control. The engine owns the live
// value (setFftSize emits), so whichever surface changes it, the other follows.
export function useVisualizerQuality() {
  const [quality, setQualityState] = useState(() => audioEngine.getFftSize());

  useEffect(() => {
    const unsubscribe = audioEngine.subscribeFftSize((size) => setQualityState(size));
    // The stored preference may differ from the module default: normalise on
    // mount so both surfaces agree with what will actually be analysed.
    let cancelled = false;
    client.settings.get(SETTING_KEY)
      .then((saved) => {
        if (cancelled) return;
        const tier = tierFor(saved);
        if (tier.fftSize !== audioEngine.getFftSize()) applyQualityTier(tier.id);
      })
      .catch(() => {});
    // Drive the engine from the module default first, so a fresh install has a
    // defined fftSize before the async read resolves.
    applyQualityTier(tierFor(audioEngine.getFftSize()).id);
    return () => { cancelled = true; unsubscribe(); };
  }, []);

  const changeQuality = useCallback((id) => {
    const tier = applyQualityTier(id);
    // Persist, and surface a rejection: a silent failure here is exactly how
    // this preference used to be dropped (the native key was not allowlisted).
    client.settings.set(SETTING_KEY, tier.id)
      .then((ok) => {
        if (ok === false) console.error('Could not save the analysis quality setting');
      })
      .catch((err) => console.error('Could not save the analysis quality setting:', err));
  }, []);

  return { quality, tier: qualityTierOf(quality), changeQuality, tiers: QUALITY_TIERS };
}

export function qualityTierOf(fftSize) {
  return QUALITY_TIERS.find((t) => t.fftSize === fftSize)
    || QUALITY_TIERS.find((t) => t.id === DEFAULT_QUALITY);
}
