// Sanitize plugin-provided SVG icons before injecting into the page.
// DOM-free tokenizer: element/attribute allowlists only — no scripts,
// event handlers, foreign content, or external references. Shape elements
// are normalized to self-closing form; <g> grouping is dropped (children
// survive without the group's transform, which icon authors rarely rely on).
export const SVG_ICON_MAX_BYTES = 4 * 1024;

const ALLOWED_ELEMENTS = new Set([
  'svg', 'path', 'circle', 'rect', 'line', 'polyline', 'polygon', 'ellipse',
]);

// Attributes allowed on <svg> itself and on child shapes.
const SVG_ATTRS = new Set([
  'viewBox', 'fill', 'stroke', 'stroke-width', 'stroke-linecap',
  'stroke-linejoin', 'stroke-opacity', 'fill-opacity', 'opacity',
]);
const SHAPE_ATTRS = new Set([
  'd', 'cx', 'cy', 'r', 'rx', 'ry', 'x', 'y', 'width', 'height',
  'points', 'fill', 'stroke', 'stroke-width', 'stroke-linecap', 'stroke-linejoin',
  'stroke-opacity', 'fill-opacity', 'opacity', 'transform',
]);
const FORBIDDEN_IN_VALUE = /<|>|javascript:|data:/i;

export function sanitizeSvgIcon(input) {
  if (typeof input !== 'string') return null;
  const trimmed = input.trim();
  if (!trimmed || trimmed.length > SVG_ICON_MAX_BYTES) return null;
  if (!/^<svg[\s>]/i.test(trimmed)) return null;

  const tagRe = /<\/?([a-zA-Z][\w-]*)((?:\s+[a-zA-Z-]+(?:\s*=\s*"[^"]*")?)*)\s*\/?>/g;
  const attrRe = /([a-zA-Z-]+)(?:\s*=\s*"([^"]*)")?/g;
  const shapes = [];
  let m;

  while ((m = tagRe.exec(trimmed)) !== null) {
    const tag = m[1].toLowerCase();
    if (!ALLOWED_ELEMENTS.has(tag) || tag === 'svg') continue;
    const allowed = SHAPE_ATTRS;
    const attrs = [];
    let am;
    while ((am = attrRe.exec(m[2])) !== null) {
      const name = am[1].toLowerCase();
      const value = am[2] ?? '';
      if (allowed.has(name) && !FORBIDDEN_IN_VALUE.test(value)) {
        attrs.push(`${am[1]}="${value}"`);
      }
    }
    shapes.push(`<${tag}${attrs.length ? ' ' + attrs.join(' ') : ''}/>`);
  }

  if (!shapes.length) return null;
  return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor">${shapes.join('')}</svg>`;
}

// Renders a sanitized plugin icon string; returns null when invalid so the
// caller can fall back to a generic placeholder.
export function renderablePluginIcon(icon) {
  return sanitizeSvgIcon(icon);
}
