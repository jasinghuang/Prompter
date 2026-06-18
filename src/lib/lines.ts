/**
 * 给定一组元素（按 token 顺序）的 offsetTop，返回每个元素所属的视觉行号。
 * 相同 offsetTop（容差 1px，应对亚像素）归为同一行；行号从 0 开始递增。
 *
 * 用于逐行高亮：渲染后测量每个字的 offsetTop，相同者视为同一视觉折行行。
 */
export function computeLineIndices(offsetTops: number[]): number[] {
  const distinctTops: number[] = [];
  return offsetTops.map((top) => {
    const idx = distinctTops.findIndex((t) => Math.abs(t - top) < 1);
    if (idx === -1) {
      distinctTops.push(top);
      return distinctTops.length - 1;
    }
    return idx;
  });
}
