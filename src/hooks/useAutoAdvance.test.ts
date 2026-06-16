import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { renderHook } from '@testing-library/react';
import { useAutoAdvance } from './useAutoAdvance';

// 手动 mock performance.now 与 requestAnimationFrame，精确按帧驱动，
// 避免 Vitest fake timers 对 rAF/performance.now 联动不稳定的问题。
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

/** 手动按帧推进：每帧推进 frameMs，触发该帧前入队的所有 rAF 回调。 */
function tickFrames(frames: number, frameMs: number) {
  for (let i = 0; i < frames; i++) {
    nowMs += frameMs;
    const queue = rafQueue.slice();
    rafQueue = [];
    queue.forEach((cb) => cb(nowMs));
  }
}

describe('useAutoAdvance', () => {
  it('running=false 时不推进', () => {
    const onAdvance = vi.fn();
    renderHook(() =>
      useAutoAdvance({ running: false, wpn: 160, enabled: true, onAdvance })
    );
    tickFrames(20, 50);
    expect(onAdvance).not.toHaveBeenCalled();
  });

  it('running=true 时按 WPN 推进', () => {
    const onAdvance = vi.fn();
    renderHook(() =>
      useAutoAdvance({ running: true, wpn: 160, enabled: true, onAdvance })
    );
    // 160 WPN → 375ms/字；16 帧 × 50ms = 800ms → 应推进约 2 字
    tickFrames(16, 50);
    const total = onAdvance.mock.calls.reduce((sum, [n]) => sum + n, 0);
    expect(total).toBeGreaterThanOrEqual(1);
  });

  it('enabled=false 时即使 running 也不推进', () => {
    const onAdvance = vi.fn();
    renderHook(() =>
      useAutoAdvance({ running: true, wpn: 160, enabled: false, onAdvance })
    );
    tickFrames(20, 50);
    expect(onAdvance).not.toHaveBeenCalled();
  });
});
