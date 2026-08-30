import { FONT_SIZE_MIN, FONT_SIZE_MAX } from '../types';

/**
 * 双指捏合换算字号：按间距比例缩放起始字号，按步进 2 取偶并夹在 [FONT_SIZE_MIN, FONT_SIZE_MAX]。
 * startDistance 为 0 时（两指重叠）返回起始字号。
 */
export function computePinchFontSize(currentDistance: number, startDistance: number, startFontSize: number): number {
  if (startDistance <= 0) return startFontSize;
  const raw = startFontSize * (currentDistance / startDistance);
  const stepped = Math.round(raw / 2) * 2;
  return Math.min(FONT_SIZE_MAX, Math.max(FONT_SIZE_MIN, stepped));
}
