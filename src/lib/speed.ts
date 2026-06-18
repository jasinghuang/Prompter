export const SPEED_PRESETS = [
  { id: 'slow', name: '龟速', wpn: 80 },
  { id: 'normal', name: '标准', wpn: 160 },
  { id: 'fast', name: '快语', wpn: 240 },
  { id: 'very-fast', name: '极速', wpn: 320 },
] as const;

export const SPEED_MIN = 30;
export const SPEED_MAX = 600;

/** 每推进一个字符需要的毫秒数。 */
export function msPerChar(wpn: number): number {
  if (wpn <= 0) return Infinity;
  return 60000 / wpn;
}

/** 预估总时长（秒）= 可读字数 / WPN * 60。 */
export function estimateDurationSeconds(charCount: number, wpn: number): number {
  if (wpn <= 0 || charCount <= 0) return 0;
  return (charCount / wpn) * 60;
}

/**
 * 自动推进的单步计算（纯函数）。
 * 给定当前累积量 accumulatorMs 与本帧增量 deltaMs，
 * 返回新的累积量（扣除已消耗）与本帧应推进的字符数。
 */
export function stepAutoAdvance(
  accumulatorMs: number,
  deltaMs: number,
  wpn: number
): { accumulator: number; advance: number } {
  const next = accumulatorMs + deltaMs;
  const mpc = msPerChar(wpn);
  if (mpc === Infinity || next < mpc) return { accumulator: next, advance: 0 };
  const advance = Math.floor(next / mpc);
  return { accumulator: next - advance * mpc, advance };
}
