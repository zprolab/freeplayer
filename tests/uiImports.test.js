import { describe, it, expect } from 'vitest';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

// `vite build` does NOT fail on an undefined component reference — a JSX tag
// whose identifier was never imported compiles fine and throws at runtime. That
// happened during the design-system migration (Button used in two screens with
// no import), so it is guarded here.
const root = join(__dirname, '..', 'src');

function walk(dir) {
  return readdirSync(dir).flatMap((entry) => {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) return walk(full);
    return full.endsWith('.jsx') || full.endsWith('.js') ? [full] : [];
  });
}

function importedNames(src) {
  const names = new Set();
  for (const m of src.matchAll(/import\s+([A-Za-z0-9_]+)\s*,\s*\{([^}]*)\}\s+from/g)) {
    names.add(m[1]);
    for (const part of m[2].split(',')) if (part.trim()) names.add(part.trim().split(/\s+as\s+/).pop());
  }
  for (const m of src.matchAll(/import\s*\{([^}]*)\}\s*from/g)) {
    for (const part of m[1].split(',')) if (part.trim()) names.add(part.trim().split(/\s+as\s+/).pop());
  }
  for (const m of src.matchAll(/import\s+([A-Za-z0-9_]+)\s+from/g)) names.add(m[1]);
  for (const m of src.matchAll(/import\s+\*\s+as\s+([A-Za-z0-9_]+)\s+from/g)) names.add(m[1]);
  return names;
}

function definedNames(src) {
  const names = new Set();
  // function/const/let/class declarations, including default-exported ones.
  for (const m of src.matchAll(/(?:function|const|let|var|class)\s+([A-Za-z0-9_]+)/g)) names.add(m[1]);
  return names;
}

describe('component references resolve', () => {
  it('every JSX element name is imported or defined in its module', () => {
    const problems = [];
    for (const file of walk(root)) {
      const src = readFileSync(file, 'utf8');
      const available = new Set([...importedNames(src), ...definedNames(src)]);
      for (const m of src.matchAll(/<([A-Z][A-Za-z0-9_]*)/g)) {
        const name = m[1];
        if (available.has(name)) continue;
        const line = src.slice(0, m.index).split('\n').length;
        problems.push(`${relative(root, file)}:${line} <${name}>`);
      }
    }
    expect(problems).toEqual([]);
  });

  it('the design-system entry point exports what screens import', async () => {
    const ui = await import('../src/ui/components/index.js');
    for (const name of ['Button', 'IconButton', 'SegmentedControl', 'ToggleSwitch']) {
      expect(typeof ui[name], `${name} missing from src/ui/components`).toBe('function');
    }
  });
});
