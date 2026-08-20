import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, fireEvent, screen, act } from '@testing-library/react';
import { ScriptEditor } from './ScriptEditor';
import { Script } from '../types';

const makeScript = (over: Partial<Script> = {}): Script => ({
  id: '1', title: '原标题', content: '原内容', createdAt: 1, updatedAt: 1, ...over,
});

beforeEach(() => vi.useFakeTimers());
afterEach(() => vi.useRealTimers());

describe('ScriptEditor', () => {
  it('编辑标题 500ms 后触发 onSave（防抖）', () => {
    const onSave = vi.fn();
    render(<ScriptEditor script={makeScript()} pauseKeyword="" onPauseKeywordChange={() => {}} pauseOnParagraph={false} onPauseOnParagraphChange={() => {}} onSplit={() => {}} onSave={onSave} onBack={() => {}} />);
    const title = screen.getByDisplayValue('原标题');
    fireEvent.change(title, { target: { value: '新标题' } });
    expect(onSave).not.toHaveBeenCalled();
    act(() => vi.advanceTimersByTime(500));
    expect(onSave).toHaveBeenCalledWith('1', '新标题', '原内容');
  });

  it('编辑正文 500ms 后触发 onSave', () => {
    const onSave = vi.fn();
    render(<ScriptEditor script={makeScript()} pauseKeyword="" onPauseKeywordChange={() => {}} pauseOnParagraph={false} onPauseOnParagraphChange={() => {}} onSplit={() => {}} onSave={onSave} onBack={() => {}} />);
    const content = screen.getByDisplayValue('原内容');
    fireEvent.change(content, { target: { value: '新内容' } });
    act(() => vi.advanceTimersByTime(500));
    expect(onSave).toHaveBeenCalledWith('1', '原标题', '新内容');
  });

  it('返回按钮调用 onBack', () => {
    const onBack = vi.fn();
    render(<ScriptEditor script={makeScript()} pauseKeyword="" onPauseKeywordChange={() => {}} pauseOnParagraph={false} onPauseOnParagraphChange={() => {}} onSplit={() => {}} onSave={() => {}} onBack={onBack} />);
    fireEvent.click(screen.getByTitle('返回'));
    expect(onBack).toHaveBeenCalled();
  });

  it('「自动暂停」标题为白色（非 white/50）', () => {
    render(<ScriptEditor script={makeScript()} pauseKeyword="" onPauseKeywordChange={() => {}} pauseOnParagraph={false} onPauseOnParagraphChange={() => {}} onSplit={() => {}} onSave={() => {}} onBack={() => {}} />);
    const el = screen.getByText('自动暂停');
    expect(el.className).toContain('text-white');
    expect(el.className).not.toContain('text-white/50');
  });

  it('标题输入框 placeholder 使用 white/30', () => {
    render(<ScriptEditor script={makeScript()} pauseKeyword="" onPauseKeywordChange={() => {}} pauseOnParagraph={false} onPauseOnParagraphChange={() => {}} onSplit={() => {}} onSave={() => {}} onBack={() => {}} />);
    const el = screen.getByPlaceholderText('稿件标题');
    expect(el.className).toContain('placeholder-white/30');
    expect(el.className).not.toContain('#71717A');
  });

  it('正文文字为白色（非 white/50），placeholder 使用 white/30', () => {
    render(<ScriptEditor script={makeScript()} pauseKeyword="" onPauseKeywordChange={() => {}} pauseOnParagraph={false} onPauseOnParagraphChange={() => {}} onSplit={() => {}} onSave={() => {}} onBack={() => {}} />);
    const el = screen.getByPlaceholderText('在此输入或粘贴提词稿件...');
    expect(el.className).toContain('text-white');
    expect(el.className).not.toContain('text-white/50');
    expect(el.className).toContain('placeholder-white/30');
    expect(el.className).not.toContain('#71717A');
  });

  it('智能拆分按钮与标题输入框同一行（靠右）', () => {
    render(<ScriptEditor script={makeScript()} pauseKeyword="" onPauseKeywordChange={() => {}} pauseOnParagraph={false} onPauseOnParagraphChange={() => {}} onSplit={() => {}} onSave={() => {}} onBack={() => {}} />);
    const btn = screen.getByRole('button', { name: '智能拆分' });
    const title = screen.getByPlaceholderText('稿件标题');
    expect(btn.parentElement).toBe(title.parentElement);
    expect(btn.parentElement?.className).toContain('flex');
    expect(btn.parentElement?.querySelector('[data-segmented-pill]')).toBeNull(); // 不再与自动暂停同模块
  });

  it('返回按钮与标题输入框同一行（左侧）', () => {
    render(<ScriptEditor script={makeScript()} pauseKeyword="" onPauseKeywordChange={() => {}} pauseOnParagraph={false} onPauseOnParagraphChange={() => {}} onSplit={() => {}} onSave={() => {}} onBack={() => {}} />);
    const back = screen.getByTitle('返回');
    const title = screen.getByPlaceholderText('稿件标题');
    expect(back.parentElement).toBe(title.parentElement);
    expect(back.parentElement?.className).toContain('flex');
    expect(back.compareDocumentPosition(title) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy(); // 返回按钮在标题左侧
  });

  it('返回按钮图标与页面内容左缘对齐（按钮左扩入页边距、图标居中）', () => {
    render(<ScriptEditor script={makeScript()} pauseKeyword="" onPauseKeywordChange={() => {}} pauseOnParagraph={false} onPauseOnParagraphChange={() => {}} onSplit={() => {}} onSave={() => {}} onBack={() => {}} />);
    const back = screen.getByTitle('返回');
    expect(back.className).toContain('-ml-3'); // 44px 盒左移 12px → 20px 图标起点恰好 16px
    expect(back.className).toContain('justify-center');
    expect(back.className).not.toContain('justify-start');
  });
});
