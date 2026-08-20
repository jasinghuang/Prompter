import { describe, it, expect, vi } from 'vitest';
import { render, fireEvent, screen } from '@testing-library/react';
import { AutoPauseControl } from './AutoPauseControl';
import { SettingsPanel } from './SettingsPanel';
import { DEFAULT_SETTINGS } from '../types';

/** 药丸选项是否处于选中态（选中 = text-white 精确 token） */
function pillSelected(mode: string): boolean {
  const btn = document.querySelector(`[data-pill-value="${mode}"]`);
  return btn ? btn.className.split(/\s+/).includes('text-white') : false;
}

describe('AutoPauseControl', () => {
  it('药丸选项顺序为 关闭、空行、关键词', () => {
    render(<AutoPauseControl keyword="" paragraph={false} onChange={vi.fn()} />);
    const labels = Array.from(document.querySelectorAll('[data-segmented-pill] button')).map((b) => b.textContent);
    expect(labels).toEqual(['关闭', '空行', '关键词']);
  });

  it('面板模式：关键词输入框出现在药丸下方', () => {
    const onChange = vi.fn();
    render(<AutoPauseControl keyword="" paragraph={false} onChange={onChange} />);
    fireEvent.click(screen.getByText('关键词'));
    const input = screen.getByPlaceholderText('输入关键词');
    expect(input.parentElement?.className).not.toContain('flex'); // 不在同一行
  });

  it('inline 模式：关键词输入框在药丸右侧同一行', () => {
    const onChange = vi.fn();
    render(<AutoPauseControl inline keyword="" paragraph={false} onChange={onChange} />);
    fireEvent.click(screen.getByText('关键词'));
    const input = screen.getByPlaceholderText('输入关键词');
    expect(input.parentElement?.className).toContain('flex'); // 同一行
    const pill = input.parentElement!.querySelector('[data-segmented-pill]');
    expect(pill).toBeTruthy();
    expect(pill!.compareDocumentPosition(input) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy(); // 输入框在药丸右侧
  });

  it('从空行切换到关键词，保持关键词模式并显示输入框', () => {
    const onChange = vi.fn();
    const { rerender } = render(
      <AutoPauseControl keyword="" paragraph={true} onChange={onChange} />
    );

    expect(pillSelected('paragraph')).toBe(true);
    expect(screen.queryByPlaceholderText('输入关键词')).toBeNull();

    fireEvent.click(screen.getByText('关键词'));
    expect(onChange).toHaveBeenCalledWith({ pauseOnParagraph: false });

    // 模拟父组件更新：keyword 仍为空，paragraph 变为 false
    rerender(<AutoPauseControl keyword="" paragraph={false} onChange={onChange} />);

    // 应该保持在关键词模式
    expect(pillSelected('keyword')).toBe(true);
    expect(screen.getByPlaceholderText('输入关键词')).toBeTruthy();
  });

  it('通过 SettingsPanel 集成：从空行切换到关键词不会跳回关闭', () => {
    const onChange = vi.fn();
    const paragraphSettings = { ...DEFAULT_SETTINGS, pauseKeyword: '', pauseOnParagraph: true };

    const { rerender } = render(
      <SettingsPanel open={true} settings={paragraphSettings} onChange={onChange} onClose={vi.fn()} />
    );

    // 空行模式
    expect(pillSelected('paragraph')).toBe(true);

    // 点击关键词
    fireEvent.click(screen.getByText('关键词'));
    expect(onChange).toHaveBeenCalledWith({ pauseOnParagraph: false });

    // 父组件更新：keyword 空，paragraph 关
    const keywordOffSettings = { ...DEFAULT_SETTINGS, pauseKeyword: '', pauseOnParagraph: false };
    rerender(
      <SettingsPanel open={true} settings={keywordOffSettings} onChange={onChange} onClose={vi.fn()} />
    );

    // 应该保持关键词模式，不是关闭
    expect(pillSelected('keyword')).toBe(true);
    expect(screen.getByPlaceholderText('输入关键词')).toBeTruthy();
    expect(pillSelected('off')).toBe(false);
  });
});
