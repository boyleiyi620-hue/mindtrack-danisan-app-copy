# MindTrack Psikolog Uygulaması — Kaynak Kod Arşivi

Bu arşiv, MindTrack psikolog uygulamasının güncel Flutter kaynak kodlarını içerir.
Sunucu tarafı **Supabase** üzerine taşınmıştır; Firebase bağımlılığı kalmamıştır.

## İçerik

- `lib/`: Flutter/Dart uygulama kaynakları
- `android/`: Android proje dosyaları, `client` ve `psychologist` ürün varyantları
- `web/`: Web platform yapılandırması (psikolog ve danışan için ayrı `index`/`manifest`)
- `supabase/migrations/`: Veritabanı şeması, RLS politikaları, RPC'ler, depolama
- `supabase/config.toml`: Supabase CLI yapılandırması
- `scripts/build_web.sh`: Psikolog ve danışan web çıktılarını üreten betik
- `pubspec.yaml` ve `pubspec.lock`: Flutter bağımlılıkları

## Paket kimliği

| Varyant | Application ID |
| --- | --- |
| Danışan | `tr.mindtrack.app.danisan` |
| Psikolog | `tr.mindtrack.app.psikolog` |

## Kurulum

Supabase projesi olmadan uygulama oturum açamaz. Adımlar için
**[SUPABASE-KURULUM.md](SUPABASE-KURULUM.md)** dosyasına bakın. Özet:

```bash
flutter pub get

flutter build apk --release --flavor psychologist \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_PUBLISHABLE_KEY="$SUPABASE_PUBLISHABLE_KEY"
```

`SUPABASE_URL` ve `SUPABASE_PUBLISHABLE_KEY` derleme zamanında verilir; kaynak koda
gömülmez ve repoya yazılmaz.

## Derleme ortamı

Flutter Stable, Android SDK ve Java 17+ gereklidir. Gerekli Flutter sürümü
**3.38 veya üzeri** (proje Dart 3.13 ile yazıldı).

## Güvenlik notu

- Kullanıcı parolaları arşive dahil değildir ve uygulamada saklanmaz; doğrulama
  Supabase Auth tarafından yapılır.
- Uygulama yalnızca `anon` (publishable) anahtarını kullanır. `service_role`
  (secret) anahtarı hiçbir yerde kullanılmaz ve istemciye verilmez.
- Tüm veri erişimi veritabanındaki RLS politikalarıyla sınırlıdır: her kullanıcı
  yalnızca kendi satırlarını görebilir/ düzenleyebilir.
- Eşleşme kodları yalnızca `claim_pairing_code` RPC'si üzerinden atomik olarak
  sahiplenilir; listelenemez.

## Senkronizasyon

Psikolog mobil ve Web sürümleri aynı Supabase projesini ve aynı kullanıcı UUID'sini
kullanır. Psikologun tüm klinik kaydı `psychologist_state` tablosunda **tek bir
jsonb satırı** olarak tutulur; bu sayede satır sayısı veri büyüdükçe artmaz.
Yazma kuyruğu, art arda yapılan işlemlerin son durumunun uzak veritabanına
iletilmesini sağlar. Değişiklikler diğer cihazlara **Realtime** ile anında ulaşır.
