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

// Let Flutter's generated loader own engine initialization and runApp. A
// custom entrypoint callback can leave the app permanently blank if
// any part of that hand-off throws.
const bootObserver = new MutationObserver(() => {
  if (!document.querySelector('flt-glass-pane')) return;
  window.clearTimeout(slowBootTimer);
  bootSplash?.remove();
  bootObserver.disconnect();
});
bootObserver.observe(document.documentElement, { childList: true, subtree: true });

_flutter.loader.load({ config: { canvasKitBaseUrl: 'canvaskit/' } });
