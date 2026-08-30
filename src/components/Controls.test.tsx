import { describe, it, expect, vi } from 'vitest';
import { render, fireEvent, screen } from '@testing-library/react';
import { Controls } from './Controls';

const baseProps = {
  fontSize: 64,
  speed: 160,
  visible: true,
  isPlaying: false,
  onTogglePlay: vi.fn(),
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

  it('显示当前字号和速度值', () => {
    render(<Controls {...baseProps} fontSize={72} speed={200} />);
    expect(screen.getByText('72')).toBeInTheDocument();
    expect(screen.getByText('200')).toBeInTheDocument();
  });

  it('点击步进按钮按步长调整字号', () => {
    const onFontSizeChange = vi.fn();
    render(<Controls {...baseProps} fontSize={64} onFontSizeChange={onFontSizeChange} />);
    fireEvent.click(screen.getByLabelText('减小字号'));
    expect(onFontSizeChange).toHaveBeenCalledWith(62);
    fireEvent.click(screen.getByLabelText('增大字号'));
    expect(onFontSizeChange).toHaveBeenCalledWith(66);
  });

  it('字号步进在下限不越界', () => {
    const onFontSizeChange = vi.fn();
    render(<Controls {...baseProps} fontSize={24} onFontSizeChange={onFontSizeChange} />);
    fireEvent.click(screen.getByLabelText('减小字号'));
    expect(onFontSizeChange).toHaveBeenCalledWith(24);
  });

  it('点击步进按钮按步长调整速度', () => {
    const onSpeedChange = vi.fn();
    render(<Controls {...baseProps} speed={160} onSpeedChange={onSpeedChange} />);
    fireEvent.click(screen.getByLabelText('减小速度'));
    expect(onSpeedChange).toHaveBeenCalledWith(150);
    fireEvent.click(screen.getByLabelText('增大速度'));
    expect(onSpeedChange).toHaveBeenCalledWith(170);
  });

  it('暂停时显示播放按钮，点击触发 onTogglePlay', () => {
    const onTogglePlay = vi.fn();
    render(<Controls {...baseProps} isPlaying={false} onTogglePlay={onTogglePlay} />);
    const btn = screen.getByLabelText('播放');
    fireEvent.click(btn);
    expect(onTogglePlay).toHaveBeenCalledTimes(1);
  });

  it('播放时按钮语义为暂停', () => {
    render(<Controls {...baseProps} isPlaying />);
    expect(screen.getByLabelText('暂停')).toBeInTheDocument();
  });

  it('数值胶囊为白色等宽字体', () => {
    render(<Controls {...baseProps} fontSize={64} speed={160} />);
    for (const el of [screen.getByText('64'), screen.getByText('160')]) {
      expect(el.className).toContain('font-mono');
      expect(el.className).toContain('text-white');
      expect(el.className).not.toContain('text-white/50');
    }
  });
});
