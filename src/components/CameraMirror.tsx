import { useEffect, useRef, useState } from 'react';
import { CameraOff, X } from 'lucide-react';

interface Props {
  open: boolean;
  onClose: () => void;
}

/**
 * 前置化妆镜：打开才取流（getUserMedia 前置摄像头），关闭立即释放全部轨道
 * （系统摄像头指示灯熄灭）。纯本地预览：不录制、不上传、水平镜像。
 */
export function CameraMirror({ open, onClose }: Props) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const [status, setStatus] = useState<'loading' | 'ready' | 'error'>('loading');
  const [errorMsg, setErrorMsg] = useState('');

  useEffect(() => {
    if (!open) return;
    let cancelled = false;
    setStatus('loading');
    setErrorMsg('');

    const start = async () => {
      try {
        if (!navigator.mediaDevices?.getUserMedia) {
          throw new DOMException('no mediaDevices', 'NotFoundError');
        }
        const stream = await navigator.mediaDevices.getUserMedia({
          video: { facingMode: 'user', width: { ideal: 720 } },
          audio: false,
        });
        if (cancelled) {
          stream.getTracks().forEach((t) => t.stop()); // 关闭发生在取流飞行中 → 释放刚拿到的流
          return;
        }
        streamRef.current = stream;
        if (videoRef.current) {
          videoRef.current.srcObject = stream;
          videoRef.current.play().catch(() => { /* muted 自动播放，失败由状态兜底 */ });
        }
        setStatus('ready');
      } catch (err) {
        if (cancelled) return;
        const name = (err as DOMException).name;
        if (name === 'NotAllowedError' || name === 'SecurityError') setErrorMsg('摄像头权限被拒绝，可在系统设置中允许后重试');
        else if (name === 'NotFoundError' || name === 'OverconstrainedError') setErrorMsg('未检测到可用的摄像头');
        else setErrorMsg('摄像头暂时不可用（可能被其他应用占用）');
        setStatus('error');
      }
    };
    start();

    return () => {
      cancelled = true;
      streamRef.current?.getTracks().forEach((t) => t.stop());
      streamRef.current = null;
      if (videoRef.current) videoRef.current.srcObject = null;
    };
  }, [open]);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open, onClose]);

  if (!open) return null;

  return (
    <div className="absolute inset-0 z-[75] flex items-center justify-center bg-black/55 backdrop-blur-sm" onClick={onClose}>
      <div
        className="relative aspect-[3/4] h-[82%] overflow-hidden rounded-[22px] border border-white/10 bg-[#131316] shadow-2xl"
        style={{ animation: 'mirror-pop 0.22s cubic-bezier(0.22, 1, 0.36, 1)' }}
        onClick={(e) => e.stopPropagation()}
      >
        <video ref={videoRef} autoPlay playsInline muted className="h-full w-full -scale-x-100 object-cover" />
        {status !== 'ready' && (
          <div className="absolute inset-0 flex flex-col items-center justify-center gap-3 p-6 text-center text-[13px] text-white/50">
            {status === 'loading' ? (
              <>
                <span className="h-7 w-7 animate-spin rounded-full border-[3px] border-white/15 border-t-[#D4A432]" />
                <span>正在开启前置摄像头…</span>
              </>
            ) : (
              <>
                <CameraOff size={22} className="text-white/30" />
                <span>{errorMsg}</span>
              </>
            )}
          </div>
        )}
        <button
          onClick={onClose}
          aria-label="关闭镜子"
          className="absolute right-2.5 top-2.5 flex h-[34px] w-[34px] items-center justify-center rounded-full border border-white/15 bg-black/45 text-white transition-colors hover:bg-black/70 active:scale-95"
        >
          <X size={15} />
        </button>
      </div>
    </div>
  );
}
