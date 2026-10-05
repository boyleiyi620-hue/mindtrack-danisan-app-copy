# Değişiklik Günlüğü

Bu dosya, MindTrack web/PWA sürümlerindeki kullanıcıya yansıyan değişiklikleri
kısa ve izlenebilir biçimde tutar.

## 1.0.1+2 — 2026-10-05

- Google OAuth ve üretim yönlendirme ayarları etkinleştirildi.
- Danışan uygulaması `/client/` altında ayrı web/PWA giriş noktası olarak
  yayınlandı.
- Android WebView ve Chrome/PWA için uyarlamalı Flutter render seçimi eklendi.
- Danışan başlangıcında yalnızca aktif sekme ve gerekli canlı veri akışları
  yükleniyor.
- Genel klinik arama, randevu hatırlatmaları ve güvenli yedek geri yükleme
  iyileştirmeleri yayınlandı.
- PWA güncellemeleri açık düzenlemeleri zorla yenilemeden uygulanıyor.

## Sürümleme kuralı

- `MAJOR.MINOR.PATCH+BUILD` biçimi kullanılır.
- Kullanıcıya görünen web/PWA değişikliklerinde `PATCH` artırılır.
- Her üretim web derlemesinde `BUILD` artırılır.
