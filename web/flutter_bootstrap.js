{{flutter_js}}
{{flutter_build_config}}
// Build output contains CanvasKit locally. Use it instead of the default
// gstatic CDN URL, which the production CSP intentionally blocks.
const bootSplash = document.getElementById('mindtrack-boot');
const bootMessage = document.getElementById('mindtrack-boot-message');
const retryButton = document.getElementById('mindtrack-boot-retry');
const slowBootTimer = window.setTimeout(() => {
  if (bootMessage) {
    bootMessage.textContent = 'Uygulama beklenenden uzun sürüyor. Bağlantınızı kontrol edin.';
  }
  if (retryButton) retryButton.hidden = false;
}, 15000);

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
    bootSplash?.remove();
    bootObserver.disconnect();
  }, 1200);
});
bootObserver.observe(document.documentElement, { childList: true, subtree: true });

function showStartupError(message) {
  if (!bootSplash?.isConnected) return;
  startupFailed = true;
  window.clearTimeout(firstCanvasTimer);
  if (bootMessage) bootMessage.textContent = message;
  if (retryButton) retryButton.hidden = false;
}

window.addEventListener('error', () => showStartupError(
  'Uygulama yüklenemedi. Bağlantınızı kontrol edip yeniden deneyin.',
));
window.addEventListener('unhandledrejection', () => showStartupError(
  'Uygulama başlatılamadı. Yeniden deneyin.',
));

_flutter.loader.load({ config: { canvasKitBaseUrl: 'canvaskit/' } });
