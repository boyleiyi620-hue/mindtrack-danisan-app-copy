# MindTrack erişilebilirlik ve yayın operasyonu

## Ortam ayrımı

- `master` push'u GitHub `Production` environment'ını seçer. Manuel build başka
  bir dalda başlatılırsa `Preview` environment'ı seçilir.
- Her environment'ta `SUPABASE_URL` değişkeni ve
  `SUPABASE_PUBLISHABLE_KEY` secret'ı ayrı tanımlanmalıdır. Build, biri eksikse
  durur; production bağlantısına sessiz geri dönüş yapmaz.
- `SUPABASE_PUBLISHABLE_KEY` istemciye gömülür ve public anahtar olmalıdır.
  `service_role` veya başka bir secret anahtar Flutter derlemesine kesinlikle
  verilmez.
- Şu anda GitHub'da `Production` ve `Preview` environment'ları var, ancak bu
  değerler ayarlı değil. Production build'i yeniden etkinleştirmek için
  `Production` değerleri eklenmeli; ayrı bir Supabase staging projesi kurulana
  kadar `Preview` build'i bilerek başarısız olur. Bu dala ait Vercel Preview'ı
  production verisiyle kullanmayın.

## Health ve uptime

Derleme çıktısında `/health.json` bulunur. GitHub Actions bu adresi 15 dakikada
bir, üç denemeyle kontrol eder. Kontrol HTTPS, yönlendirme olmaması, HTTP 200 ve
`mindtrack-web` hizmeti için geçerli `status: ok` JSON yanıtı bekler; istek
10 saniyede zaman aşımına uğrar. İş akışı başarısız olduğunda GitHub Actions
başarısız çalıştırma bildirimi gönderir (depo bildirim ayarlarına bağlıdır).

Kurulum:

1. GitHub deposunda **Settings → Secrets and variables → Actions → Variables**
   altında `MINDTRACK_HEALTH_URL` değişkenini oluştur.
2. Değeri üretim adresinin `https://.../health.json` yolu olsun.
3. **Actions → Web uptime check → Run workflow** ile ilk kontrolü başlat.

Yerel veya staging kontrolü:

```bash
node scripts/check_uptime.mjs https://staging.example.com/health.json 3
```

Bu kontrol web barındırıcısının statik health dosyasını doğrular; Supabase
erişilebilirliğini veya Realtime bağlantısını ölçmez. Supabase durumu için
uygulama içindeki senkronizasyon göstergesi ve sağlayıcı panellerindeki alarmlar
izlenmelidir. GitHub Actions kurtarma e-postası ayrıca göndermez; normale dönüş
takibi gerekiyorsa harici uptime servisi bağlanmalıdır.

## Limit ve alarm kontrol listesi

- Supabase database, Storage, bandwidth ve Auth e-posta kullanım alarmı açılır.
- Vercel build, function ve bandwidth limitleri izlenir.
- `client_error_events` içindeki `critical` ve çözülmemiş hatalar günlük
  kontrol edilir veya bir webhook/e-posta kanalına bağlanır.
- Production deploy öncesi staging health kontrolü ve Flutter CI başarılı
  olmalıdır.

## Dış sistem bağımlılıkları

Bu kontroller repo içinde doğrulanabilir; ancak production ve ayrı staging
Supabase projeleri, GitHub environment değerleri, güvenli Vercel Preview ayarı,
özel SMTP, Supabase PITR, GitHub depo değişkeni ve sağlayıcı kullanım alarmları
yönetim panellerinde etkinleştirilmeden Aşama 2 tamamlanmış sayılmaz.
