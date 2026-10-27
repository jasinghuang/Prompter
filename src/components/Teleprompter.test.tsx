import { describe, it, expect, beforeEach, vi } from 'vitest';
import { useState } from 'react';
import { render, screen, act, fireEvent } from '@testing-library/react';
import { Teleprompter } from './Teleprompter';
import { Script, DEFAULT_SETTINGS, TeleprompterSettings } from '../types';

// mock useAutoScroll，暴露 onReachEnd 供测试触发（jsdom 无真实滚动）
vi.mock('../hooks/useAutoScroll', () => ({
  useAutoScroll: vi.fn(),
}));

// mock 自动暂停钩子，暴露 reset 供测试断言（restart 时重置命中记录）
vi.mock('../hooks/usePauseOnKeyword', () => ({
  usePauseOnKeyword: vi.fn(),
}));
vi.mock('../hooks/usePauseOnParagraph', () => ({
  usePauseOnParagraph: vi.fn(),
}));

import { useAutoScroll } from '../hooks/useAutoScroll';
import { usePauseOnKeyword } from '../hooks/usePauseOnKeyword';
import { usePauseOnParagraph } from '../hooks/usePauseOnParagraph';

const script: Script = { id: '1', title: '测试稿', content: '一二三四五', createdAt: 1, updatedAt: 1 };
let reachEnd: (() => void) | null = null;
let resetKeywordPause = vi.fn();
let resetParagraphPause = vi.fn();

beforeEach(() => {
  localStorage.clear();
  localStorage.setItem('prompter_onboarded', '1'); // 跳过 onboarding 遮罩
  reachEnd = null;
  resetKeywordPause = vi.fn();
  resetParagraphPause = vi.fn();
  vi.mocked(useAutoScroll).mockImplementation((opts: any) => {
    reachEnd = opts.onReachEnd;
    return { current: 0 } as any;
  });
  vi.mocked(usePauseOnKeyword).mockReturnValue(resetKeywordPause);
  vi.mocked(usePauseOnParagraph).mockReturnValue(resetParagraphPause);
});

function renderTel(settings: TeleprompterSettings = DEFAULT_SETTINGS) {
  const handlers = {
    onIndexChange: vi.fn(),
    onChangeSettings: vi.fn(),
    onBack: vi.fn(),
    onEdit: vi.fn(),
    onCompleted: vi.fn(),
    onToggleFilmed: vi.fn(),
  };
  render(
    <Teleprompter
      script={script}
      settings={settings}
      index={0}
      onIndexChange={handlers.onIndexChange}
      onChangeSettings={handlers.onChangeSettings}
      onBack={handlers.onBack}
      onEdit={handlers.onEdit}
      onCompleted={handlers.onCompleted}
      isFilmed={false}
      onToggleFilmed={handlers.onToggleFilmed}
    />
  );
  return handlers;
}

const LIST_MODE: TeleprompterSettings = { ...DEFAULT_SETTINGS, completeAction: 'list' };

describe('Teleprompter 读完动作', () => {
  it('list：onReachEnd 触发 onCompleted 并显示提示', () => {
    const h = renderTel(LIST_MODE);
    act(() => reachEnd!());
    expect(h.onCompleted).toHaveBeenCalledTimes(1);
    expect(screen.getByText(/已读完/)).toBeInTheDocument();
  });

  it('list：1.2s 后自动调用 onBack', () => {
    vi.useFakeTimers();
    const h = renderTel(LIST_MODE);
    act(() => reachEnd!());
    expect(h.onBack).not.toHaveBeenCalled();
    act(() => { vi.advanceTimersByTime(1200); });
    expect(h.onBack).toHaveBeenCalledTimes(1);
    vi.useRealTimers();
  });

  it('none（默认）：onReachEnd 只停止播放，不标记/不提示/不返回', () => {
    const h = renderTel(); // DEFAULT_SETTINGS.completeAction = 'none'
    act(() => reachEnd!());
    expect(h.onCompleted).not.toHaveBeenCalled();
    expect(h.onBack).not.toHaveBeenCalled();
    expect(screen.queryByText(/已读完/)).toBeNull();
  });

  it('restart：滚动回到开头，不标记/不提示/不返回', () => {
    const h = renderTel({ ...DEFAULT_SETTINGS, completeAction: 'restart' });
    const vp = document.querySelector('.teleprompter-touch') as HTMLElement;
    vp.scrollTop = 500; // 模拟已滚到末尾
    act(() => reachEnd!());
    expect(vp.scrollTop).toBe(0);
    expect(h.onCompleted).not.toHaveBeenCalled();
    expect(h.onBack).not.toHaveBeenCalled();
    expect(screen.queryByText(/已读完/)).toBeNull();
    expect(screen.getByLabelText('已暂停')).toBeInTheDocument(); // 暂停在开头
  });

  it('restart：可重复触发，第二次读完同样不标记/不返回', () => {
    const h = renderTel({ ...DEFAULT_SETTINGS, completeAction: 'restart' });
    act(() => reachEnd!());
    act(() => reachEnd!());
    expect(h.onCompleted).not.toHaveBeenCalled();
    expect(h.onBack).not.toHaveBeenCalled();
  });

  it('restart：重置自动暂停命中记录，重读时暂停重新生效', () => {
    renderTel({ ...DEFAULT_SETTINGS, completeAction: 'restart' });
    act(() => reachEnd!());
    expect(resetKeywordPause).toHaveBeenCalledTimes(1);
    expect(resetParagraphPause).toHaveBeenCalledTimes(1);
  });

  it('顶栏圆形「标记已拍摄」按钮：点击回调并弹 toast', () => {
    const h = renderTel();
    fireEvent.click(screen.getByLabelText('标记为已拍摄'));
    expect(h.onToggleFilmed).toHaveBeenCalledTimes(1);
    expect(screen.getByText('已标记拍摄 ✓')).toBeInTheDocument();
  });

  it('暂停时中央显示播放提示，容器穿透不拦截点击', () => {
    renderTel();
    const hint = screen.getByText('点击屏幕任意位置播放');
    expect(hint.closest('div')!.className).toContain('pointer-events-none');
  });

  it('暂停时计时旁为双竖线暂停图标，播放中右上角操作胶囊自动隐藏', () => {
    renderTel();
    // 暂停态：状态格内是 CirclePause 图标
    const statusCell = screen.getByLabelText('已暂停');
    expect(statusCell.querySelector('svg')).not.toBeNull();
    // 轻点屏幕开始播放（viewport 的 pointer 切换）
    const vp = document.querySelector('.teleprompter-touch')!;
    fireEvent.pointerDown(vp, { clientY: 100 });
    fireEvent.pointerUp(vp, { clientY: 100 });
    // 播放中：红点态 + 右上角操作胶囊淡出且不可点
    expect(screen.getByLabelText('播放中')).toBeInTheDocument();
    const settingsWrap = screen.getByLabelText('设置').parentElement!.parentElement!;
    expect(settingsWrap.className).toContain('opacity-0');
    expect(settingsWrap.className).toContain('pointer-events-none');
    // 再轻点暂停 → 胶囊恢复
    fireEvent.pointerDown(vp, { clientY: 100 });
    fireEvent.pointerUp(vp, { clientY: 100 });
    expect(screen.getByLabelText('设置').parentElement!.parentElement!.className).not.toContain('opacity-0');
  });

  it('手动返回不触发 onCompleted', () => {
    const h = renderTel(LIST_MODE);
    act(() => {
      screen.getByLabelText('返回').click();
    });
    expect(h.onCompleted).not.toHaveBeenCalled();
    expect(h.onBack).toHaveBeenCalledTimes(1);
  });
});

describe('Teleprompter 回到顶部按钮', () => {
  /**
   * jsdom 无真实布局：mock 内容元素 scrollHeight 与视口 clientHeight，
   * 触发 resize 使 measure() 重测，再设 scrollTop 并派发 scroll。
   */
  function setScroll(
    vp: HTMLElement,
    { contentHeight, clientHeight, scrollTop }: { contentHeight: number; clientHeight: number; scrollTop: number }
  ) {
    const ct = vp.firstElementChild as HTMLElement;
    Object.defineProperty(ct, 'scrollHeight', { value: contentHeight, configurable: true });
    Object.defineProperty(vp, 'clientHeight', { value: clientHeight, configurable: true });
    act(() => { window.dispatchEvent(new Event('resize')); });
    act(() => {
      vp.scrollTop = scrollTop;
      fireEvent.scroll(vp);
    });
  }

  function viewport(): HTMLElement {
    return document.querySelector('.teleprompter-touch') as HTMLElement;
  }

  it('滚到最底部且暂停时显示回到顶部按钮', () => {
    renderTel();
    setScroll(viewport(), { contentHeight: 1000, clientHeight: 500, scrollTop: 500 });
    expect(screen.getByLabelText('回到顶部')).toBeInTheDocument();
  });

  it('不在底部时不显示', () => {
    renderTel();
    setScroll(viewport(), { contentHeight: 1000, clientHeight: 500, scrollTop: 100 });
    expect(screen.queryByLabelText('回到顶部')).toBeNull();
  });

  it('内容不足一屏时不显示', () => {
    renderTel();
    setScroll(viewport(), { contentHeight: 400, clientHeight: 500, scrollTop: 0 });
    expect(screen.queryByLabelText('回到顶部')).toBeNull();
  });

  it('点击回到顶部滚动归零并隐藏按钮', () => {
    renderTel();
    const vp = viewport();
    setScroll(vp, { contentHeight: 1000, clientHeight: 500, scrollTop: 500 });
    fireEvent.click(screen.getByLabelText('回到顶部'));
    expect(vp.scrollTop).toBe(0);
    act(() => { fireEvent.scroll(vp); });
    expect(screen.queryByLabelText('回到顶部')).toBeNull();
  });

  it('播放中不显示回到顶部按钮', () => {
    renderTel();
    const vp = viewport();
    setScroll(vp, { contentHeight: 1000, clientHeight: 500, scrollTop: 500 });
    expect(screen.getByLabelText('回到顶部')).toBeInTheDocument();
    // 轻点屏幕开始播放
    act(() => {
      fireEvent.pointerDown(vp, { clientY: 100 });
      fireEvent.pointerUp(vp, { clientY: 100 });
    });
    expect(screen.queryByLabelText('回到顶部')).toBeNull();
  });
});

describe('Teleprompter 双指捏合调字号', () => {
  function viewport(): HTMLElement {
    return document.querySelector('.teleprompter-touch') as HTMLElement;
  }

  /** 构造触摸点（jsdom Touch polyfill 见 test-setup） */
  const t = (id: number, x: number, y: number) => ({ identifier: id, clientX: x, clientY: y });

  it('两指张开放大字号（钳制在上限）', () => {
    const h = renderTel(); // 默认字号 64
    const vp = viewport();
    act(() => {
      fireEvent.touchStart(vp, { touches: [t(1, 300, 200), t(2, 340, 200)] }); // 间距 40
      fireEvent.touchMove(vp, { touches: [t(1, 300, 200), t(2, 380, 200)] }); // 间距 80 → 64×2=128 → clamp 120
    });
    expect(h.onChangeSettings).toHaveBeenLastCalledWith({ fontSize: 120 });
  });

  it('两指收拢缩小字号', () => {
    const h = renderTel();
    const vp = viewport();
    act(() => {
      fireEvent.touchStart(vp, { touches: [t(1, 300, 200), t(2, 340, 200)] });
      fireEvent.touchMove(vp, { touches: [t(1, 300, 200), t(2, 320, 200)] }); // 间距 20 → 64×0.5=32
    });
    expect(h.onChangeSettings).toHaveBeenLastCalledWith({ fontSize: 32 });
  });

  it('两指间距变化不足 12px 时不调整字号（轻点误判防护）', () => {
    const h = renderTel();
    const vp = viewport();
    act(() => {
      fireEvent.touchStart(vp, { touches: [t(1, 300, 200), t(2, 340, 200)] }); // 间距 40
      fireEvent.touchMove(vp, { touches: [t(1, 300, 200), t(2, 345, 200)] }); // 变化 5px → 忽略
    });
    expect(h.onChangeSettings).not.toHaveBeenCalled();
    act(() => {
      fireEvent.touchMove(vp, { touches: [t(1, 300, 200), t(2, 360, 200)] }); // 变化 20px → 生效
    });
    expect(h.onChangeSettings).toHaveBeenLastCalledWith({ fontSize: 96 }); // 64 × 60/40
  });

  it('捏合中显示字号反馈胶囊，松手 0.6s 后消失', () => {
    vi.useFakeTimers();
    renderTel();
    const vp = viewport();
    act(() => {
      fireEvent.touchStart(vp, { touches: [t(1, 300, 200), t(2, 340, 200)] });
      fireEvent.touchMove(vp, { touches: [t(1, 300, 200), t(2, 380, 200)] });
    });
    expect(screen.getByText('字号 120px')).toBeInTheDocument();
    act(() => {
      fireEvent.touchEnd(vp, { touches: [], changedTouches: [t(1, 300, 200), t(2, 380, 200)] });
    });
    expect(screen.getByText('字号 120px')).toBeInTheDocument(); // 尚未消失
    act(() => { vi.advanceTimersByTime(600); });
    expect(screen.queryByText('字号 120px')).toBeNull();
    vi.useRealTimers();
  });

  it('捏合结束不切换播放状态', () => {
    renderTel();
    const vp = viewport();
    act(() => {
      fireEvent.touchStart(vp, { touches: [t(1, 300, 200), t(2, 340, 200)] });
      fireEvent.touchEnd(vp, { touches: [], changedTouches: [t(1, 300, 200), t(2, 340, 200)] });
    });
    expect(screen.getByLabelText('已暂停')).toBeInTheDocument(); // 仍处于暂停态
  });

  it('一指抬起后剩余手指拖动不再调整字号', () => {
    const h = renderTel();
    const vp = viewport();
    act(() => {
      fireEvent.touchStart(vp, { touches: [t(1, 300, 200), t(2, 340, 200)] });
      fireEvent.touchEnd(vp, { touches: [t(1, 300, 200)], changedTouches: [t(2, 340, 200)] });
      fireEvent.touchMove(vp, { touches: [t(1, 400, 200)] }); // 单指拖动 → 不再触发
    });
    expect(h.onChangeSettings).not.toHaveBeenCalled();
  });

  it('捏合过程连续移动持续生效（字号变化不中断手势）', () => {
    // Harness：onChangeSettings 真实更新 settings prop，字号变化触发 effect 重挂载
    function Harness() {
      const [settings, setSettings] = useState({ ...DEFAULT_SETTINGS });
      return (
        <Teleprompter
          script={script}
          settings={settings}
          index={0}
          onIndexChange={vi.fn()}
          onChangeSettings={(patch) => setSettings((s) => ({ ...s, ...patch }))}
          onBack={vi.fn()}
          onEdit={vi.fn()}
          onCompleted={vi.fn()}
          isFilmed={false}
          onToggleFilmed={vi.fn()}
        />
      );
    }
    render(<Harness />);
    const vp = viewport();
    act(() => {
      fireEvent.touchStart(vp, { touches: [t(1, 300, 200), t(2, 340, 200)] }); // 间距 40
      fireEvent.touchMove(vp, { touches: [t(1, 300, 200), t(2, 380, 200)] }); // 间距 80 → 120
    });
    // 真实设备上每次 move 是独立事件，中间夹着重渲染
    act(() => {
      fireEvent.touchMove(vp, { touches: [t(1, 300, 200), t(2, 320, 200)] }); // 间距 20 → 32
    });
    expect(screen.getByText('32')).toBeInTheDocument(); // 胶囊显示最终字号
  });

  it('真实设置更新下捏合胶囊在松手 0.6s 后消失', () => {
    vi.useFakeTimers();
    function Harness() {
      const [settings, setSettings] = useState({ ...DEFAULT_SETTINGS });
      return (
        <Teleprompter
          script={script}
          settings={settings}
          index={0}
          onIndexChange={vi.fn()}
          onChangeSettings={(patch) => setSettings((s) => ({ ...s, ...patch }))}
          onBack={vi.fn()}
          onEdit={vi.fn()}
          onCompleted={vi.fn()}
          isFilmed={false}
          onToggleFilmed={vi.fn()}
        />
      );
    }
    render(<Harness />);
    const vp = viewport();
    act(() => {
      fireEvent.touchStart(vp, { touches: [t(1, 300, 200), t(2, 340, 200)] });
      fireEvent.touchMove(vp, { touches: [t(1, 300, 200), t(2, 380, 200)] });
    });
    expect(screen.getByText('字号 120px')).toBeInTheDocument();
    act(() => {
      fireEvent.touchEnd(vp, { touches: [], changedTouches: [t(1, 300, 200), t(2, 380, 200)] });
    });
    act(() => { vi.advanceTimersByTime(600); });
    expect(screen.queryByText('字号 120px')).toBeNull();
    vi.useRealTimers();
  });

  it('单指轻点仍可切换播放', () => {
    renderTel();
    const vp = viewport();
    act(() => {
      fireEvent.pointerDown(vp, { pointerId: 1, clientX: 200, clientY: 100 });
      fireEvent.pointerUp(vp, { pointerId: 1, clientX: 200, clientY: 100 });
    });
    expect(screen.getByLabelText('播放中')).toBeInTheDocument(); // 已开始播放
  });
});
