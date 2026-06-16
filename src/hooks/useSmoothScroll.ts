import { useCallback, useRef } from 'react';

/** 把 element 滚动到容器中线（垂直居中）。用 rAF 缓动，避免瞬移卡顿。 */
export function useSmoothScroll() {
  const rafRef = useRef<number | null>(null);

  const cancel = useCallback(() => {
    if (rafRef.current !== null) {
      cancelAnimationFrame(rafRef.current);
      rafRef.current = null;
    }
  }, []);

  const scrollIntoContainerCenter = useCallback(
    (container: HTMLElement, target: HTMLElement) => {
      cancel();
      const computeTarget = () =>
        target.offsetTop - container.clientHeight / 2 + target.offsetHeight / 2;

      const animate = () => {
        const goal = computeTarget();
        const current = container.scrollTop;
        const diff = goal - current;
        // 误差小于 1px 视为到位
        if (Math.abs(diff) < 1) {
          container.scrollTop = goal;
          rafRef.current = null;
          return;
        }
        container.scrollTop = current + diff * 0.18; // 缓动系数
        rafRef.current = requestAnimationFrame(animate);
      };
      rafRef.current = requestAnimationFrame(animate);
    },
    [cancel]
  );

  return { scrollIntoContainerCenter, cancel };
}
