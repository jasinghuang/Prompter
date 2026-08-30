import { describe, it, expect, vi } from 'vitest';
import { render, fireEvent, screen } from '@testing-library/react';
import { Controls } from './Controls';

const baseProps = {
  fontSize: 64,
  speed: 160,
  visible: true,
  onFontSizeChange: vi.fn(),
  onSpeedChange: vi.fn(),
};

describe('Controls', () => {
  it('渲染字号和速度滑块', () => {
    render(<Controls {...baseProps} />);
    expect(screen.getByLabelText('字号')).toBeInTheDocument();
    expect(screen.getByLabelText('速度')).toBeInTheDocument();
  });

  it('拖动字号滑块调用 onFontSizeChange', () => {
    const onFontSizeChange = vi.fn();
    render(<Controls {...baseProps} onFontSizeChange={onFontSizeChange} />);
    fireEvent.change(screen.getByLabelText('字号'), { target: { value: '48' } });
    expect(onFontSizeChange).toHaveBeenCalledWith(48);
  });

  it('拖动速度滑块调用 onSpeedChange', () => {
    const onSpeedChange = vi.fn();
    render(<Controls {...baseProps} onSpeedChange={onSpeedChange} />);
    fireEvent.change(screen.getByLabelText('速度'), { target: { value: '240' } });
    expect(onSpeedChange).toHaveBeenCalledWith(240);
  });

  it('标签与数值分离：暗淡标签 + 独立数值胶囊', () => {
    render(<Controls {...baseProps} fontSize={72} speed={200} />);
    // 标签为暗淡小字
    for (const el of [screen.getByText('字号'), screen.getByText('速度')]) {
      expect(el.className).toContain('text-white/50');
    }
    // 数值在白色等宽胶囊中
    for (const el of [screen.getByText('72'), screen.getByText('200')]) {
      expect(el.className).toContain('font-mono');
      expect(el.className).toContain('text-white');
      expect(el.className).not.toContain('text-white/50');
    }
  });

  it('visible=false 时工具栏隐藏且不可交互', () => {
    render(<Controls {...baseProps} visible={false} />);
    const bar = document.querySelector('.glass-bar') as HTMLElement;
    expect(bar.className).toContain('pointer-events-none');
  });
});
