import { describe, it, expect, vi } from 'vitest';
import { renderHook } from '@testing-library/react';
import { usePauseOnKeyword } from './usePauseOnKeyword';

describe('usePauseOnKeyword', () => {
  it('播放中 activeIndex 移过关键词 → onPause 命中', () => {
    const onPause = vi.fn();
    const { rerender } = renderHook(
      ({ idx }) => usePauseOnKeyword({ isPlaying: true, activeIndex: idx, content: 'hello world test', keyword: 'world', onPause }),
      { initialProps: { idx: 0 } },
    );
    rerender({ idx: 11 }); // 移到 'world' 之后
    expect(onPause).toHaveBeenCalledTimes(1);
    expect(onPause).toHaveBeenCalledWith(expect.stringContaining('world'));
  });

  it('未播放不触发', () => {
    const onPause = vi.fn();
    renderHook(() => usePauseOnKeyword({ isPlaying: false, activeIndex: 11, content: 'hello world', keyword: 'world', onPause }));
    expect(onPause).not.toHaveBeenCalled();
  });

  it('关键词为空不触发', () => {
    const onPause = vi.fn();
    renderHook(() => usePauseOnKeyword({ isPlaying: true, activeIndex: 5, content: 'hello world', keyword: '', onPause }));
    expect(onPause).not.toHaveBeenCalled();
  });

  it('关键词变化后重置，新关键词可再次命中', () => {
    const onPause = vi.fn();
    const { rerender } = renderHook(
      ({ kw }) => usePauseOnKeyword({ isPlaying: true, activeIndex: 10, content: 'aa bb cc dd ee', keyword: kw, onPause }),
      { initialProps: { kw: 'bb' } },
    );
    expect(onPause).toHaveBeenCalledTimes(1); // 命中 bb
    rerender({ kw: 'cc' }); // 关键词变化 → 重置 → 命中 cc
    expect(onPause).toHaveBeenCalledTimes(2);
  });
});
