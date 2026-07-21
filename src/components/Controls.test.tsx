import { describe, it, expect, vi } from 'vitest';
import { render, fireEvent, screen } from '@testing-library/react';
import { Controls } from './Controls';

const baseProps = {
  fontSize: 64,
  speed: 160,
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
});
