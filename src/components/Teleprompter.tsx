import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { ChevronLeft, Settings, Edit3, Maximize2 } from 'lucide-react';
import { Script, TeleprompterSettings, ScrollMode } from '../types';
import { countReadableChars } from '../lib/tokens';
import { estimateDurationSeconds, SPEED_MIN, SPEED_MAX } from '../lib/speed';
import { formatTime } from '../lib/format';
import { useTimer } from '../hooks/useTimer';
import { useAutoScroll } from '../hooks/useAutoScroll';
import { useWakeLock } from '../hooks/useWakeLock';
import { ScriptText } from './ScriptText';
import { Controls } from './Controls';
import { SettingsPanel } from './SettingsPanel';

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
  const [mode, setMode] = useState<ScrollMode>('auto');
  const [isPlaying, setIsPlaying] = useState(false);
  const [showSettings, setShowSettings] = useState(false);
  const [showLandscapeHint, setShowLandscapeHint] = useState(false);
  const [wakeLockFailed, setWakeLockFailed] = useState(false);
  const [widthTick, setWidthTick] = useState(0);
  const [activeIndex, setActiveIndex] = useState(index);
  const activeIndexRef = useRef(index);
  const [maxOffset, setMaxOffset] = useState(0);
  const maxOffsetRef = useRef(0);

  const viewportRef = useRef<HTMLDivElement>(null);
  const contentRef = useRef<HTMLDivElement>(null);
  const spansRef = useRef<HTMLElement[]>([]);
  // 速度实时引用（键盘快捷键用）
  const scrollSpeedRef = useRef(settings.scrollSpeed);
  // 拖拽状态
  const dragRef = useRef<{ y: number; offset: number; moved: boolean; id: number } | null>(null);
  const lastTapRef = useRef(0);

  const charCount = useMemo(() => countReadableChars(script.content), [script.content]);
  const estimatedTotal = estimateDurationSeconds(charCount, settings.scrollSpeed);

  const { elapsedSeconds, start: startTimer, stop: stopTimer } = useTimer();
  const { request, release } = useWakeLock();

  const layoutKey = `${settings.fontSize}|${settings.letterSpacing}|${settings.lineHeight}|${settings.textAlign}|${settings.horizontalPadding}|${widthTick}|${maxOffset}`;

  const applyOffset = useCallback((offset: number) => {
    const ct = contentRef.current;
    if (ct) ct.style.transform = TRANSFORM(offset);
  }, []);

  // 由位移反推中线对应的字（纯计算，跨字才 setState）
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
      // 重新定位当前字到中线（布局变化后保持视觉位置）
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

  // 像素速度 = 每字平均垂直像素 × 字率
  const pxPerSec = charCount > 0 && maxOffset > 0 ? (maxOffset / charCount) * (settings.scrollSpeed / 60) : 0;

  const getContent = useCallback(() => contentRef.current, []);
  const getMaxOffset = useCallback(() => maxOffsetRef.current, []);

  const offsetRef = useAutoScroll({
    running: mode === 'auto' && isPlaying,
    pxPerSec,
    getContent,
    getMaxOffset,
    onTick: computeActive,
    onReachEnd: () => setIsPlaying(false),
  });

  useEffect(() => {
    scrollSpeedRef.current = settings.scrollSpeed;
  });

  // 横屏提示 + 宽度变化触发重测
  useEffect(() => {
    const check = () => {
      setShowLandscapeHint(window.innerHeight > window.innerWidth);
      setWidthTick((t) => t + 1);
    };
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

  const togglePlay = useCallback(() => setIsPlaying((p) => !p), []);

  // 点击按钮后立即失焦，避免空格/方向键被按钮拦截或双重触发
  useEffect(() => {
    const onClick = (e: MouseEvent) => {
      const btn = (e.target as HTMLElement | null)?.closest('button');
      if (btn) btn.blur();
    };
    window.addEventListener('click', onClick, true);
    return () => window.removeEventListener('click', onClick, true);
  }, []);

  // 键盘快捷键：空格 播放/暂停；↑/↓ 调速度（Shift 微调）
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
        if (t && t.tagName === 'INPUT') return; // 焦点在滑块上时交给滑块自身
        e.preventDefault();
        const step = e.shiftKey ? 5 : 20;
        const delta = (e.code === 'ArrowUp' ? 1 : -1) * step;
        const next = Math.min(SPEED_MAX, Math.max(SPEED_MIN, scrollSpeedRef.current + delta));
        onChangeSettings({ scrollSpeed: next });
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onChangeSettings]);

  const handleSetMode = (m: ScrollMode) => {
    setMode(m);
    setIsPlaying(false);
  };

  const seekToIndex = useCallback((i: number) => {
    const len = script.content.length;
    scrollToIndex(Math.min(Math.max(0, i), Math.max(0, len - 1)));
  }, [script.content.length, scrollToIndex]);

  const advance = useCallback((n: number) => {
    seekToIndex(activeIndexRef.current + n);
  }, [seekToIndex]);

  // 进度条跳转
  const seekToFraction = (frac: number) => {
    const max = maxOffsetRef.current;
    const off = Math.max(0, Math.min(max, frac * max));
    offsetRef.current = off;
    applyOffset(off);
    computeActive(off);
  };

  // 统一 pointer 交互：拖拽自由滚动 / 双击暂停
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
    if (!d.moved && Math.abs(dy) < 6) return; // 点击抖动阈值
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
    if (d.moved) {
      computeActive(offsetRef.current);
      lastTapRef.current = 0; // 拖拽后重置双击
      return;
    }
    // 未拖拽 → 双击检测
    const now = Date.now();
    if (now - lastTapRef.current < 300) {
      setIsPlaying((p) => !p);
      lastTapRef.current = 0;
    } else {
      lastTapRef.current = now;
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

  const enterFullscreen = () => {
    if (document.fullscreenEnabled) document.documentElement.requestFullscreen?.().catch(() => {});
  };

  const progress = maxOffset > 0 ? offsetRef.current / maxOffset : 0;
  const bandHeight = 2 * settings.fontSize * settings.lineHeight;
  const pad = `${settings.horizontalPadding}%`;

  return (
    <div className="relative h-[100dvh] w-screen overflow-hidden bg-black">
      {/* 顶部栏 */}
      <div className="absolute inset-x-0 top-0 z-50 flex items-center justify-between bg-gradient-to-b from-black/90 to-transparent p-3">
        <div className="flex items-center gap-2">
          <button onClick={handleBack} className="rounded-full bg-neutral-900/60 p-2 text-neutral-400 hover:text-white"><ChevronLeft size={18} /></button>
          <div className="flex items-center gap-1.5 rounded-lg border border-neutral-800 bg-neutral-900/60 px-2.5 py-1">
            <span className="h-1.5 w-1.5 rounded-full bg-red-500" style={{ boxShadow: isPlaying ? '0 0 6px #ef4444' : 'none' }} />
            <span className="font-mono text-xs tabular-nums text-neutral-200">{formatTime(elapsedSeconds)}</span>
          </div>
        </div>
        <div className="flex items-center gap-2">
          <span className="max-w-[140px] truncate text-[11px] text-neutral-500">{script.title}</span>
          <button onClick={handleEdit} className="rounded-full bg-neutral-900/60 p-2 text-neutral-400 hover:text-white"><Edit3 size={18} /></button>
          <button onClick={() => setShowSettings(true)} className="rounded-full bg-neutral-900/60 p-2 text-neutral-400 hover:text-white"><Settings size={18} /></button>
        </div>
      </div>

      {/* 进度条 */}
      <div className="absolute inset-x-4 top-14 z-40 flex items-center gap-2">
        <span className="font-mono text-[9px] tabular-nums text-neutral-600">{formatTime(elapsedSeconds)}</span>
        <input
          type="range" min={0} max={1} step={0.001} value={progress}
          onChange={(e) => seekToFraction(parseFloat(e.target.value))}
          className="h-1 w-full accent-yellow-500"
        />
        <span className="font-mono text-[9px] tabular-nums text-neutral-600">{formatTime(estimatedTotal)}</span>
      </div>

      {/* 阅读区色块（2 行高，居中） */}
      <div
        className="reading-band pointer-events-none absolute inset-x-0 top-1/2 z-10 -translate-y-1/2"
        style={{ height: `${bandHeight}px` }}
      >
        <span className="absolute left-3 top-1/2 -translate-y-1/2 bg-black px-1.5 text-[8px] uppercase tracking-widest text-yellow-500/50">Reading Area</span>
      </div>

      {/* 阅读区：viewport（overflow hidden）+ content（transform 位移）。拖拽/双击/点字 */}
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
          className="mx-auto max-w-4xl cursor-grab pb-[18vh] pt-[16vh] active:cursor-grabbing"
          style={{ position: 'relative', transform: TRANSFORM(0), willChange: 'transform' }}
        >
          <ScriptText
            content={script.content}
            currentIndex={activeIndex}
            onTokenClick={(i) => seekToIndex(i)}
            layoutKey={layoutKey}
          />
        </div>
      </div>

      {/* 控制条 */}
      <Controls
        mode={mode}
        isPlaying={isPlaying}
        wpn={settings.scrollSpeed}
        onSetMode={handleSetMode}
        onTogglePlay={togglePlay}
        onJump={(d) => advance(d)}
        onSpeedChange={(v) => onChangeSettings({ scrollSpeed: v })}
      />

      {/* 全屏按钮 */}
      <button onClick={enterFullscreen} className="absolute bottom-5 right-4 z-50 rounded-full border border-neutral-800 bg-neutral-900/80 p-2.5 text-neutral-400 backdrop-blur-xl hover:text-white" title="全屏">
        <Maximize2 size={18} />
      </button>

      {/* 快捷键提示 */}
      <div className="pointer-events-none absolute bottom-5 left-4 z-40 hidden text-[10px] text-neutral-600 sm:block">
        空格 播放/暂停 · ↑↓ 调速度 · 双击 播放/暂停 · 拖拽 自由浏览
      </div>

      {/* 横屏提示 */}
      {showLandscapeHint && (
        <div className="absolute inset-x-0 bottom-24 z-40 mx-auto w-fit rounded-full bg-black/80 px-4 py-2 text-center text-xs text-neutral-300 backdrop-blur">
          建议横放设备以获得最佳提词效果
        </div>
      )}

      {wakeLockFailed && (
        <div className="absolute inset-x-0 bottom-32 z-40 mx-auto w-fit rounded-full bg-black/80 px-4 py-2 text-center text-xs text-yellow-400/90 backdrop-blur">
          当前设备无法自动保持常亮，请在系统设置中调长自动锁屏
        </div>
      )}

      <SettingsPanel
        open={showSettings}
        settings={settings}
        onChange={onChangeSettings}
        onClose={() => setShowSettings(false)}
      />
    </div>
  );
}
