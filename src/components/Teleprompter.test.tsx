import { describe, it, expect, beforeEach, vi } from 'vitest';
import { render, screen, act } from '@testing-library/react';
import { Teleprompter } from './Teleprompter';
import { Script, DEFAULT_SETTINGS, TeleprompterSettings } from '../types';

// mock useAutoScroll，暴露 onReachEnd 供测试触发（jsdom 无真实滚动）
vi.mock('../hooks/useAutoScroll', () => ({
  useAutoScroll: vi.fn(),
}));

// mock 自动暂停钩子，暴露 reset 供测试断言（restart 时重置命中记录）
vi.mock('../hooks/usePauseOnKeyword', () => ({
  usePauseOnKeyword: vi.fn(),
}));
vi.mock('../hooks/usePauseOnParagraph', () => ({
  usePauseOnParagraph: vi.fn(),
}));

import { useAutoScroll } from '../hooks/useAutoScroll';
import { usePauseOnKeyword } from '../hooks/usePauseOnKeyword';
import { usePauseOnParagraph } from '../hooks/usePauseOnParagraph';

const script: Script = { id: '1', title: '测试稿', content: '一二三四五', createdAt: 1, updatedAt: 1 };
let reachEnd: (() => void) | null = null;
let resetKeywordPause = vi.fn();
let resetParagraphPause = vi.fn();

beforeEach(() => {
  localStorage.clear();
  localStorage.setItem('prompter_onboarded', '1'); // 跳过 onboarding 遮罩
  reachEnd = null;
  resetKeywordPause = vi.fn();
  resetParagraphPause = vi.fn();
  vi.mocked(useAutoScroll).mockImplementation((opts: any) => {
    reachEnd = opts.onReachEnd;
    return { current: 0 } as any;
  });
  vi.mocked(usePauseOnKeyword).mockReturnValue(resetKeywordPause);
  vi.mocked(usePauseOnParagraph).mockReturnValue(resetParagraphPause);
});

function renderTel(settings: TeleprompterSettings = DEFAULT_SETTINGS) {
  const handlers = {
    onIndexChange: vi.fn(),
    onChangeSettings: vi.fn(),
    onBack: vi.fn(),
    onEdit: vi.fn(),
    onCompleted: vi.fn(),
  };
  render(
    <Teleprompter
      script={script}
      settings={settings}
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

const LIST_MODE: TeleprompterSettings = { ...DEFAULT_SETTINGS, completeAction: 'list' };

describe('Teleprompter 读完动作', () => {
  it('list：onReachEnd 触发 onCompleted 并显示提示', () => {
    const h = renderTel(LIST_MODE);
    act(() => reachEnd!());
    expect(h.onCompleted).toHaveBeenCalledTimes(1);
    expect(screen.getByText(/已读完/)).toBeInTheDocument();
  });

  it('list：1.2s 后自动调用 onBack', () => {
    vi.useFakeTimers();
    const h = renderTel(LIST_MODE);
    act(() => reachEnd!());
    expect(h.onBack).not.toHaveBeenCalled();
    act(() => { vi.advanceTimersByTime(1200); });
    expect(h.onBack).toHaveBeenCalledTimes(1);
    vi.useRealTimers();
  });

  it('none（默认）：onReachEnd 只停止播放，不标记/不提示/不返回', () => {
    const h = renderTel(); // DEFAULT_SETTINGS.completeAction = 'none'
    act(() => reachEnd!());
    expect(h.onCompleted).not.toHaveBeenCalled();
    expect(h.onBack).not.toHaveBeenCalled();
    expect(screen.queryByText(/已读完/)).toBeNull();
  });

  it('restart：滚动回到开头，不标记/不提示/不返回', () => {
    const h = renderTel({ ...DEFAULT_SETTINGS, completeAction: 'restart' });
    const vp = document.querySelector('.teleprompter-touch') as HTMLElement;
    vp.scrollTop = 500; // 模拟已滚到末尾
    act(() => reachEnd!());
    expect(vp.scrollTop).toBe(0);
    expect(h.onCompleted).not.toHaveBeenCalled();
    expect(h.onBack).not.toHaveBeenCalled();
    expect(screen.queryByText(/已读完/)).toBeNull();
    expect(screen.getByLabelText('播放')).toBeInTheDocument(); // 暂停在开头
  });

  it('restart：可重复触发，第二次读完同样不标记/不返回', () => {
    const h = renderTel({ ...DEFAULT_SETTINGS, completeAction: 'restart' });
    act(() => reachEnd!());
    act(() => reachEnd!());
    expect(h.onCompleted).not.toHaveBeenCalled();
    expect(h.onBack).not.toHaveBeenCalled();
  });

  it('restart：重置自动暂停命中记录，重读时暂停重新生效', () => {
    renderTel({ ...DEFAULT_SETTINGS, completeAction: 'restart' });
    act(() => reachEnd!());
    expect(resetKeywordPause).toHaveBeenCalledTimes(1);
    expect(resetParagraphPause).toHaveBeenCalledTimes(1);
  });

  it('手动返回不触发 onCompleted', () => {
    const h = renderTel(LIST_MODE);
    act(() => {
      screen.getByLabelText('返回').click();
    });
    expect(h.onCompleted).not.toHaveBeenCalled();
    expect(h.onBack).toHaveBeenCalledTimes(1);
  });
});
