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
    fireEvent.click(screen.getByRole('switch', { name: '镜像翻转' }));
    expect(onChange).toHaveBeenCalledWith(expect.objectContaining({ mirror: true }));
  });

  it('所有区块标题统一：text-sm font-semibold 白字，无 white/50', () => {
    render(<SettingsPanel {...baseProps} />);
    const titles = ['字号', '字间距', '行距', '两边间距', '滚动速度', '对齐方式', '镜像翻转'];
    for (const t of titles) {
      const el = screen.getByText(t);
      expect(el.className).toContain('text-sm');
      expect(el.className).toContain('font-semibold');
      expect(el.className).toContain('text-white');
      expect(el.className).not.toContain('text-white/50');
    }
  });

  it('速度预设快捷按钮已移除', () => {
    render(<SettingsPanel {...baseProps} />);
    for (const name of ['龟速', '标准', '快语', '极速']) {
      expect(screen.queryByText(name)).toBeNull();
    }
  });

  it('镜像翻转不再渲染小字说明', () => {
    render(<SettingsPanel {...baseProps} />);
    expect(screen.queryByText('用于分光镜反射')).toBeNull();
  });

  it('自动暂停不再渲染小字说明', () => {
    render(<SettingsPanel {...baseProps} />);
    expect(screen.queryByText('滚动到关键词时暂停')).toBeNull();
    expect(screen.queryByText('遇到空行时暂停')).toBeNull();
    expect(screen.queryByText('未启用')).toBeNull();
  });

  it('面板标题为「设置」', () => {
    render(<SettingsPanel {...baseProps} />);
    expect(screen.queryByText('提词设置')).toBeNull();
    expect(screen.getByText('设置')).toBeInTheDocument();
  });
});
