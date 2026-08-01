import { describe, it, expect, vi } from 'vitest';
import { render, fireEvent, screen } from '@testing-library/react';
import { SettingsPanel } from './SettingsPanel';
import { DEFAULT_SETTINGS } from '../types';

const baseProps = {
  open: true,
  settings: DEFAULT_SETTINGS,
  onChange: vi.fn(),
  onClose: vi.fn(),
};

describe('SettingsPanel', () => {
  it('open=false 时不渲染', () => {
    const { container } = render(<SettingsPanel {...baseProps} open={false} />);
    expect(container.querySelector('input[type="range"]')).toBeNull();
  });

  it('拖动字号滑块调用 onChange({ fontSize })', () => {
    const onChange = vi.fn();
    render(<SettingsPanel {...baseProps} onChange={onChange} />);
    fireEvent.change(screen.getByLabelText('字号'), { target: { value: '90' } });
    expect(onChange).toHaveBeenCalledWith(expect.objectContaining({ fontSize: 90 }));
  });

  it('拖动两边间距滑块调用 onChange({ horizontalPadding })', () => {
    const onChange = vi.fn();
    render(<SettingsPanel {...baseProps} onChange={onChange} />);
    fireEvent.change(screen.getByLabelText('两边间距'), { target: { value: '15' } });
    expect(onChange).toHaveBeenCalledWith(expect.objectContaining({ horizontalPadding: 15 }));
  });

  it('点击居中对齐按钮调用 onChange({ textAlign: "center" })', () => {
    const onChange = vi.fn();
    render(<SettingsPanel {...baseProps} onChange={onChange} />);
    fireEvent.click(screen.getByLabelText('居中对齐'));
    expect(onChange).toHaveBeenCalledWith(expect.objectContaining({ textAlign: 'center' }));
  });

  it('镜像开关点击切换', () => {
    const onChange = vi.fn();
    render(<SettingsPanel {...baseProps} onChange={onChange} />);
    fireEvent.click(screen.getByRole('switch'));
    expect(onChange).toHaveBeenCalledWith(expect.objectContaining({ mirror: true }));
  });

  it('点击预设按钮"标准"设置 scrollSpeed=160', () => {
    const onChange = vi.fn();
    render(<SettingsPanel {...baseProps} settings={{ ...DEFAULT_SETTINGS, scrollSpeed: 80 }} onChange={onChange} />);
    fireEvent.click(screen.getByText('标准'));
    expect(onChange).toHaveBeenCalledWith(expect.objectContaining({ scrollSpeed: 160 }));
  });
});
