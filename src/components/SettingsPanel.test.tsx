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

  it('读完动作：点击「返回列表」调用 onChange({ completeAction: "list" })', () => {
    const onChange = vi.fn();
    render(<SettingsPanel {...baseProps} onChange={onChange} />);
    fireEvent.click(screen.getByRole('button', { name: '返回列表' }));
    expect(onChange).toHaveBeenCalledWith(expect.objectContaining({ completeAction: 'list' }));
  });

  it('读完动作：点击「回到开头」调用 onChange({ completeAction: "restart" })', () => {
    const onChange = vi.fn();
    render(<SettingsPanel {...baseProps} onChange={onChange} />);
    fireEvent.click(screen.getByRole('button', { name: '回到开头' }));
    expect(onChange).toHaveBeenCalledWith(expect.objectContaining({ completeAction: 'restart' }));
  });

  it('读完动作：点击「不开启」调用 onChange({ completeAction: "none" })', () => {
    const onChange = vi.fn();
    render(<SettingsPanel {...baseProps} settings={{ ...DEFAULT_SETTINGS, completeAction: 'list' }} onChange={onChange} />);
    fireEvent.click(screen.getByRole('button', { name: '不开启' }));
    expect(onChange).toHaveBeenCalledWith(expect.objectContaining({ completeAction: 'none' }));
  });

  it('读完动作：药丸式分段选择器，选项按钮不含图标', () => {
    render(<SettingsPanel {...baseProps} />);
    const section = screen.getByText('读完动作').parentElement!;
    const group = section.querySelector('[data-segmented-pill]');
    expect(group).toBeTruthy();
    expect(group!.className).toContain('rounded-full'); // 药丸容器
    const buttons = Array.from(group!.querySelectorAll('button'));
    expect(buttons).toHaveLength(3);
    for (const b of buttons) {
      expect(b.querySelector('svg')).toBeNull(); // 无图标
    }
  });

  it('读完动作：当前选中项高亮（选中返回列表时 pill 定位到该按钮）', () => {
    render(<SettingsPanel {...baseProps} settings={{ ...DEFAULT_SETTINGS, completeAction: 'list' }} />);
    const group = screen.getByText('读完动作').parentElement!.querySelector('[data-segmented-pill]')!;
    const selected = group.querySelector('[data-pill-value="list"]');
    expect(selected?.className).toContain('text-white'); // 选中项白色文字
    const unselected = group.querySelector('[data-pill-value="none"]');
    expect(unselected?.className).toContain('text-white/35'); // 未选中项弱化
  });

  it('所有区块标题统一：text-sm font-semibold 白字，无 white/50', () => {
    render(<SettingsPanel {...baseProps} />);
    const titles = ['字号', '字间距', '行距', '两边间距', '滚动速度', '对齐方式', '镜像翻转', '读完动作', '自动暂停'];
    for (const t of titles) {
      const el = screen.getByText(t);
      expect(el.className).toContain('text-sm');
      expect(el.className).toContain('font-semibold');
      expect(el.className).toContain('text-white');
      expect(el.className).not.toContain('text-white/50');
    }
  });

  it('读完动作选项文字为 text-xs，比标题（text-sm）小一级', () => {
    render(<SettingsPanel {...baseProps} />);
    const group = screen.getByText('读完动作').parentElement!.querySelector('[data-segmented-pill]')!;
    const buttons = Array.from(group.querySelectorAll('button'));
    expect(buttons).toHaveLength(3);
    for (const b of buttons) {
      expect(b.className).toContain('text-xs');
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
