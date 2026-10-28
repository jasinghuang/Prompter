import { describe, it, expect, vi, beforeAll, afterAll } from 'vitest';
import { renderHook } from '@testing-library/react';
import { useMediaSession } from './useMediaSession';

// jsdom 无 mediaSession：注入 mock 实现
type Handler = (() => void) | null;
const handlers = new Map<string, Handler>();
const setActionHandler = vi.fn((action: string, h: Handler) => handlers.set(action, h));
const metadataAssign = vi.fn();

const mediaSessionMock = {
  setActionHandler,
  playbackState: 'none' as string,
  set metadata(m: unknown) { metadataAssign(m); },
  get metadata() { return undefined; },
};

class MediaMetadataStub {
  title: string;
  artist: string;
  constructor(init: { title: string; artist?: string }) {
    this.title = init.title;
    this.artist = init.artist ?? '';
  }
}

beforeAll(() => {
  Object.defineProperty(navigator, 'mediaSession', { value: mediaSessionMock, configurable: true });
  (globalThis as unknown as { MediaMetadata: unknown }).MediaMetadata = MediaMetadataStub;
});
afterAll(() => {
  delete (globalThis as unknown as { MediaMetadata?: unknown }).MediaMetadata;
});

function fire(action: string) {
  const h = handlers.get(action);
  if (!h) throw new Error(`handler ${action} 未注册`);
  h();
}

describe('useMediaSession', () => {
  it('注册 play/pause/nexttrack/previoustrack；play 与 pause 都映射到切换播放', () => {
    const onTogglePlay = vi.fn();
    renderHook(() => useMediaSession({ title: '测试稿', isPlaying: false, onTogglePlay, onSpeedUp: vi.fn(), onSpeedDown: vi.fn() }));
    fire('play');
    fire('pause');
    expect(onTogglePlay).toHaveBeenCalledTimes(2);
  });

  it('双击(nexttrack)→加速、三击(previoustrack)→减速', () => {
    const onSpeedUp = vi.fn();
    const onSpeedDown = vi.fn();
    renderHook(() => useMediaSession({ title: '测试稿', isPlaying: false, onTogglePlay: vi.fn(), onSpeedUp, onSpeedDown }));
    fire('nexttrack');
    expect(onSpeedUp).toHaveBeenCalledTimes(1);
    fire('previoustrack');
    expect(onSpeedDown).toHaveBeenCalledTimes(1);
  });

  it('metadata 写入稿件标题；isPlaying 同步 playbackState', () => {
    const { rerender } = renderHook(({ playing }: { playing: boolean }) =>
      useMediaSession({ title: '广发证券稿', isPlaying: playing, onTogglePlay: vi.fn(), onSpeedUp: vi.fn(), onSpeedDown: vi.fn() }),
      { initialProps: { playing: false } },
    );
    expect(metadataAssign).toHaveBeenCalled();
    expect(mediaSessionMock.playbackState).toBe('paused');
    rerender({ playing: true });
    expect(mediaSessionMock.playbackState).toBe('playing');
  });

  it('卸载时注销全部 handler', () => {
    const { unmount } = renderHook(() => useMediaSession({ title: 't', isPlaying: false, onTogglePlay: vi.fn(), onSpeedUp: vi.fn(), onSpeedDown: vi.fn() }));
    unmount();
    expect(setActionHandler).toHaveBeenCalledWith('play', null);
    expect(setActionHandler).toHaveBeenCalledWith('pause', null);
    expect(setActionHandler).toHaveBeenCalledWith('nexttrack', null);
    expect(setActionHandler).toHaveBeenCalledWith('previoustrack', null);
  });
});
