import { describe, it, expect, vi, afterEach } from 'vitest';
import { render, screen, fireEvent, waitFor, act } from '@testing-library/react';
import { useState } from 'react';
import { CameraMirror } from './CameraMirror';

afterEach(() => {
  delete (navigator as unknown as { mediaDevices?: unknown }).mediaDevices;
});

function Harness() {
  const [open, setOpen] = useState(true);
  return <CameraMirror open={open} onClose={() => setOpen(false)} />;
}

describe('CameraMirror', () => {
  it('open=false 时不渲染', () => {
    render(<CameraMirror open={false} onClose={() => {}} />);
    expect(screen.queryByLabelText('关闭镜子')).toBeNull();
  });

  it('环境无 mediaDevices → 显示「未检测到可用的摄像头」', async () => {
    render(<Harness />);
    await waitFor(() => expect(screen.getByText('未检测到可用的摄像头')).toBeInTheDocument());
  });

  it('取流成功 → video 挂流；关闭 → 停止全部轨道并卸载', async () => {
    const stop = vi.fn();
    const fakeStream = { getTracks: () => [{ stop }, { stop }] };
    Object.defineProperty(navigator, 'mediaDevices', {
      configurable: true,
      value: { getUserMedia: vi.fn().mockResolvedValue(fakeStream) },
    });
    render(<Harness />);
    // 加载态先出现
    expect(screen.getByText('正在开启前置摄像头…')).toBeInTheDocument();
    // 就绪：video 拿到流，加载态消失
    await waitFor(() => {
      expect(document.querySelector('video')!.srcObject).toBe(fakeStream);
      expect(screen.queryByText('正在开启前置摄像头…')).toBeNull();
    });
    // 关闭：轨道全部停止
    fireEvent.click(screen.getByLabelText('关闭镜子'));
    await waitFor(() => expect(stop).toHaveBeenCalledTimes(2));
    expect(screen.queryByLabelText('关闭镜子')).toBeNull();
  });

  it('权限被拒 → 显示权限引导文案', async () => {
    Object.defineProperty(navigator, 'mediaDevices', {
      configurable: true,
      value: { getUserMedia: vi.fn().mockRejectedValue(new DOMException('denied', 'NotAllowedError')) },
    });
    render(<Harness />);
    await waitFor(() => expect(screen.getByText(/摄像头权限被拒绝/)).toBeInTheDocument());
  });

  it('取流飞行中关闭 → 刚拿到的流立即释放', async () => {
    const stop = vi.fn();
    const fakeStream = { getTracks: () => [{ stop }] };
    let resolveGet: (s: unknown) => void = () => {};
    Object.defineProperty(navigator, 'mediaDevices', {
      configurable: true,
      value: { getUserMedia: () => new Promise((res) => { resolveGet = res as typeof resolveGet; }) },
    });
    const { rerender } = render(<CameraMirror open onClose={() => {}} />);
    rerender(<CameraMirror open={false} onClose={() => {}} />); // 关闭发生在飞行中
    await act(async () => { resolveGet(fakeStream); });
    await waitFor(() => expect(stop).toHaveBeenCalled());
  });
});
