export const EQ_BANDS = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];
export const EQ_MIN = -12;
export const EQ_MAX = 12;
export const EQ_STEP = 0.5;

export const EQ_PRESETS = [
  { name: '平坦', values: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0] },
  { name: '低音增强', values: [6, 6, 5, 3.5, 2, 0, 0, 0, 0, 0] },
  { name: '人声清晰', values: [0, 0, 0, 0, 0, 3, 3, 3, 2, 0] },
  { name: '古典', values: [3, 3, 2, 0, 0, 0, 0, 1.5, 2, 3] },
  { name: '摇滚', values: [5, 5, 4, 2, 0, 0, 1, 3, 4.5, 5] },
  { name: '流行', values: [0.5, 1, 1.5, 2.5, 3, 3, 2.5, 1.5, 1, 0.5] },
];

export function sliderFrac(value, min = EQ_MIN, max = EQ_MAX) {
  return (value - min) / (max - min);
}
