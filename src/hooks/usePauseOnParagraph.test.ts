import { describe, it, expect, vi } from 'vitest';
import { renderHook } from '@testing-library/react';
import { usePauseOnParagraph } from './usePauseOnParagraph';

describe('usePauseOnParagraph', () => {
  it('播放到段落起点 → onPause', () => {
    const onPause = vi.fn();
    const starts = new Set([5]);
    const { rerender } = renderHook(
      ({ idx }) => usePauseOnParagraph({ isPlaying: true, activeIndex: idx, paragraphStarts: starts, enabled: true, onPause }),
      { initialProps: { idx: 0 } },
    );
    rerender({ idx: 5 });
    expect(onPause).toHaveBeenCalledWith('已暂停：段落分隔');
  });

  it('未启用（enabled=false）不触发', () => {
    const onPause = vi.fn();
    renderHook(() => usePauseOnParagraph({ isPlaying: true, activeIndex: 5, paragraphStarts: new Set([5]), enabled: false, onPause }));
    expect(onPause).not.toHaveBeenCalled();
  });

  it('未播放不触发', () => {
    const onPause = vi.fn();
    renderHook(() => usePauseOnParagraph({ isPlaying: false, activeIndex: 5, paragraphStarts: new Set([5]), enabled: true, onPause }));
    expect(onPause).not.toHaveBeenCalled();
  });

  it('同一段落起点只触发一次', () => {
    const onPause = vi.fn();
    const starts = new Set([5]);
    const { rerender } = renderHook(
      ({ idx }) => usePauseOnParagraph({ isPlaying: true, activeIndex: idx, paragraphStarts: starts, enabled: true, onPause }),
      { initialProps: { idx: 5 } },
    );
    expect(onPause).toHaveBeenCalledTimes(1); // idx=5 初次命中
    rerender({ idx: 6 }); // 离开起点
    rerender({ idx: 5 }); // 回到同一起点
    expect(onPause).toHaveBeenCalledTimes(1); // 不再触发
  });
});
