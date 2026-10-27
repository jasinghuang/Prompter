import type { ReactNode } from 'react';

/**
 * 双胶囊控件体系（播放页顶栏、编辑页返回共用）：
 * 胶囊壳 44px 触控行（= T1 层级），内格 34px、图标 18px、分颊 1px×16px。
 * 底色与卡片同族（rgba(19,19,22,.72) + 1px 白 7% 描边），
 * 不用 backdrop-filter —— 规避 Chromium 文字残影与 iOS standalone 花屏。
 */

export function Capsule({ children }: { children: ReactNode }) {
  return (
    <div className="flex h-11 shrink-0 items-center rounded-full border border-white/[0.07] bg-[rgba(19,19,22,0.72)] px-[5px]">
      {children}
    </div>
  );
}

export function CapsuleDivider() {
  return <span aria-hidden="true" className="mx-[5px] h-4 w-px bg-white/10" />;
}

interface CapsuleButtonProps {
  label: string;
  onClick: () => void;
  children: ReactNode;
  /** 高亮态（如已拍摄标记）：格内衬绿底、图标绿色 */
  active?: boolean;
}

export function CapsuleButton({ label, onClick, children, active }: CapsuleButtonProps) {
  return (
    <button
      onClick={onClick}
      aria-label={label}
      title={label}
      className={`flex h-[34px] min-w-[34px] items-center justify-center rounded-full px-[11px] transition-colors active:scale-95 ${
        active ? 'bg-green-500/[0.16] text-green-400' : 'text-white/65 hover:bg-white/10 hover:text-white'
      }`}
    >
      {children}
    </button>
  );
}
