import { Settings, Minimize2, Type, AlignJustify, FlipHorizontal, Gauge, MoveHorizontal } from 'lucide-react';
import { TeleprompterSettings, FONT_SIZE_MIN, FONT_SIZE_MAX, LETTER_SPACING_MIN, LETTER_SPACING_MAX, LINE_HEIGHT_MIN, LINE_HEIGHT_MAX, } from '../types';
import { SPEED_MIN, SPEED_MAX, SPEED_PRESETS } from '../lib/speed';

interface Props {
  open: boolean;
  settings: TeleprompterSettings;
  onChange: (patch: Partial<TeleprompterSettings>) => void;
  onClose: () => void;
}

function Slider({
  label, icon, value, min, max, step, suffix, onChange,
}: {
  label: string;
  icon: React.ReactNode;
  value: number;
  min: number;
  max: number;
  step: number;
  suffix?: string;
  onChange: (v: number) => void;
}) {
  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between text-sm">
        <span className="flex items-center gap-2 text-neutral-400">{icon}{label}</span>
        <span className="font-mono text-white">{value}{suffix}</span>
      </div>
      <input
        type="range" aria-label={label}
        min={min} max={max} step={step} value={value}
        onChange={(e) => onChange(parseFloat(e.target.value))}
        className="w-full accent-yellow-500"
      />
    </div>
  );
}

export function SettingsPanel({ open, settings, onChange, onClose }: Props) {
  if (!open) return null;
  return (
    <div className="absolute inset-0 z-[70] flex justify-end">
      <div className="absolute inset-0 bg-black/60" onClick={onClose} />
      <div className="relative h-full w-80 max-w-[85vw] overflow-y-auto border-l border-neutral-800 bg-neutral-900 p-6 shadow-2xl">
        <div className="mb-6 flex items-center justify-between">
          <h2 className="flex items-center gap-2 text-lg font-semibold text-white">
            <Settings size={20} /> 提词设置
          </h2>
          <button onClick={onClose} className="text-neutral-500 hover:text-white" aria-label="关闭设置">
            <Minimize2 size={20} />
          </button>
        </div>

        <div className="space-y-6">
          <Slider label="字号" icon={<Type size={16} />} value={settings.fontSize}
            min={FONT_SIZE_MIN} max={FONT_SIZE_MAX} step={2} suffix="px"
            onChange={(v) => onChange({ fontSize: v })} />
          <Slider label="字间距" icon={<MoveHorizontal size={16} />} value={settings.letterSpacing}
            min={LETTER_SPACING_MIN} max={LETTER_SPACING_MAX} step={0.01} suffix="em"
            onChange={(v) => onChange({ letterSpacing: v })} />
          <Slider label="行距" icon={<AlignJustify size={16} />} value={settings.lineHeight}
            min={LINE_HEIGHT_MIN} max={LINE_HEIGHT_MAX} step={0.1}
            onChange={(v) => onChange({ lineHeight: v })} />
          <Slider label="滚动速度" icon={<Gauge size={16} />} value={settings.scrollSpeed}
            min={SPEED_MIN} max={SPEED_MAX} step={20} suffix=" WPN"
            onChange={(v) => onChange({ scrollSpeed: v })} />
          <div className="flex flex-wrap gap-2">
            {SPEED_PRESETS.map((p) => (
              <button
                key={p.id}
                onClick={() => onChange({ scrollSpeed: p.wpn })}
                className={`rounded-lg px-2.5 py-1 text-xs font-bold transition-colors ${
                  settings.scrollSpeed === p.wpn
                    ? 'bg-yellow-500/15 text-yellow-500'
                    : 'bg-neutral-800 text-neutral-400 hover:text-white'
                }`}
              >
                {p.name}
              </button>
            ))}
          </div>

          <div className="flex items-center justify-between rounded-xl bg-neutral-800 p-4">
            <div className="flex items-center gap-3">
              <FlipHorizontal size={18} className="text-neutral-400" />
              <div>
                <span className="block text-sm text-white">镜像翻转</span>
                <span className="text-[10px] text-neutral-500">用于分光镜反射</span>
              </div>
            </div>
            <button
              role="switch" aria-checked={settings.mirror}
              onClick={() => onChange({ mirror: !settings.mirror })}
              className={`relative h-6 w-12 rounded-full transition-colors ${settings.mirror ? 'bg-yellow-500' : 'bg-neutral-700'}`}
            >
              <span className={`absolute top-1 h-4 w-4 rounded-full bg-white transition-all ${settings.mirror ? 'left-7' : 'left-1'}`} />
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
