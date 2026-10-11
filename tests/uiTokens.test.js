import { describe, it, expect } from 'vitest';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

// CSS failure mode is silence: a typo'd or missing custom property resolves to
// nothing and the declaration is dropped, which is how UI drift starts. These
// checks make the token layer self-verifying.
const root = join(__dirname, '..', 'src');
const cssDir = join(root, 'styles');
const uiTokens = join(root, 'ui', 'tokens');

function read(file) {
  return readFileSync(file, 'utf8');
}

function declaredVars(css) {
  const names = new Set();
  for (const m of css.matchAll(/(--[a-z0-9-]+)\s*:/gi)) names.add(m[1]);
  return names;
}

function referencedVars(css) {
  const names = new Set();
  for (const m of css.matchAll(/var\(\s*(--[a-z0-9-]+)/gi)) names.add(m[1]);
  return names;
}

const primitiveCss = read(join(uiTokens, 'primitive.css'));
const semanticCss = read(join(uiTokens, 'semantic.css'));

const primitiveVars = declaredVars(primitiveCss);
const semanticVars = declaredVars(semanticCss);

describe('design system tokens', () => {
  it('declares every semantic token exactly once', () => {
    const seen = new Map();
    for (const m of semanticCss.matchAll(/(--fp-[a-z0-9-]+)\s*:/gi)) {
      seen.set(m[1], (seen.get(m[1]) || 0) + 1);
    }
    const duplicates = [...seen.entries()].filter(([, n]) => n > 1).map(([name]) => name);
    expect(duplicates).toEqual([]);
  });

  it('resolves every semantic token to a declared primitive (no dangling var())', () => {
    const unresolved = [...referencedVars(semanticCss)]
      .filter((name) => !primitiveVars.has(name) && !semanticVars.has(name));
    expect(unresolved).toEqual([]);
  });

  it('offers the full scale: space, type, radius, elevation, z-index', () => {
    const all = new Set([...semanticVars, ...primitiveVars]);
    for (const prefix of ['--fp-space-', '--fp-font-', '--fp-radius-', '--fp-shadow-', '--fp-z-']) {
      expect([...all].some((n) => n.startsWith(prefix)), `no ${prefix}* token`).toBe(true);
    }
    // The z scale must be strictly ordered so overlays cannot interleave.
    const zs = [...semanticCss.matchAll(/--fp-z-([a-z-]+):\s*(\d+)/g)]
      .map(([, name, n]) => [name, Number(n)]);
    expect(zs.length).toBeGreaterThanOrEqual(4);
    const values = zs.map(([, n]) => n);
    expect([...values].sort((a, b) => a - b)).toEqual(values);
    expect(new Set(values).size).toBe(values.length);
  });

  it('has fully retired the legacy --gl-* layer', () => {
    // Phase 3 migrated all 439 references onto semantic tokens and deleted the
    // duplicate definitions. A `var(--gl-*)` reappearing means someone reached
    // for the old name again. Comments describing the migration are allowed.
    const offenders = [];
    const files = [
      ...readdirSync(cssDir).filter((f) => f.endsWith('.css')).map((f) => join(cssDir, f)),
      ...readdirSync(uiTokens).filter((f) => f.endsWith('.css')).map((f) => join(uiTokens, f)),
    ];
    for (const file of files) {
      const stripped = read(file).replace(/\/\*[\s\S]*?\*\//g, ''); // ignore comments
      for (const m of stripped.matchAll(/var\((--gl-[a-z0-9-]+)\)/g)) {
        offenders.push(`${file.split('/').pop()} ${m[1]}`);
      }
    }
    expect(offenders).toEqual([]);
  });

  it('leaves no var() reference without a declaration or a fallback', () => {
    // A var() with neither a declaration nor a fallback resolves to nothing and
    // the declaration is dropped silently — how UI drift starts. Phase 3 fixed
    // the last two (--gl-text in edit-form.css).
    const declared = new Set([...primitiveVars, ...semanticVars]);
    const missing = [];
    for (const file of readdirSync(cssDir).filter((f) => f.endsWith('.css'))) {
      const css = read(join(cssDir, file));
      for (const m of css.matchAll(/var\(\s*(--[a-z0-9-]+)\s*([,)])/gi)) {
        const name = m[1];
        if (m[2] === ',') continue;                                   // has a fallback
        if (declared.has(name) || css.includes(`${name}:`)) continue;  // resolves
        missing.push(`${file}:${css.slice(0, m.index).split('\n').length} ${name}`);
      }
    }
    expect(missing).toEqual([]);
  });

  it('has promoted the --np-* palette out of its page-local scope', () => {
    // --np-* was declared on `.now-playing` but consumed by lyrics.css and
    // immersive.css, which also render outside that subtree — the declarations
    // resolved to nothing there. They are semantic tokens now.
    const offenders = [];
    for (const file of readdirSync(cssDir).filter((f) => f.endsWith('.css'))) {
      const stripped = read(join(cssDir, file)).replace(/\/\*[\s\S]*?\*\//g, '');
      if (/var\(--np-[a-z0-9-]+\)/.test(stripped) || /--np-[a-z0-9-]+\s*:/.test(stripped)) {
        offenders.push(file);
      }
    }
    expect(offenders).toEqual([]);
  });
});

describe('z-index layering', () => {
  // Overlays must be ordered by the token scale, never by ad-hoc numbers: the
  // app previously had 200 in both modal.css and equalizer.css (resolved by
  // import order) and a confirm dialog at 250 that responsive.css pushed below
  // the modal that opened it.
  const SCALE = ['--fp-z-chrome', '--fp-z-popover', '--fp-z-modal', '--fp-z-modal-nested', '--fp-z-immersive'];

  it('resolves every layer to a distinct, increasing value', () => {
    const values = SCALE.map((name) => {
      const m = semanticCss.match(new RegExp(`${name}:\\s*(\\d+)`));
      expect(m, `${name} missing from semantic.css`).not.toBeNull();
      return Number(m[1]);
    });
    expect([...values].sort((a, b) => a - b)).toEqual(values);
    expect(new Set(values).size).toBe(values.length);
  });

  it('leaves no raw numeric z-index in the stylesheet layer', () => {
    // Local stacking *inside* a surface (z-index 0/1/2) is fine; anything that
    // claims a layer band must come from the scale.
    const offenders = [];
    for (const file of readdirSync(cssDir).filter((f) => f.endsWith('.css'))) {
      const css = read(join(cssDir, file));
      css.split('\n').forEach((line, i) => {
        const m = line.match(/z-index:\s*(\d+)/);
        if (m && Number(m[1]) >= 10) offenders.push(`${file}:${i + 1} z-index: ${m[1]}`);
      });
    }
    expect(offenders).toEqual([]);
  });

  it('keeps the confirm dialog above the modal that opens it', () => {
    const modal = Number(semanticCss.match(/--fp-z-modal:\s*(\d+)/)[1]);
    const nested = Number(semanticCss.match(/--fp-z-modal-nested:\s*(\d+)/)[1]);
    expect(nested).toBeGreaterThan(modal);
    // settings.css owns the reset-confirmation overlay.
    expect(read(join(cssDir, 'settings.css'))).toContain('var(--fp-z-modal-nested)');
  });
});

describe('stylesheet integrity', () => {
  it('has balanced parentheses in every stylesheet', () => {
    // A var() rewrite once dropped a closing paren and shipped a build that only
    // lightningcss rejected. Balanced per FILE, not per line: multiline
    // linear-gradient() declarations legitimately span lines.
    const offenders = [];
    const scan = (dir, files) => {
      for (const file of files.filter((f) => f.endsWith('.css'))) {
        let css = read(join(dir, file)).replace(/\/\*[\s\S]*?\*\//g, ' ');
        css = css.replace(/"(?:[^"\\]|\\.)*"/g, '""').replace(/'(?:[^'\\]|\\.)*'/g, "''");
        const opens = (css.match(/\(/g) || []).length;
        const closes = (css.match(/\)/g) || []).length;
        if (opens !== closes) offenders.push(`${file}: ${opens} open vs ${closes} close`);
      }
    };
    scan(cssDir, readdirSync(cssDir));
    scan(uiTokens, readdirSync(uiTokens));
    expect(offenders).toEqual([]);
  });

  it('leaves no malformed var() with an extra closing paren', () => {
    // The original form of this check flagged `var(--a))`, which is also what a
    // LEGAL fallback looks like: `var(--a, var(--b))`. So it was really asserting
    // balance, not nesting. Balance must be counted per DECLARATION, not per line:
    // a multi-line value splits its parentheses across lines, and a line-based
    // count then reports every continuation as unbalanced.
    const offenders = [];
    for (const file of readdirSync(cssDir).filter((f) => f.endsWith('.css'))) {
      const css = read(join(cssDir, file)).replace(/\/\*[\s\S]*?\*\//g, '');
      for (const decl of css.split(';')) {
        const opens = (decl.match(/\(/g) || []).length;
        const closes = (decl.match(/\)/g) || []).length;
        if (closes !== opens) {
          const firstLine = decl.trim().split('\n')[0].slice(0, 40);
          offenders.push(`${file}: "${firstLine}" (${opens} open, ${closes} close)`);
        }
      }
    }
    expect(offenders).toEqual([]);
  });

  // A declaration that only redeclares a RETIRED name is silent: the override
  // applies to a variable nothing reads, so the intent (a narrower rail, a
  // tablet breakpoint) never takes effect and nothing errors anywhere.
  //
  // This shipped twice. The token migration renamed every `var()` reference from
  // --sidebar-width to --fp-sidebar-width but missed the DECLARATIONS in
  // sidebar.css (the collapsed rail) and responsive.css (the tablet width), so
  // collapsing the sidebar did nothing at all.
  it('never redeclares a retired token name', () => {
    const known = new Set([...declaredVars(primitiveCss), ...declaredVars(semanticCss)]);
    const offenders = [];
    for (const file of readdirSync(cssDir).filter((f) => f.endsWith('.css'))) {
      // Strip comments first: prose that explains the rename necessarily mentions
      // the retired name, and matching that would make the guard fail on its own
      // documentation.
      const css = read(join(cssDir, file)).replace(/\/\*[\s\S]*?\*\//g, (m) => m.replace(/[^\n]/g, ' '));
      css.split('\n').forEach((line, i) => {
        for (const m of line.matchAll(/(--[a-z0-9-]+)\s*:/g)) {
          const name = m[1];
          if (known.has(name)) continue;               // a real token
          const prefixed = `--fp-${name.slice(2)}`;
          // The prefixed variant existing means this is a stale declaration of a
          // renamed token, not a genuinely new local variable.
          if (known.has(prefixed)) offenders.push(`${file}:${i + 1} ${name} should be ${prefixed}`);
        }
      });
    }
    expect(offenders).toEqual([]);
  });

  // The collapsed rail is the concrete case above; assert the cascade is
  // connected, so a future rename cannot silently disconnect it again.
  it('the collapsed sidebar rail overrides a token that is actually read', () => {
    const css = read(join(cssDir, 'sidebar.css'));
    const block = css.match(/\.app--sidebar-collapsed\s*\{([^}]*)\}/);
    expect(block, '.app--sidebar-collapsed block must exist').not.toBeNull();
    const override = block[1].match(/(--[a-z0-9-]+)\s*:\s*72px/);
    expect(override, 'the collapsed rail must declare a 72px width').not.toBeNull();
    const all = readdirSync(cssDir).filter((f) => f.endsWith('.css'))
      .map((f) => read(join(cssDir, f))).join('\n');
    expect(all.includes(`var(${override[1]})`), `${override[1]} is declared but never read`).toBe(true);
  });
});
