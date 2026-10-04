# MindTrack — Eksiklik Analizi ve Yapılacaklar Listesi

**Tarih:** 2026-10-04  
**Kapsam:** Flutter (psikolog + danışan web/Android uygulaması), Supabase (Postgres/Auth/Realtime/Storage), Vercel, GitHub Actions  
**Amaç:** Uygulamayı şirkete aylık kiralama modeliyle sunulabilir hale getirmek  
**Ödeme modeli:** IBAN (elle tahsilat) → uygulama içi ödeme/abonelik sistemi YOK

> Bu belge salt tespit ve planlama içindir. Hiçbir değişiklik yapılmamıştır.

---

## 0. Yönetici Özeti

Kod tabanı işlevsel ve olgun bir ilk sürüm: 57 Dart dosyası, ~24.900 satır, 10 Supabase migration, RLS politikaları yazılmış, gerçek zamanlı senkronizasyon ve testler mevcut. Mimari temel sağlam.

Ancak **ticari kiralama için 3 kritik blokaj** var:
1. Android release APK'sı internetsiz çalışıyor (izin eksik) ve debug key ile imzalanıyor.
2. Tüm klinik veri (SOAP notları, tanı kodları, risk planları) cihazda **şifresiz düz metin** saklanıyor.
3. **Lisans/abonelik/kiracı yönetimi hiç yok** — IBAN ile tahsilat için manuel lisans sistemi kurulması gerekiyor.

Ayrıca KVKK uyumluğu açısından ciddi boşluklar var: aydınlatma metni yok, hesap silme yok, denetim kaydı yok, kayıtlı onay metni **yanlış** (verinin bulutta da tutulduğünü söylüyor).

**Tahmini iş yükü:** Blokajlar ~3-5 gün, güvenlik/KVKK ~2 hafta, lisans sistemi ~1 hafta, altyapı taşıma ~3 gün, hukuki dokümanlar (senin tarafında hukukçuyla) paralel.

---

## 🔴 BÖLÜM 1 — KRİTİK BLOKAJLAR (Yayına Çıkamaz)

### 1.1 Android release APK'sı İnternet İzni Almıyor
- **Dosya:** `android/app/src/main/AndroidManifest.xml`
- **Sorun:** Ana manifest'te **hiç `uses-permission` yok**. `INTERNET` izni sadece `src/debug/` ve `src/profile/` manifestlerinde var (Flutter şablonu varsayılanı).
- **Etki:** `flutter build apk --release` ile üretilen APK Supabase'e hiç ulaşamaz. Veri senkronizasyonu, Google girişi, OTP girişi tamamen çalışmaz. Uygulama sessizce offline çalışır ve kullanıcı veri kaybı yaşar.
- **Yapılacak:** `<application>` öncesine `<uses-permission android:name="android.permission.INTERNET"/>` ekle. Gerekirse `ACCESS_NETWORK_STATE` de ekle.

### 1.2 Release Derlemesi Debug Key ile İmzalanıyor
- **Dosya:** `android/app/build.gradle.kts:55`
- **Sorun:** `signingConfig = signingConfigs.getByName("debug")`
- **Etki:** APK üretilir ama: (a) Play Store'a yüklenemez, (b) kullanıcıya dağıtılan APK'yı yeni sürümle **güncelleyemezsin** (farklı imza = farklı uygulama), (c) debug keystore bilinir ve herkesin üretebilmesi mümkün — güvenlik riski.
- **Yapılacak:**
  - Production keystore oluştur (`keytool -genkey`), parolasını güvenli yerde sakla, **asla git'e koyma**.
  - `android/key.properties` + keystore dosyası üret (git'e ekle `.gitignore`).
  - `build.gradle.kts`'te release `signingConfigs.release` kullansın; keystore yoksa release derlemeyi **hata** ile durdursun.
  - İki flavor (`client`, `psychologist`) için ayrı keystore düşün.

### 1.3 KVKK Onay Metni Yanlış Bilgi Veriyor
- **Dosya:** `lib/screens/auth/auth_screen.dart:434`
- **Sorun:** Onay kutusu **"Verilerim yalnızca bu cihazda saklanır"** diyor. Oysa tüm veri Supabase'e (bulutta) yazılıyor (`_saveRemote`), cihazlar arası senkronize ediliyor.
- **Etki:** Kullanıcıya yanlış bilgi verilmesi = KVKK ihlali riski. Veri işleme yerini (yurt içi/yurt dışı) doğru bildirmek zorunlu.
- **Yapılacak:** Metni gerçeği yansıtacak şekilde değiştir + tıklanabilir tam metin.

### 1.4 Lisans / Abonelik Sistemi Hiç Yok
IBAN ile tahsilat yapılacağı için, uygulama içi ödeme olmayacak — ama **lisans kontrolü elle yönetilmek zorunda**. Şu anda hiçbir kısıt yok:
- Süre kavramı yok (başlangıç/bitiş tarihi).
- Plan/ paket kavramı yok.
- Cihaz sınırı yok — kullanıcı 10 cihazda kullanabilir.
- İptal / askıya alma / yenileme mekanizması yok.
- Yönetici paneli yok.
- **Sonuç:** Müşteri ödeme yapmasa bile süresiz kullanmaya devam eder. Gelir güvenliği yok.

**Yapılacak (Bölüm 3'te detaylı):**

### 1.5 Tek Kullanıcılı Mimari — Çok Kiracı (Multi-tenant) Yapı Yok
- **Dosya:** `lib/models/user_account.dart:8` — `clinic` sadece bir metin alanı.
- **Sorun:** Her hesap tek bir psikolog. Bir klinik/kurum müşterisi olarak satış yapacaksan, kurum altında birden fazla psikolog + asistan + yönetici olmalı.
- **Etki:** "Şirkete aylık kiralamak" hedefi için her müşteri ayrı bireysel hesap olarak gelirse ölçeklenmez; kurum müşterisi alınamaz.
- **Yapılacak:** `organizations` (kiracı) + `memberships` (rol) tabloları ve ekranı.

---

## 🔴 BÖLÜM 2 — GÜVENLİK VE VERİ KORUMASI

Bu uygulama **sağlık verisi** işliyor (tanı kodları, SOAP notları, risk/güvenlik planları, doğum tarihi, terapi içeriği). KVKK'ya göre bu **özel nitelikli kişisel veri**dir ve en yüksek koruma seviyesini gerektirir.

### 2.1 Cihazda Veri Şifresiz Saklanıyor — KRİTİK
- **Dosya:** `lib/data/data_store.dart:57, 143`, `lib/data/account_store.dart`
- **Sorun:** Tüm klinik veri (`AppData`) `SharedPreferences`'a **şifresiz JSON** olarak yazılıyor. Web'de bu `localStorage` = tarayıcıda düz metin.
- **Etki:** Cihaz kaybolur/çalınır veya birinin tarayıcısına erişirse tüm danışan kayıtları açık okunur. Web'de XSS açığı = tüm veri sızıntısı.
- **Yapılacak:**
  - Cihazda `flutter_secure_storage` veya AES-256-GCM ile şifreli depolama (anahtar Keystore/Keychain'de).
  - Web için: veriyi `IndexedDB` + WebCrypto ile şifreli sakla, anahtarı sunucudan (Supabase) çek ve oturumla bağla.
  - Alternatif/ek: cihazdaki hassas alanların (SOAP, tanı) maskelenmesi.

### 2.2 Şifre Hashleme Çok Zayıf
- **Dosya:** `lib/data/crypto_utils.dart:14` — `hashPassword = sha256(tuz + şifre)`
- **Sorun:** Tek tur SHA-256, maliyet faktörü yok. Modern kırılma (hashcat) saniyeler içinde milyonlarca deneme yapar. PIN hash'i de aynı yöntemle.
- **Etki:** Yerel `pwdHash`/`pinHash` değişiklik hâlinde ele geçerse kolayca kırılır. Şifreler `123456` gibi basitse saniyeler içinde çözülür.
- **Yapılacak:** Argon2id veya bcrypt (yan tuz + yüksek iterasyon). `crypto` paketi yetmez; `cryptography` veya `argon2` paketi gerekli.
- **Not:** Asıl yetkilendirme Supabase Auth'ta; yerel hash sadece önbellek. Yine de düzeltilmeli.

### 2.3 Web Güvenlik Başlıkları (Security Headers) Yok
- **Dosya:** `scripts/vercel.json`
- **Sorun:** Sadece `Cache-Control` başlıkları var. Şunlar yok:
  - `Content-Security-Policy` (XSS koruması)
  - `Strict-Transport-Security` (HSTS)
  - `X-Frame-Options` / `frame-ancestors` (clickjacking)
  - `X-Content-Type-Options`, `Referrer-Policy`
- **Yapılacak:** Vercel'e CSP + HSTS + diğer başlıklar ekle.

### 2.4 KVKK Denetim Kaydı (Audit Log) Yok
- **Sorun:** Kim neye ne zaman baktı/değiştirdi kaydı tutulmuyor. KVKK md. 12 "veri işleme faaliyetinin kaydını tutma" yükümlülüğü.
- **Yapılacak:** `audit_log` tablosu + RPC: giriş/çıkış, danışan görüntüleme, kayıt oluşturma/değiştirme/silme olayları. Psikolog kendi panelinden son hareketleri görebilmeli.

### 2.5 "Hesabımı Sil" / Veri Silme Yok — KVKK md. 11 Zorunlu
- **Dosya:** `lib/screens/tabs/settings_tab.dart` — hiçbir silme fonksiyonu yok
- **Sorun:** Kullanıcı verilerini toplamak/taşımak/çıkarmak için geri alma hakkı var ama **silme talebi hakkı da** var ve uygulanmıyor. Ayrıca abonelik iptali sonrası veri saklama süresi belirsiz.
- **Yapılacak:**
  - Hesap silme akışı: uyarı → onay → verilerin uzak + yerel tamamen yok edilmesi.
  - KVKK md. 7 gereği "silme/yok sayma" talebi için altyapı.
  - Saklama süresi sonunda otomatik silme.

### 2.6 Onam (Consent) Kaydı ve Sürüm Takibi Yok
- **Sorun:** `patients.consented` boolean alanı var ama: onay metni sürümü yok, onay zaman damgası yok, onaylayan kişi/IP yok, metin değişince yeniden onay istenmiyor.
- **Yapılacak:** `consents` tablosu: metin sürümü, hash, zaman, IP, kullanıcı, versiyon geçmişi.

### 2.7 API Hız Limiti / Kaba Kuvvet Koruması Yok
- **Sorun:** Giriş denemelerinde uygulama tarafında hız sınırı yok. Supabase Auth'un kendi korumasına bağlı.
- **Yapılacak:** Vercel WAF rate limit + uygulamada deneme sayacı/gecikmeli kilit. OTP gönderme spam koruması kritik.

### 2.8 Google OAuth Yönlendirme Doğrulaması Yok
- **Sorun:** `signInWithGoogle` çalışıyor ama redirect URL'leri panelden elle ayarlanıyor. Yeni domain'e (şirket domaini) geçerken unutulursa giriş bozulur.
- **Yapılacak:** Alan adı geçişinde redirect URL listesini güncelleme prosedürü + dokümantasyon.

### 2.9 Oturum Yönetimi Yok
- **Sorun:** "Açık kalan cihazları gör ve kapat" özelliği yok. Oturum süresi kısıtı yok.
- **Yapılacak:** Cihaz/oturum listesi, uzaktan oturum sonlandırma, hesap sahibi değişikliği.

---

## 🟠 BÖLÜM 3 — LİSANS / ABONELİK SİSTEMİ (IBAN Modeli İçin)

IBAN ile tahsilat yapılacağı için uygulamada ödeme alınmayacak. Bunun yerine **elle yönetilen bir lisans sistemi** kurulmalı. Müşteri IBAN'a para yatıracak, sen de sistemden lisansını aç/uzat/kapatacaksın.

### 3.1 Veritabanı Tarafı — Eklenecek Tablolar
```sql
organizations (id, name, tax_no, plan, status, created_at)      -- kiracı şirket/klinik
licenses (
  id, organization_id, psychologist_user_id,
  plan,                    -- 'solo' | 'clinic' | 'enterprise'
  starts_at, ends_at,      -- abonelik dönemi
  status,                  -- 'active' | 'expired' | 'suspended' | 'cancelled'
  max_devices,             -- cihaz sınırı
  grace_days,              -- ödeme gecikmesi toleransı (örn. 7 gün)
  notes, created_at, updated_at
)
license_devices (
  id, license_id, device_id, device_name, platform,
  first_seen_at, last_seen_at
)
payment_records (          -- IBAN tahsilat kaydı (elle girilir)
  id, organization_id, amount, currency, period_start, period_end,
  paid_at, reference, note, created_at
)
```

### 3.2 Lisans Doğrulama Akışı
- Uygulama açılışta lisans durumunu sunucudan çeker (önbellekli, çevrimdışı toleranslı).
- **Aktif lisans** → tam kullanım.
- **Süresi dolmuş + grace period** → tam kullanım, uyarı göster.
- **Süresi dolmuş (grace de bitmiş)** → **salt okunur moda düşer** (veri görüntülenir, düzenlenemez), veri kaybı olmaz, açık bir uyarı gösterilir.
- **Askıya alınmış / iptal** → giriş engellenir (veri export seçeneği sunulur).
- Cihaz sayısı aşılırsa yeni cihazda uyarı ve ek cihaz talebi.

### 3.3 Yönetici Paneli
- Müşteri (klinik) ekleme, lisans atama, uzatma, askıya alma, iptal.
- Ödeme kaydı girme (IBAN tahsilatı sonrası elle).
- Kullanım raporu: aktif kiracı sayısı, cihaz sayısı, son girişler, süresi dolanlar.
- **Bu ayrı bir uygulama** (veya `/admin` web sayfası) olmalı — müşterilere görünmemeli.

### 3.4 Şirket Adına Ölçeklenebilirlik
- **Çoklu kullanıcı / rol:** Yönetici (klinik), psikolog, asistan. Danışan listesi rol bazlı paylaşılsın (asistan tüm notları görmemeli).
- **Marka:** Uygulama adı, logosu, rengi kiracıya göre değiştirilebilir (white-label) — ayrıca ücretli paket olarak sunulabilir.
- **Toplu yönetim:** Toplu form gönderimi, kurum raporları, danışan devri (terapist değişikliğinde veri aktarımı).

---

## 🟠 BÖLÜM 4 — ALTYAPI TAŞIMA VE PROFESYONELLEŞTİRME

### 4.1 Supabase
- [ ] **Pro plana geç** (ücretsiz plan 500MB DB, 1GB dosya — çok sayıda müşteriyle yetersiz).
- [ ] **Prod / Staging ayrımı:** Şu an tek proje (`aqswdmhwqhrsempoiqfv`) hem geliştirme hem canlı. Geliştirici yanlışlıkla prod verisini bozabilir. Ayrı projeler oluştur.
- [ ] **Özel alan adı** bağla (API endpoint'i kendi domainin üzerinden).
- [ ] **Yedekleme:** Otomatik günlük yedek + PITR (point-in-time recovery) aç. Geri yükleme provası yap (yedeğin işe yaradığını kanıtla).
- [ ] **SMTP:** Supabase'in varsayılan e-posta servisi çok düşük limitli (saatte ~2-4 e-posta). OTP giriş kullanılıyorsa **kendi SMTP sağlayıcına** (Resend, SendGrid, Postmark) geç. **Bu, OTP giriş açısından blokajdır.**
- [ ] **Auth ayarları:** E-posta doğrulamasını `true` yap (şu an `false` — `supabase/config.toml`), rate limit'leri sıkılaştır, şifre politikası tanımla (min 8 karakter, karmaşıklık).
- [ ] **API anahtarı rotasyonu** ve anahtarın GitHub Secrets'a taşınması.
- [ ] **Realtime** kanal sayısı ve mesaj limitleri izlenmeli.

### 4.2 Vercel
- [ ] **Pro plana geç** (ücretsiz planın bandwidth/dayanıklılık limitleri ticari kullanımda riskli).
- [ ] **Özel alan adı** bağla + otomatik TLS.
- [ ] **Ortam ayrımı:** Production ve Preview dağıtımları ayrı Supabase projesine bağlansın.
- [ ] **Rate limiting / WAF** aç.
- [ ] **Analytics / log** ve uptime izleme.

### 4.3 GitHub Actions / CI-CD
- **Dosya:** `.github/workflows/build-web.yml`
- [ ] Anahtar şu an workflow'a **düz yazılmış** → GitHub Secrets'a taşı.
- [ ] **PR'larda kalite kapısı yok.** Şu an sadece `master`'a push olunca build + commit ediliyor. PR'da `flutter analyze` + `flutter test` çalışsın, başarısızsa merge engellensin.
- [ ] **Branch protection** aç (`master` korunsun).
- [ ] **CI'ın doğrudan `git push` yapması** riskli — release tag + GitHub Releases ile dağıtım yapılmalı.
- [ ] **Sürümleme:** Versiyonlama (`1.0.0` tek sabit), CHANGELOG.md, semver disiplini.
- [ ] **Android release CI** yok — APK imzalı build için pipeline kur.
- [ ] Flutter sürümü CI'da sabit (`3.47.6`), README'de `3.38+` yazıyor → tutarsızlık düzeltilmeli, `.fvmrc` veya `fvm` standardı.

### 4.4 Depo Hijyeni
- [ ] `build/client` ve `build/psych` **derleme çıktıları git'e commit ediliyor** (CI her push'ta). Depoyu şişiriyor, sürüm geçmişi bozuluyor. **Build'leri git'ten çıkar, release artifact olarak dağıt.**
- [ ] Ölü dosyaları temizle: `lib/main_psy_backup.dart` (asıl psikolog girişi bunu import ediyor — kafa karışıklığı yaratıyor), `main_psy_backup` adlandırması düzeltilmeli.
- [ ] Depo gizliliği kontrolü: geçmişte sürülmüş anahtar var mı? GitHub'da repo **private** olmalı.

---

## 🟠 BÖLÜM 5 — HUKUKİ VE İŞ (Senin Tarafında)

Uygulama Türkiye'de sağlık verisi işlediği için bu kısım atlanamaz. Sen hukukçuna danışmalısın.

### 5.1 Zorunlu Dokümanlar (Yok — Hazırlanmalı)
- [ ] **KVKK Aydınlatma Metni** (veri sorumlusu kim, veriler nerede işlenir, yurt dışı aktarım var mı, haklar neler).
- [ ] **Gizlilik Politikası** (web'de yayımlanacak sayfa).
- [ ] **Kullanım Koşulları / Hizmet Şartları** (SaaS sözleşmesi).
- [ ] **Abonelik Sözleşmesi** (aylık kira, fesih, iade koşulları — IBAN modeline uygun).
- [ ] **Veri İşleme Sözleşmesi (DVS)** — sen veri sorumlusu, müşteri veri işleyen ise veya tersi. KVKK md. 8.
- [ ] **Açık Rıza / Onam formu metni** (özel nitelikli veri için ayrı ve açık rıza zorunlu).
- [ ] **İade / İptal politikası**.
- [ ] **İrtibat kişisi / DPO** bilgisi (KVKK md. 18'deki 10 yıl saklama yükümlülüğü için).

### 5.2 Yurt Dışı Veri Aktarımı — KRİTİK
- **Sorun:** Supabase ve Vercel **ABD'de** barındırıyor. Sağlık verisi = özel nitelikli kişisel veri.
- **Etki:** Yurt dışı aktarım için KVKK md. 6 kapsamında **yeterli koruma** veya **açık rıza** şart. Aksi halde idari para cezası + veri ihlali.
- **Yapılacak:** Ya (a) Türkiye'de/AB'de barındırma (Verizon/AWS Frankfurt bölgesi veya TR barındırmalı alternatif), ya (b) açık rıza metni + aktarım değerlendirmesi. Hukukçuya danış **karar burada kritik**.

### 5.3 Faturalama
- [ ] IBAN ile tahsilat yapacaksan **e-arşiv fatura** kesme zorunluluğu (gelir vergisi). Muhasebe entegrasyonu planla.
- [ ] Abonelik dönemi takibi ve hatırlatma için abonelik yönetimi.
- [ ] KDV uygulaması (SaaS hizmeti) — muhasebeciye teyit et.

### 5.4 Uygulama Mağazası
- [ ] **Google Play**: Sağlık uygulamaları için Sağlık Uygulamaları Politikası, Sağlık Uygulaması Beyanı, `health` permission beyanı gerekir. **Play Console geliştirici hesabı ($25 tek sefer)** ve **Sağlık Uygulaması Beyan Formu** gerekiyor.
- [ ] **Apple App Store**: Sağlık verisi işleyen uygulamalarda gizlilik politikası URL'si ve açık rıza şart. (Şu an yalnızca Android/web var; iOS eklenecekse.)
- [ ] Alternatif: Mağazaya koymadan doğrudan APK dağıtımı (ama güncelleme/dağıtım zorluğu).

---

## 🟡 BÖLÜM 6 — ÜRÜN VE ÖZELLİK EKSİKLERİ

### 6.1 Kritik Eksik Özellikler
- [ ] **Otomatik yedekleme & geri yükleme:** Şu an sadece CSV dışa aktarım var (4 tür: danışan, randevu, not, plan). **Tüm veriyi kapsayan JSON yedek al / geri yükle** — müşteri başka yere geçerse verisini alabilmeli (veri taşınabilirliği).
- [ ] **Randevu hatırlatmaları:** E-posta/SMS/WhatsApp bildirimi. Psikolog uygulamasının en çok ihtiyaç duyulan özelliği; şu an hiç yok.
- [ ] **Yazılı/işlem kaydı (Audit trail):** Kim bu notu yazdı, ne zaman değiştirdi, kim sildi.
- [ ] **Yumuşak silme (Soft delete):** Silinen kayıtlar kalıcı olarak yok oluyor (kurtarma yok). `deleted_at` alanı + geri dönüşüm kutusu.
- [ ] **Onam/imza ekranı:** Danışan uygulamasından ölçek formu/kvkk onamı PDF indirip imzaya verme.
- [ ] **Veri saklama süresi ayarı** ve otomatik arşivleme/silme.

### 6.2 Kullanılabilirlik / Arama
- [ ] **Genel arama:** Tüm notlarda, danışanlarda, form yanıtlarında tek alandan arama. Şu an sekme bazlı ve sınırlı.
- [ ] **Terapist devri:** Danışanı başka psikoloğa aktarma (kurumda terapist değişikliği).
- [ ] **PDF rapor üretimi:** Seans notu / özet raporu PDF olarak dışa aktarılabilir olmalı (mevcut PDF kütüphanesi ayrı bir şey — bu ikinci bir özellik).
- [ ] **Toplu işlemler:** Toplu form gönderimi, toplu etiketleme.
- [ ] **Çoklu dil / i18n:** Metinler kod içine gömülü. Yeni dil eklemek için `flutter_localizations` bağımlılığı var ama kullanılmıyor.

### 6.3 Güvenlik Açısından Riskli Mevcut Özellikler
- **Lisanslı ölçekler** (`lib/data/form_presets.dart:86`): BDI-II gibi ölçekler Pearson/Beck lisansına tabidir. Şu an "placeholder" olarak duruyor — **doğru yaklaşım**, ama ticari kullanımda bu ölçekleri satma/sağlama riski var. Uyarı metinleri yeterli mi kontrol edilmeli.
- **Risk/güvenlik planı** (`SafetyPlan`) var ama **kriz durumunda uyarı/eskalasyon mekanizması yok** (acil durum kişisi, irtibat bildirimi).

---

## 🟡 BÖLÜM 7 — KOD KALİTESİ VE BAKIM

### 7.1 Dosya Boyutları (Monolitik yapı — bakımı zor)
| Dosya | Satır | Sorun |
|---|---|---|
| `lib/data/diagnosis_codes.dart` | 5.040 | Muhtemelen salt veri tablosu — ayrı dosyaya/veritabanına taşı |
| `lib/screens/tabs/clients_tab.dart` | 2.521 | Widget'lar ayrıştırılmalı |
| `lib/screens/tabs/forms_tab.dart` | 2.160 | Aynı |
| `lib/screens/tabs/appointments_tab.dart` | 1.768 | Aynı |
| `lib/main.dart` | 1.482 | Danışan uygulaması — ekranlar klasöre taşı |
| `lib/screens/tabs/settings_tab.dart` | 1.000 | Aynı |

**Yapılacak:** Her ekranı `screens/<feature>/` altında bileşenlere böl. Bileşen sınırları ve `const` constructor kullanımı düzenli olsun.

### 7.2 Mimari
- [ ] **State yönetimi:** Sadece `ChangeNotifier` var. Bu ölçekte yönetilebilir ama büyüyen ekranlarda zorlaşır. `Riverpod`/`Bloc` değerlendirilmeli (veya en azından repository pattern netleştirilmeli).
- [ ] `main_psy_backup.dart` / `main_psych.dart` ikilisi kafa karıştırıcı — psikolog giriş noktası "backup" dosyasını import ediyor. Temizlenmeli.
- [ ] `supabase` tek backend dosyasında (892 satır) — alan bazlı servislere ayrılabilir.

### 7.3 Test
- [ ] Test kapsamı zayıf: sadece `models_test.dart` (182) + `widget_test.dart` (903).
- [ ] **Eksik:** Supabase backend testleri, RLS/güvenlik testleri, senkronizasyon (çevrimdışı→çevrimiçi) testleri, veri kaybı senaryoları.
- [ ] Testlerde gerçek Supabase bağlantısı yok — entegrasyon testi kurulmalı (CI'da test Supabase projesine bağlanmalı).
- [ ] Kod kapsam (coverage) raporu CI'a eklensin.

### 7.4 Lint / Statik Analiz
- [ ] `analysis_options.yaml` çok gevşek — sadece varsayılan `flutter_lints`. `strict-casts`, `strict-raw-types` gibi kurallar açılmalı.
- [ ] `flutter analyze` CI'da **hata olarak** değerlendirilmeli (`--fatal-infos`).
- [ ] Çok sayıda `print`/`debugPrint` production kodda temizlenmeli.

### 7.5 Dokümantasyon
- [ ] `CHANGELOG.md` yok.
- [ ] Kurulum dokümanları var (iyi) ama **lisans yönetimi, yeni ortam kurulumu (yeni Supabase/Vercel), anahtar rotasyonu** için operasyon kılavuzu (runbook) yok.
- [ ] README'de Flutter sürüm tutarsızlığı (`3.38+` vs CI `3.47.6`).

---

## 🟢 BÖLÜM 8 — KALİTELİ OLANLAR (Bozulmadan koru)

Bu kısırlar iyi yapılmış, taşıma sırasında bozulmamalı:
- [x] RLS politikaları detaylı ve düşünülmüş (sütun bazlı GRANT dahil).
- [x] `SECURITY DEFINER` RPC'ler ile danışan tarafı daraltılmış.
- [x] Eşleşme kodu tahmin edilemez (8 karakter, salt okunur RPC ile sahiplenme).
- [x] `service_role` anahtarı istemciye verilmiyor.
- [x] Supabase anahtarları `--dart-define` ile veriliyor, kaynak koda gömülü değil (build script'i ve workflow hariç — orada düzeltilmeli).
- [x] Yerel-öncelikli mimari (ağ yokken de çalışır).
- [x] PDF'ler Storage'a çıkarılıyor (jsonb şişmesi engellenmiş).
- [x] Yazma kuyruğu ile senkronizasyon kaybı engellenmiş.
- [x] Uzak veri bozuksa yerel veri üzerine yazılmıyor.
- [x] Web'de SPA rewrite ve cache stratejisi düşünülmüş.
- [x] Testler var ve CI'da çalışıyor.

---

## 📋 ÖNERİLEN SIRALAMA (Yol Haritası)

### Aşama 1 — Yayın Blokajlarını Kaldır (3-5 gün)
1. Android INTERNET izni (1.1)
2. Release imzalama + keystore (1.2)
3. KVKK onay metnini düzelt (1.3)
4. Tam yedek al, temiz Supabase projesi aç (4.1)

### Aşama 2 — Güvenlik & KVKK Temeli (1.5-2 hafta)
5. Cihazda şifreli depolama (2.1)
6. Güçlü hash'e geçiş (2.2)
7. Web güvenlik başlıkları (2.3)
8. Hesap silme + KVKK talep süreci (2.5)
9. Onam kaydı + sürüm takibi (2.6)
10. Denetim kaydı (2.4)

### Aşama 3 — Lisans Sistemi (1 hafta)
11. Lisans/organizasyon tabloları + RPC'ler (3.1)
12. Uygulamada lisans kontrolü + salt-okunur mod (3.2)
13. Yönetici paneli (3.3)
14. Cihaz sınırı (3.2)

### Aşama 4 — Altyapı Taşıma (3 gün)
15. Supabase Pro + özel alan + SMTP (4.1)
16. Vercel Pro + özel alan + WAF (4.2)
17. CI kalite kapısı + secrets + release hattı (4.3)
18. Build çıktılarını git'ten çıkar (4.4)
19. Yedekleme + geri yükleme provası (4.1)

### Aşama 5 — Hukuki (senin tarafında, paralel)
20. KVKK aydınlatma metni + gizlilik politikası (5.1)
21. Abonelik sözleşmesi + iade politikası (5.1)
22. Yurt dışı aktarım kararı — **hukukçuya danış** (5.2)
23. Faturalama planı (5.3)

### Aşama 6 — Ürün Tamamlama (sürekli)
24. Tam JSON yedek/geri yükleme (6.1)
25. Randevu hatırlatmaları (6.1)
26. Genel arama (6.2)
27. Kodun bölünmesi + test kapsamı (7.x)

---

## ❓ Netleştirilmesi Gereken Sorular

1. **Kiralama hedefi kim?** Bireysel psikolog mu, klinik/kurum mu? → Multi-tenant zorunluluğunu belirler.
2. **Web, Android, iOS hangileri dağıtılacak?** → Mağaza politika maliyeti değişir.
3. **Veri Türkiye'de mi kalmalı?** → Sunucu seçimini ve hukuki riski doğrudan etkiler.
4. **Kaç müşteri hedefleniyor?** → Supabase planı ve ölçek kararları.
5. **Müşteri başına aylık ne, kaç kullanıcı?** → Cihaz sınırı ve paket tasarımı.
6. **Hukukçu var mı?** → KVKK ve abonelik sözleşmesi için.
7. **Mevcut müşteri verisi var mı?** → Taşıma planı.

---

*Bu liste canlı bir dokümandır. Onaylandığında Aşama 1'den başlanacaktır.*
