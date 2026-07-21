import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, cleanup } from '@testing-library/react';
import { AddToHomeScreenPrompt } from './AddToHomeScreenPrompt';
import * as pwa from '../lib/pwa';

beforeEach(() => {
  cleanup();
  localStorage.clear();
  vi.restoreAllMocks();
});

describe('AddToHomeScreenPrompt', () => {
  it('不满足条件时不渲染', () => {
    vi.spyOn(pwa, 'detectStandalone').mockReturnValue(false);
    vi.spyOn(pwa, 'detectIOS').mockReturnValue(false);
    render(<AddToHomeScreenPrompt />);
    expect(screen.queryByText(/添加到主屏幕|安装到主屏幕/)).toBeNull();
  });

  it('iOS + 未关闭时渲染提示文案', () => {
    vi.spyOn(pwa, 'detectStandalone').mockReturnValue(false);
    vi.spyOn(pwa, 'detectIOS').mockReturnValue(true);
    render(<AddToHomeScreenPrompt />);
    expect(screen.getByText(/添加到主屏幕/)).toBeInTheDocument();
  });

  it('点关闭按钮后写 localStorage 并消失', () => {
    vi.spyOn(pwa, 'detectStandalone').mockReturnValue(false);
    vi.spyOn(pwa, 'detectIOS').mockReturnValue(true);
    const { container } = render(<AddToHomeScreenPrompt />);
    fireEvent.click(container.querySelector('[aria-label="关闭"]')!);
    expect(localStorage.getItem('prompter_aths_dismissed')).toBe('1');
    expect(container.querySelector('[aria-label="关闭"]')).toBeNull();
  });
});
