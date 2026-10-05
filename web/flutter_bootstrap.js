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

_flutter.loader.load({
  onEntrypointLoaded: async (engineInitializer) => {
    try {
      // Keep CanvasKit's default WebGL acceleration; CPU-only rendering is
      // noticeably slower on phones.
      const appRunner = await engineInitializer.initializeEngine({
        canvasKitBaseUrl: 'canvaskit/',
      });
      await appRunner.runApp();
      window.clearTimeout(slowBootTimer);
      bootSplash?.remove();
    } catch (error) {
      window.clearTimeout(slowBootTimer);
      console.error('MindTrack web app failed to start:', error);
      if (bootMessage) bootMessage.textContent = 'Uygulama açılamadı. Lütfen yeniden deneyin.';
      if (retryButton) retryButton.hidden = false;
    }
  },
});
