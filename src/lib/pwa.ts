/** localStorage key：用户已关闭「添加到主屏幕」引导 */
export const ATTS_DISMISSED_KEY = 'prompter_aths_dismissed';

export interface InstallPromptState {
  standalone: boolean;
  dismissed: boolean;
  isIOS: boolean;
  hasBeforeInstallPrompt: boolean;
}

/**
 * 是否显示「添加到主屏幕」引导：
 * 已 standalone / 已关闭 → 否；iOS 或有 beforeinstallprompt → 是；其余 → 否。
 */
export function shouldShowInstallPrompt(state: InstallPromptState): boolean {
  if (state.standalone || state.dismissed) return false;
  return state.isIOS || state.hasBeforeInstallPrompt;
}

/** 当前是否 standalone（主屏全屏）模式 */
export function detectStandalone(): boolean {
  if (typeof window === 'undefined') return false;
  const nav = window.navigator as Navigator & { standalone?: boolean };
  return nav.standalone === true || window.matchMedia('(display-mode: standalone)').matches;
}

/** 是否 iOS Safari（需手动引导，无 beforeinstallprompt） */
export function detectIOS(): boolean {
  if (typeof navigator === 'undefined') return false;
  const ua = navigator.userAgent || '';
  return /iPad|iPhone|iPod/.test(ua) || (ua.includes('Macintosh') && 'ontouchend' in document);
}

export interface SolidGlassState {
  isIOS: boolean;
  standalone: boolean;
}

/**
 * iOS standalone（PWA）下是否降级为无模糊玻璃：
 * WebKit 的 backdrop-filter 在 iOS standalone 有已知渲染 bug——
 * 静止画面出现花屏/残影，旋转屏幕重建图层后才消失。
 * 该环境改用纯半透明底（html.glass-solid），其余环境保留毛玻璃。
 */
export function shouldUseSolidGlass(state: SolidGlassState): boolean {
  return state.isIOS && state.standalone;
}
