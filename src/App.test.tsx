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

  it('智能拆分的产物继承父稿件的文件夹', async () => {
    localStorage.setItem('prompter_scripts', JSON.stringify([
      { id: '1', title: '批次', content: '甲段\n\n乙段', createdAt: 1, updatedAt: 1, folder: '带货' },
    ]));
    render(<App />);
    fireEvent.click(screen.getByText('批次')); // 打开提词页
    fireEvent.click(screen.getByLabelText('编辑')); // 顶栏编辑进入编辑页
    fireEvent.click(screen.getByRole('button', { name: /智能拆分/ }));
    await act(async () => { await new Promise((r) => setTimeout(r, 300)); });
    const scripts = JSON.parse(localStorage.getItem('prompter_scripts')!);
    expect(scripts).toHaveLength(2);
    expect(scripts.every((s: { folder?: string }) => s.folder === '带货')).toBe(true);
  });

  it('新建稿件 → 编辑页归入新分组 → 返回列表出现文件夹 chip 与卡片标签', async () => {
    render(<App />);
    fireEvent.click(screen.getByRole('button', { name: /新建稿件/ }));
    fireEvent.change(screen.getByPlaceholderText('在此输入或粘贴提词稿件...'), { target: { value: '内容' } });
    fireEvent.click(screen.getByLabelText('新建分组'));
    fireEvent.change(screen.getByLabelText('新分组名'), { target: { value: '带货' } });
    fireEvent.keyDown(screen.getByLabelText('新分组名'), { key: 'Enter' });
    fireEvent.click(screen.getByTitle('返回'));
    // chips 行与卡片分组标签都出现（两处「带货」）
    await waitFor(() => expect(screen.getAllByText('带货').length).toBeGreaterThanOrEqual(2));
    expect(JSON.parse(localStorage.getItem('prompter_scripts')!)[0].folder).toBe('带货');
  });

  it('批量删除后撤销可整批恢复', async () => {
    localStorage.setItem('prompter_scripts', JSON.stringify([
      { id: '1', title: '甲', content: '内容一', createdAt: 2, updatedAt: 2 },
      { id: '2', title: '乙', content: '内容二', createdAt: 1, updatedAt: 1 },
    ]));
    render(<App />);
    // 长按进入多选
    const card = screen.getByTestId('content-1').parentElement!;
    fireEvent.pointerDown(card, { clientX: 100, clientY: 50 });
    await act(async () => { await new Promise((r) => setTimeout(r, 550)); });
    fireEvent.pointerUp(card);
    fireEvent.click(screen.getByText('全选'));
    fireEvent.click(screen.getByText(/删除所选 2/));
    fireEvent.click(screen.getByText('确认删除'));
    await waitFor(() => expect(screen.queryByText('甲')).toBeNull());
    expect(screen.queryByText('乙')).toBeNull();
    // 撤销 → 两篇都回来
    fireEvent.click(screen.getByText('撤销删除'));
    await waitFor(() => {
      expect(screen.getByText('甲')).toBeInTheDocument();
      expect(screen.getByText('乙')).toBeInTheDocument();
    });
    expect(JSON.parse(localStorage.getItem('prompter_scripts')!).map((s: { id: string }) => s.id).sort()).toEqual(['1', '2']);
  });

  it('文件夹视图打开稿件返回后，仍停留在该文件夹', () => {
    localStorage.setItem('prompter_scripts', JSON.stringify([
      { id: '1', title: '甲', content: '内容一', createdAt: 2, updatedAt: 2 },
      { id: '2', title: '乙', content: '内容二', createdAt: 1, updatedAt: 1, folder: '口播' },
    ]));
    render(<App />);
    // 进入「口播」文件夹（chips 行在前的同名元素）
    fireEvent.click(screen.getAllByText('口播')[0]);
    expect(screen.queryByText('甲')).toBeNull(); // 只剩乙
    // 打开乙再返回
    fireEvent.click(screen.getByText('乙'));
    fireEvent.click(screen.getByLabelText('返回'));
    // 仍在文件夹视图：甲仍隐藏、乙在
    expect(screen.queryByText('甲')).toBeNull();
    expect(screen.getByText('乙')).toBeInTheDocument();
  });

  it('从播放页返回列表后，刚打开的卡片保持高亮', () => {
    localStorage.setItem('prompter_scripts', JSON.stringify([
      { id: '1', title: '甲', content: '内容一', createdAt: 2, updatedAt: 2 },
      { id: '2', title: '乙', content: '内容二', createdAt: 1, updatedAt: 1 },
    ]));
    render(<App />);
    fireEvent.click(screen.getByText('乙')); // 打开乙
    fireEvent.click(screen.getByLabelText('返回')); // 返回列表
    const card2 = screen.getByTestId('content-2').parentElement!;
    expect(card2.className).toContain('card-hello');
    const card1 = screen.getByTestId('content-1').parentElement!;
    expect(card1.className).not.toContain('card-hello');
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

  it('删除后 2 秒内可撤销：恢复稿件与已拍摄标记', async () => {
    localStorage.setItem('prompter_scripts', JSON.stringify([
      { id: '1', title: '甲', content: '内容一', createdAt: 2, updatedAt: 2 },
      { id: '2', title: '乙', content: '内容二', createdAt: 1, updatedAt: 1 },
    ]));
    localStorage.setItem('prompter_filmed', JSON.stringify(['1']));
    render(<App />);
    // 删除第一张卡（按钮 → 退场动画 → 真正删除）
    fireEvent.click(screen.getByTestId('delete-1'));
    fireEvent(screen.getByTestId('content-1').parentElement!, new Event('animationend', { bubbles: true }));
    await waitFor(() => expect(screen.queryByText('甲')).toBeNull());
    // 撤销提示出现（仅「撤销删除」四个字，位于顶部）
    expect(screen.getByText('撤销删除')).toBeInTheDocument();
    fireEvent.click(screen.getByText('撤销删除'));
    // 卡片与已拍摄标记均恢复
    await waitFor(() => expect(screen.getByText('甲')).toBeInTheDocument());
    expect(JSON.parse(localStorage.getItem('prompter_scripts')!).map((s: { id: string }) => s.id)).toEqual(['1', '2']);
    expect(JSON.parse(localStorage.getItem('prompter_filmed')!)).toContain('1');
  });

  it('撤销提示 2 秒后自动消失', async () => {
    localStorage.setItem('prompter_scripts', JSON.stringify([
      { id: '1', title: '甲', content: '内容一', createdAt: 1, updatedAt: 1 },
    ]));
    render(<App />);
    fireEvent.click(screen.getByTestId('delete-1'));
    fireEvent(screen.getByTestId('content-1').parentElement!, new Event('animationend', { bubbles: true }));
    await waitFor(() => expect(screen.getByText('撤销删除')).toBeInTheDocument());
    await waitFor(() => expect(screen.queryByText('撤销删除')).toBeNull(), { timeout: 3000 });
  });
});
