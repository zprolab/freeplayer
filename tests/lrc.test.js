import { describe, it, expect } from 'vitest';
import { parseLRC, sanitizeText } from '@/features/lyrics/lrc';

describe('sanitizeText', () => {
  it('keeps non-BMP characters intact instead of emitting lone surrogates', () => {
    // Regression: the old loop skipped the high surrogate and appended only
    // the low one, so every emoji / rare CJK ext char rendered as tofu.
    const out = sanitizeText('晚安 🌙 ok');
    expect(out).toBe('晚安 🌙 ok');
    for (let i = 0; i < out.length; i++) {
      const c = out.charCodeAt(i);
      if (c >= 0xd800 && c <= 0xdbff) {
        const n = out.charCodeAt(i + 1);
        expect(n >= 0xdc00 && n <= 0xdfff).toBe(true);
        i++;
      } else {
        expect(c >= 0xdc00 && c <= 0xdfff).toBe(false);
      }
    }
  });

  it('replaces control and invisible characters with spaces', () => {
    expect(sanitizeText('a\u0000b\u200Bc')).toBe('a b c');
    expect(sanitizeText('x\uFEFFy')).toBe('x y');
  });
});

describe('parseLRC', () => {
  it('parses timestamped lines and preserves emoji text', () => {
    const entries = parseLRC('[00:12.50]晚安 🌙\n[00:15]再见');
    expect(entries).toHaveLength(2);
    expect(entries[0].text).toBe('晚安 🌙');
    expect(entries[0].time).toBeCloseTo(12.5);
    expect(entries[1].text).toBe('再见');
  });

  it('skips metadata-only lines', () => {
    expect(parseLRC('[ti:Song]\n[ar:Artist]')).toEqual([]);
  });
});
