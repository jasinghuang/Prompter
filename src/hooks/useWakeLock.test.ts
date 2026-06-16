import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { useWakeLock } from './useWakeLock';

type WL = { released: Promise<void>; release: () => Promise<void> };

beforeEach(() => {
  // 默认无 wakeLock
  // @ts-expect-error delete if present
  delete navigator.wakeLock;
});
afterEach(() => vi.restoreAllMocks());

describe('useWakeLock', () => {
  it('不支持时 request 返回的 Promise reject', async () => {
    const { result } = renderHook(() => useWakeLock());
    await expect(result.current.request()).rejects.toBeDefined();
  });

  it('支持时 request 调用 navigator.wakeLock.request', async () => {
    const release = vi.fn().mockResolvedValue(undefined);
    const request = vi.fn().mockResolvedValue({ release } as unknown as WL);
    Object.defineProperty(navigator, 'wakeLock', { value: { request }, configurable: true });
    const { result } = renderHook(() => useWakeLock());
    await act(() => result.current.request());
    expect(request).toHaveBeenCalledWith('screen');
  });

  it('release 幂等（无 active 时不报错）', async () => {
    const { result } = renderHook(() => useWakeLock());
    await expect(result.current.release()).resolves.toBeUndefined();
  });
});
