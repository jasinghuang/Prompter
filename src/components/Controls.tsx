import { FONT_SIZE_MIN, FONT_SIZE_MAX } from '../types';
import { SPEED_MIN, SPEED_MAX } from '../lib/speed';

interface Props {
  fontSize: number;
  speed: number;
  visible: boolean;
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

/** 暗淡标签 + 独立数值胶囊（标签与胶囊间距 4px） */
function ParamLabel({ label, value }: { label: string; value: number }) {
  return (
    <span className="flex shrink-0 items-center gap-1 whitespace-nowrap">
      <span className="text-xs text-white/50">{label}</span>
      <span className="rounded-md bg-white/10 px-2.5 py-0.5 font-mono text-sm font-semibold tabular-nums text-white">
        {value}
      </span>
    </span>
  );
}

export function Controls({ fontSize, speed, visible, onFontSizeChange, onSpeedChange }: Props) {
  return (
    <div
      className={`absolute bottom-[calc(1rem+env(safe-area-inset-bottom))] left-4 right-4 z-50 flex items-center gap-4 rounded-2xl border border-white/10 glass-bar px-4 py-3 transition-all duration-300 ${
        visible ? 'translate-y-0 opacity-100' : 'translate-y-24 opacity-0 pointer-events-none'
      }`}
    >
      <ParamLabel label="字号" value={fontSize} />
      <input
        type="range"
        aria-label="字号"
        min={FONT_SIZE_MIN}
        max={FONT_SIZE_MAX}
        step={2}
        value={fontSize}
        onChange={(e) => onFontSizeChange(parseInt(e.target.value, 10))}
        className={SLIDER_CLASS}
      />
      <ParamLabel label="速度" value={speed} />
      <input
        type="range"
        aria-label="速度"
        min={SPEED_MIN}
        max={SPEED_MAX}
        step={10}
        value={speed}
        onChange={(e) => onSpeedChange(parseInt(e.target.value, 10))}
        className={SLIDER_CLASS}
      />
    </div>
  );
}
