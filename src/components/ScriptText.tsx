import { memo, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { tokenize } from '../lib/tokens';
import { computeLineIndices } from '../lib/lines';

interface Props {
  content: string;
  currentIndex: number;
  onTokenClick: (index: number) => void;
  /** 影响折行的布局参数指纹（字号/间距/行距/对齐/内边距/宽度）；变化时重新测量视觉行 */
  layoutKey: string;
}

/**
 * 逐行高亮：渲染后测量每个字的 offsetTop，相同 offsetTop 归为同一视觉行。
 * 当前字所在行整行设为 current，其上方为 read，下方为 unread。
 */
export const ScriptText = memo(function ScriptText({ content, currentIndex, onTokenClick, layoutKey }: Props) {
  const wrapRef = useRef<HTMLDivElement>(null);
  const tokens = useMemo(() => tokenize(content), [content]);
  // 每个 token 的视觉行号；初始按 index 各异（测量前的占位，paint 前会被 useLayoutEffect 覆盖）
  const [tokenLine, setTokenLine] = useState<number[]>(() => tokens.map((_, i) => i));

  useLayoutEffect(() => {
    const wrap = wrapRef.current;
    if (!wrap) return;
    const spans = Array.from(wrap.querySelectorAll<HTMLElement>('span[data-idx]'));
    const tops = spans.map((s) => s.offsetTop);
    const spanLine = computeLineIndices(tops);

    // 映射回 token：\n token（渲染为 <br>，未测量）复用前一个非换行 token 的行号
    const lineOfToken: number[] = new Array(tokens.length).fill(0);
    let lastLine = 0;
    let si = 0;
    for (let i = 0; i < tokens.length; i++) {
      if (tokens[i].char === '\n') {
        lineOfToken[i] = lastLine;
      } else {
        const line = spanLine[si] ?? lastLine;
        lineOfToken[i] = line;
        lastLine = line;
        si++;
      }
    }
    setTokenLine(lineOfToken);
  }, [tokens, layoutKey]);

  const safeIndex = Math.min(currentIndex, tokens.length - 1);
  const currentLine = safeIndex < 0 ? 0 : (tokenLine[safeIndex] ?? 0);

  return (
    <div ref={wrapRef}>
      {tokens.map((t) => {
        if (t.char === '\n') return <br key={t.id} />;
        const myLine = tokenLine[t.id] ?? 0;
        const state = myLine < currentLine ? 'read' : myLine === currentLine ? 'current' : 'unread';
        return (
          <span
            key={t.id}
            data-idx={t.id}
            data-state={state}
            onClick={() => onTokenClick(t.id)}
            className="word"
          >
            {t.char}
          </span>
        );
      })}
    </div>
  );
});
