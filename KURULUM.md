# MindTrack — Kurulum ve Kullanım Rehberi

MindTrack, psikologlar için çalışan bir klinik takip uygulamasıdır. Psikolog
uygulaması cihazda **yerel-öncelikli** çalışır, ancak oturum açtığınızda kayıtlarınız
**Supabase** ile cihazlarınız arasında eş zamanlı olarak senkronize edilir.
Psikolog ↔ danışan akışı (eşleşme kodu, randevu, görev, ödev, form yanıtı)
Supabase üzerinden gerçek zamanlı aktarılır.

> Firebase kaldırılmıştır. Sunucu tarafındaki her şey artık Supabase'tir.
> Supabase projesini ilk kez kuruyorsanız **[SUPABASE-KURULUM.md](SUPABASE-KURULUM.md)**
> dosyasını sırayla uygulayın.

---

## 1) Ön koşul: Supabase projesi

Uygulamanın çalışması için bir Supabase projesi ve iki değer gerekir:

- `SUPABASE_URL` — örn. `https://abcdefghijklm.supabase.co`
- `SUPABASE_PUBLISHABLE_KEY` — proje ayarlarındaki `sb_publishable_…` publishable anahtar
- `SUPABASE_PUBLISHABLE_KEY` — proje ayarlarındaki `sb_publishable_…` publishable anahtar

Bu iki değeri almak, veritabanı tablolarını oluşturmak ve Free planı yapılandırmak
 için **[SUPABASE-KURULUM.md](SUPABASE-KURULUM.md)** adımlarını izleyin.

> 🔒 `service_role` (secret) anahtarını asla buraya yazmayın ve uygulamaya
> vermeyin. Uygulama yalnızca `anon` anahtarı kullanır.

---

## 2) Hızlı Başlangıç (Web — önerilen)

```bash
```bash
# 1) Bağımlılıklar
flutter pub get

# 2) Supabase bağlantısı
export SUPABASE_URL="https://yfxepfxgiceplghlrxek.supabase.co"
export SUPABASE_PUBLISHABLE_KEY="sb_publishable_-2LSJNP29XcL3ykiRQ8aaQ_kxZ7aKAn"

# 3) Psikolog + danışan web çıktısı
./scripts/build_web.sh
```

Çıktılar:
- `build/psych` → psikolog uygulaması
- `build/client` → danışan uygulaması

### Yayınlama

`build/psych` ve `build/client` klasörleri **statik** dosyalardır; Firebase Hosting
yerine herhangi bir statik barındırma servisine yüklenebilir:

```bash
# Örnek: herhangi bir statik sunucu ile denemek için
cd build/psych && python3 -m http.server 8080
```

Servisler: Netlify, Vercel, Cloudflare Pages, GitHub Pages veya kendi sunucunuz.
(Android telefonunuzda `adb reverse tcp:8080 tcp:8080` ile ya da aynı ağdaki IP
ile de açabilirsiniz.)

> **Zorunlu:** Her iki uygulama da Flutter SPA'sıdır. Barındırma **tüm**
> adresleri `index.html`'e yönlendirmelidir (`/*` → `/index.html`, `200`);
> aksi hâlde paylaşılan kod gibi derin bağlantılar 404 döner.
> Servise göre ayarlar ve ayrıntılar için
> [README_WEB_KAYNAK_KODU.md](README_WEB_KAYNAK_KODU.md#yayınlama) bölümüne bakın.

---

## 3) Android APK (mobil)

Flutter SDK yüklü bir makinede:

```bash
flutter pub get

# Psikolog APK'sı
flutter build apk --release --flavor psychologist \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_PUBLISHABLE_KEY="$SUPABASE_PUBLISHABLE_KEY"

# Danışan APK'sı
flutter build apk --release --flavor client \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_PUBLISHABLE_KEY="$SUPABASE_PUBLISHABLE_KEY"
```

Çıktılar:
- `build/app/outputs/flutter-apk/psychologist-release.apk`
- `build/app/outputs/flutter-apk/client-release.apk`

Gerekli Flutter sürümü: **3.38 veya üzeri** (proje Dart 3.13 ile yazıldı).

---

## 4) Nasıl çalışır?

- **Kayıt / Giriş** — Supabase Auth (e-posta + şifre). Şifreler sunucuda
  saklanmaz; doğrulama Supabase tarafından yapılır.
- **Senkronizasyon** — Psikolog uygulaması klinik kaydı cihazda tutmaya devam
  eder; oturum açıkken arka planda Supabase'e yazar, başka bir cihazda açıldığında
  oradan okur. Ağ yokken uygulama normal çalışır, bağlantı gelince eşitlenir.
- **Gerçek zamanlı akış** — Psikolog bir randevu/görev/ödev atadığında veya danışan
  bir istek gönderdiğinde karşı tarafın ekranı anında güncellenir.
- **PDF kütüphanesi** — PDF'ler cihazda tutulur, yedeklenirken Supabase Storage'a
  yüklenir. 2 MB dosya sınırı uygulanır.

---

## 5) Uygulama Özellikleri

- **Giriş / Kayıt**: Supabase Auth ile e-posta + şifre.
- **Genel Bakış**: Bugünkü randevular, risk uyarıları, istatistikler, yaklaşan randevular, açık görevler.
- **Formlar**: Değerlendirme formu oluşturma/düzenleme/doldurma, otomatik puanlama ve risk algılama.
- **Danışanlar**: Danışan kartları, SOAP seans notları, tedavi planı hedefleri, güvenlik planı ve acil hatlar.
- **Randevular**: Aylık takvim, hafta görünümü, tekrarlı randevular, geçmiş tarihe randevu engeli, çakışma uyarısı.
- **Görevler**: Açık/gecikmiş görev takibi, öncelik ve son tarih yönetimi.
- **Sonuçlar**: Form analizleri, puan trendi grafiği, risk işaretli değerlendirmeler, aylık akış.
- **PDF Kütüphanesi**: Kategoriler, PDF yükleme, uygulama içinde görüntüleme, yeni sekmede açma ve indirme.
- **Raporlar**: Seçilen hafta veya ay için danışan, iletişim, randevu türü ve durum bilgilerini uygulama temasında HTML/PDF'e hazır rapor olarak indirme.
- **Ayarlar**: Profil, PIN kilidi, CSV dışa aktarım ve KVKK.

---

## 6) Veri ve Gizlilik

- Psikologun klinik kaydı cihazda saklanır ve oturum açıldığında Supabase ile
  senkronize edilir. **E-posta adresi ve parola uygulamaya gömülü değildir.**
- Veri erişimi, veritabanındaki satır güvenliği (RLS) politikalarıyla kısıtlıdır:
  her kullanıcı yalnızca kendine ait kayıtları görebilir.
- PDF dosyaları için dosya sınırı **2 MB** uygulanır; dosyalar özel bir depolama
  kovasında tutulur ve herkese açık değildir.
- Klinik veriler oturum açıkken Supabase'e senkronize edilir; yönetim paylaşımı için Raporlar ekranındaki dönemsel rapor kullanılmalıdır.
- Bu uygulama tıbbi tanı koymaz; mesleki kararları destekleyen bir kayıt aracıdır.

---

## 7) Testler (geliştiriciler için)

```bash
flutter test      # akış testleri
flutter analyze   # statik analiz
```

---

## 8) Sık karşılaşılan sorunlar

| Belirti | Çözüm |
| --- | --- |
| Giriş yapılamıyor, "Sunucuya ulaşılamadı" | `--dart-define` ile `SUPABASE_URL` / `SUPABASE_PUBLISHABLE_KEY` verilmeden derlenmiş. Yeniden derleyin. |
| `relation "public.xxx" does not exist` | Migration çalıştırılmamış → [SUPABASE-KURULUM.md](SUPABASE-KURULUM.md) bölüm 2. |
| Proje "PAUSED" görünüyor | Ücretsiz plan 7 gün hareketsizlikte projeyi duraklatır; dashboard'da **Restore**. |

Ayrıntılı liste için [SUPABASE-KURULUM.md](SUPABASE-KURULUM.md) bölüm 7.

---

Sürüm 1.0 — Flutter (Dart 3.13) · Backend: Supabase (Postgres + Auth + Realtime + Storage)
