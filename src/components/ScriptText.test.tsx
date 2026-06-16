import { describe, it, expect, vi } from 'vitest';
import { render } from '@testing-library/react';
import { ScriptText } from './ScriptText';

describe('ScriptText', () => {
  it('按字符渲染，换行渲染为换行', () => {
    const { container } = render(
      <ScriptText content={'ab\nc'} currentIndex={0} onTokenClick={() => {}} />
    );
    const spans = container.querySelectorAll('span[data-idx]');
    // a, b, c 三个 span（\n 渲染为 <br>，不算 span）
    expect(spans).toHaveLength(3);
    expect(container.querySelectorAll('br')).toHaveLength(1);
  });

  it('当前字标记 data-state="current"，已读 "read"，未读 "unread"', () => {
    const { container } = render(
      <ScriptText content={'abcde'} currentIndex={2} onTokenClick={() => {}} />
    );
    const states = Array.from(container.querySelectorAll('span[data-idx]')).map((s) =>
      s.getAttribute('data-state')
    );
    expect(states).toEqual(['read', 'read', 'current', 'unread', 'unread']);
  });

  it('点击字符回调其 index', () => {
    const onClick = vi.fn();
    const { container } = render(
      <ScriptText content={'abc'} currentIndex={0} onTokenClick={onClick} />
    );
    (container.querySelector('span[data-idx="2"]') as HTMLElement).click();
    expect(onClick).toHaveBeenCalledWith(2);
  });
});
