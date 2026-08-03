import { useEffect, useState } from 'react';
import { Share, X } from 'lucide-react';
import { ATTS_DISMISSED_KEY, detectStandalone, detectIOS } from '../lib/pwa';

interface BeforeInstallPromptEvent extends Event {
  prompt: () => Promise<void>;
}

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
    <div className="toast-spring fixed bottom-5 left-1/2 z-[90] flex w-[92vw] max-w-md -translate-x-1/2 items-center gap-3 rounded-2xl border border-[#26262B] bg-[#131316]/95 p-4 shadow-2xl backdrop-blur-xl">
      <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-[rgba(212,164,50,0.12)]">
        <Share size={18} className="text-[#D4A432]" />
      </div>
      <div className="flex-1 text-sm leading-snug text-[#A1A1AA]">
        {isIOS
          ? '点 Safari 底部「分享」→「添加到主屏幕」，以后像 App 一样全屏打开'
          : '安装到主屏幕，以后全屏打开'}
      </div>
      <button
        onClick={isIOS ? dismiss : install}
        className="btn-spring btn-press shrink-0 rounded-full bg-[#D4A432] px-4 py-2 text-xs font-bold text-[#0A0A0B] active:scale-[0.97] focus-ring"
        style={{ minHeight: '44px' }}
      >
        {isIOS ? '知道' : '安装'}
      </button>
      <button
        onClick={dismiss}
        aria-label="关闭"
        className="btn-spring shrink-0 rounded-full p-2 text-[#71717A] hover:bg-[rgba(212,164,50,0.08)] hover:text-[#F5F5F5] focus-ring"
        style={{ minHeight: '44px', minWidth: '44px' }}
      >
        <X size={16} />
      </button>
    </div>
  );
}
