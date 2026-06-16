import { memo } from 'react';
import { tokenize } from '../lib/tokens';

interface Props {
  content: string;
  currentIndex: number;
  onTokenClick: (index: number) => void;
}

function stateOf(index: number, currentIndex: number): 'read' | 'current' | 'unread' {
  if (index < currentIndex) return 'read';
  if (index === currentIndex) return 'current';
  return 'unread';
}

export const ScriptText = memo(function ScriptText({ content, currentIndex, onTokenClick }: Props) {
  const tokens = tokenize(content);
  return (
    <>
      {tokens.map((t) => {
        if (t.char === '\n') return <br key={t.id} />;
        return (
          <span
            key={t.id}
            data-idx={t.id}
            data-state={stateOf(t.id, currentIndex)}
            onClick={() => onTokenClick(t.id)}
            className="word"
          >
            {t.char}
          </span>
        );
      })}
    </>
  );
});
