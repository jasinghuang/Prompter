import { Type, Gauge, Play, Pause } from 'lucide-react';
import { FONT_SIZE_MIN, FONT_SIZE_MAX } from '../types';
import { SPEED_MIN, SPEED_MAX } from '../lib/speed';

interface Props {
  fontSize: number;
  speed: number;
  visible: boolean;
  isPlaying: boolean;
  onTogglePlay: () => void;
  onFontSizeChange: (v: number) => void;
  onSpeedChange: (v: number) => void;
}

/** 全宽滑块：44px 高命中区，8px 视觉轨道，24px 滑块（mt -8px 居中于轨道） */
const SLIDER_CLASS = [
  'h-11 min-w-0 flex-1 cursor-pointer appearance-none bg-transparent',
  '[&::-webkit-slider-runnable-track]:h-2 [&::-webkit-slider-runnable-track]:rounded-full [&::-webkit-slider-runnable-track]:bg-white/15',
  '[&::-webkit-slider-thumb]:appearance-none [&::-webkit-slider-thumb]:mt-[-8px] [&::-webkit-slider-thumb]:h-6 [&::-webkit-slider-thumb]:w-6 [&::-webkit-slider-thumb]:rounded-full [&::-webkit-slider-thumb]:bg-white [&::-webkit-slider-thumb]:shadow-md [&::-webkit-slider-thumb]:active:scale-90',
  '[&::-moz-range-track]:h-2 [&::-moz-range-track]:rounded-full [&::-moz-range-track]:bg-white/15',
  '[&::-moz-range-thumb]:h-6 [&::-moz-range-thumb]:w-6 [&::-moz-range-thumb]:rounded-full [&::-moz-range-thumb]:border-0 [&::-moz-range-thumb]:bg-white',
].join(' ');

const STEP_BTN_CLASS =
  'flex h-11 w-11 shrink-0 items-center justify-center rounded-lg bg-white/5 text-base text-white/70 transition-colors hover:bg-white/10 hover:text-white active:scale-95';

/** 参数块：头部行（图标+标签+数值胶囊）+ 控件行（− 滑块 +） */
function SliderBlock({
  icon,
  label,
  value,
  min,
  max,
  step,
  onChange,
}: {
  icon: React.ReactNode;
  label: string;
  value: number;
  min: number;
  max: number;
  step: number;
  onChange: (v: number) => void;
}) {
  const dec = () => onChange(Math.max(min, value - step));
  const inc = () => onChange(Math.min(max, value + step));

  return (
    <div className="space-y-1">
      <div className="flex items-center justify-between">
        <span className="flex items-center gap-1.5">
          <span className="text-white/30">{icon}</span>
          <span className="text-sm font-semibold text-white">{label}</span>
        </span>
        <span className="w-12 shrink-0 rounded-md bg-white/10 py-0.5 text-center font-mono text-sm font-semibold tabular-nums text-white">
          {value}
        </span>
      </div>
      <div className="flex items-center gap-2">
        <button onClick={dec} aria-label={`减小${label}`} className={STEP_BTN_CLASS}>
          −
        </button>
        <input
          type="range"
          aria-label={label}
          min={min}
          max={max}
          step={step}
          value={value}
          onChange={(e) => onChange(parseInt(e.target.value, 10))}
          className={SLIDER_CLASS}
        />
        <button onClick={inc} aria-label={`增大${label}`} className={STEP_BTN_CLASS}>
          +
        </button>
      </div>
    </div>
  );
}

export function Controls({ fontSize, speed, visible, isPlaying, onTogglePlay, onFontSizeChange, onSpeedChange }: Props) {
  return (
    <div
      className={`absolute bottom-[calc(1rem+env(safe-area-inset-bottom))] left-4 right-4 z-50 flex items-center gap-3 rounded-2xl border border-white/10 glass-bar px-4 py-3 transition-all duration-300 ${
        visible ? 'translate-y-0 opacity-100' : 'translate-y-24 opacity-0 pointer-events-none'
      }`}
    >
      {/* Two parameter blocks, sliders take the full remaining width */}
      <div className="flex min-w-0 flex-1 flex-col gap-2">
        <SliderBlock
          icon={<Type size={16} />}
          label="字号"
          value={fontSize}
          min={FONT_SIZE_MIN}
          max={FONT_SIZE_MAX}
          step={2}
          onChange={onFontSizeChange}
        />
        <SliderBlock
          icon={<Gauge size={16} />}
          label="速度"
          value={speed}
          min={SPEED_MIN}
          max={SPEED_MAX}
          step={10}
          onChange={onSpeedChange}
        />
      </div>

      {/* Big Play/Pause */}
      <button
        onClick={onTogglePlay}
        className="flex h-14 w-14 shrink-0 items-center justify-center rounded-full bg-white/15 text-white transition-all hover:bg-white/25 active:scale-90"
        aria-label={isPlaying ? '暂停' : '播放'}
      >
        {isPlaying ? <Pause size={26} fill="currentColor" /> : <Play size={26} fill="currentColor" className="ml-0.5" />}
      </button>
    </div>
  );
}
