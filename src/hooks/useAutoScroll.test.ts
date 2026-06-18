import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { renderHook } from '@testing-library/react';
import { useAutoScroll } from './useAutoScroll';

let nowMs = 0;
let rafQueue: FrameRequestCallback[] = [];

beforeEach(() => {
  nowMs = 0;
  rafQueue = [];
  vi.stubGlobal('performance', { now: () => nowMs });
  vi.stubGlobal('requestAnimationFrame', (cb: FrameRequestCallback) => {
    rafQueue.push(cb);
    return rafQueue.length;
  });
  vi.stubGlobal('cancelAnimationFrame', () => {});
});
afterEach(() => vi.unstubAllGlobals());

function tickFrames(frames: number, frameMs: number) {
  for (let i = 0; i < frames; i++) {
    nowMs += frameMs;
    const queue = rafQueue.slice();
    rafQueue = [];
    queue.forEach((cb) => cb(nowMs));
  }
}

function makeContent() {
  return { style: { transform: '' } } as unknown as HTMLElement;
}

describe('useAutoScroll', () => {
  it('running=false 时不位移', () => {
    const c = makeContent();
    renderHook(() =>
      useAutoScroll({ running: false, pxPerSec: 100, getContent: () => c, getMaxOffset: () => 1000, onTick: () => {}, onReachEnd: () => {} })
    );
    tickFrames(20, 50);
    expect(c.style.transform).toBe('');
  });

  it('running=true 时按 pxPerSec 连续位移（亚像素）', () => {
    const c = makeContent();
    renderHook(() =>
      useAutoScroll({ running: true, pxPerSec: 100, getContent: () => c, getMaxOffset: () => 1000, onTick: () => {}, onReachEnd: () => {} })
    );
    tickFrames(10, 50); // 500ms × 100px/s = 50px
    expect(c.style.transform).toBe('translate3d(0, -50px, 0)');
  });

  it('支持亚像素位移（低速也能平滑推进）', () => {
    const c = makeContent();
    renderHook(() =>
      useAutoScroll({ running: true, pxPerSec: 10, getContent: () => c, getMaxOffset: () => 1000, onTick: () => {}, onReachEnd: () => {} })
    );
    tickFrames(1, 16); // 16ms × 10px/s = 0.16px
    expect(c.style.transform).toBe('translate3d(0, -0.16px, 0)');
  });

  it('到达 maxOffset 触发 onReachEnd 并夹到 max', () => {
    const onReachEnd = vi.fn();
    const c = makeContent();
    renderHook(() =>
      useAutoScroll({ running: true, pxPerSec: 1000, getContent: () => c, getMaxOffset: () => 100, onTick: () => {}, onReachEnd })
    );
    tickFrames(10, 50);
    expect(c.style.transform).toBe('translate3d(0, -100px, 0)');
    expect(onReachEnd).toHaveBeenCalled();
  });

  it('onTick 回调最新 offset', () => {
    const onTick = vi.fn();
    const c = makeContent();
    renderHook(() =>
      useAutoScroll({ running: true, pxPerSec: 100, getContent: () => c, getMaxOffset: () => 1000, onTick, onReachEnd: () => {} })
    );
    tickFrames(10, 50);
    expect(onTick).toHaveBeenLastCalledWith(50);
  });
});
