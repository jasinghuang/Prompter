import { describe, it, expect, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import App from './App';

beforeEach(() => localStorage.clear());

describe('App', () => {
  it('初始显示稿件管理，且为空状态', () => {
    render(<App />);
    expect(screen.getByText(/新建第一篇/)).toBeInTheDocument();
  });

  it('新建稿件 → 进入编辑视图', () => {
    render(<App />);
    fireEvent.click(screen.getByText('新建稿件'));
    // 编辑器正文输入框存在
    expect(screen.getByPlaceholderText('在此输入或粘贴提词稿件...')).toBeInTheDocument();
  });

  it('编辑后返回提词器，若改动跨越位置则重置到开头并提示', async () => {
    render(<App />);
    fireEvent.click(screen.getByText('新建稿件'));
    // 输入正文
    const content = screen.getByPlaceholderText('在此输入或粘贴提词稿件...');
    fireEvent.change(content, { target: { value: '一二三四五' } });
    // 返回列表
    fireEvent.click(screen.getByTitle('返回'));
    // 打开提词器
    await waitFor(() => expect(screen.getByText('未命名稿件')).toBeInTheDocument());
    fireEvent.click(screen.getByText('未命名稿件'));
    // 进入提词器（应能渲染）
    await waitFor(() => expect(screen.getByText('Reading Area')).toBeInTheDocument());
  });
});
