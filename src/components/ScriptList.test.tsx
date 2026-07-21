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
    fireEvent.change(screen.getByPlaceholderText('搜索...'), { target: { value: '视频' } });
    expect(screen.getByText('视频脚本')).toBeInTheDocument();
    expect(screen.queryByText('会议发言')).toBeNull();
  });

  it('新建按钮调用 onCreate', () => {
    const onCreate = vi.fn();
    render(
      <ScriptList scripts={scripts} onOpen={() => {}} onEdit={() => {}} onDelete={() => {}} onCreate={onCreate} />
    );
    fireEvent.click(screen.getByRole('button', { name: /新建|稿/ }));
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

  it('清空全部按钮调用 onDeleteAll（含确认）', () => {
    const onDeleteAll = vi.fn();
    render(
      <ScriptList scripts={scripts} onOpen={() => {}} onEdit={() => {}} onDelete={() => {}} onCreate={() => {}} onDeleteAll={onDeleteAll} />
    );
    fireEvent.click(screen.getByText('清空全部'));
    fireEvent.click(screen.getByText('确认清空'));
    expect(onDeleteAll).toHaveBeenCalled();
  });

  it('导入面板：粘贴内容后确认调用 onImport', () => {
    const onImport = vi.fn();
    render(
      <ScriptList scripts={scripts} onOpen={() => {}} onEdit={() => {}} onDelete={() => {}} onCreate={() => {}} onImport={onImport} />
    );
    fireEvent.click(screen.getByText('导入'));
    fireEvent.change(screen.getByPlaceholderText(/稿件标题/), { target: { value: '我的稿' } });
    fireEvent.change(screen.getByPlaceholderText(/粘贴稿件内容/), { target: { value: '正文内容' } });
    fireEvent.click(screen.getByText('导入确认'));
    expect(onImport).toHaveBeenCalledWith('我的稿', '正文内容');
  });

  it('导入内容为空时确认按钮禁用', () => {
    const onImport = vi.fn();
    render(
      <ScriptList scripts={scripts} onOpen={() => {}} onEdit={() => {}} onDelete={() => {}} onCreate={() => {}} onImport={onImport} />
    );
    fireEvent.click(screen.getByText('导入'));
    expect(screen.getByText('导入确认')).toBeDisabled();
  });

  it('空状态显示引导', () => {
    render(
      <ScriptList scripts={[]} onOpen={() => {}} onEdit={() => {}} onDelete={() => {}} onCreate={() => {}} />
    );
    expect(screen.getByText(/新建第一篇/)).toBeInTheDocument();
  });
});
