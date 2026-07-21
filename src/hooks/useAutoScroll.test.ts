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

function makeViewport() {
  const el = { scrollTop: 0, scrollHeight: 2000, clientHeight: 800 } as unknown as HTMLElement;
  return el;
}

describe('useAutoScroll', () => {
  it('running=false 时不位移', () => {
    const vp = makeViewport();
    renderHook(() =>
      useAutoScroll({ running: false, pxPerSec: 100, getViewport: () => vp, getMaxOffset: () => 1000, onTick: () => {}, onReachEnd: () => {} })
    );
    tickFrames(20, 50);
    expect(vp.scrollTop).toBe(0);
  });

  it('running=true 时按 pxPerSec 连续位移', () => {
    const vp = makeViewport();
    renderHook(() =>
      useAutoScroll({ running: true, pxPerSec: 100, getViewport: () => vp, getMaxOffset: () => 1000, onTick: () => {}, onReachEnd: () => {} })
    );
    tickFrames(10, 50); // 500ms × 100px/s = 50px
    expect(vp.scrollTop).toBe(50);
  });

  it('支持亚像素位移', () => {
    const vp = makeViewport();
    renderHook(() =>
      useAutoScroll({ running: true, pxPerSec: 10, getViewport: () => vp, getMaxOffset: () => 1000, onTick: () => {}, onReachEnd: () => {} })
    );
    tickFrames(1, 16); // 16ms × 10px/s = 0.16px
    expect(vp.scrollTop).toBeCloseTo(0.16, 2);
  });

  it('到达 maxOffset 触发 onReachEnd 并夹到 max', () => {
    const onReachEnd = vi.fn();
    const vp = makeViewport();
    renderHook(() =>
      useAutoScroll({ running: true, pxPerSec: 1000, getViewport: () => vp, getMaxOffset: () => 100, onTick: () => {}, onReachEnd })
    );
    tickFrames(10, 50);
    expect(vp.scrollTop).toBe(100);
    expect(onReachEnd).toHaveBeenCalled();
  });

  it('onTick 回调最新 scrollTop', () => {
    const onTick = vi.fn();
    const vp = makeViewport();
    renderHook(() =>
      useAutoScroll({ running: true, pxPerSec: 100, getViewport: () => vp, getMaxOffset: () => 1000, onTick, onReachEnd: () => {} })
    );
    tickFrames(10, 50);
    expect(onTick).toHaveBeenLastCalledWith(50);
  });
});
