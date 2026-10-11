import { describe, it, expect } from 'vitest';
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join, relative, dirname } from 'node:path';

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

  // A relative import that does not resolve only surfaces at `vite build` (and
  // then as a Rollup resolution failure, after every other check has passed).
  // During the data-seam extraction a scripted rewrite emitted `core/settings`
  // instead of `./core/settings` in src/App.jsx, and a depth miscount emitted
  // `../core/client` from files one level deeper than intended. Both were
  // invisible to lint, to vitest and to the JSX-name guard above.
  it('every relative import resolves to a file that exists', () => {
    const problems = [];
    for (const file of walk(root)) {
      const src = readFileSync(file, 'utf8');
      for (const m of src.matchAll(/from\s+'(\.[^']+)'/g)) {
        // Strip Vite's query suffix (`./sandbox.js?raw`, `../../LICENSE?raw`):
        // it is a loader directive, not part of the path on disk.
        const spec = m[1].split('?')[0];
        const base = join(dirname(file), spec);
        const hit = [base, `${base}.js`, `${base}.jsx`, `${base}/index.js`, `${base}/index.jsx`]
          .some((candidate) => existsSync(candidate));
        if (hit) continue;
        const line = src.slice(0, m.index).split('\n').length;
        problems.push(`${relative(root, file)}:${line} '${m[1]}'`);
      }
    }
    expect(problems).toEqual([]);
  });

  // Aliased imports bypass the guard above entirely, which is how six broken
  // asset paths (`@/../assets/logo.svg` in three files) passed lint, vitest and
  // `vite build` while being wrong. The alias map here mirrors vite.config.js.
  it('every aliased import resolves to a file that exists', () => {
    const aliases = {
      '@/': `${root}/`,
      '@assets/': join(root, '..', 'assets') + '/',
      '@root/': join(root, '..') + '/',
    };
    const problems = [];
    for (const file of walk(root)) {
      const src = readFileSync(file, 'utf8');
      // `@/x` (empty alias name) and `@assets/x` both match: the name is optional.
      for (const m of src.matchAll(/from\s+'(@[a-z]*\/)([^']+)'/g)) {
        const [, prefix, rest] = m;
        const base = aliases[prefix] ? join(aliases[prefix], rest.split('?')[0]) : null;
        if (!base) { problems.push(`unknown alias '${prefix}'`); continue; }
        const hit = [base, `${base}.js`, `${base}.jsx`, `${base}/index.js`, `${base}/index.jsx`]
          .some((candidate) => existsSync(candidate));
        if (hit) continue;
        const line = src.slice(0, m.index).split('\n').length;
        problems.push(`${relative(root, file)}:${line} '${prefix}${rest}'`);
      }
    }
    expect(problems).toEqual([]);
  });

  // Bare specifiers (no leading . or /) are treated as node_modules by the
  // bundler, so a missing './' fails the build with a confusing message.
  it('no relative import is written as a bare specifier', () => {
    const problems = [];
    for (const file of walk(root)) {
      const src = readFileSync(file, 'utf8');
      for (const m of src.matchAll(/from\s+'(?![./])((?:core|ui|utils|components|hooks|plugins|features|app)\/[^']+)'/g)) {
        const line = src.slice(0, m.index).split('\n').length;
        problems.push(`${relative(root, file)}:${line} '${m[1]}'`);
      }
    }
    expect(problems).toEqual([]);
  });
});
