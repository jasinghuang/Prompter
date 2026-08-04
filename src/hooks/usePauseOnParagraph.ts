import { useEffect, useRef } from 'react';

interface Options {
  isPlaying: boolean;
  activeIndex: number;
  paragraphStarts: Set<number>;
  enabled: boolean;
  /** 命中段落起点时回调（通常: 停止播放 + 提示） */
  onPause: (msg: string) => void;
}

/**
 * 自动暂停：播放到段落起点时暂停（CF10，从 Teleprompter 抽出）。
 * 同一段落起点只触发一次（用 pausedAtRef 记录已暂停的位置）。
 */
export function usePauseOnParagraph({ isPlaying, activeIndex, paragraphStarts, enabled, onPause }: Options) {
  const pausedAtRef = useRef(-1);
  const onPauseRef = useRef(onPause);
  onPauseRef.current = onPause;

  useEffect(() => {
    if (!isPlaying || !enabled) return;
    if (paragraphStarts.has(activeIndex) && pausedAtRef.current !== activeIndex) {
      pausedAtRef.current = activeIndex;
      onPauseRef.current('已暂停：段落分隔');
    }
  }, [activeIndex, isPlaying, enabled, paragraphStarts]);
}
