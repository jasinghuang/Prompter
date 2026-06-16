import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { ChevronLeft, Settings, Edit3, Maximize2 } from 'lucide-react';
import { Script, TeleprompterSettings, ScrollMode } from '../types';
import { countReadableChars } from '../lib/tokens';
import { estimateDurationSeconds } from '../lib/speed';
import { formatTime } from '../lib/format';
import { useTimer } from '../hooks/useTimer';
import { useAutoAdvance } from '../hooks/useAutoAdvance';
import { useSmoothScroll } from '../hooks/useSmoothScroll';
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
  const [mode, setMode] = useState<ScrollMode>('auto');
  const [isPlaying, setIsPlaying] = useState(false);
  const [showSettings, setShowSettings] = useState(false);
  const [showLandscapeHint, setShowLandscapeHint] = useState(false);
  const [wakeLockFailed, setWakeLockFailed] = useState(false);

  const containerRef = useRef<HTMLDivElement>(null);
  const charCount = useMemo(() => countReadableChars(script.content), [script.content]);
  const estimatedTotal = estimateDurationSeconds(charCount, settings.scrollSpeed);

  const { elapsedSeconds, start: startTimer, stop: stopTimer } = useTimer();
  const { scrollIntoContainerCenter } = useSmoothScroll();
  const { request, release } = useWakeLock();

  // 字数变化（编辑返回）导致越界时钳制
  useEffect(() => {
    const len = script.content.length;
    if (index > len - 1) onIndexChange(Math.max(0, len - 1));
  }, [script.content.length]); // eslint-disable-line react-hooks/exhaustive-deps

  // 横屏提示：竖屏进入时显示一次
  useEffect(() => {
    const check = () => setShowLandscapeHint(window.innerHeight > window.innerWidth);
    check();
    window.addEventListener('resize', check);
    return () => window.removeEventListener('resize', check);
  }, []);

  // 当前字变化 → 平滑滚动到中线
  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;
    const el = container.querySelector<HTMLElement>(`span[data-idx="${index}"]`);
    if (el) scrollIntoContainerCenter(container, el);
  }, [index, scrollIntoContainerCenter]);

  const advance = useCallback((n: number) => {
    const len = script.content.length;
    const next = Math.min(Math.max(0, index + n), Math.max(0, len - 1));
    if (next >= len - 1 && n > 0) setIsPlaying(false); // 到结尾停止
    if (next !== index) onIndexChange(next);
  }, [index, script.content.length, onIndexChange]);

  // 自动推进：auto 模式 + 播放中
  useAutoAdvance({
    running: mode === 'auto' && isPlaying,
    wpn: settings.scrollSpeed,
    enabled: true,
    onAdvance: advance,
  });

  // 播放/暂停副作用：计时器 + Wake Lock
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

  const togglePlay = () => setIsPlaying((p) => !p);
  const handleSetMode = (m: ScrollMode) => {
    setMode(m);
    setIsPlaying(false);
  };

  // 进度条跳转
  const seekToFraction = (frac: number) => {
    const len = script.content.length;
    onIndexChange(Math.round(frac * Math.max(0, len - 1)));
  };

  // 手动模式：拖拽自由滚动，松手后高亮离中线最近的字
  const onPointerUp = useCallback(() => {
    if (mode !== 'manual') return;
    const container = containerRef.current;
    if (!container) return;
    const mid = container.scrollTop + container.clientHeight / 2;
    const spans = Array.from(container.querySelectorAll<HTMLElement>('span[data-idx]'));
    let best = 0;
    let bestDist = Infinity;
    for (const s of spans) {
      const center = s.offsetTop + s.offsetHeight / 2;
      const d = Math.abs(center - mid);
      if (d < bestDist) { bestDist = d; best = Number(s.dataset.idx); }
    }
    onIndexChange(best);
  }, [mode, onIndexChange]);

  const enterFullscreen = () => {
    if (document.fullscreenEnabled) document.documentElement.requestFullscreen?.().catch(() => {});
  };

  const progress = script.content.length > 1 ? index / (script.content.length - 1) : 0;

  return (
    <div className="relative h-[100dvh] w-screen overflow-hidden bg-black">
      {/* 顶部栏 */}
      <div className="absolute inset-x-0 top-0 z-50 flex items-center justify-between bg-gradient-to-b from-black/90 to-transparent p-3">
        <div className="flex items-center gap-2">
          <button onClick={onBack} className="rounded-full bg-neutral-900/60 p-2 text-neutral-400 hover:text-white"><ChevronLeft size={18} /></button>
          <div className="flex items-center gap-1.5 rounded-lg border border-neutral-800 bg-neutral-900/60 px-2.5 py-1">
            <span className="h-1.5 w-1.5 rounded-full bg-red-500" style={{ boxShadow: isPlaying ? '0 0 6px #ef4444' : 'none' }} />
            <span className="font-mono text-xs tabular-nums text-neutral-200">{formatTime(elapsedSeconds)}</span>
          </div>
        </div>
        <div className="flex items-center gap-2">
          <span className="max-w-[140px] truncate text-[11px] text-neutral-500">{script.title}</span>
          <button onClick={onEdit} className="rounded-full bg-neutral-900/60 p-2 text-neutral-400 hover:text-white"><Edit3 size={18} /></button>
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

      {/* 阅读线 */}
      <div className="pointer-events-none absolute inset-x-0 top-1/2 z-10 h-px bg-yellow-500/30">
        <span className="absolute left-3 top-1/2 -translate-y-1/2 bg-black px-1.5 text-[8px] uppercase tracking-widest text-yellow-500/50">Reading Area</span>
      </div>

      {/* 阅读区 */}
      <div
        ref={containerRef}
        onPointerUp={onPointerUp}
        className={`teleprompter-touch h-full w-full overflow-y-auto px-[8%] pb-[18vh] pt-[16vh] ${settings.mirror ? 'mirror-mode' : ''}`}
        style={{
          fontSize: `${settings.fontSize}px`,
          lineHeight: settings.lineHeight,
          letterSpacing: `${settings.letterSpacing}em`,
        }}
      >
        <div className="mx-auto max-w-4xl text-center">
          <ScriptText content={script.content} currentIndex={index} onTokenClick={(i) => onIndexChange(i)} />
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
      />

      {/* 全屏按钮 */}
      <button onClick={enterFullscreen} className="absolute bottom-5 right-4 z-50 rounded-full border border-neutral-800 bg-neutral-900/80 p-2.5 text-neutral-400 backdrop-blur-xl hover:text-white" title="全屏">
        <Maximize2 size={18} />
      </button>

      {/* 横屏提示 */}
      {showLandscapeHint && (
        <div className="absolute inset-x-0 bottom-24 z-40 mx-auto w-fit rounded-full bg-black/80 px-4 py-2 text-center text-xs text-neutral-300 backdrop-blur">
          建议横放设备以获得最佳提词效果
        </div>
      )}

      {/* Wake Lock 降级提示 */}
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
