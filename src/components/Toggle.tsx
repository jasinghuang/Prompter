import type { ReactNode } from 'react';

interface Props {
  checked: boolean;
  onChange: (v: boolean) => void;
  label: string;
  description?: string;
  icon?: ReactNode;
}

/**
 * 设置项开关：左 icon + 标题/副标题，右 switch。
 * 滑块用 left-0.5 锚定 + translate-x 平移，避免 absolute 无 left 时依赖 static position 漂移。
 */
export function Toggle({ checked, onChange, label, description, icon }: Props) {
  return (
    <div className="flex items-center justify-between border-t border-white/5 pt-5">
      <div className="flex items-center gap-3">
        {icon}
        <div>
          <span className="block text-sm font-semibold text-white">{label}</span>
          {description && <span className="text-[11px] text-white/30">{description}</span>}
        </div>
      </div>
      <button
        role="switch"
        aria-label={label}
        aria-checked={checked}
        onClick={() => onChange(!checked)}
        className={`relative h-6 w-12 rounded-full ${checked ? 'bg-[#D4A432]' : 'bg-white/10'}`}
        style={{ transition: 'background-color 0.2s ease' }}
      >
        <span
          className={`absolute left-0.5 top-0.5 h-5 w-5 rounded-full bg-white shadow-sm transition-transform duration-200 ${
            checked ? 'translate-x-6' : 'translate-x-0'
          }`}
        />
      </button>
    </div>
  );
}
