import { Settings, Minimize2, Type, AlignJustify, FlipHorizontal, Gauge, MoveHorizontal, Move, AlignLeft, AlignCenter, AlignRight, CirclePause } from 'lucide-react';
import { TeleprompterSettings, TextAlign, FONT_SIZE_MIN, FONT_SIZE_MAX, LETTER_SPACING_MIN, LETTER_SPACING_MAX, LINE_HEIGHT_MIN, LINE_HEIGHT_MAX, PADDING_MIN, PADDING_MAX } from '../types';
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

const ALIGN_OPTIONS: { value: TextAlign; Icon: typeof AlignLeft; label: string }[] = [
  { value: 'left', Icon: AlignLeft, label: '左对齐' },
  { value: 'center', Icon: AlignCenter, label: '居中对齐' },
  { value: 'right', Icon: AlignRight, label: '右对齐' },
];

export function SettingsPanel({ open, settings, onChange, onClose }: Props) {
  if (!open) return null;
  return (
    <div className="absolute inset-0 z-[70] flex justify-end">
      <div className="absolute inset-0 bg-black/60" onClick={onClose} />
      <div className="relative h-full w-80 max-w-[85vw] overflow-y-auto border-l border-neutral-800 bg-neutral-900 px-6 pb-[calc(1.5rem+env(safe-area-inset-bottom))] pt-[calc(1.5rem+env(safe-area-inset-top))] shadow-2xl">
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
          <Slider label="两边间距" icon={<Move size={16} />} value={settings.horizontalPadding}
            min={PADDING_MIN} max={PADDING_MAX} step={1} suffix="%"
            onChange={(v) => onChange({ horizontalPadding: v })} />
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

          {/* 对齐方式 */}
          <div className="space-y-2">
            <span className="flex items-center gap-2 text-sm text-neutral-400"><AlignLeft size={16} />对齐方式</span>
            <div className="flex gap-2">
              {ALIGN_OPTIONS.map(({ value, Icon, label }) => (
                <button
                  key={value}
                  title={label}
                  aria-label={label}
                  onClick={() => onChange({ textAlign: value })}
                  className={`flex flex-1 items-center justify-center rounded-lg py-2 transition-colors ${
                    settings.textAlign === value
                      ? 'bg-yellow-500/15 text-yellow-500'
                      : 'bg-neutral-800 text-neutral-400 hover:text-white'
                  }`}
                >
                  <Icon size={18} />
                </button>
              ))}
            </div>
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

          {/* 自动暂停关键词 */}
          <div className="space-y-3 rounded-xl bg-neutral-800 p-4">
            <div className="flex items-center gap-3">
              <CirclePause size={18} className="text-neutral-400" />
              <div>
                <span className="block text-sm text-white">自动暂停</span>
                <span className="text-[10px] text-neutral-500">滚动到关键词时自动暂停</span>
              </div>
            </div>
            <input
              type="text"
              value={settings.pauseKeyword}
              onChange={(e) => onChange({ pauseKeyword: e.target.value })}
              placeholder="输入关键词（留空关闭）"
              className="w-full rounded-lg border border-neutral-700 bg-neutral-900 px-3 py-2 text-sm text-white placeholder-neutral-600 focus:border-yellow-500/50 focus:outline-none"
            />
          </div>
        </div>
      </div>
    </div>
  );
}
