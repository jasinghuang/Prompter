import { describe, it, expect, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor, act, within } from '@testing-library/react';
import App from './App';

beforeEach(() => localStorage.clear());

describe('App', () => {
  it('初始显示稿件管理，且为空状态', () => {
    render(<App />);
    expect(screen.getByText(/暂无稿件/)).toBeInTheDocument();
  });

  it('新建稿件 → 进入编辑视图', () => {
    render(<App />);
    // 新建按钮：桌面端显示"新建"，移动端显示"稿"
    const btn = screen.getByRole('button', { name: /新建稿件/ });
    fireEvent.click(btn);
    // 编辑器正文输入框存在
    expect(screen.getByPlaceholderText('在此输入或粘贴提词稿件...')).toBeInTheDocument();
  });

  it('编辑后返回提词器应能渲染', async () => {
    render(<App />);
    const btn = screen.getByRole('button', { name: /新建稿件/ });
    fireEvent.click(btn);
    // 输入正文
    const content = screen.getByPlaceholderText('在此输入或粘贴提词稿件...');
    fireEvent.change(content, { target: { value: '一二三四五' } });
    // 返回列表
    fireEvent.click(screen.getByTitle('返回'));
    // 打开提词器
    await waitFor(() => expect(screen.getByText('未命名稿件')).toBeInTheDocument());
    fireEvent.click(screen.getByText('未命名稿件'));
    // 进入提词器：验证 back 按钮存在
    await waitFor(() => expect(screen.getByLabelText('返回')).toBeInTheDocument());
  });

  it('空行模式拆分：按空行切分为多篇并返回列表', async () => {
    render(<App />);
    fireEvent.click(screen.getByRole('button', { name: /新建稿件/ }));
    fireEvent.change(screen.getByPlaceholderText('在此输入或粘贴提词稿件...'), {
      target: { value: '标题甲\n内容甲\n\n标题乙\n内容乙' },
    });
    fireEvent.click(screen.getByRole('button', { name: /智能拆分/ }));
    await act(async () => { await new Promise((r) => setTimeout(r, 600)); }); // 冲掉防抖保存
    expect(screen.queryByText(/暂无稿件/)).toBeNull();
    const scripts = JSON.parse(localStorage.getItem('prompter_scripts')!);
    expect(scripts).toHaveLength(2);
    expect(scripts.map((s: { title: string }) => s.title)).toEqual(['标题乙', '标题甲']);
  });

  it('关键词模式拆分：在每个关键词前切分、段首保留关键词', async () => {
    render(<App />);
    fireEvent.click(screen.getByRole('button', { name: /新建稿件/ }));
    fireEvent.change(screen.getByPlaceholderText('在此输入或粘贴提词稿件...'), {
      target: { value: '开场白\n主持人：大家好' },
    });
    const row = screen.getByRole('button', { name: /智能拆分/ }).parentElement!;
    fireEvent.click(within(row).getByRole('button', { name: '关键词' }));
    fireEvent.change(screen.getByPlaceholderText('输入拆分关键词'), { target: { value: '主持人：' } });
    fireEvent.click(screen.getByRole('button', { name: /智能拆分/ }));
    await act(async () => { await new Promise((r) => setTimeout(r, 600)); }); // 冲掉防抖保存
    expect(screen.queryByText(/暂无稿件/)).toBeNull();
    const scripts = JSON.parse(localStorage.getItem('prompter_scripts')!);
    expect(scripts).toHaveLength(2);
    expect(scripts.map((s: { title: string }) => s.title)).toEqual(['主持人：大家好', '开场白']);
  });

  it('清理已删除稿件的 filmed 残留', () => {
    localStorage.setItem('prompter_filmed', JSON.stringify(['gone']));
    localStorage.setItem('prompter_scripts', JSON.stringify([
      { id: '1', title: 't', content: 'c', createdAt: 1, updatedAt: 1 },
    ]));
    render(<App />);
    // clearStale 应移除不存在的 'gone'
    expect(JSON.parse(localStorage.getItem('prompter_filmed')!)).toEqual([]);
  });
});
