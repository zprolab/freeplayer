/**
 * Parse raw LRC text into an array of { time, text } entries.
 * Handles: [mm:ss.xx]text, [mm:ss]text, multi-timestamp lines,
 * and metadata tags like [ti:], [ar:], [al:], [length:].
 */
export function parseLRC(raw) {
  if (!raw) return [];

  const lines = raw.split(/\r?\n/);
  const entries = [];

  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed) continue;

    // Collect all time tags on this line
    const timeRegex = /\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]/g;
    const times = [];
    let match;
    while ((match = timeRegex.exec(trimmed)) !== null) {
      const minutes = parseInt(match[1], 10);
      const seconds = parseInt(match[2], 10);
      const centiseconds = match[3]
        ? parseInt(match[3].padEnd(2, '0').slice(0, 2), 10)
        : 0;
      times.push(minutes * 60 + seconds + centiseconds / 100);
    }

    if (times.length === 0) continue; // metadata line, skip

    // Get the text after the last time tag
    const textStart = trimmed.lastIndexOf(']') + 1;
    const text = sanitizeText(trimmed.slice(textStart).trim());
    if (!text) continue; // skip empty lyric lines

    for (const time of times) {
      entries.push({ time, text });
    }
  }

  // Sort by time
  entries.sort((a, b) => a.time - b.time);

  // Deduplicate adjacent entries with same text
  const deduped = [];
  for (let i = 0; i < entries.length; i++) {
    if (i === 0 || entries[i].text !== entries[i - 1].text) {
      deduped.push(entries[i]);
    }
  }

  return deduped;
}

/**
 * Sanitize lyric text: replace control chars and non-renderable glyphs
 * with spaces so we never show tofu (□) or ? as placeholders.
 */
export function sanitizeText(text) {
  if (!text) return text;
  let result = '';
  // Iterate by code point (for...of), not UTF-16 unit. Indexing text[i] and
  // skipping the trailing surrogate of a pair appended ONLY the low surrogate,
  // so every non-BMP character (emoji, rare CJK ext) came out as a lone
  // surrogate — the exact tofu this function exists to avoid.
  for (const ch of text) {
    const cp = ch.codePointAt(0);
    if (
      cp === undefined ||
      cp <= 0x08 ||                           // C0 controls (except \t=0x09, \n=0x0A, \r=0x0D)
      cp === 0x0B || cp === 0x0C ||           // VT, FF
      (cp >= 0x0E && cp <= 0x1F) ||           // rest of C0
      (cp >= 0x7F && cp <= 0x9F) ||           // DEL + C1 controls
      (cp >= 0x200B && cp <= 0x200F) ||       // zero-width space & joiners
      (cp >= 0x2028 && cp <= 0x202E) ||       // line/paragraph sep, bidi controls
      (cp >= 0x2060 && cp <= 0x206F) ||       // word joiner, invisible operators
      cp === 0xFEFF ||                        // BOM / zero-width no-break space
      cp === 0xFFFD                           // replacement character
    ) {
      result += ' ';
    } else {
      result += ch;
    }
  }
  return result;
}
