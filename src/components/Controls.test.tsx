import { describe, it, expect, vi } from 'vitest';
import { render, fireEvent, screen } from '@testing-library/react';
import { Controls } from './Controls';

const baseProps = {
  mode: 'manual' as const,
  isPlaying: false,
  wpn: 160,
  onSetMode: vi.fn(),
  onTogglePlay: vi.fn(),
  onJump: vi.fn(),
};

describe('Controls', () => {
  it('点手动模式按钮调用 onSetMode("manual")', () => {
    const onSetMode = vi.fn();
    render(<Controls {...baseProps} onSetMode={onSetMode} />);
    fireEvent.click(screen.getByTitle('手动模式'));
    expect(onSetMode).toHaveBeenCalledWith('manual');
  });

  it('点播放按钮调用 onTogglePlay', () => {
    const onTogglePlay = vi.fn();
    render(<Controls {...baseProps} onTogglePlay={onTogglePlay} />);
    fireEvent.click(screen.getByTitle('播放'));
    expect(onTogglePlay).toHaveBeenCalled();
  });

  it('快进/后退调用 onJump(+20 / -20)', () => {
    const onJump = vi.fn();
    render(<Controls {...baseProps} onJump={onJump} />);
    fireEvent.click(screen.getByTitle('后退'));
    fireEvent.click(screen.getByTitle('快进'));
    expect(onJump).toHaveBeenNthCalledWith(1, -20);
    expect(onJump).toHaveBeenNthCalledWith(2, 20);
  });

  it('速度档仅在 auto 模式显示', () => {
    const { rerender } = render(<Controls {...baseProps} mode="manual" />);
    expect(screen.queryByTitle('速度')).toBeNull();
    rerender(<Controls {...baseProps} mode="auto" />);
    expect(screen.getByText(/160/)).toBeInTheDocument();
  });

  it('播放中按钮标题为"暂停"', () => {
    render(<Controls {...baseProps} isPlaying mode="manual" />);
    expect(screen.getByTitle('暂停')).toBeInTheDocument();
  });
});
