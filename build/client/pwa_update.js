// Updates activate automatically, but not while a text editor is focused.
(() => {
  if (!('serviceWorker' in navigator)) return;

  let acceptedUpdate = false;
  let controllerChangedWhileEditing = false;
  let hadControllerAtStartup = Boolean(navigator.serviceWorker.controller);
  let pendingRegistration;
  let installPromptEvent;

  function sessionValue(key) {
    try {
      return sessionStorage.getItem(key);
    } catch (_) {
      return null;
    }
  }

  function setSessionValue(key, value) {
    try {
      sessionStorage.setItem(key, value);
    } catch (_) {
      // Private browsing may disable storage; dismissing the banner still works.
    }
  }

  let connectivityNotice;
  function refreshConnectivityNotice(online) {
    if (!connectivityNotice) {
      connectivityNotice = document.createElement('div');
      connectivityNotice.setAttribute('role', 'status');
      connectivityNotice.setAttribute('aria-live', 'polite');
      connectivityNotice.style.cssText =
        'position:fixed;z-index:2147483000;left:16px;right:16px;top:12px;' +
        'max-width:560px;margin:0 auto;padding:10px 14px;border-radius:10px;' +
        'background:#7b2e22;color:#fff;box-shadow:0 6px 20px #0003;' +
        'font:600 13px/1.4 system-ui,sans-serif;text-align:center';
      document.body.append(connectivityNotice);
    }
    connectivityNotice.textContent = online
      ? 'Bağlantı geri geldi. Bekleyen değişiklikler senkronize edilecek.'
      : 'Sunucuya erişilemiyor. Senkron durumunu kontrol edin; bu sırada diğer cihazlarla bağlantı kurulamayabilir.';
    connectivityNotice.style.display = 'block';
    if (online) {
      window.setTimeout(() => {
        if (navigator.onLine) connectivityNotice.style.display = 'none';
      }, 6000);
    }
  }

  window.addEventListener('offline', () => refreshConnectivityNotice(false));
  window.addEventListener('online', () => refreshConnectivityNotice(true));
  if (!navigator.onLine) refreshConnectivityNotice(false);

  function showInstallBanner(message, actionLabel, onAction) {
    if (sessionValue('mindtrack-install-dismissed') === '1') return;
    const banner = document.createElement('aside');
    banner.setAttribute('role', 'status');
    banner.style.cssText =
      'position:fixed;z-index:2147483000;left:16px;right:16px;bottom:16px;' +
      'max-width:560px;margin-left:auto;padding:14px 16px;border-radius:14px;' +
      'background:#173c39;color:#fff;box-shadow:0 8px 28px #0004;' +
      'font:14px/1.45 system-ui,sans-serif;display:flex;align-items:center;gap:12px';

    const copy = document.createElement('span');
    copy.textContent = message;
    copy.style.flex = '1';
    const action = document.createElement('button');
    action.type = 'button';
    action.textContent = actionLabel;
    action.style.cssText =
      'border:0;border-radius:8px;padding:9px 12px;background:#fff;color:#173c39;' +
      'font:600 13px system-ui,sans-serif;white-space:nowrap;cursor:pointer';
    action.addEventListener('click', async () => {
      if (onAction) await onAction();
      banner.remove();
    });
    const close = document.createElement('button');
    close.type = 'button';
    close.setAttribute('aria-label', 'Kapat');
    close.textContent = '×';
    close.style.cssText =
      'border:0;background:transparent;color:#fff;font:24px/1 system-ui,sans-serif;' +
      'cursor:pointer;padding:0 2px';
    close.addEventListener('click', () => {
      setSessionValue('mindtrack-install-dismissed', '1');
      banner.remove();
    });
    banner.append(copy, action, close);
    document.body.append(banner);
  }

  window.addEventListener('beforeinstallprompt', (event) => {
    event.preventDefault();
    installPromptEvent = event;
    showInstallBanner('MindTrack’i ana ekrana ekleyip daha hızlı açabilirsiniz.', 'Yükle', async () => {
      installPromptEvent.prompt();
      await installPromptEvent.userChoice;
      installPromptEvent = null;
    });
  });

  const isAppleMobile = /iPhone|iPad|iPod/.test(navigator.userAgent) ||
    (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  if (isAppleMobile && !navigator.standalone) {
    showInstallBanner(
      'MindTrack’i ana ekrana eklemek için Paylaş menüsünden “Ana Ekrana Ekle”yi seçin.',
      'Anladım',
    );
  }

  function isTextEditor(element) {
    return element instanceof HTMLElement &&
      (element.matches('input, textarea, [contenteditable="true"]') ||
        element.closest('[contenteditable="true"]') !== null);
  }

  // Flutter web uses a focused DOM editor while a text field is being edited.
  // Wait for focus to leave it; blur fires before the save button's click,
  // hence the short delay lets the save handler finish before offering reload.
  document.addEventListener('focusout', () => {
    window.setTimeout(() => {
      if (isTextEditor(document.activeElement)) return;
      if (controllerChangedWhileEditing) {
        window.location.reload();
      } else {
        offerUpdate();
      }
    }, 700);
  }, true);

  navigator.serviceWorker.addEventListener('controllerchange', () => {
    // First-time PWA control does not require reloading: this document already
    // has the current network response. Reload only when replacing an old SW.
    if (!hadControllerAtStartup) {
      hadControllerAtStartup = true;
      return;
    }
    if (isTextEditor(document.activeElement)) {
      controllerChangedWhileEditing = true;
      return;
    }
    window.location.reload();
  });

  function offerUpdate() {
    const waiting = pendingRegistration?.waiting;
    if (!waiting || acceptedUpdate || isTextEditor(document.activeElement)) return;
    acceptedUpdate = true;
    waiting.postMessage({ type: 'SKIP_WAITING' });
  }

  function watchRegistration(registration) {
    if (!registration) return;
    pendingRegistration = registration;
    offerUpdate();
    registration.addEventListener('updatefound', () => {
      const worker = registration.installing;
      if (!worker) return;
      worker.addEventListener('statechange', () => {
        if (worker.state === 'installed' && navigator.serviceWorker.controller) {
          pendingRegistration = registration;
          offerUpdate();
        }
      });
    });
    registration.update().then(offerUpdate).catch(() => {});
    window.setInterval(() => {
      if (document.visibilityState === 'visible') {
        registration.update().then(offerUpdate).catch(() => {});
      }
    }, 60 * 60 * 1000);
  }

  window.mindTrackWatchServiceWorker = watchRegistration;
})();
