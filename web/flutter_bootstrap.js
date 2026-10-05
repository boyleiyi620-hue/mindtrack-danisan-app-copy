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

function findVisibleCanvas(root) {
  const canvases = root.querySelectorAll?.('canvas') ?? [];
  for (const canvas of canvases) {
    if (canvas.width > 0 && canvas.height > 0) return canvas;
  }
  for (const element of root.querySelectorAll?.('*') ?? []) {
    if (element.shadowRoot) {
      const canvas = findVisibleCanvas(element.shadowRoot);
      if (canvas) return canvas;
    }
  }
  return null;
}

let firstCanvasTimer;
let observedFlutterShadowRoot;
let startupFailed = false;
const bootObserver = new MutationObserver(() => {
  const flutterShadowRoot = document.querySelector('flt-glass-pane')?.shadowRoot;
  if (flutterShadowRoot && flutterShadowRoot !== observedFlutterShadowRoot) {
    observedFlutterShadowRoot = flutterShadowRoot;
    bootObserver.observe(flutterShadowRoot, { childList: true, subtree: true });
  }
  if (startupFailed || firstCanvasTimer || !findVisibleCanvas(document)) return;
  // The renderer allocates its canvas before Flutter paints its first frame.
  // Keep the splash briefly so slow phones do not expose a blank white view.
  firstCanvasTimer = window.setTimeout(() => {
    if (startupFailed) return;
    window.clearTimeout(slowBootTimer);
    window.clearTimeout(retryTimer);
    bootSplash?.remove();
    bootObserver.disconnect();
  }, 1200);
});
bootObserver.observe(document.documentElement, { childList: true, subtree: true });

function showStartupError(message, detail = '') {
  if (!bootSplash?.isConnected) return;
  startupFailed = true;
  window.clearTimeout(firstCanvasTimer);
  window.clearTimeout(slowBootTimer);
  window.clearTimeout(retryTimer);
  if (bootMessage) bootMessage.textContent = message;
  if (bootDetail) {
    bootDetail.textContent = detail.slice(0, 180);
    bootDetail.hidden = !detail;
  }
  if (retryButton) retryButton.hidden = false;
}

window.addEventListener('error', (event) => {
  const target = event.target;
  const failedScript = target instanceof HTMLScriptElement
    ? new URL(target.src, document.baseURI).pathname.split('/').pop()
    : '';
  const detail = failedScript || event.error?.message || event.message || '';
  console.error('MindTrack startup error:', detail, event.error ?? target);
  showStartupError('Uygulama yüklenemedi. Bağlantınızı kontrol edip yeniden deneyin.', detail);
});
window.addEventListener('unhandledrejection', (event) => {
  const reason = event.reason;
  const detail = reason instanceof Error ? reason.message : String(reason ?? '');
  console.error('MindTrack startup rejection:', reason);
  showStartupError('Uygulama başlatılamadı. Yeniden deneyin.', detail);
});

// Mobile Chromium WebViews/PWAs can expose WebGL but fail CanvasKit shader
// compilation on some GPU drivers. Prefer the software path on touch Android;
// desktop and iOS keep the accelerated renderer.
const isTouchAndroid = /Android/i.test(navigator.userAgent) &&
  window.matchMedia('(pointer: coarse)').matches;

_flutter.loader.load({
  config: {
    canvasKitBaseUrl: 'canvaskit/',
    canvasKitForceCpuOnly: isTouchAndroid,
  },
});
