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
    fireEvent.click(screen.getByText('新建稿件'));
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

  it('删除按钮调用 onDelete（含确认）', () => {
    const onDelete = vi.fn();
    render(
      <ScriptList scripts={scripts} onOpen={() => {}} onEdit={() => {}} onDelete={onDelete} onCreate={() => {}} />
    );
    fireEvent.click(screen.getByTestId('delete-1'));
    fireEvent.click(screen.getByText('确认删除'));
    expect(onDelete).toHaveBeenCalledWith('1');
  });

  it('空状态显示引导', () => {
    render(
      <ScriptList scripts={[]} onOpen={() => {}} onEdit={() => {}} onDelete={() => {}} onCreate={() => {}} />
    );
    expect(screen.getByText(/新建第一篇/)).toBeInTheDocument();
  });
});
