import { describe, it, expect, vi } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { useSwipeAction } from './useSwipeAction';

// 构造最小 TouchEvent（只用到 touches[0].clientX/Y）
const touch = (x: number, y: number) => ({ touches: [{ clientX: x, clientY: y }] } as unknown as React.TouchEvent);

describe('useSwipeAction', () => {
  it('初始 offset=0、shaking=false', () => {
    const { result } = renderHook(() => useSwipeAction({ onCommitRight: vi.fn(), onCommitLeft: vi.fn() }));
    expect(result.current.offset).toBe(0);
    expect(result.current.shaking).toBe(false);
  });

  it('左滑越过删除阈值（<= -130）→ 触发震动 + onCommitLeft', () => {
    const onCommitLeft = vi.fn();
    const { result } = renderHook(() => useSwipeAction({ onCommitRight: vi.fn(), onCommitLeft }));
    act(() => {
      result.current.bind.onTouchStart(touch(160, 50));
      result.current.bind.onTouchMove(touch(10, 50)); // dx = -150
    });
    expect(result.current.shaking).toBe(true);
    act(() => result.current.bind.onTouchEnd());
    expect(onCommitLeft).toHaveBeenCalledTimes(1);
  });

  it('左滑未越过阈值 → 回弹、不 commit', () => {
    const onCommitLeft = vi.fn();
    const { result } = renderHook(() => useSwipeAction({ onCommitRight: vi.fn(), onCommitLeft }));
    act(() => {
      result.current.bind.onTouchStart(touch(100, 50));
      result.current.bind.onTouchMove(touch(30, 50)); // dx = -70
    });
    expect(result.current.shaking).toBe(false);
    act(() => result.current.bind.onTouchEnd());
    expect(onCommitLeft).not.toHaveBeenCalled();
    expect(result.current.offset).toBe(0);
  });

  it('右滑越过标记阈值（> 40）→ onCommitRight', () => {
    const onCommitRight = vi.fn();
    const { result } = renderHook(() => useSwipeAction({ onCommitRight, onCommitLeft: vi.fn() }));
    act(() => {
      result.current.bind.onTouchStart(touch(50, 50));
      result.current.bind.onTouchMove(touch(120, 50)); // dx = 70
    });
    act(() => result.current.bind.onTouchEnd());
    expect(onCommitRight).toHaveBeenCalledTimes(1);
  });

  it('onTouchCancel 只回弹、不 commit（系统中断）', () => {
    const onCommitLeft = vi.fn();
    const { result } = renderHook(() => useSwipeAction({ onCommitRight: vi.fn(), onCommitLeft }));
    act(() => {
      result.current.bind.onTouchStart(touch(160, 50));
      result.current.bind.onTouchMove(touch(10, 50)); // dx = -150 已越过
    });
    expect(result.current.shaking).toBe(true);
    act(() => result.current.bind.onTouchCancel());
    expect(onCommitLeft).not.toHaveBeenCalled();
    expect(result.current.offset).toBe(0);
  });

  it('纵向滑动被忽略（不阻塞页面滚动）', () => {
    const { result } = renderHook(() => useSwipeAction({ onCommitRight: vi.fn(), onCommitLeft: vi.fn() }));
    act(() => {
      result.current.bind.onTouchStart(touch(50, 50));
      result.current.bind.onTouchMove(touch(50, 120)); // dy=70 > dx=0
    });
    expect(result.current.offset).toBe(0);
  });
});
