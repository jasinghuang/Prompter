/**
 * 触觉反馈工具 —— 封装 navigator.vibrate()，带特性检测。
 *
 * 注意事项：
 * - 需要 HTTPS + 用户手势触发，普通 Safari 标签页不支持（iOS 16.4+ PWA 可用）
 * - 不支持时静默跳过，不影响功能逻辑
 */

/** 轻量确认（标记已拍摄等正向操作） */
const PATTERN_LIGHT: number[] = [50, 20, 50];

/** 较强确认（删除等不可逆操作） */
const PATTERN_STRONG: number[] = [100, 40, 100];

export function hapticLight() {
  try {
    if ('vibrate' in navigator) navigator.vibrate(PATTERN_LIGHT);
  } catch {
    /* noop */
  }
}

export function hapticStrong() {
  try {
    if ('vibrate' in navigator) navigator.vibrate(PATTERN_STRONG);
  } catch {
    /* noop */
  }
}
