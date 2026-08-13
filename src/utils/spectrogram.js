// Shift spectrogram history up by one row and append the new frame.
// Returns the buffer (same instance when possible) — the caller keeps a
// module-level reference across frames so history survives remounts.
export function pushSpectrogramFrame(buffer, numRows, freqData) {
  if (!buffer || buffer.length !== numRows || buffer[0].length !== freqData.length) {
    const oldLen = buffer ? buffer.length : 0;
    const next = new Array(numRows);
    const diff = numRows - oldLen;
    for (let i = 0; i < numRows; i++) {
      next[i] = new Uint8Array(freqData.length);
      const src = buffer && i >= diff ? buffer[i - diff] : null;
      if (src) next[i].set(src);
    }
    buffer = next;
  }
  // Byte-copy each row into the one above. Array.prototype.copyWithin would
  // move references instead, aliasing rows onto the same Uint8Array and
  // collapsing the whole history onto the latest frame.
  for (let i = 0; i < numRows - 1; i++) {
    buffer[i].set(buffer[i + 1]);
  }
  buffer[numRows - 1].set(freqData);
  return buffer;
}
