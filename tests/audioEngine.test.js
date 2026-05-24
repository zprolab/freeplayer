import { describe, it, expect, beforeEach } from 'vitest';
import { AudioEngine } from '../src/audioEngine';

describe('AudioEngine', () => {
  let engine;

  beforeEach(() => {
    engine = new AudioEngine();
  });

  it('creates an instance with null initial state', () => {
    expect(engine.ctx).toBeNull();
    expect(engine.analyser).toBeNull();
    expect(engine.gainNode).toBeNull();
    expect(engine.sourceNode).toBeNull();
    expect(engine.connectedElement).toBeNull();
  });

  it('connect() returns null for null audio element', () => {
    expect(engine.connect(null)).toBeNull();
  });

  it('connect() creates audio graph for valid element', () => {
    const el = {};
    const an = engine.connect(el);
    expect(an).not.toBeNull();
    expect(engine.ctx).not.toBeNull();
    expect(engine.analyser).not.toBeNull();
    expect(engine.gainNode).not.toBeNull();
    expect(engine.sourceNode).not.toBeNull();
    expect(engine.connectedElement).toBe(el);
  });

  it('connect() returns cached analyser for same element', () => {
    const el = {};
    const an1 = engine.connect(el);
    const an2 = engine.connect(el);
    expect(an1).toBe(an2);
  });

  it('setGain() applies gain without throwing', () => {
    const el = {};
    engine.connect(el);
    expect(() => engine.setGain(-3)).not.toThrow();
    expect(() => engine.setGain(0)).not.toThrow();
    expect(() => engine.setGain(6)).not.toThrow();
  });

  it('resume() works on running context', () => {
    const el = {};
    engine.connect(el);
    expect(() => engine.resume()).not.toThrow();
  });

  it('dispose() cleans up all nodes', () => {
    const el = {};
    engine.connect(el);
    engine.dispose();
    expect(engine.sourceNode).toBeNull();
    expect(engine.analyser).toBeNull();
    expect(engine.gainNode).toBeNull();
    expect(engine.connectedElement).toBeNull();
  });
});
