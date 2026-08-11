import { describe, it, expect, beforeEach } from 'vitest';
import { AudioEngine } from '../src/audioEngine';

describe('AudioEngine', () => {
  let engine;

  beforeEach(() => {
    engine = new AudioEngine();
  });

  it('wires a fresh graph on first connect() without throwing', () => {
    expect(() => engine.connect({})).not.toThrow();
    expect(engine.connect({})).not.toBeNull();
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

  it('dispose() is idempotent and a later connect() rebuilds the graph', () => {
    engine.connect({});
    engine.dispose();
    expect(() => engine.dispose()).not.toThrow();
    expect(engine.connect({})).not.toBeNull();
  });

  it('switching to a new element detaches the previous source without throwing', () => {
    const elA = {};
    const elB = {};
    engine.connect(elA);
    expect(() => engine.connect(elB)).not.toThrow();
    expect(engine.connectedElement).toBe(elB);
  });

  it('setGain/setVolume/applyEq are safe no-ops on a closed context', () => {
    engine.connect({});
    engine.ctx.state = 'closed'; // simulate an externally closed context
    expect(() => engine.setVolume(0.5)).not.toThrow();
    expect(() => engine.setGain(-6)).not.toThrow();
    expect(() => engine.applyEq([0, 0, 0, 0, 0, 0, 0, 0, 0, 0], true)).not.toThrow();
  });

  it('a closed context triggers a full graph rebuild on the next connect()', () => {
    const el = {};
    const an1 = engine.connect(el);
    engine.ctx.state = 'closed';
    const an2 = engine.connect(el);
    expect(an2).not.toBeNull();
    expect(an2).not.toBe(an1); // rebuilt, not the dead analyser
  });
});
