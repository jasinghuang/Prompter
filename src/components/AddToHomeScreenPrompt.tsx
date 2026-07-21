import { useEffect, useState } from 'react';
import { Share, X } from 'lucide-react';
import { ATTS_DISMISSED_KEY, detectStandalone, detectIOS } from '../lib/pwa';

interface BeforeInstallPromptEvent extends Event {
  prompt: () => Promise<void>;
}

/**
 * 「添加到主屏幕」引导。
 * iOS：提示用户「分享 → 添加到主屏幕」；Android：捕获 beforeinstallprompt 触发系统安装。
 */
export function AddToHomeScreenPrompt() {
  const [show, setShow] = useState(false);
  const [deferred, setDeferred] = useState<BeforeInstallPromptEvent | null>(null);

  useEffect(() => {
    const dismissed = localStorage.getItem(ATTS_DISMISSED_KEY) === '1';
    if (detectIOS() && !dismissed && !detectStandalone()) {
      setShow(true);
    }
    const onBIP = (e: Event) => {
      e.preventDefault();
      const ev = e as BeforeInstallPromptEvent;
      setDeferred(ev);
      if (!dismissed && !detectStandalone()) setShow(true);
    };
    window.addEventListener('beforeinstallprompt', onBIP);
    return () => window.removeEventListener('beforeinstallprompt', onBIP);
  }, []);

  const dismiss = () => {
    localStorage.setItem(ATTS_DISMISSED_KEY, '1');
    setShow(false);
  };

  const install = async () => {
    if (!deferred) return;
    await deferred.prompt();
    setDeferred(null);
    setShow(false);
  };

  if (!show) return null;
  const isIOS = detectIOS();

  return (
    <div className="fixed bottom-5 left-1/2 z-[90] flex w-[92vw] max-w-md -translate-x-1/2 items-center gap-3 rounded-2xl border border-yellow-500/30 bg-neutral-900/95 p-4 shadow-2xl backdrop-blur-xl">
      <Share size={20} className="shrink-0 text-yellow-500" />
      <div className="flex-1 text-sm leading-snug text-neutral-200">
        {isIOS
          ? '点 Safari 底部「分享」→「添加到主屏幕」，以后像 App 一样全屏打开'
          : '安装到主屏幕，以后全屏打开'}
      </div>
      <button
        onClick={isIOS ? dismiss : install}
        className="shrink-0 rounded-full bg-yellow-500 px-3 py-1.5 text-xs font-bold text-black"
      >
        {isIOS ? '知道' : '安装'}
      </button>
      <button onClick={dismiss} aria-label="关闭" className="shrink-0 text-neutral-500 hover:text-white">
        <X size={16} />
      </button>
    </div>
  );
}
