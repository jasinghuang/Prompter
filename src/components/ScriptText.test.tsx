import { describe, it, expect, vi } from 'vitest';
import { render } from '@testing-library/react';
import { ScriptText } from './ScriptText';

// 注：逐行分组的真实行为由 lib/lines.test.ts 的 computeLineIndices 覆盖。
// jsdom 下 offsetTop 恒 0（所有字同行），此处仅验证渲染结构与交互。
describe('ScriptText', () => {
  it('按字符渲染，换行渲染为换行', () => {
    const { container } = render(
      <ScriptText content={'ab\nc'} currentIndex={0} onTokenClick={() => {}} layoutKey="x" />
    );
    const wrap = container.querySelector('div')!;
    const spans = wrap.querySelectorAll('span[data-idx]');
    // a, b, c 三个 span（\n 渲染为 <br>）
    expect(spans).toHaveLength(3);
    expect(wrap.querySelectorAll('br')).toHaveLength(1);
  });

  it('点击字符回调其 index', () => {
    const onClick = vi.fn();
    const { container } = render(
      <ScriptText content={'abc'} currentIndex={0} onTokenClick={onClick} layoutKey="x" />
    );
    (container.querySelector('span[data-idx="2"]') as HTMLElement).click();
    expect(onClick).toHaveBeenCalledWith(2);
  });

  it('currentIndex 越界时不崩溃', () => {
    expect(() =>
      render(<ScriptText content={'abc'} currentIndex={99} onTokenClick={() => {}} layoutKey="x" />)
    ).not.toThrow();
  });
});
