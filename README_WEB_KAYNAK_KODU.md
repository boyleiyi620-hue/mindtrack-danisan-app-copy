# MindTrack Web Uygulaması — Kaynak Kod Arşivi

Bu arşiv, MindTrack **psikolog** Web uygulamasının kaynaklarını ve üretim
yapılandırmasını içerir. Sunucu tarafı **Supabase** üzerine taşınmıştır; Firebase
Hosting'e gerek kalmamıştır.

> ⚠️ Eski Firebase adresi (`https://mindtrack-sync-2026-6bf9c.web.app/`) artık
> kullanılamaz. Firebase projesi kapatıldı; yayın için aşağıdaki adımları izleyin.

## İçerik

- `lib/`: Flutter Web uygulamasının Dart kaynakları
- `web/`: Web platformu yapılandırması
  - `index_psychologist.html` / `manifest_psychologist.json` — psikolog uygulaması
  - `index_client.html` / `manifest_client.json` — danışan uygulaması
- `supabase/migrations/`: Veritabanı şeması ve güvenlik politikaları
- `scripts/build_web.sh`: İki uygulamayı da derleyen betik
- `pubspec.yaml` ve `pubspec.lock`: Flutter bağımlılıkları

## Yeniden derleme

Supabase projesi kurulduktan sonra ([SUPABASE-KURULUM.md](SUPABASE-KURULUM.md)):

```bash
flutter pub get
export SUPABASE_URL="https://aqswdmhwqhrsempoiqfv.supabase.co"
export SUPABASE_PUBLISHABLE_KEY="sb_publishable_ugqE_bZ_IyNedJMk1I_saA_-eMtQAjE"
./scripts/build_web.sh
```

Çıktılar:

- `build/psych` — psikolog uygulaması
- `build/client` — danışan uygulaması

## Yayınlama

Bu klasörler tamamen statiktir; Firebase CLI'ye gerek yoktur. Herhangi bir
statik barındırma servisine yükleyebilirsiniz:

- Netlify / Vercel / Cloudflare Pages / GitHub Pages
- Kendi statik sunucunuz (nginx, Caddy vb.)

> ### § Zorunlu: SPA yönlendirme (rewrite)
>
> İki uygulama da Flutter SPA'sıdır. Barındırma, **tüm** adresleri
> `index.html` dosyasına yönlendirmelidir. Bu kural olmadan uygulama ana
> sayfada açılır ama derin bağlantılar (paylaşılan kod, eşleşme,
> herhangi bir `/{yol}`) **404** döner.
>
> Yönlendirme yapılmadan `curl -o /dev/null -w '%{http_code}' <site>/pairing`
> komutu `404`, kural varken `200` dönmelidir.
>
> | Servis | Ayar |
> | --- | --- |
> | Netlify | `netlify.toml` içinde `[[redirects]] from = "/*" to = "/index.html" status = 200` |
> | Vercel | `vercel.json` içinde `{"rewrites": [{"source": "/(.*)", "destination": "/index.html"}]}` |
> | Cloudflare Pages | `_redirects` dosyasına `/*  /index.html  200` |
> | nginx | `try_files $uri $uri/ /index.html;` |
>
> Not: Bu kural **asset** isteklerini de `index.html`'e yönlendirdiği için
> mevcut dosyalar (çöktü, `*.js`, `*.png`) zaten diskte oldukları için
> servis tarafından önce sunulur; statik dosya servisi yapan her barındır
> bunu varsayılan olarak yapar.

Yayımlama sırasında `SUPABASE_URL` ve `SUPABASE_PUBLISHABLE_KEY` **derleme
zamanında** verilmiş olmalıdır. Bu değerler olmadan derlenen çıktı açılır ancak
giriş yapılamaz. `sb_publishable_...` anahtarı istemci tarafında zaten
görünürdür ve tek başına erişim sağlamaz — tüm yetki
denetimini veritabanındaki RLS yapar.

## Senkronizasyon

Web ve psikolog Android uygulaması aynı Supabase projesini ve aynı kullanıcı
UUID'sini kullanır. Psikolog verileri `psychologist_state` tablosunda tek bir
jsonb satırı olarak tutulur; değişiklikler yazma kuyruğu ile uzak kayda
iletilir ve diğer cihazlara Realtime ile anında ulaşır.

## Güvenlik

- Kullanıcı parolaları arşive dahil değildir ve istemcide saklanmaz.
- `service_role` (secret) anahtarı kullanılmaz; istemciye verilmemelidir.
- Veri erişimi `supabase/migrations/` içindeki RLS politikalarıyla sınırlıdır.
