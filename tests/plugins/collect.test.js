import { describe, it, expect } from 'vitest';
import { resolveRelPath, rewriteModule, collectModuleGraph, LIMITS } from '../../src/plugins/collect';

describe('resolveRelPath', () => {
  it('normalizes ./ and ../', () => {
    expect(resolveRelPath('main.js', './helper.js')).toBe('helper.js');
    expect(resolveRelPath('lib/main.js', '../util.js')).toBe('util.js');
    expect(resolveRelPath('main.js', './a/b.js')).toBe('a/b.js');
  });
  it('rejects escapes, absolutes and non-js', () => {
    expect(resolveRelPath('main.js', '../../evil.js')).toBeNull();
    expect(resolveRelPath('main.js', '/abs.js')).toBeNull();
    expect(resolveRelPath('main.js', './data.json')).toBeNull();
  });
});

describe('rewriteModule', () => {
  it('rewrites static import declarations', () => {
    const src = "import x from './a.js'; import './b.js'; import * as y from '../lib/c.js'; import { z } from './d.js';";
    const out = rewriteModule(src, (spec) => ({ url: `blob:${spec}` }));
    expect(out).toContain("import x from 'blob:./a.js'");
    expect(out).toContain("import 'blob:./b.js'");
    expect(out).toContain("blob:../lib/c.js");
    expect(out).toContain("blob:./d.js");
    expect(out).not.toContain("'./a.js'");
  });
  it('rewrites literal dynamic imports', () => {
    const out = rewriteModule("const m = await import('./e.js');", (spec) => ({ url: `blob:${spec}` }));
    expect(out).toContain("import('blob:./e.js')");
  });
  it('rejects non-literal dynamic imports', () => {
    expect(() => rewriteModule("const p = name; import(p);", () => ({ url: 'blob:x' })))
      .toThrow(/string literal/);
  });
  it('rejects unresolvable imports', () => {
    expect(() => rewriteModule("import './missing.js';", () => null)).toThrow(/cannot resolve/);
  });
  it('ignores import-like text in comments and strings', () => {
    const src = "// import './fake.js';\nconst s = \"import './fake2.js'\";\nimport './real.js';";
    const out = rewriteModule(src, (spec) => ({ url: `blob:${spec}` }));
    expect(out).not.toContain("blob:./fake.js");
    expect(out).not.toContain("blob:./fake2.js");
    expect(out).toContain("blob:./real.js");
  });
  it('handles escaped quotes inside strings', () => {
    const src = "const s = 'it\\'s fine'; import './real.js';";
    const out = rewriteModule(src, (spec) => ({ url: `blob:${spec}` }));
    expect(out).toContain("blob:./real.js");
  });
  it('does not rewrite import text inside strings with escapes', () => {
    const src = "const s = 'it\\'s: import \"./x.js\" here'; import './real.js';";
    const out = rewriteModule(src, (spec) => ({ url: `blob:${spec}` }));
    expect(out).not.toContain("blob:./x.js");
    expect(out).toContain("blob:./real.js");
  });
  it('does not treat regex literal slashes as comments', () => {
    const src = "const re = /https?:\\/\\/x/;\nimport './real.js';";
    const out = rewriteModule(src, (spec) => ({ url: `blob:${spec}` }));
    expect(out).toContain("blob:./real.js");
  });
  it('does not rewrite import text inside regex literals', () => {
    const src = "const re = /import('fake.js')/; import('./real.js');";
    const out = rewriteModule(src, (spec) => ({ url: `blob:${spec}` }));
    expect(out).not.toContain("blob:./fake.js");
    expect(out).toContain("blob:./real.js");
  });
  it('does not throw on import text inside regex literals', () => {
    expect(() => rewriteModule('const re = /import(p)/;', () => ({ url: 'blob:x' }))).not.toThrow();
  });
  it('rejects dynamic imports with non-literal expressions', () => {
    expect(() => rewriteModule("import('./a.js' + suffix);", () => ({ url: 'blob:x' })))
      .toThrow(/string literal/);
  });
  it('rejects empty dynamic import spec', () => {
    expect(() => rewriteModule("import('');", (spec) => (spec ? { url: 'blob:x' } : null)))
      .toThrow(/cannot resolve/);
  });
  it('rejects empty static import spec', () => {
    expect(() => rewriteModule("import '';", (spec) => (spec ? { url: 'blob:x' } : null)))
      .toThrow(/cannot resolve/);
  });
  it('rewrites imports directly after } with unified boundaries', () => {
    const out = rewriteModule("if (x) {}import './a.js';", (spec) => ({ url: `blob:${spec}` }));
    expect(out).toContain("blob:./a.js");
  });
});

describe('collectModuleGraph', () => {
  const fs = {
    'main.js': "import './a.js'; import './b.js';",
    'a.js': "import '../lib/c.js';",
    'lib/c.js': 'export const c = 1;',
    'b.js': "import './a.js';", // diamond, not a cycle
  };
  async function readFile(path) {
    const src = fs[path];
    if (!src) return null;
    return { source: src, bytes: Buffer.byteLength(src) };
  }
  it('collects transitive dependencies breadth-first', async () => {
    const res = await collectModuleGraph('main.js', readFile);
    expect(res.error).toBeUndefined();
    const paths = res.modules.map((m) => m.path).sort();
    expect(paths).toEqual(['a.js', 'b.js', 'lib/c.js', 'main.js'].sort());
  });
  it('detects cycles', async () => {
    const cyc = {
      'm.js': "import './x.js';",
      'x.js': "import './m.js';",
    };
    const res = await collectModuleGraph('m.js', async (p) => cyc[p] ? { source: cyc[p], bytes: 1 } : null);
    expect(res.error).toContain('circular');
  });
  it('errors on missing files', async () => {
    const res = await collectModuleGraph('main.js', async () => null);
    expect(res.error).toContain('main.js');
  });
  it('enforces total size limit', async () => {
    const big = { 'main.js': 'export const a = 1;', 'huge.js': `export const s = '${'x'.repeat(LIMITS.totalBytes)}';` };
    const res = await collectModuleGraph('main.js', async (p) => {
      if (p === 'main.js') return { source: "import './huge.js';", bytes: 20 };
      if (p === 'huge.js') return { source: big['huge.js'], bytes: LIMITS.totalBytes };
      return null;
    });
    expect(res.error).toContain('size');
  });
});
