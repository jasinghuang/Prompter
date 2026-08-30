export interface Script {
  id: string;
  title: string;
  content: string;
  createdAt: number;
  updatedAt: number;
}

export type ScrollMode = 'manual' | 'auto';

export type TextAlign = 'left' | 'center' | 'right';

/** 读完动作：none=不开启 / list=返回列表 / restart=回到开头 */
export type CompleteAction = 'none' | 'list' | 'restart';

/** 智能拆分模式：paragraph=按空行 / keyword=按关键词 */
export type SplitMode = 'paragraph' | 'keyword';

export interface TeleprompterSettings {
  fontSize: number;
  letterSpacing: number;
  lineHeight: number;
  scrollSpeed: number;
  mirror: boolean;
  /** 阅读区左右内边距（百分比），默认 8 */
  horizontalPadding: number;
  /** 文本对齐，默认 left */
  textAlign: TextAlign;
  /** 自动暂停关键词（空字符串 = 不启用），默认 '' */
  pauseKeyword: string;
  /** 遇到空行自动暂停（段落分隔），默认 false */
  pauseOnParagraph: boolean;
  /** 读完动作，默认 none */
  completeAction: CompleteAction;
  /** 智能拆分模式，默认 paragraph（按空行） */
  splitMode: SplitMode;
  /** 智能拆分关键词（空字符串 = 未设置），默认 '' */
  splitKeyword: string;
}

export const DEFAULT_SETTINGS: TeleprompterSettings = {
  fontSize: 64,
  letterSpacing: 0.05,
  lineHeight: 1.6,
  scrollSpeed: 160,
  mirror: false,
  horizontalPadding: 8,
  textAlign: 'left',
  pauseKeyword: '',
  pauseOnParagraph: false,
  completeAction: 'none',
  splitMode: 'paragraph',
  splitKeyword: '',
};

export const FONT_SIZE_MIN = 24;
export const FONT_SIZE_MAX = 120;
export const LETTER_SPACING_MIN = 0;
export const LETTER_SPACING_MAX = 0.3;
export const LINE_HEIGHT_MIN = 1.0;
export const LINE_HEIGHT_MAX = 2.5;
export const PADDING_MIN = 4;
export const PADDING_MAX = 20;
