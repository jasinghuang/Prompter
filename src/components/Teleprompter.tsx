import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { ChevronLeft, ChevronRight, Edit3 } from 'lucide-react';
import { Script, TeleprompterSettings } from '../types';
import { countReadableChars } from '../lib/tokens';
import { estimateDurationSeconds, SPEED_MIN, SPEED_MAX } from '../lib/speed';
import { formatTime } from '../lib/format';
import { useTimer } from '../hooks/useTimer';
import { useAutoScroll } from '../hooks/useAutoScroll';
import { useWakeLock } from '../hooks/useWakeLock';
import { ScriptText } from './ScriptText';
import { Controls } from './Controls';

interface Props {
  script: Script;
  settings: TeleprompterSettings;
  index: number;
  onIndexChange: (i: number) => void;
  onChangeSettings: (patch: Partial<TeleprompterSettings>) => void;
  onBack: () => void;
  onEdit: () => void;
}

const TRANSFORM = (offset: number) => `translate3d(0, ${-offset}px, 0)`;

export function Teleprompter({ script, settings, index, onIndexChange, onChangeSettings, onBack, onEdit }: Props) {
  const [isPlaying, setIsPlaying] = useState(false);
  const [wakeLockFailed, setWakeLockFailed] = useState(false);
  const [widthTick, setWidthTick] = useState(0);
  const [activeIndex, setActiveIndex] = useState(index);
  const activeIndexRef = useRef(index);
  const [maxOffset, setMaxOffset] = useState(0);
  const maxOffsetRef = useRef(0);

  const viewportRef = useRef<HTMLDivElement>(null);
  const contentRef = useRef<HTMLDivElement>(null);
  const spansRef = useRef<HTMLElement[]>([]);
  const dragRef = useRef<{ y: number; offset: number; moved: boolean; id: number } | null>(null);

  const charCount = useMemo(() => countReadableChars(script.content), [script.content]);
  const estimatedTotal = estimateDurationSeconds(charCount, settings.scrollSpeed);

  const { elapsedSeconds, start: startTimer, stop: stopTimer } = useTimer();
  const { request, release } = useWakeLock();

  const applyOffset = useCallback((offset: number) => {
    const ct = contentRef.current;
    if (ct) ct.style.transform = TRANSFORM(offset);
  }, []);

  // 由位移反推中线对应的字（跨字才 setState）
  const computeActive = useCallback((offset: number) => {
    const vp = viewportRef.current;
    if (!vp) return;
    const mid = offset + vp.clientHeight / 2;
    const spans = spansRef.current;
    let idx = -1;
    for (const s of spans) {
      if (s.offsetTop + s.offsetHeight / 2 >= mid) {
        idx = Number(s.dataset.idx);
        break;
      }
    }
    if (idx === -1 && spans.length) idx = Number(spans[spans.length - 1].dataset.idx);
    if (idx >= 0 && idx !== activeIndexRef.current) {
      activeIndexRef.current = idx;
      setActiveIndex(idx);
    }
  }, []);

  // 测量 maxOffset + 缓存 spans + 重新定位到当前字
  useLayoutEffect(() => {
    const vp = viewportRef.current;
    const ct = contentRef.current;
    if (!vp || !ct) return;
    const measure = () => {
      spansRef.current = Array.from(ct.querySelectorAll<HTMLElement>('span[data-idx]'));
      const max = Math.max(0, ct.scrollHeight - vp.clientHeight);
      maxOffsetRef.current = max;
      setMaxOffset(max);
      const target = spansRef.current.find((s) => Number(s.dataset.idx) === activeIndexRef.current);
      if (target) {
        const off = Math.max(0, target.offsetTop - vp.clientHeight / 2 + target.offsetHeight / 2);
        offsetRef.current = off;
        ct.style.transform = TRANSFORM(off);
      }
    };
    measure();
    if (typeof ResizeObserver !== 'undefined') {
      const ro = new ResizeObserver(measure);
      ro.observe(ct);
      ro.observe(vp);
      return () => ro.disconnect();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [script.content, settings.fontSize, settings.letterSpacing, settings.lineHeight, settings.horizontalPadding, widthTick]);

  // 像素速度
  const pxPerSec = charCount > 0 && maxOffset > 0 ? (maxOffset / charCount) * (settings.scrollSpeed / 60) : 0;

  const getContent = useCallback(() => contentRef.current, []);
  const getMaxOffset = useCallback(() => maxOffsetRef.current, []);

  const offsetRef = useAutoScroll({
    running: isPlaying,
    pxPerSec,
    getContent,
    getMaxOffset,
    onTick: computeActive,
    onReachEnd: () => setIsPlaying(false),
  });

  // 宽度变化触发重测
  useEffect(() => {
    const check = () => setWidthTick((t) => t + 1);
    check();
    window.addEventListener('resize', check);
    return () => window.removeEventListener('resize', check);
  }, []);

  // 把第 i 个字滚到中线
  const scrollToIndex = useCallback((i: number) => {
    const vp = viewportRef.current;
    const ct = contentRef.current;
    if (!vp || !ct) return;
    const target = spansRef.current.find((s) => Number(s.dataset.idx) === i);
    if (target) {
      const off = Math.max(0, target.offsetTop - vp.clientHeight / 2 + target.offsetHeight / 2);
      offsetRef.current = off;
      ct.style.transform = TRANSFORM(off);
    }
    activeIndexRef.current = i;
    setActiveIndex(i);
  }, [offsetRef]);

  // 外部 index 变化（编辑返回 / 首次进入）
  useEffect(() => {
    scrollToIndex(index);
  }, [index, scrollToIndex]);

  // 播放/暂停：计时器 + Wake Lock
  useEffect(() => {
    if (isPlaying) {
      startTimer();
      request().catch(() => setWakeLockFailed(true));
    } else {
      stopTimer();
      release();
    }
    return () => {
      release();
    };
  }, [isPlaying]); // eslint-disable-line react-hooks/exhaustive-deps

  // 点击按钮后立即失焦
  useEffect(() => {
    const onClick = (e: MouseEvent) => {
      const btn = (e.target as HTMLElement | null)?.closest('button');
      if (btn) btn.blur();
    };
    window.addEventListener('click', onClick, true);
    return () => window.removeEventListener('click', onClick, true);
  }, []);

  // 键盘快捷键：空格播放/暂停；↑/↓ 调速度
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.code === 'Space') {
        if (e.repeat) return;
        e.preventDefault();
        setIsPlaying((p) => !p);
        return;
      }
      if (e.code === 'ArrowUp' || e.code === 'ArrowDown') {
        const t = e.target as HTMLElement | null;
        if (t && t.tagName === 'INPUT') return;
        e.preventDefault();
        const step = e.shiftKey ? 5 : 20;
        const delta = (e.code === 'ArrowUp' ? 1 : -1) * step;
        const next = Math.min(SPEED_MAX, Math.max(SPEED_MIN, settings.scrollSpeed + delta));
        onChangeSettings({ scrollSpeed: next });
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onChangeSettings, settings.scrollSpeed]);

  const seekToIndex = useCallback((i: number) => {
    const len = script.content.length;
    scrollToIndex(Math.min(Math.max(0, i), Math.max(0, len - 1)));
  }, [script.content.length, scrollToIndex]);

  // 进度条跳转
  const seekToFraction = (frac: number) => {
    const max = maxOffsetRef.current;
    const off = Math.max(0, Math.min(max, frac * max));
    offsetRef.current = off;
    applyOffset(off);
    computeActive(off);
  };

  // 统一 pointer 交互：拖拽自由滚动 / 单击播放暂停
  const onPointerDown = useCallback((e: React.PointerEvent) => {
    dragRef.current = { y: e.clientY, offset: offsetRef.current, moved: false, id: e.pointerId };
    try {
      (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
    } catch {
      /* ignore */
    }
  }, [offsetRef]);

  const onPointerMove = useCallback((e: React.PointerEvent) => {
    const d = dragRef.current;
    if (!d || d.id !== e.pointerId) return;
    const dy = e.clientY - d.y;
    if (!d.moved && Math.abs(dy) < 6) return;
    d.moved = true;
    const max = maxOffsetRef.current;
    const next = Math.max(0, Math.min(max, d.offset - dy));
    offsetRef.current = next;
    applyOffset(next);
  }, [applyOffset, offsetRef]);

  const onPointerUp = useCallback((e: React.PointerEvent) => {
    const d = dragRef.current;
    dragRef.current = null;
    if (!d || d.id !== e.pointerId) return;
    if (!d.moved) {
      // 单击 → 切换播放/暂停
      setIsPlaying((p) => !p);
    } else {
      computeActive(offsetRef.current);
    }
  }, [computeActive, offsetRef]);

  const handleBack = () => {
    onIndexChange(activeIndexRef.current);
    onBack();
  };
  const handleEdit = () => {
    onIndexChange(activeIndexRef.current);
    onEdit();
  };

  const progress = maxOffset > 0 ? offsetRef.current / maxOffset : 0;
  const pad = `${settings.horizontalPadding}%`;

  return (
    <div className="relative h-[100dvh] w-screen overflow-hidden bg-black">
      {/* 顶部栏 */}
      <div className="absolute inset-x-0 top-0 z-50 flex items-center justify-between bg-gradient-to-b from-black/90 to-transparent px-3 pb-3 pt-[calc(0.75rem+env(safe-area-inset-top))]">
        <div className="flex items-center gap-2">
          <button onClick={handleBack} className="rounded-full bg-neutral-900/60 p-2.5 text-neutral-400 hover:text-white" aria-label="返回">
            <ChevronLeft size={18} />
          </button>
          <div className="flex items-center gap-1.5 rounded-lg border border-neutral-800 bg-neutral-900/60 px-2.5 py-1">
            <span className="h-1.5 w-1.5 rounded-full bg-red-500" style={{ boxShadow: isPlaying ? '0 0 6px #ef4444' : 'none' }} />
            <span className="font-mono text-xs tabular-nums text-neutral-200">{formatTime(elapsedSeconds)}</span>
          </div>
        </div>
        <button onClick={handleEdit} className="rounded-full bg-neutral-900/60 p-2.5 text-neutral-400 hover:text-white" aria-label="编辑">
          <Edit3 size={18} />
        </button>
      </div>

      {/* 进度条 */}
      <div className="absolute inset-x-4 z-40" style={{ top: 'calc(3rem + env(safe-area-inset-top))' }}>
        <input
          type="range" min={0} max={1} step={0.001} value={progress}
          onChange={(e) => seekToFraction(parseFloat(e.target.value))}
          className="h-0.5 w-full accent-yellow-500"
        />
      </div>

      {/* 阅读区箭头：左右两边大箭头指向中间 */}
      <div className="pointer-events-none absolute left-1.5 top-1/2 z-10 -translate-y-1/2">
        <ChevronRight size={56} className="text-yellow-500/35" strokeWidth={1.5} />
      </div>
      <div className="pointer-events-none absolute right-1.5 top-1/2 z-10 -translate-y-1/2">
        <ChevronLeft size={56} className="text-yellow-500/35" strokeWidth={1.5} />
      </div>

      {/* 阅读区：viewport（overflow hidden）+ content（transform 位移）。拖拽/单击/点字 */}
      <div
        ref={viewportRef}
        className={`teleprompter-touch absolute inset-0 overflow-hidden ${settings.mirror ? 'mirror-mode' : ''}`}
        style={{
          fontSize: `${settings.fontSize}px`,
          lineHeight: settings.lineHeight,
          letterSpacing: `${settings.letterSpacing}em`,
          textAlign: settings.textAlign,
          paddingLeft: pad,
          paddingRight: pad,
        }}
      >
        <div
          ref={contentRef}
          onPointerDown={onPointerDown}
          onPointerMove={onPointerMove}
          onPointerUp={onPointerUp}
          onPointerCancel={onPointerUp}
          className="mx-auto max-w-4xl cursor-pointer pb-[18vh] pt-[16vh]"
          style={{ position: 'relative', transform: TRANSFORM(0), willChange: 'transform' }}
        >
          <ScriptText
            content={script.content}
            onTokenClick={(i) => seekToIndex(i)}
          />
        </div>
      </div>

      {/* 底部控制条：字号 + 速度 */}
      <Controls
        fontSize={settings.fontSize}
        speed={settings.scrollSpeed}
        onFontSizeChange={(v) => onChangeSettings({ fontSize: v })}
        onSpeedChange={(v) => onChangeSettings({ scrollSpeed: v })}
      />

      {/* WakeLock 失败提示 */}
      {wakeLockFailed && (
        <div className="absolute inset-x-0 bottom-36 z-40 mx-auto w-fit rounded-full bg-black/80 px-4 py-2 text-center text-xs text-yellow-400/90 backdrop-blur">
          当前设备无法自动保持常亮，请在系统设置中调长自动锁屏
        </div>
      )}
    </div>
  );
}
