import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, fireEvent, screen, act, within } from '@testing-library/react';
import { ScriptEditor } from './ScriptEditor';
import { Script } from '../types';

const makeScript = (over: Partial<Script> = {}): Script => ({
  id: '1', title: '原标题', content: '原内容', createdAt: 1, updatedAt: 1, ...over,
});

const makeProps = (over: Record<string, unknown> = {}) => ({
  script: makeScript(),
  folder: undefined,
  folders: ['口播', 'vlog'] as string[],
  onFolderChange: vi.fn(),
  pauseKeyword: '',
  onPauseKeywordChange: vi.fn(),
  pauseOnParagraph: false,
  onPauseOnParagraphChange: vi.fn(),
  splitMode: 'paragraph' as const,
  splitKeyword: '',
  onSplitModeChange: vi.fn(),
  onSplitKeywordChange: vi.fn(),
  onSave: vi.fn(),
  onBack: vi.fn(),
  onSplit: vi.fn(),
  ...over,
});

beforeEach(() => vi.useFakeTimers());
afterEach(() => vi.useRealTimers());

function splitRow(): HTMLElement {
  const btn = screen.getByRole('button', { name: /智能拆分/ });
  return btn.parentElement as HTMLElement;
}

function splitButton(): HTMLButtonElement {
  return screen.getByRole('button', { name: /智能拆分/ }) as HTMLButtonElement;
}

describe('ScriptEditor', () => {
  it('编辑标题 500ms 后触发 onSave（防抖）', () => {
    const onSave = vi.fn();
    render(<ScriptEditor {...makeProps({ onSave })} />);
    const title = screen.getByDisplayValue('原标题');
    fireEvent.change(title, { target: { value: '新标题' } });
    expect(onSave).not.toHaveBeenCalled();
    act(() => vi.advanceTimersByTime(500));
    expect(onSave).toHaveBeenCalledWith('1', '新标题', '原内容');
  });

  it('编辑正文 500ms 后触发 onSave', () => {
    const onSave = vi.fn();
    render(<ScriptEditor {...makeProps({ onSave })} />);
    const content = screen.getByDisplayValue('原内容');
    fireEvent.change(content, { target: { value: '新内容' } });
    act(() => vi.advanceTimersByTime(500));
    expect(onSave).toHaveBeenCalledWith('1', '原标题', '新内容');
  });

  it('返回按钮调用 onBack', () => {
    const onBack = vi.fn();
    render(<ScriptEditor {...makeProps({ onBack })} />);
    fireEvent.click(screen.getByTitle('返回'));
    expect(onBack).toHaveBeenCalled();
  });

  it('「自动暂停」标题为白色（非 white/50）', () => {
    render(<ScriptEditor {...makeProps()} />);
    const el = screen.getByText('自动暂停');
    expect(el.className).toContain('text-white');
    expect(el.className).not.toContain('text-white/50');
  });

  it('标题输入框 placeholder 使用 white/30', () => {
    render(<ScriptEditor {...makeProps()} />);
    const el = screen.getByPlaceholderText('稿件标题');
    expect(el.className).toContain('placeholder-white/30');
    expect(el.className).not.toContain('#71717A');
  });

  it('正文文字为白色（非 white/50），placeholder 使用 white/30', () => {
    render(<ScriptEditor {...makeProps()} />);
    const el = screen.getByPlaceholderText('在此输入或粘贴提词稿件...');
    expect(el.className).toContain('text-white');
    expect(el.className).not.toContain('text-white/50');
    expect(el.className).toContain('placeholder-white/30');
    expect(el.className).not.toContain('#71717A');
  });

  it('返回按钮与标题输入框同一行（左侧，胶囊壳包裹）', () => {
    render(<ScriptEditor {...makeProps()} />);
    const back = screen.getByTitle('返回');
    const title = screen.getByPlaceholderText('稿件标题');
    // 胶囊壳与标题同处标题行，按钮在壳内居中
    const capsule = back.parentElement!;
    expect(capsule.className).toContain('rounded-full');
    const wrapper = capsule.parentElement!;
    expect(wrapper.parentElement).toBe(title.parentElement);
    expect(wrapper.parentElement!.className).toContain('flex');
    expect(back.compareDocumentPosition(title) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy(); // 返回按钮在标题左侧
  });

  it('返回按钮胶囊与播放页同位（顶 12px、左 16px+safe-area，无负 margin）', () => {
    render(<ScriptEditor {...makeProps()} />);
    const back = screen.getByTitle('返回');
    const capsule = back.parentElement!;
    const wrapper = capsule.parentElement!;
    expect(wrapper.className).not.toMatch(/-m[ltrb]-/); // 无负外距
    const main = wrapper.closest('main')!;
    expect(main.className).toContain('pt-[calc(0.75rem+env(safe-area-inset-top))]');
    expect(back.className).toContain('justify-center');
  });

  // ── 智能拆分工具栏 ──

  it('智能拆分按钮与拆分模式分段控件同一行，且不在标题行', () => {
    render(<ScriptEditor {...makeProps()} />);
    const row = splitRow();
    const pill = row.querySelector('[data-segmented-pill]');
    const title = screen.getByPlaceholderText('稿件标题');
    expect(splitButton().parentElement).toBe(row);
    expect(pill).not.toBeNull();
    expect(row.contains(pill)).toBe(true);
    expect(title.parentElement).not.toBe(row);
  });

  it('默认空行模式不显示关键词输入框', () => {
    render(<ScriptEditor {...makeProps()} />);
    expect(screen.queryByPlaceholderText('输入拆分关键词')).toBeNull();
  });

  it('切换到关键词模式显示输入框并回调', () => {
    const onSplitModeChange = vi.fn();
    render(<ScriptEditor {...makeProps({ onSplitModeChange })} />);
    fireEvent.click(within(splitRow()).getByRole('button', { name: '关键词' }));
    expect(onSplitModeChange).toHaveBeenCalledWith('keyword');
  });

  it('拆分关键词输入触发回调', () => {
    const onSplitKeywordChange = vi.fn();
    render(<ScriptEditor {...makeProps({ splitMode: 'keyword', onSplitKeywordChange })} />);
    fireEvent.change(screen.getByPlaceholderText('输入拆分关键词'), { target: { value: '主持人：' } });
    expect(onSplitKeywordChange).toHaveBeenCalledWith('主持人：');
  });

  it('空行模式：正文含空行时按钮可用', () => {
    render(<ScriptEditor {...makeProps({ script: makeScript({ content: '甲\n\n乙' }) })} />);
    expect(splitButton().disabled).toBe(false);
  });

  it('空行模式：正文无空行时按钮禁用', () => {
    render(<ScriptEditor {...makeProps({ script: makeScript({ content: '甲乙' }) })} />);
    expect(splitButton().disabled).toBe(true);
  });

  it('关键词模式：关键词为空时按钮禁用', () => {
    render(<ScriptEditor {...makeProps({ splitMode: 'keyword', splitKeyword: '', script: makeScript({ content: '甲主持人：乙' }) })} />);
    expect(splitButton().disabled).toBe(true);
  });

  it('关键词模式：正文不含关键词时按钮禁用', () => {
    render(<ScriptEditor {...makeProps({ splitMode: 'keyword', splitKeyword: '主持人：', script: makeScript({ content: '甲乙' }) })} />);
    expect(splitButton().disabled).toBe(true);
  });

  it('关键词模式：正文含关键词时按钮可用', () => {
    render(<ScriptEditor {...makeProps({ splitMode: 'keyword', splitKeyword: '主持人：', script: makeScript({ content: '甲主持人：乙' }) })} />);
    expect(splitButton().disabled).toBe(false);
  });

  it('点击智能拆分传入编辑器当前内容（不等待防抖保存）', () => {
    const onSplit = vi.fn();
    render(<ScriptEditor {...makeProps({ script: makeScript({ content: '旧内容' }), onSplit })} />);
    fireEvent.change(screen.getByPlaceholderText('在此输入或粘贴提词稿件...'), { target: { value: '新\n\n内容' } });
    fireEvent.click(splitButton());
    expect(onSplit).toHaveBeenCalledWith('新\n\n内容');
  });

  it('分组行：未分组默认高亮，点选文件夹回调 onFolderChange', () => {
    const onFolderChange = vi.fn();
    render(<ScriptEditor {...makeProps({ onFolderChange })} />);
    // 未分组 chip 高亮
    expect(screen.getByText('未分组').className).toContain('bg-white/15');
    fireEvent.click(screen.getByText('口播'));
    expect(onFolderChange).toHaveBeenCalledWith('口播');
  });

  it('分组行：当前文件夹高亮，点「未分组」回调 null', () => {
    const onFolderChange = vi.fn();
    render(<ScriptEditor {...makeProps({ folder: 'vlog', onFolderChange })} />);
    expect(screen.getByText('vlog').className).toContain('bg-white/15');
    fireEvent.click(screen.getByText('未分组'));
    expect(onFolderChange).toHaveBeenCalledWith(null);
  });

  it('分组行：内联新建分组，回车提交回调新名称', () => {
    const onFolderChange = vi.fn();
    render(<ScriptEditor {...makeProps({ onFolderChange })} />);
    fireEvent.click(screen.getByLabelText('新建分组'));
    fireEvent.change(screen.getByLabelText('新分组名'), { target: { value: '带货' } });
    fireEvent.keyDown(screen.getByLabelText('新分组名'), { key: 'Enter' });
    expect(onFolderChange).toHaveBeenCalledWith('带货');
  });

  it('分组行：中文输入法选字的回车（isComposing）不误提交', () => {
    const onFolderChange = vi.fn();
    render(<ScriptEditor {...makeProps({ onFolderChange })} />);
    fireEvent.click(screen.getByLabelText('新建分组'));
    const input = screen.getByLabelText('新分组名');
    fireEvent.change(input, { target: { value: '带货' } });
    fireEvent.keyDown(input, { key: 'Enter', isComposing: true });
    expect(onFolderChange).not.toHaveBeenCalled(); // 值尚未合成，不提交
    expect(input).toBeInTheDocument(); // 输入框保持打开
    fireEvent.keyDown(input, { key: 'Enter' }); // 真正的回车才提交
    expect(onFolderChange).toHaveBeenCalledWith('带货');
  });
});
