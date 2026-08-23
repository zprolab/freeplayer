import { describe, it, expect } from 'vitest';
import { pushSpectrogramFrame } from '../src/utils/spectrogram';

describe('pushSpectrogramFrame', () => {
  it('creates a buffer on first call', () => {
    const buf = pushSpectrogramFrame(null, 4, new Uint8Array([1, 2, 3]));
    expect(buf).toHaveLength(4);
    expect(buf.every((row) => row instanceof Uint8Array && row.length === 3)).toBe(true);
  });

  it('appends a new frame at the bottom row', () => {
    let buf = pushSpectrogramFrame(null, 4, new Uint8Array([9, 9, 9]));
    expect(Array.from(buf[3])).toEqual([9, 9, 9]);
    expect(Array.from(buf[2])).toEqual([0, 0, 0]);
  });

  it('scrolls history: each frame shifts up, rows stay distinct', () => {
    let buf = null;
    const frames = [
      new Uint8Array([1, 1, 1]),
      new Uint8Array([2, 2, 2]),
      new Uint8Array([3, 3, 3]),
    ];
    for (const f of frames) buf = pushSpectrogramFrame(buf, 4, f);
    expect(Array.from(buf[0])).toEqual([0, 0, 0]);
    expect(Array.from(buf[1])).toEqual([1, 1, 1]);
    expect(Array.from(buf[2])).toEqual([2, 2, 2]);
    expect(Array.from(buf[3])).toEqual([3, 3, 3]);
  });

  it('never aliases rows onto the same object', () => {
    let buf = null;
    for (let f = 0; f < 10; f++) {
      buf = pushSpectrogramFrame(buf, 4, new Uint8Array([f, f, f]));
    }
    const unique = new Set(buf);
    expect(unique.size).toBe(4);
    for (let i = 0; i < 4; i++) {
      expect(Array.from(buf[i])).toEqual([10 - 4 + i, 10 - 4 + i, 10 - 4 + i]);
    }
  });

  it('handles resize: reallocates when numRows changes', () => {
    let buf = pushSpectrogramFrame(null, 4, new Uint8Array([1, 1, 1]));
    const next = pushSpectrogramFrame(buf, 6, new Uint8Array([2, 2, 2]));
    expect(next).not.toBe(buf);
    expect(next).toHaveLength(6);
    expect(Array.from(next[4])).toEqual([1, 1, 1]);
    expect(Array.from(next[5])).toEqual([2, 2, 2]);
  });

  it('reallocates when buffer length differs from freq data length', () => {
    let buf = pushSpectrogramFrame(null, 4, new Uint8Array([1, 1, 1]));
    const next = pushSpectrogramFrame(buf, 4, new Uint8Array([2, 2, 2, 2]));
    expect(next).not.toBe(buf);
    expect(next[0].length).toBe(4);
    expect(Array.from(next[3])).toEqual([2, 2, 2, 2]);
  });
});
