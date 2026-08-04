import { describe, it, expect, vi } from 'vitest';
import { render, fireEvent, screen } from '@testing-library/react';
import { ScriptList } from './ScriptList';
import { Script } from '../types';

const scripts: Script[] = [
  { id: '1', title: '视频脚本', content: '今天介绍产品', createdAt: 1, updatedAt: 100 },
  { id: '2', title: '会议发言', content: '各位同事好', createdAt: 1, updatedAt: 200 },
];

describe('ScriptList', () => {
  it('渲染所有稿件标题', () => {
    render(
      <ScriptList scripts={scripts} onOpen={() => {}} onEdit={() => {}} onDelete={() => {}} onCreate={() => {}} />
    );
    expect(screen.getByText('视频脚本')).toBeInTheDocument();
    expect(screen.getByText('会议发言')).toBeInTheDocument();
  });

  it('搜索过滤（标题）', () => {
    render(
      <ScriptList scripts={scripts} onOpen={() => {}} onEdit={() => {}} onDelete={() => {}} onCreate={() => {}} />
    );
    fireEvent.change(screen.getByPlaceholderText('搜索稿件...'), { target: { value: '视频' } });
    expect(screen.getByText('视频脚本')).toBeInTheDocument();
    expect(screen.queryByText('会议发言')).toBeNull();
  });

  it('新建按钮调用 onCreate', () => {
    const onCreate = vi.fn();
    render(
      <ScriptList scripts={scripts} onOpen={() => {}} onEdit={() => {}} onDelete={() => {}} onCreate={onCreate} />
    );
    fireEvent.click(screen.getByRole('button', { name: /新建稿件/ }));
    expect(onCreate).toHaveBeenCalled();
  });

  it('卡片点击调用 onOpen', () => {
    const onOpen = vi.fn();
    render(
      <ScriptList scripts={scripts} onOpen={onOpen} onEdit={() => {}} onDelete={() => {}} onCreate={() => {}} />
    );
    fireEvent.click(screen.getByText('视频脚本'));
    expect(onOpen).toHaveBeenCalledWith('1');
  });

  it('删除按钮直接调用 onDelete（无确认弹窗）', () => {
    const onDelete = vi.fn();
    render(
      <ScriptList scripts={scripts} onOpen={() => {}} onEdit={() => {}} onDelete={onDelete} onCreate={() => {}} />
    );
    fireEvent.click(screen.getByTestId('delete-1'));
    expect(onDelete).toHaveBeenCalledWith('1');
    expect(screen.queryByText('确认删除')).toBeNull();
  });

  it('左滑越过 -130 松手直接删除（无弹窗）', () => {
    const onDelete = vi.fn();
    render(
      <ScriptList scripts={scripts} onOpen={() => {}} onEdit={() => {}} onDelete={onDelete} onCreate={() => {}} />
    );
    const card = screen.getByTestId('content-1').parentElement!;
    fireEvent.touchStart(card, { touches: [{ clientX: 160, clientY: 50 }] });
    fireEvent.touchMove(card, { touches: [{ clientX: 10, clientY: 50 }] }); // dx = -150
    fireEvent.touchEnd(card);
    expect(onDelete).toHaveBeenCalledWith('1');
    expect(screen.queryByText('确认删除')).toBeNull();
  });

  it('左滑未越过 -130 松手不删除', () => {
    const onDelete = vi.fn();
    render(
      <ScriptList scripts={scripts} onOpen={() => {}} onEdit={() => {}} onDelete={onDelete} onCreate={() => {}} />
    );
    const card = screen.getByTestId('content-1').parentElement!;
    fireEvent.touchStart(card, { touches: [{ clientX: 100, clientY: 50 }] });
    fireEvent.touchMove(card, { touches: [{ clientX: 30, clientY: 50 }] }); // dx = -70
    fireEvent.touchEnd(card);
    expect(onDelete).not.toHaveBeenCalled();
  });

  it('清空全部按钮调用 onDeleteAll（含确认）', () => {
    const onDeleteAll = vi.fn();
    render(
      <ScriptList scripts={scripts} onOpen={() => {}} onEdit={() => {}} onDelete={() => {}} onCreate={() => {}} onDeleteAll={onDeleteAll} />
    );
    fireEvent.click(screen.getByText('清空全部'));
    fireEvent.click(screen.getByText('确认清空'));
    expect(onDeleteAll).toHaveBeenCalled();
  });

  it('空状态显示引导', () => {
    render(
      <ScriptList scripts={[]} onOpen={() => {}} onEdit={() => {}} onDelete={() => {}} onCreate={() => {}} />
    );
    expect(screen.getByText(/暂无稿件/)).toBeInTheDocument();
  });

  it('滑动中内容层不透明背景（修复重叠），静止时透明', () => {
    render(
      <ScriptList scripts={scripts} onOpen={() => {}} onEdit={() => {}} onDelete={() => {}} onCreate={() => {}} />
    );
    const contentLayer = screen.getByTestId('content-1');
    // 静止：无内联背景
    expect(contentLayer.style.background).toBe('');
    // 模拟左滑（dx = 50 → 10 = -40）
    const card = contentLayer.parentElement!;
    fireEvent.touchStart(card, { touches: [{ clientX: 50, clientY: 50 }] });
    fireEvent.touchMove(card, { touches: [{ clientX: 10, clientY: 50 }] });
    expect(contentLayer.style.background).not.toBe('');
  });
});
