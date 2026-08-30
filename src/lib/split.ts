/** 按连续空行切分稿件，去除首尾空白并过滤空段 */
export function splitByParagraphs(content: string): string[] {
  return content
    .split(/\n{2,}/)
    .map((p) => p.trim())
    .filter((p) => p !== '');
}

/** 在每个关键词出现处之前切分（字面量匹配），新段以关键词开头；空关键词返回空数组 */
export function splitByKeyword(content: string, keyword: string): string[] {
  if (!keyword) return [];
  const parts: string[] = [];
  let prev = 0;
  let idx = content.indexOf(keyword);
  while (idx !== -1) {
    parts.push(content.slice(prev, idx));
    prev = idx;
    idx = content.indexOf(keyword, idx + keyword.length);
  }
  parts.push(content.slice(prev));
  return parts
    .map((p) => p.trim())
    .filter((p) => p !== '');
}
