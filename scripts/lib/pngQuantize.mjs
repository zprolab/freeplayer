// PNG → indexed-PNG quantiser (no native deps).
//
// The app icons are flat artwork: a single fill colour, a handful of glyph
// colours and a hard-edged rounded rect. Their PNGs are nevertheless stored as
// 8-bit RGBA, which costs ~4x what the data needs. Re-encoding them as 8-bit
// palette images cuts the .icns by ~76% (109 KB -> 27 KB) with no visible
// difference — verified by rendering the 1024px result.
//
// Written here rather than shelling out to pngquant/oxipng because neither
// ships with macOS and the repo takes no image dependencies beyond resvg.
//
// Only handles what resvg emits (8-bit truecolour + alpha, non-interlaced).

import { deflateSync, inflateSync } from 'node:zlib';

const PNG_SIG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

function parseChunks(buf) {
  if (!buf.subarray(0, 8).equals(PNG_SIG)) throw new Error('not a PNG');
  const chunks = [];
  let i = 8;
  while (i + 8 <= buf.length) {
    const len = buf.readUInt32BE(i);
    const type = buf.toString('latin1', i + 4, i + 8);
    const data = buf.subarray(i + 8, i + 8 + len);
    chunks.push({ type, data });
    i += 12 + len;
    if (type === 'IEND') break;
  }
  return chunks;
}

function paeth(a, b, c) {
  const p = a + b - c;
  const pa = Math.abs(p - a);
  const pb = Math.abs(p - b);
  const pc = Math.abs(p - c);
  if (pa <= pb && pa <= pc) return a;
  return pb <= pc ? b : c;
}

/** Undo PNG filtering → raw RGBA bytes. */
function toRgba(idat, width, height, channels) {
  const raw = inflateSync(idat);
  const stride = width * channels;
  const out = Buffer.alloc(width * height * 4);
  const prev = Buffer.alloc(stride);
  let p = 0;
  for (let y = 0; y < height; y++) {
    const filter = raw[p++];
    const line = Buffer.from(raw.subarray(p, p + stride));
    p += stride;
    for (let i = 0; i < stride; i++) {
      const a = i >= channels ? line[i - channels] : 0;
      const b = prev[i];
      const c = i >= channels ? prev[i - channels] : 0;
      if (filter === 1) line[i] = (line[i] + a) & 0xff;
      else if (filter === 2) line[i] = (line[i] + b) & 0xff;
      else if (filter === 3) line[i] = (line[i] + ((a + b) >> 1)) & 0xff;
      else if (filter === 4) line[i] = (line[i] + paeth(a, b, c)) & 0xff;
    }
    for (let x = 0; x < width; x++) {
      const s = x * channels;
      const d = (y * width + x) * 4;
      out[d] = line[s];
      out[d + 1] = channels >= 3 ? line[s + 1] : line[s];
      out[d + 2] = channels >= 3 ? line[s + 2] : line[s];
      out[d + 3] = channels === 4 ? line[s + 3] : channels === 2 ? line[s + 1] : 255;
    }
    line.copy(prev);
  }
  return out;
}

/** Median-cut palette over 5-bit-per-channel buckets (plenty for flat art). */
function medianCut(rgba, maxColors) {
  const hist = new Map();
  for (let i = 0; i < rgba.length; i += 4) {
    if (rgba[i + 3] < 128) continue; // transparent pixels get the reserved index
    const key = ((rgba[i] >> 3) << 10) | ((rgba[i + 1] >> 3) << 5) | (rgba[i + 2] >> 3);
    hist.set(key, (hist.get(key) || 0) + 1);
  }
  let buckets = [[...hist.entries()]];
  const centre = (key) => [((key >> 10) & 31) << 3, ((key >> 5) & 31) << 3, (key & 31) << 3];

  while (buckets.length < maxColors) {
    let best = null;
    for (let bi = 0; bi < buckets.length; bi++) {
      const bucket = buckets[bi];
      if (bucket.length < 2) continue;
      const total = bucket.reduce((n, [, c]) => n + c, 0);
      for (let ch = 0; ch < 3; ch++) {
        let min = 255;
        let max = 0;
        for (const [key] of bucket) {
          const v = centre(key)[ch];
          if (v < min) min = v;
          if (v > max) max = v;
        }
        const score = (max - min) * total;
        if (!best || score > best.score) best = { bi, ch, score };
      }
    }
    if (!best || best.score <= 0) break;
    const bucket = buckets[best.bi].slice().sort((a, b) => centre(a[0])[best.ch] - centre(b[0])[best.ch]);
    const total = bucket.reduce((n, [, c]) => n + c, 0);
    let acc = 0;
    let split = 1;
    for (let i = 0; i < bucket.length; i++) {
      acc += bucket[i][1];
      if (acc >= total / 2) { split = Math.max(1, i); break; }
    }
    buckets.splice(best.bi, 1, bucket.slice(0, split), bucket.slice(split));
  }

  return buckets.map((bucket) => {
    let total = 0;
    let r = 0;
    let g = 0;
    let b = 0;
    for (const [key, count] of bucket) {
      const [cr, cg, cb] = centre(key);
      total += count; r += cr * count; g += cg * count; b += cb * count;
    }
    return [Math.round(r / total), Math.round(g / total), Math.round(b / total)];
  });
}

function crc32(buf) {
  let c;
  const table = crc32.table || (crc32.table = (() => {
    const t = new Int32Array(256);
    for (let n = 0; n < 256; n++) {
      c = n;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      t[n] = c;
    }
    return t;
  })());
  let crc = -1;
  for (let i = 0; i < buf.length; i++) crc = (crc >>> 8) ^ table[(crc ^ buf[i]) & 0xff];
  return (crc ^ -1) >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, 'latin1'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([len, body, crc]);
}

/**
 * Quantise an 8-bit truecolour(+alpha) PNG to an 8-bit palette PNG.
 * Pixels with alpha < 128 become the reserved index (transparent); opaque
 * pixels map to their nearest palette entry. Returns the original buffer
 * unchanged if it is already indexed or not a supported layout.
 */
export function quantizePng(buf, { maxColors = 256 } = {}) {
  const chunks = parseChunks(buf);
  const ihdr = chunks.find((c) => c.type === 'IHDR');
  const width = ihdr.data.readUInt32BE(0);
  const height = ihdr.data.readUInt32BE(4);
  const depth = ihdr.data[8];
  const colorType = ihdr.data[9];
  const interlace = ihdr.data[12];
  const isRgba = depth === 8 && (colorType === 6 || colorType === 2 || colorType === 0) && interlace === 0;
  if (!isRgba) return buf; // already indexed / unsupported → leave alone

  const channels = colorType === 6 ? 4 : colorType === 2 ? 3 : 1;
  const idat = Buffer.concat(chunks.filter((c) => c.type === 'IDAT').map((c) => c.data));
  const rgba = toRgba(idat, width, height, channels);

  const transparentIndex = 255;
  const palette = medianCut(rgba, Math.min(maxColors, 256) - 1);
  const nearest = new Map();
  const lookup = (r, g, b) => {
    const key = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3);
    const hit = nearest.get(key);
    if (hit !== undefined) return hit;
    let bestIndex = 0;
    let bestDist = Infinity;
    for (let i = 0; i < palette.length; i++) {
      const [pr, pg, pb] = palette[i];
      const d = (pr - r) ** 2 + (pg - g) ** 2 + (pb - b) ** 2;
      if (d < bestDist) { bestDist = d; bestIndex = i; }
    }
    nearest.set(key, bestIndex);
    return bestIndex;
  };

  const stride = width;
  const rows = Buffer.alloc(height * (stride + 1));
  for (let y = 0; y < height; y++) {
    const rowStart = y * (stride + 1);
    rows[rowStart] = 0; // filter: none — palette art filters poorly
    for (let x = 0; x < width; x++) {
      const s = (y * width + x) * 4;
      rows[rowStart + 1 + x] = rgba[s + 3] < 128
        ? transparentIndex
        : lookup(rgba[s], rgba[s + 1], rgba[s + 2]);
    }
  }

  const plte = Buffer.alloc(palette.length * 3);
  palette.forEach(([r, g, b], i) => {
    plte[i * 3] = r; plte[i * 3 + 1] = g; plte[i * 3 + 2] = b;
  });
  const trns = Buffer.alloc(palette.length);
  trns.fill(255);
  trns[transparentIndex] = 0;

  const outIhdr = Buffer.alloc(13);
  outIhdr.writeUInt32BE(width, 0);
  outIhdr.writeUInt32BE(height, 4);
  outIhdr[8] = 8;   // bit depth
  outIhdr[9] = 3;   // colour type: indexed
  return Buffer.concat([
    PNG_SIG,
    chunk('IHDR', outIhdr),
    chunk('PLTE', plte),
    chunk('tRNS', trns),
    chunk('IDAT', deflateSync(rows, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

/**
 * Re-quantise the PNGs inside an .icns container.
 *
 * Needed because `iconutil` decodes the iconset's indexed PNGs and re-encodes
 * them as RGBA, undoing the saving above (109 KB -> 87 KB instead of -> 27 KB).
 * Runs on iconutil's output: walks the chunks, quantises every PNG image body,
 * and rebuilds the container with corrected lengths.
 */
export function quantizeIcns(buf) {
  if (buf.toString('latin1', 0, 4) !== 'icns') return buf;
  const out = [buf.subarray(0, 8)];
  let i = 8;
  while (i + 8 <= buf.length) {
    const type = buf.toString('latin1', i, i + 4);
    const size = buf.readUInt32BE(i + 4);
    if (size < 8 || i + size > buf.length) break;
    let body = buf.subarray(i + 8, i + size);
    if (body.subarray(0, 8).equals(PNG_SIG)) body = quantizePng(body);
    const header = Buffer.alloc(8);
    header.write(type, 0, 'latin1');
    header.writeUInt32BE(body.length + 8, 4);
    out.push(header, body);
    i += size;
  }
  const result = Buffer.concat(out);
  result.writeUInt32BE(result.length, 4);
  return result;
}
