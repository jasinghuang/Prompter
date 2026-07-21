import { memo, useMemo } from 'react';
import { tokenize } from '../lib/tokens';

interface Props {
  content: string;
  onTokenClick: (index: number) => void;
}

/**
 * 提词器文本渲染：逐字渲染为 span，全部白色。
 * 每个字挂 data-idx 供 Teleprompter 做滚动定位。
 */
export const ScriptText = memo(function ScriptText({ content, onTokenClick }: Props) {
  const tokens = useMemo(() => tokenize(content), [content]);

  return (
    <div>
      {tokens.map((t) => {
        if (t.char === '\n') return <br key={t.id} />;
        return (
          <span
            key={t.id}
            data-idx={t.id}
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
