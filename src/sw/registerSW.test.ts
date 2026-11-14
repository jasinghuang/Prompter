import { describe, it, expect, vi } from 'vitest';
import { registerSW } from './registerSW';

describe('registerSW', () => {
  it('不支持 serviceWorker 时静默跳过', async () => {
    // jsdom 默认不提供 navigator.serviceWorker
    await expect(registerSW('/Prompter/sw.js')).resolves.toBeUndefined();
  });

  it('支持时调用 register 并传入 URL', async () => {
    const register = vi.fn().mockResolvedValue({});
    Object.defineProperty(navigator, 'serviceWorker', {
      value: { register },
      configurable: true,
    });
    await registerSW('/Prompter/sw.js');
    expect(register).toHaveBeenCalledWith('/Prompter/sw.js');
  });

  it('register 抛错时不传播', async () => {
    const register = vi.fn().mockRejectedValue(new Error('fail'));
    Object.defineProperty(navigator, 'serviceWorker', {
      value: { register },
      configurable: true,
    });
    await expect(registerSW('/Prompter/sw.js')).resolves.toBeUndefined();
  });
});
