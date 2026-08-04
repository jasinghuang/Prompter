import { describe, it, expect, beforeEach, vi } from 'vitest';
import { render, screen, act } from '@testing-library/react';
import { Teleprompter } from './Teleprompter';
import { Script, DEFAULT_SETTINGS } from '../types';

// mock useAutoScroll，暴露 onReachEnd 供测试触发（jsdom 无真实滚动）
vi.mock('../hooks/useAutoScroll', () => ({
  useAutoScroll: vi.fn(),
}));

import { useAutoScroll } from '../hooks/useAutoScroll';

const script: Script = { id: '1', title: '测试稿', content: '一二三四五', createdAt: 1, updatedAt: 1 };
let reachEnd: (() => void) | null = null;

beforeEach(() => {
  localStorage.clear();
  localStorage.setItem('prompter_onboarded', '1'); // 跳过 onboarding 遮罩
  reachEnd = null;
  vi.mocked(useAutoScroll).mockImplementation((opts: any) => {
    reachEnd = opts.onReachEnd;
    return { current: 0 } as any;
  });
});

function renderTel(overrides: Partial<{ onBack: ReturnType<typeof vi.fn>; onCompleted: ReturnType<typeof vi.fn> }> = {}) {
  const handlers = {
    onIndexChange: vi.fn(),
    onChangeSettings: vi.fn(),
    onBack: vi.fn(),
    onEdit: vi.fn(),
    onCompleted: vi.fn(),
    ...overrides,
  };
  render(
    <Teleprompter
      script={script}
      settings={DEFAULT_SETTINGS}
      index={0}
      onIndexChange={handlers.onIndexChange}
      onChangeSettings={handlers.onChangeSettings}
      onBack={handlers.onBack}
      onEdit={handlers.onEdit}
      onCompleted={handlers.onCompleted}
    />
  );
  return handlers;
}

describe('Teleprompter 读完回流', () => {
  it('onReachEnd 触发 onCompleted 并显示提示', () => {
    const h = renderTel();
    act(() => reachEnd!());
    expect(h.onCompleted).toHaveBeenCalledTimes(1);
    expect(screen.getByText(/已读完/)).toBeInTheDocument();
  });

  it('1.2s 后自动调用 onBack', () => {
    vi.useFakeTimers();
    const h = renderTel();
    act(() => reachEnd!());
    expect(h.onBack).not.toHaveBeenCalled();
    act(() => { vi.advanceTimersByTime(1200); });
    expect(h.onBack).toHaveBeenCalledTimes(1);
    vi.useRealTimers();
  });

  it('手动返回不触发 onCompleted', () => {
    const h = renderTel();
    // 点返回按钮（aria-label="返回"）
    act(() => {
      screen.getByLabelText('返回').click();
    });
    expect(h.onCompleted).not.toHaveBeenCalled();
    expect(h.onBack).toHaveBeenCalledTimes(1);
  });
});
