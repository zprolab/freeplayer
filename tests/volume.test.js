import { describe, it, expect, beforeEach, vi } from 'vitest';
import { AudioEngine } from '../src/audioEngine';

// Root cause: in WKWebView, once an <audio> element is routed through the
// Web Audio graph (createMediaElementSource), the element's volume/muted
// attributes are ignored. Entering the Now Playing page mounts the
// visualizer which calls audioEngine.connect(), so from that moment the
// element volume (the app's only user-volume control) stops applying:
// effective level jumps to 1.0 and the slider no longer has any effect.
//
// The graph's gain node must therefore be the volume authority: it applies
// userVolume × replaygain, and connect() must normalize the element volume
// so the same volume is heard before and after the graph takes over.
describe('AudioEngine volume authority (graph connected)', () => {
  let engine;
  beforeEach(() => {
    engine = new AudioEngine();
  });

  it('gain node created at connect() carries pending user volume × replaygain', () => {
    const el = {};
    engine.setVolume(0.5);
    engine.setGain(-6); // -6 dB replaygain → ×0.501
    engine.connect(el);
    expect(engine.gainNode.gain.value).toBeCloseTo(0.5 * Math.pow(10, -6 / 20), 5);
  });

  it('setVolume after connect() updates gain node (slider keeps working)', () => {
    engine.connect({});
    const spy = vi.spyOn(engine.gainNode.gain, 'setTargetAtTime');
    engine.setVolume(0.3);
    expect(spy).toHaveBeenCalledWith(0.3, expect.any(Number), expect.any(Number));
  });

  it('setGain() multiplies with user volume instead of replacing it', () => {
    engine.connect({});
    engine.setVolume(0.4);
    const spy = vi.spyOn(engine.gainNode.gain, 'setTargetAtTime');
    engine.setGain(0);
    expect(spy).toHaveBeenCalledWith(0.4, expect.any(Number), expect.any(Number));
  });

  it('connect() normalizes the routed element volume to 1 (single authority)', () => {
    const el = { volume: 0.8 };
    engine.connect(el);
    expect(el.volume).toBe(1);
  });

  it('setVolume clamps to the 0..1 range', () => {
    engine.connect({});
    const spy = vi.spyOn(engine.gainNode.gain, 'setTargetAtTime');
    engine.setVolume(1.7);
    expect(spy).toHaveBeenLastCalledWith(1, expect.any(Number), expect.any(Number));
    engine.setVolume(-0.3);
    expect(spy).toHaveBeenLastCalledWith(0, expect.any(Number), expect.any(Number));
  });
});
