{{flutter_js}}
{{flutter_build_config}}
// Build output contains CanvasKit locally. Use it instead of the default
// gstatic CDN URL, which the production CSP intentionally blocks.
const bootSplash = document.getElementById('mindtrack-boot');
const bootMessage = document.getElementById('mindtrack-boot-message');
const bootDetail = document.getElementById('mindtrack-boot-detail');
const retryButton = document.getElementById('mindtrack-boot-retry');
const slowBootTimer = window.setTimeout(() => {
  if (bootMessage) {
    bootMessage.textContent = 'İlk açılışta uygulama dosyaları yükleniyor. Lütfen sayfayı açık tutun.';
  }
}, 15000);
const retryTimer = window.setTimeout(() => {
  if (bootMessage) {
    bootMessage.textContent = 'Açılış tamamlanamadı. İnternet bağlantınızı kontrol edip yeniden deneyin.';
  }
  if (retryButton) retryButton.hidden = false;
}, 90000);

retryButton?.addEventListener('click', () => window.location.reload());

let startupFailed = false;

function showStartupError(message, detail = '') {
  if (!bootSplash?.isConnected) return;
  startupFailed = true;
  window.clearTimeout(slowBootTimer);
  window.clearTimeout(retryTimer);
  if (bootMessage) bootMessage.textContent = message;
  if (bootDetail) {
    bootDetail.textContent = detail.slice(0, 600);
    bootDetail.hidden = !detail;
  }
  if (retryButton) retryButton.hidden = false;
}

window.addEventListener('error', (event) => {
  const target = event.target;
  const failedScript = target instanceof HTMLScriptElement
    ? new URL(target.src, document.baseURI).pathname.split('/').pop()
    : '';
  const detail = failedScript || event.error?.stack || event.error?.message || event.message || '';
  console.error('MindTrack startup error:', detail, event.error ?? target);
  showStartupError('Uygulama yüklenemedi. Bağlantınızı kontrol edip yeniden deneyin.', detail);
});
window.addEventListener('unhandledrejection', (event) => {
  const reason = event.reason;
  const detail = reason?.stack || (reason instanceof Error ? reason.message : String(reason ?? ''));
  console.error('MindTrack startup rejection:', reason);
  showStartupError('Uygulama başlatılamadı. Yeniden deneyin.', detail);
});

// Normal Chrome/PWA'da GPU hızlandırması akıcılığı belirgin artırır. Android
// WebView ise WebGL context kaybına daha yatkındır; yalnızca o ortamda CPU
// fallback kullan.
const isAndroidWebView = /Android/i.test(navigator.userAgent) &&
  (/;\s*wv\)/i.test(navigator.userAgent) ||
    (/Version\/\d+.*Chrome\/\d+.*Mobile/i.test(navigator.userAgent) &&
      !window.matchMedia('(display-mode: standalone)').matches));

const flutterConfig = {
  canvasKitBaseUrl: 'canvaskit/',
  ...(isAndroidWebView ? {canvasKitForceCpuOnly: true} : {}),
};

_flutter.loader.load({
  config: flutterConfig,
  onEntrypointLoaded: async (engineInitializer) => {
    try {
      const appRunner = await engineInitializer.initializeEngine(flutterConfig);
      await appRunner.runApp();
      if (startupFailed) return;
      window.clearTimeout(slowBootTimer);
      window.clearTimeout(retryTimer);
      bootSplash?.remove();
    } catch (error) {
      const detail = error?.stack || error?.message || String(error);
      console.error('MindTrack Flutter startup failed:', error);
      showStartupError('Uygulama başlatılamadı. Yeniden deneyin.', detail);
    }
  },
});
