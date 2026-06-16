import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { useTimer } from './useTimer';

beforeEach(() => vi.useFakeTimers());
afterEach(() => vi.useRealTimers());

describe('useTimer', () => {
  it('初始 elapsed 为 0', () => {
    const { result } = renderHook(() => useTimer());
    expect(result.current.elapsedSeconds).toBe(0);
  });

  it('start 后随时间累加，stop 后停止', () => {
    const { result } = renderHook(() => useTimer());
    act(() => result.current.start());
    act(() => vi.advanceTimersByTime(3200));
    expect(result.current.elapsedSeconds).toBe(3);
    act(() => result.current.stop());
    act(() => vi.advanceTimersByTime(5000));
    expect(result.current.elapsedSeconds).toBe(3);
  });

  it('reset 归零并停止', () => {
    const { result } = renderHook(() => useTimer());
    act(() => result.current.start());
    act(() => vi.advanceTimersByTime(5000));
    act(() => result.current.reset());
    expect(result.current.elapsedSeconds).toBe(0);
    act(() => vi.advanceTimersByTime(5000));
    expect(result.current.elapsedSeconds).toBe(0);
  });

  it('卸载时清理定时器', () => {
    const { result, unmount } = renderHook(() => useTimer());
    act(() => result.current.start());
    unmount();
    expect(() => act(() => vi.advanceTimersByTime(10000))).not.toThrow();
  });
});
