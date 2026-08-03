import { Settings, Minimize2, Type, AlignJustify, FlipHorizontal, Gauge, MoveHorizontal, Move, AlignLeft, AlignCenter, AlignRight } from 'lucide-react';
import { TeleprompterSettings, TextAlign, FONT_SIZE_MIN, FONT_SIZE_MAX, LETTER_SPACING_MIN, LETTER_SPACING_MAX, LINE_HEIGHT_MIN, LINE_HEIGHT_MAX, PADDING_MIN, PADDING_MAX } from '../types';
import { SPEED_MIN, SPEED_MAX, SPEED_PRESETS } from '../lib/speed';
import { AutoPauseControl } from './AutoPauseControl';

interface Props {
  open: boolean;
  settings: TeleprompterSettings;
  onChange: (patch: Partial<TeleprompterSettings>) => void;
  onClose: () => void;
}

function Slider({
  label,
  icon,
  value,
  min,
  max,
  step,
  suffix,
  onChange,
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
        <span className="flex items-center gap-2 text-[#A1A1AA]">
          {icon}
          {label}
        </span>
        <span className="font-mono tabular-nums text-[#F5F5F5]">
          {value}
          {suffix}
        </span>
      </div>
      <input
        type="range"
        aria-label={label}
        min={min}
        max={max}
        step={step}
        value={value}
        onChange={(e) => onChange(parseFloat(e.target.value))}
        style={{ accentColor: '#D4A432' }}
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
      {/* Overlay */}
      <div className="absolute inset-0 bg-[#0A0A0B]/60" onClick={onClose} />

      {/* Drawer Panel */}
      <div
        className="drawer-spring relative h-full w-80 max-w-[85vw] overflow-y-auto border-l border-[#26262B] bg-[#131316] px-6 pb-[calc(1.5rem+env(safe-area-inset-bottom))] pt-[calc(1.5rem+env(safe-area-inset-top))] shadow-2xl"
        style={{
          animation: 'slide-in-right 0.35s cubic-bezier(0.22, 1, 0.36, 1) forwards',
        }}
      >
        {/* Header */}
        <div className="mb-6 flex items-center justify-between">
          <h2 className="flex items-center gap-2 text-lg font-semibold text-[#F5F5F5]">
            <Settings size={20} className="text-[#A1A1AA]" /> 提词设置
          </h2>
          <button
            onClick={onClose}
            className="btn-spring rounded-full p-2 text-[#71717A] hover:bg-[rgba(212,164,50,0.08)] hover:text-[#F5F5F5] focus-ring"
            aria-label="关闭设置"
            style={{ minHeight: '44px', minWidth: '44px' }}
          >
            <Minimize2 size={20} />
          </button>
        </div>

        <div className="space-y-6">
          <Slider
            label="字号"
            icon={<Type size={16} />}
            value={settings.fontSize}
            min={FONT_SIZE_MIN}
            max={FONT_SIZE_MAX}
            step={2}
            suffix="px"
            onChange={(v) => onChange({ fontSize: v })}
          />
          <Slider
            label="字间距"
            icon={<MoveHorizontal size={16} />}
            value={settings.letterSpacing}
            min={LETTER_SPACING_MIN}
            max={LETTER_SPACING_MAX}
            step={0.01}
            suffix="em"
            onChange={(v) => onChange({ letterSpacing: v })}
          />
          <Slider
            label="行距"
            icon={<AlignJustify size={16} />}
            value={settings.lineHeight}
            min={LINE_HEIGHT_MIN}
            max={LINE_HEIGHT_MAX}
            step={0.1}
            onChange={(v) => onChange({ lineHeight: v })}
          />
          <Slider
            label="两边间距"
            icon={<Move size={16} />}
            value={settings.horizontalPadding}
            min={PADDING_MIN}
            max={PADDING_MAX}
            step={1}
            suffix="%"
            onChange={(v) => onChange({ horizontalPadding: v })}
          />
          <Slider
            label="滚动速度"
            icon={<Gauge size={16} />}
            value={settings.scrollSpeed}
            min={SPEED_MIN}
            max={SPEED_MAX}
            step={10}
            suffix=" 字/分"
            onChange={(v) => onChange({ scrollSpeed: v })}
          />

          {/* Speed Presets */}
          <div className="flex flex-wrap gap-2">
            {SPEED_PRESETS.map((p) => (
              <button
                key={p.id}
                onClick={() => onChange({ scrollSpeed: p.wpn })}
                className={`btn-spring rounded-lg px-2.5 py-1.5 text-xs font-semibold focus-ring ${
                  settings.scrollSpeed === p.wpn
                    ? 'bg-[rgba(212,164,50,0.15)] text-[#D4A432]'
                    : 'bg-[#1A1A1F] text-[#A1A1AA] hover:text-[#F5F5F5] hover:bg-[#26262B]'
                }`}
              >
                {p.name}
              </button>
            ))}
          </div>

          {/* Text Alignment */}
          <div className="space-y-2">
            <span className="flex items-center gap-2 text-sm text-[#A1A1AA]">
              <AlignLeft size={16} />对齐方式
            </span>
            <div className="flex gap-2">
              {ALIGN_OPTIONS.map(({ value, Icon, label }) => (
                <button
                  key={value}
                  title={label}
                  aria-label={label}
                  onClick={() => onChange({ textAlign: value })}
                  className={`btn-spring flex flex-1 items-center justify-center rounded-lg py-2.5 focus-ring ${
                    settings.textAlign === value
                      ? 'bg-[rgba(212,164,50,0.15)] text-[#D4A432]'
                      : 'bg-[#1A1A1F] text-[#A1A1AA] hover:text-[#F5F5F5] hover:bg-[#26262B]'
                  }`}
                >
                  <Icon size={18} />
                </button>
              ))}
            </div>
          </div>

          {/* Mirror Toggle */}
          <div className="flex items-center justify-between border-t border-[#26262B] pt-5">
            <div className="flex items-center gap-3">
              <FlipHorizontal size={16} className="text-[#71717A]" />
              <div>
                <span className="block text-sm font-semibold text-[#F5F5F5]">镜像翻转</span>
                <span className="text-[11px] text-[#71717A]">用于分光镜反射</span>
              </div>
            </div>
            <button
              role="switch"
              aria-checked={settings.mirror}
              onClick={() => onChange({ mirror: !settings.mirror })}
              className={`btn-spring relative h-6 w-12 rounded-full focus-ring ${
                settings.mirror ? 'bg-[#D4A432]' : 'bg-[#26262B]'
              }`}
              style={{ transition: 'background-color 0.2s ease' }}
            >
              <span
                className={`absolute top-0.5 h-5 w-5 rounded-full bg-white shadow-sm transition-transform duration-200 ${
                  settings.mirror ? 'translate-x-6' : 'translate-x-0.5'
                }`}
              />
            </button>
          </div>

          {/* Auto Pause */}
          <div className="border-t border-[#26262B] pt-5">
            <AutoPauseControl
              keyword={settings.pauseKeyword}
              paragraph={settings.pauseOnParagraph}
              onChange={onChange}
            />
          </div>
        </div>
      </div>
    </div>
  );
}
