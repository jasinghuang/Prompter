import { Type, Gauge } from 'lucide-react';
import { FONT_SIZE_MIN, FONT_SIZE_MAX } from '../types';
import { SPEED_MIN, SPEED_MAX } from '../lib/speed';

interface Props {
  fontSize: number;
  speed: number;
  visible: boolean;
  onFontSizeChange: (v: number) => void;
  onSpeedChange: (v: number) => void;
}

export function Controls({ fontSize, speed, visible, onFontSizeChange, onSpeedChange }: Props) {
  return (
    <div
      className={`drawer-spring absolute bottom-[calc(0.75rem+env(safe-area-inset-bottom))] left-3 right-3 z-50 flex items-center gap-3 rounded-2xl border border-[#26262B] bg-[#0A0A0B]/70 px-4 py-3 shadow-2xl backdrop-blur-xl ${
        visible ? 'translate-y-0 opacity-100' : 'translate-y-24 opacity-0 pointer-events-none'
      }`}
    >
      {/* Font Size */}
      <Type size={14} className="shrink-0 text-[#A1A1AA]" />
      <input
        type="range"
        aria-label="字号"
        min={FONT_SIZE_MIN}
        max={FONT_SIZE_MAX}
        step={2}
        value={fontSize}
        onChange={(e) => onFontSizeChange(parseInt(e.target.value, 10))}
        className="h-[3px] min-w-0 flex-1"
        style={{
          accentColor: '#D4A432',
        }}
      />
      <span className="w-7 shrink-0 text-right font-mono text-[11px] tabular-nums text-[#A1A1AA]">
        {fontSize}
      </span>

      {/* Speed */}
      <Gauge size={14} className="shrink-0 text-[#A1A1AA]" />
      <input
        type="range"
        aria-label="速度"
        min={SPEED_MIN}
        max={SPEED_MAX}
        step={10}
        value={speed}
        onChange={(e) => onSpeedChange(parseInt(e.target.value, 10))}
        className="h-[3px] min-w-0 flex-1"
        style={{
          accentColor: '#D4A432',
        }}
      />
      <span className="w-8 shrink-0 text-right font-mono text-[11px] tabular-nums text-[#A1A1AA]">
        {speed}
      </span>
    </div>
  );
}
