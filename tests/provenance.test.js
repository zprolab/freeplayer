import { describe, it, expect } from 'vitest';
import { sourceLabel, sourceKind, SOURCE_LABELS } from '../src/utils/provenance';

describe('provenance', () => {
  it('labels every source the shell records', () => {
    expect(sourceLabel('file')).toBe('From file');
    expect(sourceLabel('sidecar')).toBe('Sidecar .lrc');
    expect(sourceLabel('filename')).toBe('From filename');
    expect(sourceLabel('plugin')).toBe('Online');
    expect(sourceLabel('user')).toBe('Edited');
  });

  it('falls back for an unrecorded/unknown source', () => {
    expect(sourceLabel(null)).toBe('Unknown');
    expect(sourceLabel(undefined)).toBe('Unknown');
    expect(sourceLabel('something-new')).toBe('Unknown');
    expect(Object.keys(SOURCE_LABELS)).toHaveLength(5);
  });

  it('groups sources into file / online / user for styling', () => {
    expect(sourceKind('file')).toBe('file');
    expect(sourceKind('sidecar')).toBe('file');
    expect(sourceKind('filename')).toBe('file');
    expect(sourceKind('plugin')).toBe('online');
    expect(sourceKind('user')).toBe('user');
    expect(sourceKind(null)).toBe('unknown');
  });
});
