/**
 * 触觉反馈工具 —— 跨平台兼容方案。
 *
 * - Android：使用 navigator.vibrate() 标准振动 API
 * - iOS 18+（PWA）：使用 <input type="checkbox" switch> 的非标准 WebKit 触觉反馈
 *   参考：https://github.com/ionic-team/ionic-framework/issues/29942
 * - iOS 18 以下：不支持，静默跳过
 */

// ── Android: 标准振动 API ──────────────────────────────

/** 轻量确认（标记已拍摄等正向操作） */
const PATTERN_LIGHT: number[] = [50, 20, 50];

/** 较强确认（删除等不可逆操作） */
const PATTERN_STRONG: number[] = [100, 40, 100];

function vibrateAndroid(pattern: number[]) {
  try {
    if ('vibrate' in navigator) navigator.vibrate(pattern);
  } catch {
    /* noop */
  }
}

// ── iOS 18+: checkbox switch workaround ────────────────

let hapticSwitch: HTMLLabelElement | null = null;

/**
 * 懒创建隐藏的 <input type="checkbox" switch> + <label>，
 * 程序化触发 label.click() 让 WebKit 发出原生触觉反馈。
 */
function getIosHapticSwitch(): HTMLLabelElement | null {
  if (hapticSwitch) return hapticSwitch;
  try {
    const input = document.createElement('input');
    input.type = 'checkbox';
    // @ts-expect-error —— 非标准属性，仅 iOS 18+ WebKit 识别
    input.switch = true;
    input.style.cssText = 'position:absolute;width:0;height:0;opacity:0;pointer-events:none;';

    const label = document.createElement('label');
    label.style.cssText = 'position:absolute;width:0;height:0;opacity:0;pointer-events:none;';
    label.appendChild(input);

    document.body.appendChild(label);
    hapticSwitch = label;
    return hapticSwitch;
  } catch {
    return null;
  }
}

function vibrateIos() {
  const label = getIosHapticSwitch();
  if (!label) return;
  try {
    label.click();
  } catch {
    /* noop */
  }
}

// ── 平台检测 + 统一入口 ───────────────────────────────

const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent);

export function hapticLight() {
  if (isIOS) vibrateIos();
  else vibrateAndroid(PATTERN_LIGHT);
}

export function hapticStrong() {
  if (isIOS) vibrateIos();
  else vibrateAndroid(PATTERN_STRONG);
}
