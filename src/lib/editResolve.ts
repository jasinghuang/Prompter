/**
 * 编辑文案后，决定提词器当前阅读位置如何调整。
 * - 若当前位置之前的内容（前 index 字符）未变 → 保持原 index
 * - 否则（前缀改动，或新内容短于 index）→ 重置到 0（开头）
 */
export function resolveIndexAfterEdit(
  oldContent: string,
  newContent: string,
  oldIndex: number
): number {
  if (oldIndex <= 0) return 0;
  if (newContent.length <= oldIndex) return 0;
  const oldPrefix = oldContent.slice(0, oldIndex);
  const newPrefix = newContent.slice(0, oldIndex);
  return oldPrefix === newPrefix ? oldIndex : 0;
}
