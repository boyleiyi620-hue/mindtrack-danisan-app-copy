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
- GitHub'da `Production` ve `Preview` environment'ları var. `Production`
  ortamında `SUPABASE_URL` ve `SUPABASE_PUBLISHABLE_KEY` tanımlı; `Preview`
  ortamında henüz ayrı bir Supabase bağlantısı yok. Ayrı bir Supabase staging
  projesi bağlanana kadar `Preview` build'i bilerek başarısız olur. Bu dala ait
  Vercel Preview'ı production verisiyle kullanmayın.

## Health ve uptime

Derleme çıktısında `/health.json` bulunur. GitHub Actions bu adresi 15 dakikada
bir, üç denemeyle kontrol eder. Kontrol HTTPS, yönlendirme olmaması, HTTP 200 ve
`mindtrack-web` hizmeti için geçerli `status: ok` JSON yanıtı bekler; istek
10 saniyede zaman aşımına uğrar. İş akışı başarısız olduğunda GitHub Actions
başarısız çalıştırma bildirimi gönderir (depo bildirim ayarlarına bağlıdır).

Kurulum:

1. Doğrulanmış üretim alan adını belirle.
2. GitHub deposunda **Settings → Secrets and variables → Actions → Variables**
   altında `MINDTRACK_HEALTH_URL` değişkenini oluştur.
3. Değeri üretim adresinin `https://.../health.json` yolu olsun.
4. **Actions → Web uptime check → Run workflow** ile ilk kontrolü başlat.

`MINDTRACK_HEALTH_URL` henüz tanımlı değil; gerçek production alan adı
doğrulanmadan önizleme URL'si bu değişkene yazılmamalıdır. Ayrıca zamanlanmış
kontrolün çalışması için workflow dosyasının varsayılan `master` dalında
bulunması gerekir.

Yerel veya staging kontrolü:

```bash
node scripts/check_uptime.mjs https://staging.example.com/health.json 3
```

Bu kontrol web barındırıcısının statik health dosyasını doğrular; Supabase
erişilebilirliğini veya Realtime bağlantısını ölçmez. Supabase durumu için
uygulama içindeki senkronizasyon göstergesi ve sağlayıcı panellerindeki alarmlar
izlenmelidir. GitHub Actions kurtarma e-postası ayrıca göndermez; normale dönüş
takibi gerekiyorsa harici uptime servisi bağlanmalıdır.

## Kritik senkronizasyon hata bildirimi

Uygulama üç kez başarısız olan senkronizasyonu `client_error_events` tablosuna
kaydedip `critical-error-alert` Edge Function'ını çağırır. Function, oturum
JWT'sini doğrular, olayı sunucu tarafında bulur ve webhook'a HTTPS ile yalnızca
hata kategorisi, uygulama sürümü ve zamanı yollar. Klinik kayıt, hata mesajı,
kullanıcı kimliği ve kurum kimliği webhook'a gönderilmez. Aynı kayıt için
eşzamanlı tekrar bildirimini önleyen claim alanları bulunur.

Her Supabase ortamında migration'ları uygulayıp function'ı deploy et:

```bash
supabase db push --project-ref <project-ref>
supabase functions deploy critical-error-alert --project-ref <project-ref>
supabase secrets set MINDTRACK_CRITICAL_ALERT_WEBHOOK='https://<trusted-webhook>' --project-ref <project-ref>
```

Webhook URL'si yalnızca güvenilir bir HTTPS uç noktası olmalıdır. Ayar yoksa
function bildirim göndermez; hata olayı Supabase'de kalır. Webhook geçici hata
verirse uygulama function'ı üç kez yeniden çağırır; claim serbest bırakılır ve
olay sonraki çağrıda yeniden denenebilir. Supabase function secret'ı ve webhook
ayrı staging/production projelerinde ayrı tanımlanmalıdır. Function ayrıca
Supabase runtime'ının `SUPABASE_SECRET_KEYS` içindeki `default` secret key'ine
ihtiyaç duyar; dashboard'da bu anahtarın etkin olduğunu doğrula.

## Limit ve alarm kontrol listesi

- Supabase database, Storage, bandwidth ve Auth e-posta kullanım alarmı açılır.
- Vercel build, function ve bandwidth limitleri izlenir.
- `client_error_events` içindeki `critical` ve çözülmemiş hatalar webhook
  bildirimleriyle izlenir; başarısız bildirimler ayrıca günlük kontrol edilir.
- Production deploy öncesi staging health kontrolü ve Flutter CI başarılı
  olmalıdır.

## Dış sistem bağımlılıkları

Bu kontroller repo içinde doğrulanabilir; ancak production ve ayrı staging
Supabase projeleri, GitHub environment değerleri, güvenli Vercel Preview ayarı,
özel SMTP, Supabase PITR, GitHub depo değişkeni ve sağlayıcı kullanım alarmları
yönetim panellerinde etkinleştirilmeden Aşama 2 tamamlanmış sayılmaz.
