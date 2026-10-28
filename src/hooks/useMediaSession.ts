import { useCallback, useEffect, useRef } from 'react';

interface Options {
  /** 展示在系统「正在播放」卡片上的标题（稿件标题） */
  title: string;
  isPlaying: boolean;
  /** 耳机单击（play/pause 两事件都映射到切换） */
  onTogglePlay: () => void;
  /** 耳机双击（nexttrack） */
  onSpeedUp: () => void;
  /** 耳机三击（previoustrack） */
  onSpeedDown: () => void;
}

/**
 * 生成保活 WAV（0.5s / 8kHz / 16bit）。
 * 采样为恒定值 500（约 -36dBFS 的直流）：对操作系统是"非零的真实音频流"，
 * 对扬声器是无法发声的直流信号——人耳完全听不见。
 * （幅值过低的交流/纯零采样会被 iOS 判定为无播放，媒体会话拿不到。）
 */
function createSilentAudioUrl(): string {
  const sampleRate = 8000;
  const numSamples = sampleRate / 2;
  const buffer = new ArrayBuffer(44 + numSamples * 2);
  const view = new DataView(buffer);
  const writeStr = (offset: number, s: string) => {
    for (let i = 0; i < s.length; i++) view.setUint8(offset + i, s.charCodeAt(i));
  };
  writeStr(0, 'RIFF');
  view.setUint32(4, 36 + numSamples * 2, true);
  writeStr(8, 'WAVE');
  writeStr(12, 'fmt ');
  view.setUint32(16, 16, true); // PCM chunk size
  view.setUint16(20, 1, true); // PCM
  view.setUint16(22, 1, true); // mono
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, sampleRate * 2, true); // byte rate
  view.setUint16(32, 2, true); // block align
  view.setUint16(34, 16, true); // bits
  writeStr(36, 'data');
  view.setUint32(40, numSamples * 2, true);
  for (let i = 0; i < numSamples; i++) view.setInt16(44 + i * 2, 500, true);
  return URL.createObjectURL(new Blob([buffer], { type: 'audio/wav' }));
}

/**
 * 耳机媒体键 → 提词器控制（AirPods / 蓝牙耳机 / 键盘媒体键 / 锁屏控件共用）。
 *
 * 单击 = 播放/暂停；双击 = 下一首 → 速度 +20；三击 = 上一首 → 速度 −20。
 * （AirPods Pro 的上下轻扫是系统音量，不经过浏览器，无法映射。）
 *
 * 静音音频的 play() 必须发生在用户手势内：在 Teleprompter 的
 * 轻点/空格回调里同步调用 activate()；之后音频持续循环保活会话，
 * 只切换 mediaSession.playbackState 供系统 UI 显示。
 */
export function useMediaSession({ title, isPlaying, onTogglePlay, onSpeedUp, onSpeedDown }: Options) {
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const audioUrlRef = useRef<string | null>(null);
  const activatedRef = useRef(false);
  // 回调走 ref，避免每次渲染重挂 action handler
  const cbs = useRef({ onTogglePlay, onSpeedUp, onSpeedDown });
  cbs.current = { onTogglePlay, onSpeedUp, onSpeedDown };

  /** 必须在用户手势回调内同步调用 */
  const activate = useCallback(() => {
    if (activatedRef.current) return;
    if (typeof navigator === 'undefined' || !navigator.mediaSession) return; // 环境不支持则静默跳过
    activatedRef.current = true;
    try {
      const url = createSilentAudioUrl();
      const audio = new Audio(url);
      audio.loop = true;
      audio.setAttribute('playsinline', 'true');
      audio.style.display = 'none';
      document.body.appendChild(audio); // iOS PWA 对游离 audio 元素的播放不稳定，挂进 DOM
      // 看门狗：iOS 在音频路由变化（戴上/摘下耳机）、来电打断等情况会自动暂停
      // 保活音频导致会话丢失。元素已在手势内解锁过，这里免手势直接复活。
      audio.addEventListener('pause', () => {
        if (!activatedRef.current) return;
        Promise.resolve(audio.play()).catch(() => { /* 复活失败等下次手势重试 */ });
      });
      Promise.resolve(audio.play()).catch(() => {
        // 手势外被浏览器拦截 → 允许下次手势重试
        activatedRef.current = false;
      });
      audioRef.current = audio;
      audioUrlRef.current = url;
    } catch {
      activatedRef.current = false;
    }
  }, []);

  // 挂载/卸载 action handlers
  useEffect(() => {
    const ms = navigator.mediaSession;
    if (!ms || typeof ms.setActionHandler !== 'function') return;
    const toggle = () => cbs.current.onTogglePlay();
    try {
      ms.setActionHandler('play', toggle);
      ms.setActionHandler('pause', toggle);
      ms.setActionHandler('nexttrack', () => cbs.current.onSpeedUp());
      ms.setActionHandler('previoustrack', () => cbs.current.onSpeedDown());
    } catch {
      return; // 浏览器不支持任一动作则整体放弃（能力检测粒度不做细拆）
    }
    return () => {
      try {
        ms.setActionHandler('play', null);
        ms.setActionHandler('pause', null);
        ms.setActionHandler('nexttrack', null);
        ms.setActionHandler('previoustrack', null);
      } catch { /* noop */ }
    };
  }, []);

  // 「正在播放」卡片显示稿件标题
  useEffect(() => {
    const ms = navigator.mediaSession;
    if (!ms || typeof MediaMetadata === 'undefined') return;
    try {
      ms.metadata = new MediaMetadata({ title, artist: '提词器' });
    } catch { /* noop */ }
  }, [title]);

  // 同步播放状态（音频本体持续循环保活，只翻转系统 UI 的状态）
  useEffect(() => {
    const ms = navigator.mediaSession;
    if (!ms) return;
    try {
      ms.playbackState = isPlaying ? 'playing' : 'paused';
    } catch { /* noop */ }
  }, [isPlaying]);

  // 卸载：停掉保活音频并释放资源
  useEffect(() => {
    return () => {
      activatedRef.current = false; // 先置否决，避免看门狗在清理过程中复活音频
      audioRef.current?.pause();
      audioRef.current?.remove();
      if (audioUrlRef.current) URL.revokeObjectURL(audioUrlRef.current);
      audioRef.current = null;
      audioUrlRef.current = null;
    };
  }, []);

  return { activate };
}
