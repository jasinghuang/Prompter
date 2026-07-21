import { describe, it, expect } from 'vitest';
import { shouldShowInstallPrompt } from './pwa';

describe('shouldShowInstallPrompt', () => {
  it('已 standalone 时不显示', () => {
    expect(
      shouldShowInstallPrompt({ standalone: true, dismissed: false, isIOS: true, hasBeforeInstallPrompt: false })
    ).toBe(false);
  });

  it('已关闭时不显示', () => {
    expect(
      shouldShowInstallPrompt({ standalone: false, dismissed: true, isIOS: true, hasBeforeInstallPrompt: false })
    ).toBe(false);
  });

  it('iOS + 未关闭 + 非 standalone 时显示', () => {
    expect(
      shouldShowInstallPrompt({ standalone: false, dismissed: false, isIOS: true, hasBeforeInstallPrompt: false })
    ).toBe(true);
  });

  it('Android 有 beforeinstallprompt 时显示', () => {
    expect(
      shouldShowInstallPrompt({ standalone: false, dismissed: false, isIOS: false, hasBeforeInstallPrompt: true })
    ).toBe(true);
  });

  it('桌面浏览器不显示', () => {
    expect(
      shouldShowInstallPrompt({ standalone: false, dismissed: false, isIOS: false, hasBeforeInstallPrompt: false })
    ).toBe(false);
  });
});
