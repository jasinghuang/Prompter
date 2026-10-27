import { describe, it, expect, vi } from 'vitest';
import { render, fireEvent, screen, within } from '@testing-library/react';
import { ScriptList } from './ScriptList';
import { Script } from '../types';

const scripts: Script[] = [
  { id: '1', title: '视频脚本', content: '今天介绍产品', createdAt: 1, updatedAt: 100 },
  { id: '2', title: '会议发言', content: '各位同事好', createdAt: 1, updatedAt: 200 },
];

describe('ScriptList', () => {
  it('渲染所有稿件标题', () => {
    render(
      <ScriptList scripts={scripts} filmedIds={new Set()} onToggleFilmed={() => {}} onOpen={() => {}} onEdit={() => {}} onDelete={() => {}} onCreate={() => {}} />
    );
    expect(screen.getByText('视频脚本')).toBeInTheDocument();
    expect(screen.getByText('会议发言')).toBeInTheDocument();
  });

  it('卡片有点按反馈（active 轻缩放）', () => {
    render(
      <ScriptList scripts={scripts} filmedIds={new Set()} onToggleFilmed={() => {}} onOpen={() => {}} onEdit={() => {}} onDelete={() => {}} onCreate={() => {}} />
    );
    expect(screen.getByTestId('content-1').parentElement!.className).toContain('active:scale-[0.98]');
  });

  it('highlightId 指定的卡片带「最近打开」高亮（金边 + 呼吸动画）', () => {
    render(
      <ScriptList scripts={scripts} filmedIds={new Set()} highlightId="2" onToggleFilmed={() => {}} onOpen={() => {}} onEdit={() => {}} onDelete={() => {}} onCreate={() => {}} />
    );
    const card2 = screen.getByTestId('content-2').parentElement!;
    expect(card2.className).toContain('card-hello');
    expect(card2.className).toContain('border-[#D4A432]/45');
    const card1 = screen.getByTestId('content-1').parentElement!;
    expect(card1.className).not.toContain('card-hello');
  });

  it('卡片显示字数与预计口播时长（按传入速度估算）', () => {
    render(
      <ScriptList scripts={scripts} filmedIds={new Set()} speed={160} onToggleFilmed={() => {}} onOpen={() => {}} onEdit={() => {}} onDelete={() => {}} onCreate={() => {}} />
    );
    // 「今天介绍产品」6 个可读字 @ 160 字/分 → 2.25s → 向下取整 00:02
    expect(screen.getByText('6字')).toBeInTheDocument();
    expect(screen.getByText(/约00:02/)).toBeInTheDocument();
  });

  it('搜索过滤（标题）', () => {
    render(
      <ScriptList scripts={scripts} filmedIds={new Set()} onToggleFilmed={() => {}} onOpen={() => {}} onEdit={() => {}} onDelete={() => {}} onCreate={() => {}} />
    );
    fireEvent.change(screen.getByPlaceholderText('搜索稿件...'), { target: { value: '视频' } });
    expect(screen.getByText('视频脚本')).toBeInTheDocument();
    expect(screen.queryByText('会议发言')).toBeNull();
  });

  it('新建按钮调用 onCreate', () => {
    const onCreate = vi.fn();
    render(
      <ScriptList scripts={scripts} filmedIds={new Set()} onToggleFilmed={() => {}} onOpen={() => {}} onEdit={() => {}} onDelete={() => {}} onCreate={onCreate} />
    );
    fireEvent.click(screen.getByRole('button', { name: /新建稿件/ }));
    expect(onCreate).toHaveBeenCalled();
  });

  it('卡片点击调用 onOpen', () => {
    const onOpen = vi.fn();
    render(
      <ScriptList scripts={scripts} filmedIds={new Set()} onToggleFilmed={() => {}} onOpen={onOpen} onEdit={() => {}} onDelete={() => {}} onCreate={() => {}} />
    );
    fireEvent.click(screen.getByText('视频脚本'));
    expect(onOpen).toHaveBeenCalledWith('1');
  });

  it('删除按钮触发退场动画，动画结束后才调用 onDelete（无确认弹窗）', () => {
    const onDelete = vi.fn();
    render(
      <ScriptList scripts={scripts} filmedIds={new Set()} onToggleFilmed={() => {}} onOpen={() => {}} onEdit={() => {}} onDelete={onDelete} onCreate={() => {}} />
    );
    fireEvent.click(screen.getByTestId('delete-1'));
    // 退场动画播放中，尚未真正删除
    expect(onDelete).not.toHaveBeenCalled();
    fireEvent(screen.getByTestId('content-1').parentElement!, new Event('animationend', { bubbles: true }));
    expect(onDelete).toHaveBeenCalledWith('1');
    expect(screen.queryByText('确认删除')).toBeNull();
  });

  it('左滑越过 -130 松手进入退场动画，结束后删除（无弹窗）', () => {
    const onDelete = vi.fn();
    render(
      <ScriptList scripts={scripts} filmedIds={new Set()} onToggleFilmed={() => {}} onOpen={() => {}} onEdit={() => {}} onDelete={onDelete} onCreate={() => {}} />
    );
    const card = screen.getByTestId('content-1').parentElement!;
    fireEvent.touchStart(card, { touches: [{ clientX: 160, clientY: 50 }] });
    fireEvent.touchMove(card, { touches: [{ clientX: 10, clientY: 50 }] }); // dx = -150
    fireEvent.touchEnd(card);
    expect(onDelete).not.toHaveBeenCalled(); // 等待退场动画
    fireEvent(card, new Event('animationend', { bubbles: true }));
    expect(onDelete).toHaveBeenCalledWith('1');
    expect(screen.queryByText('确认删除')).toBeNull();
  });

  it('左滑未越过 -130 松手不删除', () => {
    const onDelete = vi.fn();
    render(
      <ScriptList scripts={scripts} filmedIds={new Set()} onToggleFilmed={() => {}} onOpen={() => {}} onEdit={() => {}} onDelete={onDelete} onCreate={() => {}} />
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
      <ScriptList scripts={scripts} filmedIds={new Set()} onToggleFilmed={() => {}} onOpen={() => {}} onEdit={() => {}} onDelete={() => {}} onCreate={() => {}} onDeleteAll={onDeleteAll} />
    );
    fireEvent.click(screen.getByText('清空全部'));
    fireEvent.click(screen.getByText('确认清空'));
    expect(onDeleteAll).toHaveBeenCalled();
  });

  it('空状态显示引导', () => {
    render(
      <ScriptList scripts={[]} filmedIds={new Set()} onToggleFilmed={() => {}} onOpen={() => {}} onEdit={() => {}} onDelete={() => {}} onCreate={() => {}} />
    );
    expect(screen.getByText(/暂无稿件/)).toBeInTheDocument();
  });

  it('滑动中内容层不透明背景（修复重叠），静止时透明', () => {
    render(
      <ScriptList scripts={scripts} filmedIds={new Set()} onToggleFilmed={() => {}} onOpen={() => {}} onEdit={() => {}} onDelete={() => {}} onCreate={() => {}} />
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

  it('右滑标记调用 onToggleFilmed', () => {
    const onToggleFilmed = vi.fn();
    render(
      <ScriptList scripts={scripts} filmedIds={new Set()} onToggleFilmed={onToggleFilmed} onOpen={() => {}} onEdit={() => {}} onDelete={() => {}} onCreate={() => {}} />
    );
    const card = screen.getByTestId('content-1').parentElement!;
    fireEvent.touchStart(card, { touches: [{ clientX: 50, clientY: 50 }] });
    fireEvent.touchMove(card, { touches: [{ clientX: 120, clientY: 50 }] }); // dx = 70
    fireEvent.touchEnd(card);
    expect(onToggleFilmed).toHaveBeenCalledWith('1');
  });

  it('filmedIds 受控：已标记稿件显示绿标', () => {
    render(
      <ScriptList scripts={scripts} filmedIds={new Set(['1'])} onToggleFilmed={() => {}} onOpen={() => {}} onEdit={() => {}} onDelete={() => {}} onCreate={() => {}} />
    );
    // 已拍摄稿件标题带 line-through
    const title = screen.getByText('视频脚本');
    expect(title.className).toContain('line-through');
  });

  it('排序偏好持久化到 localStorage', () => {
    render(
      <ScriptList scripts={scripts} filmedIds={new Set()} onToggleFilmed={() => {}} onOpen={() => {}} onEdit={() => {}} onDelete={() => {}} onCreate={() => {}} onDeleteAll={() => {}} />
    );
    fireEvent.click(screen.getByText('标题'));
    const stored = JSON.parse(localStorage.getItem('prompter_sort')!);
    expect(stored.sort).toBe('title');
    expect(stored.asc).toBe(false);
  });

  it('从 localStorage 恢复排序偏好（读路径）', () => {
    localStorage.setItem('prompter_sort', JSON.stringify({ sort: 'chars', asc: true }));
    render(
      <ScriptList scripts={scripts} filmedIds={new Set()} onToggleFilmed={() => {}} onOpen={() => {}} onEdit={() => {}} onDelete={() => {}} onCreate={() => {}} onDeleteAll={() => {}} />
    );
    // 验证「字数」按钮高亮且带 ↑ 箭头
    const charsBtn = screen.getByText('字数 ↑');
    expect(charsBtn.className).toContain('bg-white/15');
  });

  it('排序记忆在组件重新挂载后保留（往返测试）', () => {
    const { unmount } = render(
      <ScriptList scripts={scripts} filmedIds={new Set()} onToggleFilmed={() => {}} onOpen={() => {}} onEdit={() => {}} onDelete={() => {}} onCreate={() => {}} onDeleteAll={() => {}} />
    );
    // 切换到标题排序
    fireEvent.click(screen.getByText('标题'));
    unmount();

    // 重新挂载 — 模拟返回页面
    render(
      <ScriptList scripts={scripts} filmedIds={new Set()} onToggleFilmed={() => {}} onOpen={() => {}} onEdit={() => {}} onDelete={() => {}} onCreate={() => {}} onDeleteAll={() => {}} />
    );
    const titleBtn = screen.getByText('标题 ↓');
    expect(titleBtn.className).toContain('bg-white/15');
  });

  it('星标稿件稳定置顶（组内保持日期排序）', () => {
    const starredScripts: Script[] = [
      { ...scripts[0] }, // id 1, updatedAt 100（新）
      { ...scripts[1], starred: true }, // id 2, updatedAt 200（旧但星标）
    ];
    render(
      <ScriptList scripts={starredScripts} filmedIds={new Set()} onToggleFilmed={() => {}} onOpen={() => {}} onEdit={() => {}} onDelete={() => {}} onCreate={() => {}} />
    );
    const first = document.querySelector('[data-testid^="content-"]')!.textContent!;
    expect(first).toContain('会议发言'); // 星标的在前
  });

  it('点击星标按钮回调 onToggleStar', () => {
    const onToggleStar = vi.fn();
    render(
      <ScriptList scripts={scripts} filmedIds={new Set()} onToggleStar={onToggleStar} onToggleFilmed={() => {}} onOpen={() => {}} onEdit={() => {}} onDelete={() => {}} onCreate={() => {}} />
    );
    // 卡片星标按钮（aria-label，避开 chips 行的「星标」文本）
    fireEvent.click(screen.getAllByLabelText('星标')[0]);
    expect(onToggleStar).toHaveBeenCalledWith('1');
  });

  it('文件夹 chips 从稿件派生，点选后只显示该文件夹的稿件', () => {
    const foldered: Script[] = [
      { ...scripts[0], folder: '口播' },
      { ...scripts[1] },
    ];
    render(
      <ScriptList scripts={foldered} filmedIds={new Set()} onToggleFilmed={() => {}} onOpen={() => {}} onEdit={() => {}} onDelete={() => {}} onCreate={() => {}} />
    );
    // chips 行的「口播」在卡片同名标签之前（DOM 顺序）
    fireEvent.click(screen.getAllByText('口播')[0]);
    expect(screen.getByText('视频脚本')).toBeInTheDocument();
    expect(screen.queryByText('会议发言')).toBeNull();
    // 切回全部恢复
    fireEvent.click(screen.getByText('全部'));
    expect(screen.getByText('会议发言')).toBeInTheDocument();
  });

  it('星标过滤只显示星标稿件', () => {
    const starredScripts: Script[] = [
      { ...scripts[0] },
      { ...scripts[1], starred: true },
    ];
    render(
      <ScriptList scripts={starredScripts} filmedIds={new Set()} onToggleFilmed={() => {}} onOpen={() => {}} onEdit={() => {}} onDelete={() => {}} onCreate={() => {}} />
    );
    fireEvent.click(screen.getByText('星标'));
    expect(screen.getByText('会议发言')).toBeInTheDocument();
    expect(screen.queryByText('视频脚本')).toBeNull();
  });

  it('卡片文件夹按钮打开移动弹层并回调 onMoveToFolder', () => {
    const onMoveToFolder = vi.fn();
    render(
      <ScriptList scripts={[{ ...scripts[0], folder: '口播' }, { ...scripts[1], folder: 'vlog' }]} filmedIds={new Set()} onMoveToFolder={onMoveToFolder} onToggleFilmed={() => {}} onOpen={() => {}} onEdit={() => {}} onDelete={() => {}} onCreate={() => {}} />
    );
    fireEvent.click(screen.getAllByLabelText('移动到文件夹')[0]);
    const sheet = screen.getByTestId('folder-sheet');
    expect(within(sheet).getByText('移动到文件夹')).toBeInTheDocument();
    // 移到 vlog（sheet 内选项，避开 chips 行同名元素）
    fireEvent.click(within(sheet).getByText('vlog'));
    expect(onMoveToFolder).toHaveBeenCalledWith('1', 'vlog');
    // 弹层关闭
    expect(screen.queryByTestId('folder-sheet')).toBeNull();
  });

  it('移动弹层内新建文件夹：创建后把稿件移入并出现 chips', () => {
    const onMoveToFolder = vi.fn();
    render(
      <ScriptList scripts={scripts} filmedIds={new Set()} onMoveToFolder={onMoveToFolder} onToggleFilmed={() => {}} onOpen={() => {}} onEdit={() => {}} onDelete={() => {}} onCreate={() => {}} />
    );
    fireEvent.click(screen.getAllByLabelText('移动到文件夹')[0]);
    const sheet = screen.getByTestId('folder-sheet');
    fireEvent.click(within(sheet).getByText('＋ 新建文件夹…'));
    fireEvent.change(screen.getByPlaceholderText('文件夹名称'), { target: { value: '带货' } });
    fireEvent.click(screen.getByText('创建'));
    expect(onMoveToFolder).toHaveBeenCalledWith('1', '带货');
    expect(screen.queryByTestId('folder-sheet')).toBeNull();
  });
});
