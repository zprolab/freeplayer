import { describe, it, expect } from 'vitest';
import { sanitizeSvgIcon, SVG_ICON_MAX_BYTES } from '../../src/plugins/svgIcon';

describe('sanitizeSvgIcon', () => {
  it('passes a plain line icon through', () => {
    const src = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor"><path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/></svg>';
    const out = sanitizeSvgIcon(src);
    expect(out).toContain('<path d="M9 18V5l12-2v13"/>');
    expect(out).toContain('<circle cx="6" cy="18" r="3"/>');
    expect(out.startsWith('<svg viewBox="0 0 24 24" fill="none" stroke="currentColor">')).toBe(true);
  });

  it('normalizes unclosed shape tags to self-closing', () => {
    const src = '<svg><path d="M1 1h22"></path><rect x="1" y="1" width="2" height="2"></rect></svg>';
    const out = sanitizeSvgIcon(src);
    expect(out).toContain('<path d="M1 1h22"/>');
    expect(out).toContain('<rect x="1" y="1" width="2" height="2"/>');
  });

  it('strips width/height/on* attrs from svg root', () => {
    const src = '<svg width="64" height="64" onload="alert(1)"><rect x="1" y="1" width="22" height="22"/></svg>';
    const out = sanitizeSvgIcon(src);
    expect(out).not.toContain('width="64"');
    expect(out).not.toContain('height="64"');
    expect(out).not.toContain('onload');
    expect(out).toContain('<rect');
  });

  it('removes scripts, event handlers and foreign elements', () => {
    const src = '<svg><script>evil()</script><path d="M1 1" onclick="x()"/><a href="https://evil"><circle cx="2" cy="2" r="1"/></a><foreignObject><div>x</div></foreignObject></svg>';
    const out = sanitizeSvgIcon(src);
    expect(out).not.toContain('script');
    expect(out).not.toContain('onclick');
    expect(out).not.toContain('<a');
    expect(out).not.toContain('foreignObject');
    expect(out).toContain('<path d="M1 1"/>');
    expect(out).toContain('<circle cx="2" cy="2" r="1"/>');
  });

  it('drops <g> grouping but keeps children', () => {
    const src = '<svg><g transform="translate(2 2)"><path d="M1 1"/></g></svg>';
    const out = sanitizeSvgIcon(src);
    expect(out).not.toContain('<g');
    expect(out).toContain('<path d="M1 1"/>');
  });

  it('rejects javascript: and data: attribute values', () => {
    const src = '<svg><path d="M1 1" fill="javascript:alert(1)"/><rect x="1" y="1" width="2" height="2" fill="data:text/html,x"/></svg>';
    const out = sanitizeSvgIcon(src);
    expect(out).not.toContain('javascript');
    expect(out).not.toContain('data:text');
    expect(out).toContain('<path d="M1 1"/>');
  });

  it('rejects non-svg roots and empty output', () => {
    expect(sanitizeSvgIcon('<html><body>x</body></html>')).toBeNull();
    expect(sanitizeSvgIcon('plain text')).toBeNull();
    expect(sanitizeSvgIcon('<svg><div>x</div></svg>')).toBeNull();
  });

  it('rejects empty and oversized inputs', () => {
    expect(sanitizeSvgIcon('')).toBeNull();
    expect(sanitizeSvgIcon(null)).toBeNull();
    expect(sanitizeSvgIcon('<svg>' + 'x'.repeat(SVG_ICON_MAX_BYTES) + '</svg>')).toBeNull();
  });
});
