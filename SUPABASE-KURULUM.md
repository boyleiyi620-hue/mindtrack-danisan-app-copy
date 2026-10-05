# MindTrack — Supabase Kurulum Rehberi

> ## ⚠️ Temel kurulum tamamlandı; kayıt bazlı geçiş kademeli ilerliyor
>
> Proje oluşturuldu. Canlı projede temel migration'lar mevcut; kayıt bazlı klinik veri
> tablosu mevcut JSON yapısını bozmadan kademeli olarak devreye alınmaktadır.
>
> | | |
> | --- | --- |
> | Proje adı | `mindtrack` |
> | Project ref | `aqswdmhwqhrsempoiqfv` |
> | URL | `https://aqswdmhwqhrsempoiqfv.supabase.co` |
> | Bölge | `ap-northeast-2` (Seoul) |
> | Plan | Free |
> | Migration | Dosyalar aşağıdaki sırayla uygulanmalı |
>
> **Kalan işler:** Migration dosyalarını sırayla çalıştırın; ardından e-posta doğrulaması için SMTP kurun.
> Bu yapılmadan yeni kullanıcı kaydolamaz.
>
> Bu dokümanın kalanı, projeyi sıfırdan kuranlar veya başka bir ortama
> taşımak isteyenler içindir.

Uygulama Firebase'den tamamen Supabase'e taşındı. Artık hiçbir Firebase projesi,
`firebase_options.dart` veya `firestore.rules` dosyası gerekmiyor.

Bu rehber, **ücretsiz (Free) plan** için hazırlanmıştır. Ücretli plana geçiş
gerektiğinde tek yapılması gereken, projeyi Free'dan Pro'ya yükseltmektir;
uygulama kodunda değişiklik gerekmez.

---

## 0) Kısa yol (5 adım)

1. <https://supabase.com/dashboard> → **New project** ile ücretsiz proje oluşturun.
2. **SQL Editor**'de `supabase/migrations/*.sql` dosyalarını sırayla çalıştırın.
3. **Authentication → Providers → Email**'de kayıt açık olduğunu doğrulayın.
4. **Project Settings → API**'den `Project URL` ve `anon` anahtarını alın.
5. `SUPABASE_URL` ve `SUPABASE_PUBLISHABLE_KEY` ile uygulamayı derleyin.

Detaylar aşağıda.

---

## 1) Proje oluşturma (ücretsiz)

<https://supabase.com/dashboard> → **New project**

| Alan | Değer |
| --- | --- |
| Name | `mindtrack` (kendi adınızı da yazabilirsiniz) |
| Database password | Güçlü bir parola. **Bu parolayı kaybederseniz veritabanına erişemezsiniz.** Bir parola yöneticisine kaydedin. |
| Region | **Europe (Frankfurt)** — Türkiye'ye en yakın bölge, gecik en düşük olur. |
| Plan | **Free** |

> **Bölge seçimi geri alınamaz.** Veritabanı fiziksel olarak seçtiğiniz bölgede
> durur ve sonradan taşınamaz. Frankfurt Türkiye için doğru seçimdir.
>
> ⚠️ **Mevcut proje `ap-northeast-2` (Seoul) bölgesindedir** — 28 Eylül'de
> oluşturulmuştur. Bunu bilerek kullanmaya devam edebilirsiniz; Supabase'nin
> CDN ve bağlantı havuzu bu mesafeyi büyük ölçüde telafi eder. Ancak sizden
> **Avrupa'ya** yakınlık önemliyse (ör. kurumsal kullanıcılar, düşük gecik beklentisi)
> bölgeyi değiştirmek için projeyi silip Frankfurt'ta yeniden oluşturmanız gerekir.
> Free planda aynı anda en fazla 2 proje tutulabilir; silme sonrası yeniden
> oluşturmak limiti ihlal etmez, ancak projedeki tüm veriler silinir.
> **Bu kurulumda veri olmadığı için (tüm tablolar boş) taşımak şu an zararsızdır.**

Oluşturma birkaç dakika sürer. Kurulum bitince proje "ACTIVE" durumuna geçer.

### Ücretsiz plan limitleri

| Kaynak | Free plan |
| --- | --- |
| Aktif proje sayısı | 2 |
| Veritabanı boyutu | 500 MB |
| Dosya depolama | 1 GB |
| Aylık aktif kullanıcı | 50.000 |
| Auth kullanıcı sayısı | sınırsız |
| Realtime mesajlaşma | sınırlı (mesaj/saniye) |

Bu limitler Supabase tarafından zaman zaman güncelleniyor. Güncel değerleri
**<https://supabase.com/pricing>** adresinden teyit etmenizde fayda var.

> ⚠️ **Önemli:** Ücretsiz projeler **7 gün hareketsiz kaldıklarında duraklatılır**
> (pause). Uygulamayı kullanmadığınız günlerde veritabanı durur. Kullanmaya
> başladığınızda panelden **Restore** ile birkaç dakika içinde ayağa kalkar.
> Yoğun kullanımda bu duraklamayı önlemek için ileride Pro plana geçmek gerekir.

### Bu uygulamanın limitlere göre yeri

Uygulama mimisi limitler için bilinçli olarak tasarlandı:

- Psikologun **tüm klinik kaydı** `psychologist_state` tablosunda **tek bir jsonb
  satırı** olarak tutulur — satır sayısı artmaz, boyut sadece veriyle orantılı büyür.
- **PDF'ler veritabanına gömülmez**, Supabase Storage'a yüklenir. 500 MB'lık
  veritabanı limiti bu sayede dakikalarca dolmaz.
- Uygulama PDF yüklemesinde zaten 2 MB dosya sınırı uygular; Free planın
  dosya başına sınırının çok altındadır.

---

## 2) Şemayı kurma (migration)

Migration dosyaları hazır ve **sırayla** çalıştırılmalıdır:

| Dosya | İçerik |
| --- | --- |
| `supabase/migrations/20260929120000_mindtrack_init.sql` | Tablolar, indeksler, RLS politikaları, sütun bazlı yetkiler |
| `supabase/migrations/20260929120100_mindtrack_functions.sql` | RPC fonksiyonları, PDF depolama kovası, realtime yayın |
| `supabase/migrations/20260929133000_appointment_workflow.sql` | Danışan randevu talebi, psikolog onayı/reddi ve iki taraflı durum senkronizasyonu |
| `supabase/migrations/20261005160000_psychologist_records.sql` | Klinik kayıtların ayrı satırlar ve RLS ile kademeli taşınacağı temel tablo |
| `supabase/migrations/20261005170000_organizations_memberships.sql` | Klinik tenant'ı, üyelikler ve `admin` / `psychologist` / `assistant` rolleri |

### Yöntem A — SQL Editor (CLI kurmanız gerekmez, önerilir)

1. Dashboard → **SQL Editor** → **New query**
2. `20260929120000_mindtrack_init.sql` içeriğinin tamamını yapıştırın → **Run**
3. Sonuç `Success` dönüyorsa yeni bir sorgu açıp
   `20260929120100_mindtrack_functions.sql` içeriğini yapıştırın → **Run**
4. `20260929133000_appointment_workflow.sql` içeriğinin tamamını yapıştırın → **Run**
5. `20261005160000_psychologist_records.sql` içeriğinin tamamını yapıştırın → **Run**
6. `20261005170000_organizations_memberships.sql` içeriğinin tamamını yapıştırın → **Run**

Oluşturulanlar:

- **Tablolar:** `psychologist_state`, `patients`, `pairing_codes`,
  `appointments`, `tasks`, `homework`, `psychologist_records`
- **Depolama kovası:** `mindtrack-pdfs` (özel, herkese kapalı)
- **Fonksiyonlar:** `claim_pairing_code`, `cancel_appointment`,
  `delete_own_appointment`, `submit_task`, `submit_homework`,
  `create_appointment_request`, `approve_appointment_request`,
  `update_shared_appointment`

### Yöntem B — Supabase CLI

```bash
npm install -g supabase        # veya: brew install supabase
supabase login                 # tarayıcıda tarayıcı ile giriş
supabase link --project-ref <PROJE-REF>

# Proje-REF, dashboard > Project Settings > API > Project ref altında
supabase db push
```

### Yöntem C — psql

```bash
psql "postgresql://postgres.<PROJE-REF>:<PAROLA>@aws-0-<BÖLGE>.pooler.supabase.com:5432/postgres" \
  -f supabase/migrations/20260929120000_mindtrack_init.sql \
  -f supabase/migrations/20260929120100_mindtrack_functions.sql
```

### Doğrulama

SQL Editor'da şu sorguyu çalıştırın:

```sql
select table_name from information_schema.tables
 where table_schema = 'public' order by table_name;
```

Altı tablo (`appointments`, `homework`, `pairing_codes`, `patients`,
`psychologist_state`, `tasks`) listelenmelidir.

**Bu proje için doğrulandı (29.09.2026):** Altı tablo oluşturuldu, RLS politikaları
ve 5 RPC hazır, `mindtrack-pdfs` kovası mevcut. Uçtan uca test yapıldı:
oturum açma → durum yazma/okuma → Storage'a PDF yükleme/indirme → eşleşme kodu
üretme/sahiplenme (tek kullanımlık doğrulaması dahil) → **farklı kullanıcının
veriyi görememesi**. Test verileri temizlendi.

---

## 3) Authentication ayarları

Dashboard → **Authentication → Sign In / Providers → Email**

- **Enable Email Provider**: açık olmalı (varsayılan olarak açıktır).
- **Confirm email**: geliştirme sırasında `false` bırakabilirsiniz; kullanıcı kayıt
  olurken e-posta doğrulaması beklemez. Canlıya almadan önce `true` yapmanız önerilir.

> **Email confirmation = false iken** kullanıcı kayıt olduğu anda oturum açılır ve
> `auth.users` tablosuna yazılır. `false` bırakmak yalnızca test içindir;
> gerçek kullanıcı verisi almadan önce mutlaka açın.

Diğer sağlayıcıların (Google, Apple vb.) kapalı kalması sorun değildir; uygulama
yalnızca e-posta/şifre ile çalışır.

### 3.1 E-posta doğrulaması (SMTP) — KRİTİK

Bu adım yapılmadan **yeni kullanıcılar kaydolamaz.**

Projenin şu anda `mailer_autoconfirm = false` (e-posta doğrulaması **açık**) ve
`smtp_host = null` (özel SMTP **yok**) durumunda. Yani:

1. Kullanıcı kaydolur → Supabase "doğrulama e-postası gönderdim" der.
2. E-posta **gönderilmez**, çünkü ücretsiz plandaki dahili SMTP yalnızca proje
   ekibinize ait adreslere ve saatte ~2-3 e-postaya izin verir.
3. Kullanıcı doğrulama linkini alamaz → **giriş yapamaz**.

Ücretsiz çözümler (dashboard → **Project Settings → Auth → SMTP**):

| Servis | Ücretsiz kota | Not |
| --- | --- | --- |
| **Resend** | 3.000 e-posta/ay | En kolay kurulum, önerilen |
| **Brevo (Sendinblue)** | 300 e-posta/gün | Ücretsiz plan mevcut |
| Supabase dahili | ~2 e-posta/saat, sadece ekip | Üretim için yeterli **değil** |

SMTP ayarlanınca e-posta doğrulaması açık kalabilir — **öyle de yapılması
tavsiye edilir**, çünkü sağlık verisi işleyen bir uygulamada hesabın gerçek bir
e-posta adresine ait olduğunu doğrulamak önemlidir.

> **Geçici çözüm (yalnızca test için):** Dashboard → Authentication → Providers →
> Email → **Confirm email** → `false` yapın. Böylece kullanıcı kayıt olur olmaz
> oturum açılır, e-posta gerekmez. Canlıya almadan önce mutlaka `true` yapıp
> SMTP bağlayın.
>
> Not: E-posta doğrulaması kapalıyken bile bir kullanıcı **veri göremez** — veri
> erişimi yalnızca psikologun verdiği 8 karakterlik eşleşme koduyla açılır.
> Yani bu ayar veri sızıntısı yaratmaz; yalnızca "bu e-posta gerçekten sana mı
> ait" sorusunu cevaplamaz.

**Parola politikası:** Minimum parola uzunluğu `8` olarak ayarlandı
(proje varsayılanı 6 idi).

---

## 4) API anahtarlarını alma

Dashboard → **Project Settings → API**

| Değer | Değer |
| --- | --- |
| **Project URL** | `https://aqswdmhwqhrsempoiqfv.supabase.co` |
| **Publishable key** | `sb_publishable_ugqE_bZ_IyNedJMk1I_saA_-eMtQAjE` |

**Kopyala-yapıştır:**

```bash
export SUPABASE_URL="https://aqswdmhwqhrsempoiqfv.supabase.co"
export SUPABASE_PUBLISHABLE_KEY="sb_publishable_ugqE_bZ_IyNedJMk1I_saA_-eMtQAjE"
```

> Publishable (`sb_publishable_…`) anahtarı istemci uygulamalarda kullanılmak
> üzere tasarlanmıştır; kaynak koda yazılabilir. Yine de bu proje
> `--dart-define` yaklaşımını kullanıyor, böylece birden fazla ortam
> (üretim/deneme) tek koddan derlenebiliyor.
>
> Panelde hâlâ `anon public` (eski `eyJ…` JWT) anahtarı da görünecektir — ikisi
> de çalışır. Hangisini kullandığınız önemli değil, ama tutarlılık için tek
> birini seçip her yerde onu kullanın.

> 🔒 **`service_role` / `secret` anahtarını ASLA derlemeyin ve istemciye
> vermeyin.** Bu anahtar RLS'i atlar; kaynak koda ya da mobilAPK'ya gömülürse
> tüm veritabanını okuyup yazabilen biri elde etmiş olursunuz. Bu projede
> hiçbir yerde kullanılmıyor.

`anon` anahtarı güvenlik açısından tek başına bir şey ifade etmez — tüm
veri erişimi RLS politikalarıyla filtrelenir. Uygulamanın RLS'i migration
dosyasında tanımlıdır.

---

## 5) Uygulamayı derleme

Anahtar ve URL **derleme zamanında** verilir; kaynak koda gömülmez.

### Web (psikolog + danışan)

```bash
flutter pub get

export SUPABASE_URL="https://aqswdmhwqhrsempoiqfv.supabase.co"
export SUPABASE_PUBLISHABLE_KEY="sb_publishable_ugqE_bZ_IyNedJMk1I_saA_-eMtQAjE"

./scripts/build_web.sh
```

Çıktılar:
- `build/psych` → psikolog uygulaması
- `build/client` → danışan uygulaması

Bu klasörler herhangi bir statik barındırma servisine (Netlify, Vercel,
Cloudflare Pages, kendi sunucunuz) yüklenebilir. **Firebase Hosting'e gerek yoktur.**

### Android APK

```bash
flutter pub get

flutter build apk --release \
  --flavor psychologist \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_PUBLISHABLE_KEY="$SUPABASE_PUBLISHABLE_KEY"

flutter build apk --release \
  --flavor client \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_PUBLISHABLE_KEY="$SUPABASE_PUBLISHABLE_KEY"
```

Çıktılar:
- `build/app/outputs/flutter-apk/psychologist-release.apk`
- `build/app/outputs/flutter-apk/client-release.apk`

### Tanılama

`--dart-define` verilmeden derlenen uygulama **açılır ama giriş ekranı kalır**;
Supabase bağlantısı kurulmadığı için sessizce devre dışıdır. Bu, anahtarı
unutmanızı kolaylaştırmamak için bilinçlidir. Derleme betiğinde
`SUPABASE_URL tanımlı olmalı` hatasıyla durur — bu hatayı görüyorsanız
tanım eksiktir.

---

## 6) Uygulamayı denemek

1. **Psikolog** olarak kayıt olun (uygulama → Kayıt).
2. Ayarlar/profil ekranından bir **eşleşme kodu** üretin (8 karakter).
3. Farklı bir cihazda veya **tarayıcının gizli penceresinde** danışan olarak
   kayıt olun ve kodu girin.
4. Psikolog tarafında danışan listesi, randevu ve görevlerin canlı olarak
   güncellendiğini görürsünüz. Eşleşme, atama, iptal ve yanıtlar **anında** aktarılır.

Realtime yayının çalıştığını doğrulamak için: iki tarayıcı penceresini yan yana
açıp birinde randevu oluşturduğunuzda diğerinde kendiliğinden belirmelidir.

---

## 7) Sorun giderme

| Belirti | Olası neden / çözüm |
| --- | --- |
| Giriş ekranında "Sunucuya ulaşılamadı" | `SUPABASE_URL` / `SUPABASE_PUBLISHABLE_KEY` derlenmemiş. Proje Settings → API'deki değerlerle yeniden derleyin. |
| `relation "public.xxx" does not exist` | Migration çalıştırılmamış. Bölüm 2'yi uygulayın. |
| `new row violates row-level security policy` | Migration'daki RLS politikaları eksik veya yanlış proje bağlı. Dosyaları **bu projeye** çalıştırdığınızdan emin olun. |
| Realtime güncelleme gelmiyor | Dashboard → **Database → Publications** bölümünde `supabase_realtime` yayınının aktif olduğunu ve tabloların ekli olduğunu kontrol edin (migration ekler). |
| PDF yüklenmiyor / "Bucket not found" | `mindtrack-pdfs` kovası oluşmamış. Migration'ların **ikincisi de** çalıştırılmış olmalı. |
| Proje "PAUSED" | 7 gün hareketsiz kalmış. Dashboard'da **Restore**'a basın. |
| Kayıt olunca "Email not confirmed" | Authentication → Providers → Email → Confirm email'i kapatın (geliştirme) veya kullanıcıya doğrulama bağlantısı gönderin. |

---

## 8) Güvenlik notları

- Tüm tablolarda **RLS açık**; her politika `auth.uid()` ile eşleşme zorunlu kılar.
- Firestore döneminde oturumu olan herkesin tüm eşleşme kodlarını
  listeleyebilmesine izin veren kural **bilinçli olarak daraltıldı**: eşleşme
  kodu artık yalnızca `claim_pairing_code` RPC'si üzerinden, atomik bir
  işlem içinde okunup sahiplenilir.
- Firestore'un `affectedKeys().hasOnly([...])` ile yaptığı sütun kısıtlaması
  Postgres'te RLS ile mümkün olmadığından karşılığı **sütun bazlı `GRANT`** ve
  **`SECURITY DEFINER` RPC'ler** ile sağlandı. Danışan, kendi profilinin
  yalnızca `display_name / first_name / last_name / email / consented`
  alanlarını yazabilir; randevu ve görev yanıtlarını yalnızca sunucu tarafı
  fonksiyonlar günceller.
- Tüm `SECURITY DEFINER` fonksiyonlarda `search_path` sabitlenmiş ve
  `PUBLIC` erişimi kapatılmıştır (search_path ele geçirme riskine karşı).

---

## 9) Ücretli plana geçiş

Hazır olduğunuzda dashboard'dan **Upgrade to Pro** yeterlidir. Uygulama
kodunda, migration dosyalarında veya yapılandırmada değişiklik gerekmez —
plan yalnızca dashboard üzerinden yönetilir. Geçiş anında:

- Proje duraklatılmaz (duraklatma yalnızca Free planda olur).
- Limitler, 7 gün hareketsiz kalınca duraklatma kuralı ve ek eşzamanlı bağlantı
  sınırları kalkar.
- Faturalandırma için kart bilgisi istenir.

Eski veriler aynı projede kalır; yalnızca limitler yükselir.
