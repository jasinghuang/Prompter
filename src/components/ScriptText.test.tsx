import { describe, it, expect } from 'vitest';
import { render } from '@testing-library/react';
import { ScriptText } from './ScriptText';

describe('ScriptText', () => {
  it('按字符渲染，换行渲染为 <br>', () => {
    const { container } = render(
      <ScriptText content={'ab\nc'} />
    );
    const wrap = container.querySelector('div')!;
    const spans = wrap.querySelectorAll('span[data-idx]');
    expect(spans).toHaveLength(3);
    expect(wrap.querySelectorAll('br')).toHaveLength(1);
  });

  it('全部文字渲染为白色 word 类名', () => {
    const { container } = render(
      <ScriptText content={'测试'} />
    );
    const spans = container.querySelectorAll('span.word');
    expect(spans).toHaveLength(2);
  });

  it('每个 span 挂 data-idx 索引', () => {
    const { container } = render(
      <ScriptText content={'abc'} />
    );
    expect(container.querySelector('span[data-idx="0"]')).toBeTruthy();
    expect(container.querySelector('span[data-idx="2"]')).toBeTruthy();
  });
});
