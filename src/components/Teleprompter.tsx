import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { ChevronLeft, Edit3, Settings } from 'lucide-react';
import { Script, TeleprompterSettings } from '../types';
import { countReadableChars } from '../lib/tokens';
import { SPEED_MIN, SPEED_MAX } from '../lib/speed';
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

export function Teleprompter({ script, settings, index, onIndexChange, onChangeSettings, onBack, onEdit }: Props) {
  const [isPlaying, setIsPlaying] = useState(false);
  const [showSettings, setShowSettings] = useState(false);
  const [wakeLockFailed, setWakeLockFailed] = useState(false);
  const [widthTick, setWidthTick] = useState(0);
  const [activeIndex, setActiveIndex] = useState(index);
  const activeIndexRef = useRef(index);
  const [maxOffset, setMaxOffset] = useState(0);
  const maxOffsetRef = useRef(0);

  const viewportRef = useRef<HTMLDivElement>(null);
  const contentRef = useRef<HTMLDivElement>(null);
  const spansRef = useRef<HTMLElement[]>([]);
  // 用于区分拖拽滚动和点击：记录 pointerdown 位置
  const touchStartRef = useRef<{ y: number; scrollTop: number } | null>(null);

  const charCount = useMemo(() => countReadableChars(script.content), [script.content]);

  const { elapsedSeconds, start: startTimer, stop: stopTimer } = useTimer();
  const { request, release } = useWakeLock();

  // 由 scrollTop 反推中线对应的字
  const computeActive = useCallback((scrollTop: number) => {
    const vp = viewportRef.current;
    if (!vp) return;
    const mid = scrollTop + vp.clientHeight / 2;
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

  // 测量 maxOffset + 缓存 spans + 跳到当前字
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
        vp.scrollTop = target.offsetTop - vp.clientHeight / 2 + target.offsetHeight / 2;
        scrollRef.current = vp.scrollTop;
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

  const pxPerSec = charCount > 0 && maxOffset > 0 ? (maxOffset / charCount) * (settings.scrollSpeed / 60) : 0;

  const getViewport = useCallback(() => viewportRef.current, []);
  const getMaxOffset = useCallback(() => maxOffsetRef.current, []);

  const scrollRef = useAutoScroll({
    running: isPlaying,
    pxPerSec,
    getViewport,
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
    if (!vp) return;
    const target = spansRef.current.find((s) => Number(s.dataset.idx) === i);
    if (target) {
      vp.scrollTop = target.offsetTop - vp.clientHeight / 2 + target.offsetHeight / 2;
      scrollRef.current = vp.scrollTop;
    }
    activeIndexRef.current = i;
    setActiveIndex(i);
  }, []);

  // 外部 index 变化
  useEffect(() => {
    scrollToIndex(index);
  }, [index, scrollToIndex]);

  // 手动滚动时同步 scrollRef + 高亮
  useEffect(() => {
    const vp = viewportRef.current;
    if (!vp) return;
    const onScroll = () => {
      scrollRef.current = vp.scrollTop;
      computeActive(vp.scrollTop);
    };
    vp.addEventListener('scroll', onScroll, { passive: true });
    return () => vp.removeEventListener('scroll', onScroll);
  }, [computeActive]);

  // 自动暂停：当 activeIndex 落入关键词范围时暂停
  const pausedAtRef = useRef(-1);

  useEffect(() => {
    const kw = settings.pauseKeyword;
    if (!isPlaying || !kw) return;
    // 从 activeIndex 往前找 max(kw.length, 30) 个字符，检查是否匹配
    const ctx = script.content.substring(
      Math.max(0, activeIndex - Math.max(kw.length, 30)),
      activeIndex + kw.length,
    );
    const idx = ctx.indexOf(kw);
    if (idx !== -1) {
      const absIdx = Math.max(0, activeIndex - Math.max(kw.length, 30)) + idx;
      if (pausedAtRef.current !== absIdx) {
        pausedAtRef.current = absIdx;
        setIsPlaying(false);
      }
    }
  }, [activeIndex, isPlaying, script.content, settings.pauseKeyword]);

  // 屏幕常亮：进入提词器即激活，离开释放
  useEffect(() => {
    request().catch(() => setWakeLockFailed(true));
    return () => { release(); };
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  // 播放/暂停：计时器
  useEffect(() => {
    if (isPlaying) {
      startTimer();
    } else {
      stopTimer();
    }
  }, [isPlaying]); // eslint-disable-line react-hooks/exhaustive-deps

  // 按钮点击后失焦
  useEffect(() => {
    const onClick = (e: MouseEvent) => {
      const btn = (e.target as HTMLElement | null)?.closest('button');
      if (btn) btn.blur();
    };
    window.addEventListener('click', onClick, true);
    return () => window.removeEventListener('click', onClick, true);
  }, []);

  // 键盘：空格 播放/暂停、↑↓ 调速度
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

  const handleBack = () => {
    onIndexChange(activeIndexRef.current);
    onBack();
  };
  const handleEdit = () => {
    onIndexChange(activeIndexRef.current);
    onEdit();
  };

  // 区分拖拽滚动与点击：手指移动 < 5px 视为点击，否则为拖拽（浏览器处理原生滚动）
  const handlePointerDown = useCallback((e: React.PointerEvent) => {
    touchStartRef.current = { y: e.clientY, scrollTop: viewportRef.current?.scrollTop ?? 0 };
  }, []);

  const handlePointerUp = useCallback((e: React.PointerEvent) => {
    const start = touchStartRef.current;
    touchStartRef.current = null;
    if (!start) return;
    // 手指移动超过 8px → 拖拽滚动，不触发点击
    if (Math.abs(e.clientY - start.y) > 8) return;
    // 点击任意位置 → 切换播放/暂停
    setIsPlaying((p) => !p);
  }, []);

  const pad = `${settings.horizontalPadding}%`;

  return (
    <div className="relative h-[100dvh] w-screen overflow-hidden bg-black">
      {/* 顶部栏 */}
      <div className="absolute inset-x-0 top-0 z-50 flex items-center justify-between bg-gradient-to-b from-black/90 to-transparent pb-3 pt-[calc(0.75rem+env(safe-area-inset-top))]" style={{ paddingLeft: 'calc(0.75rem + env(safe-area-inset-left))', paddingRight: 'calc(0.75rem + env(safe-area-inset-right))' }}>
        <div className="flex items-center gap-2">
          <button onClick={handleBack} className="rounded-full bg-neutral-900/60 p-2.5 text-neutral-400 hover:text-white" aria-label="返回">
            <ChevronLeft size={18} />
          </button>
          <div className="flex items-center gap-1.5 rounded-lg border border-neutral-800 bg-neutral-900/60 px-2.5 py-1">
            <span className="h-1.5 w-1.5 rounded-full" style={{
              backgroundColor: isPlaying ? '#ef4444' : '#525252',
              boxShadow: isPlaying ? '0 0 6px #ef4444' : 'none',
            }} />
            <span className="font-mono text-xs tabular-nums text-neutral-200">{formatTime(elapsedSeconds)}</span>
          </div>
        </div>
        <div className="flex items-center gap-1">
          <button onClick={handleEdit} className="rounded-full bg-neutral-900/60 p-2.5 text-neutral-400 hover:text-white" aria-label="编辑">
            <Edit3 size={18} />
          </button>
          <button onClick={() => setShowSettings(true)} className="rounded-full bg-neutral-900/60 p-2.5 text-neutral-400 hover:text-white" aria-label="设置">
            <Settings size={18} />
          </button>
        </div>
      </div>

      {/* 阅读区高亮竖线 */}
      <div className="pointer-events-none absolute top-1/2 z-10 -translate-y-1/2" style={{ left: 'calc(0.75rem + env(safe-area-inset-left))' }}>
        <div className="h-28 w-1 rounded-full bg-yellow-500/70 shadow-[0_0_20px_rgba(234,179,8,0.6)]" />
      </div>
      <div className="pointer-events-none absolute top-1/2 z-10 -translate-y-1/2" style={{ right: 'calc(0.75rem + env(safe-area-inset-right))' }}>
        <div className="h-28 w-1 rounded-full bg-yellow-500/70 shadow-[0_0_20px_rgba(234,179,8,0.6)]" />
      </div>

      {/* 阅读区：原生 overflow 滚动，手指拖拽带惯性 */}
      <div
        ref={viewportRef}
        onPointerDown={handlePointerDown}
        onPointerUp={handlePointerUp}
        className={`teleprompter-touch absolute inset-0 z-0 overflow-y-auto ${settings.mirror ? 'mirror-mode' : ''}`}
        style={{
          fontSize: `${settings.fontSize}px`,
          lineHeight: settings.lineHeight,
          letterSpacing: `${settings.letterSpacing}em`,
          textAlign: settings.textAlign,
          paddingLeft: pad,
          paddingRight: pad,
          WebkitOverflowScrolling: 'touch',
        }}
      >
        <div
          ref={contentRef}
          className="mx-auto max-w-4xl pb-[18vh] pt-[16vh]"
        >
          <ScriptText content={script.content} />
        </div>
      </div>

      {/* 底部控制条 */}
      <Controls
        visible={!isPlaying}
        fontSize={settings.fontSize}
        speed={settings.scrollSpeed}
        onFontSizeChange={(v) => onChangeSettings({ fontSize: v })}
        onSpeedChange={(v) => onChangeSettings({ scrollSpeed: v })}
      />

      {wakeLockFailed && (
        <div className="absolute inset-x-0 bottom-36 z-40 mx-auto w-fit rounded-full bg-black/80 px-4 py-2 text-center text-xs text-yellow-400/90 backdrop-blur">
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
