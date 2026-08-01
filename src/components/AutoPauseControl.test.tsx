import { describe, it, expect, vi } from 'vitest';
import { render, fireEvent, screen } from '@testing-library/react';
import { AutoPauseControl } from './AutoPauseControl';
import { SettingsPanel } from './SettingsPanel';
import { DEFAULT_SETTINGS } from '../types';

describe('AutoPauseControl', () => {
  it('从空行切换到关键词，保持关键词模式并显示输入框', () => {
    const onChange = vi.fn();
    const { rerender } = render(
      <AutoPauseControl keyword="" paragraph={true} onChange={onChange} />
    );

    expect(screen.getByText('遇到空行时暂停')).toBeTruthy();
    expect(screen.queryByPlaceholderText('输入关键词')).toBeNull();

    fireEvent.click(screen.getByText('关键词'));
    expect(onChange).toHaveBeenCalledWith({ pauseOnParagraph: false });

    // 模拟父组件更新：keyword 仍为空，paragraph 变为 false
    rerender(<AutoPauseControl keyword="" paragraph={false} onChange={onChange} />);

    // 应该保持在关键词模式
    expect(screen.getByText('滚动到关键词时暂停')).toBeTruthy();
    expect(screen.getByPlaceholderText('输入关键词')).toBeTruthy();
  });

  it('通过 SettingsPanel 集成：从空行切换到关键词不会跳回关闭', () => {
    const onChange = vi.fn();
    const paragraphSettings = { ...DEFAULT_SETTINGS, pauseKeyword: '', pauseOnParagraph: true };

    const { rerender } = render(
      <SettingsPanel open={true} settings={paragraphSettings} onChange={onChange} onClose={vi.fn()} />
    );

    // 空行模式
    expect(screen.getByText('遇到空行时暂停')).toBeTruthy();

    // 点击关键词
    fireEvent.click(screen.getByText('关键词'));
    expect(onChange).toHaveBeenCalledWith({ pauseOnParagraph: false });

    // 父组件更新：keyword 空，paragraph 关
    const keywordOffSettings = { ...DEFAULT_SETTINGS, pauseKeyword: '', pauseOnParagraph: false };
    rerender(
      <SettingsPanel open={true} settings={keywordOffSettings} onChange={onChange} onClose={vi.fn()} />
    );

    // 应该保持关键词模式，不是关闭
    expect(screen.getByText('滚动到关键词时暂停')).toBeTruthy();
    expect(screen.getByPlaceholderText('输入关键词')).toBeTruthy();
    expect(screen.queryByText('未启用')).toBeNull();
  });
});
