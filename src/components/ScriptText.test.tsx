import { describe, it, expect, vi } from 'vitest';
import { render } from '@testing-library/react';
import { ScriptText } from './ScriptText';

describe('ScriptText', () => {
  it('按字符渲染，换行渲染为换行', () => {
    const { container } = render(
      <ScriptText content={'ab\nc'} onTokenClick={() => {}} />
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
      <ScriptText content={'abc'} onTokenClick={onClick} />
    );
    (container.querySelector('span[data-idx="2"]') as HTMLElement).click();
    expect(onClick).toHaveBeenCalledWith(2);
  });

  it('全部文字渲染为白色 word 类名', () => {
    const { container } = render(
      <ScriptText content={'测试'} onTokenClick={() => {}} />
    );
    const spans = container.querySelectorAll('span.word');
    expect(spans).toHaveLength(2);
  });
});
