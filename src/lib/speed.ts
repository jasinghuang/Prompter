export const SPEED_MIN = 100;
export const SPEED_MAX = 700;

/** 预估口播时长（秒）= 可读字数 / 每分钟字数 * 60。 */
export function estimateDurationSeconds(charCount: number, wpn: number): number {
  if (wpn <= 0 || charCount <= 0) return 0;
  return (charCount / wpn) * 60;
}
