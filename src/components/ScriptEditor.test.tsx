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
    render(<ScriptEditor script={makeScript()} pauseKeyword="" onPauseKeywordChange={() => {}} onSave={onSave} onBack={() => {}} />);
    const title = screen.getByDisplayValue('原标题');
    fireEvent.change(title, { target: { value: '新标题' } });
    expect(onSave).not.toHaveBeenCalled();
    act(() => vi.advanceTimersByTime(500));
    expect(onSave).toHaveBeenCalledWith('1', '新标题', '原内容');
  });

  it('编辑正文 500ms 后触发 onSave', () => {
    const onSave = vi.fn();
    render(<ScriptEditor script={makeScript()} pauseKeyword="" onPauseKeywordChange={() => {}} onSave={onSave} onBack={() => {}} />);
    const content = screen.getByDisplayValue('原内容');
    fireEvent.change(content, { target: { value: '新内容' } });
    act(() => vi.advanceTimersByTime(500));
    expect(onSave).toHaveBeenCalledWith('1', '原标题', '新内容');
  });

  it('返回按钮调用 onBack', () => {
    const onBack = vi.fn();
    render(<ScriptEditor script={makeScript()} pauseKeyword="" onPauseKeywordChange={() => {}} onSave={() => {}} onBack={onBack} />);
    fireEvent.click(screen.getByTitle('返回'));
    expect(onBack).toHaveBeenCalled();
  });
});
