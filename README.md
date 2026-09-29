# MindTrack

Flutter ile yazılmış psikolog klinik takip uygulaması. Psikolog ve danışan için
ayrı uygulamalar içerir; ikisi arasındaki akış (eşleşme kodu, randevu, görev,
ödev, form yanıtı) **Supabase** üzerinden gerçek zamanlı çalışır.

> Sunucu tarafı Firebase'den **Supabase**'e taşınmıştır. Projede hiçbir Firebase
> bağımlılığı kalmamıştır.

## Kurulum

| Dosya | İçerik |
| --- | --- |
| **[SUPABASE-KURULUM.md](SUPABASE-KURULUM.md)** | Supabase projesini sıfırdan kurma (ücretsiz plan), migration çalıştırma, API anahtarı alma |
| **[KURULUM.md](KURULUM.md)** | Uygulamayı derleme ve kullanma (web + Android) |
| [WINDOWS-KURULUM.md](WINDOWS-KURULUM.md) | Windows'ta adım adım APK derleme |
| [README_KAYNAK_KODU.md](README_KAYNAK_KODU.md) | Psikolog uygulaması arşiv teslimi |
| [README_WEB_KAYNAK_KODU.md](README_WEB_KAYNAK_KODU.md) | Web uygulaması arşiv teslimi |

## Hızlı başlangıç

```bash
flutter pub get

export SUPABASE_URL="https://yfxepfxgiceplghlrxek.supabase.co"
export SUPABASE_PUBLISHABLE_KEY="sb_publishable_-2LSJNP29XcL3ykiRQ8aaQ_kxZ7aKAn"

./scripts/build_web.sh
```

## Mimari

```
lib/data/mindtrack_backend.dart   Tüm uzak veri işlemleri (tek giriş noktası)
lib/data/supabase_config.dart     URL / anahtar (derleme zamanında --dart-define)
lib/data/data_store.dart          Yerel-öncelikli durum + uzak senkronizasyon
supabase/migrations/              Şema, RLS politikaları, RPC'ler, depolama
```

- **Yerel öncelikli:** uygulama veriyi önce cihazda tutar, ağ yokken de çalışır.
- **Senkronizasyon:** oturum açıkken arka planda Supabase'e yazar, diğer
  cihazlardan okur.
- **Gerçek zamanlı:** değişiklikler `Realtime` ile anında diğer ekrana ulaşır.
- **Güvenlik:** tüm tablolarda RLS açık; `anon` anahtarı tek başına erişim
  sağlamaz. `service_role` anahtarı hiçbir yerde kullanılmaz.

## Gereksinimler

- Flutter **3.38+** (Dart 3.13)
- Java 17+
- Aktif bir Supabase projesi (Free plan yeterli)

## Testler

```bash
flutter test
flutter analyze
```

---

Sürüm 1.0 · Flutter · Supabase (Postgres + Auth + Realtime + Storage)
