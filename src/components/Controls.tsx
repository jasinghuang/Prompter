import { MousePointer2, Clock, Play, Pause, Rewind, FastForward } from 'lucide-react';
import { ScrollMode } from '../types';
import { SPEED_MIN, SPEED_MAX } from '../lib/speed';

interface Props {
  mode: ScrollMode;
  isPlaying: boolean;
  wpn: number;
  onSetMode: (mode: ScrollMode) => void;
  onTogglePlay: () => void;
  onJump: (delta: number) => void;
  onSpeedChange: (wpn: number) => void;
}

export function Controls({ mode, isPlaying, wpn, onSetMode, onTogglePlay, onJump, onSpeedChange }: Props) {
  return (
    <div className="absolute bottom-4 left-1/2 z-50 flex -translate-x-1/2 items-center gap-1 rounded-full border border-neutral-800 bg-neutral-900/85 p-2 shadow-2xl backdrop-blur-xl">
      {/* 模式 */}
      <div className="flex items-center gap-1 px-2">
        <button
          title="手动模式"
          onClick={() => onSetMode('manual')}
          className={`rounded-full p-2 transition-all ${
            mode === 'manual' ? 'bg-yellow-500 text-black' : 'text-neutral-500 hover:text-white'
          }`}
        >
          <MousePointer2 size={18} />
        </button>
        <button
          title="自动模式"
          onClick={() => onSetMode('auto')}
          className={`rounded-full p-2 transition-all ${
            mode === 'auto' ? 'bg-yellow-500 text-black' : 'text-neutral-500 hover:text-white'
          }`}
        >
          <Clock size={18} />
        </button>
      </div>

      {/* 播放控制 */}
      <div className="flex items-center gap-1 border-l border-neutral-800 px-2">
        <button
          title="后退"
          onClick={() => onJump(-20)}
          className="rounded-full p-2 text-neutral-500 transition-all hover:text-white"
        >
          <Rewind size={18} />
        </button>
        <button
          title={isPlaying ? '暂停' : '播放'}
          onClick={onTogglePlay}
          className={`rounded-full p-3 transition-all ${
            isPlaying
              ? 'bg-yellow-500/10 text-yellow-500'
              : 'bg-yellow-500 text-black shadow-[0_0_15px_rgba(234,179,8,0.4)]'
          }`}
        >
          {isPlaying ? <Pause size={22} /> : <Play size={22} fill="currentColor" />}
        </button>
        <button
          title="快进"
          onClick={() => onJump(20)}
          className="rounded-full p-2 text-neutral-500 transition-all hover:text-white"
        >
          <FastForward size={18} />
        </button>
      </div>

      {/* 速度滑块：仅 auto 模式，直接在控制条上调节，无需进设置 */}
      {mode === 'auto' && (
        <div className="flex items-center gap-2 border-l border-neutral-800 px-3" title="速度">
          <input
            type="range"
            aria-label="速度"
            min={SPEED_MIN}
            max={SPEED_MAX}
            step={10}
            value={wpn}
            onChange={(e) => onSpeedChange(parseInt(e.target.value, 10))}
            className="h-1 w-24 accent-yellow-500"
          />
          <span className="w-8 text-[10px] font-bold tabular-nums text-neutral-400">{wpn}</span>
        </div>
      )}
    </div>
  );
}
