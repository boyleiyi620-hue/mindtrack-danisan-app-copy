# MindTrack — Eksiklik Analizi ve Yol Haritası (v2)

**Tarih:** 2026-10-04 · v1'in revize edilmiş hâli (iş modeli netleşti)
*(v1 taslak: `EKSIKLIKLER-v1-taslak.md`)*

## 📌 Netleşen İş Modeli

| Konu | Karar | Etkisi |
|---|---|---|
| Müşteri tipi | **Klinik / kurum** | **Çok kiracı zorunlu** — v1'de opsiyondu, artık kritik |
| Dağıtım | **Sadece web PWA** | Android APK blokajları **düştü** ✅ |
| Veri konumu | **Türkiye'de kalmak zorunda değil** | Yurt dışı aktarım hukuki riski **düştü** ✅ |
| Fiyat | **99 TL/ay/psikolog** | Lisans modeli kolaylaştı, maliyet modeli kritik |
| Öncelik | **Sunucu çökmemeli, kesinti olmamalı** | **Erişilebilirlik** en üst öncelik |

**İyi haber:** APK imzalama/izin blokajları ve veri yerleşimi hukuki riski ortadan kalktı — v1'de en üstteydiler.

**Daha da iyi haber:** **Müşteri verisi yok** (sadece kendi test verin). Bu, projeyi çok kolaylaştırıyor:
- Taşıma/uyumluluk planı **gerekmiyor** — geriye dönük uyumluluk (backward compatibility) yazmadan temiz kırılma yapabilirsin.
- Şema değişiklikleri riski **sıfır** — gerçek bir müşterinin kaydını bozma endişen yok.
- `psychologist_state` tek satır jsonb mimarisini olduğu gibi bırakıp **baştan düzgün tablolara bölebilirsin**.
- Test verilerini tek tuşla silebilirsin.

**Kötü haber:** Kodda "psikolog telefon + bilgisayarı aynı anda kullanır" ve "kurumda sınırsız danışan" senaryolarını taşıyacak **hiçbir şey yok**. Üstelik mevcut tasarım bu senaryolarda **garanti veri kaybı** üretiyor.

---

## 📊 İŞ YÜKÜ HESABI (psikolog başına 8 danışan/gün)

Verdiğin bilgilerle depolama ve bant genişliği ihtiyacını hesapladım. **Varsayımları doğrula, sayılar buna göre değişir.**

| Varsayım | Değer |
|---|---|
| Yıllık iş günü | ~250 gün |
| Seans / gün | 8 |
| Ortalama SOAP notu (JSON) | ~2,5 KB |
| Ortalama danışan profili | ~1 KB |

**Yıllık üretim (psikolog başına, sadece metin):**

| Kayıt | Yıllık adet | Yıllık boyut |
|---|---|---|
| Seans notu (SOAP) | 2.000 | ~5 MB |
| Randevu | 2.000 | ~0,4 MB |
| Danışan profili (yeni) | ~200 | ~0,2 MB |
| Değerlendirme / form yanıtı | ~2.000 | ~2 MB |
| **TOPLAM (metin)** | | **~7-8 MB / yıl** |
| 3 yıllık birikim | | **~22-24 MB** |

### ❗ Bunun iki sonucu var

**1. `localStorage` kotası (5 MB) birinci YIL doluyor — hiç belge yüklenmese bile.**
Mevcut mimaride veri tarayıcıda 5 MB'a sığmalı. Sadece seans notları bir yılda ~5 MB. Yani **belge/PDF yüklenmeden önce** kota taşıyor. PDF'ler eklendiğinde ise (base64, +%33) **haftalar içinde** biter. Bu artık "olası risk" değil, **ölçülmüş ve kaçınılmaz** bir sonuç.

**2. Mevcut tek-satır mimarisi aylık onlarca GB bant genişliği yakar.**
Her kayıtta tüm veri yeniden gönderiliyor. Kayıtlar tuş başına değil butona basınca gidiyor (iyi — bunu doğruladım), yani günde ~20-40 kayıt demek:

| Süre | Veri boyutu | Günlük gönderim | **Aylık (psikolog başına)** |
|---|---|---|---|
| 1. yıl | ~8 MB | ~160-320 MB | **~5-10 GB** |
| 3. yıl | ~24 MB | ~480-960 MB | **~15-30 GB** |

Normal SaaS uygulamaları kullanıcı başına **ayda 100 MB'ın altında** bant kullanır. Burada **100-300 kat** fazla. 20 psikolog × 3. yıl ≈ **300-600 GB/ay** → plan limitlerini aşar, hem maliyet patlar hem de uygulama yavaşlar.

> Bu, "sunucu çökmesin" isteğinin en pahalı kısmı: sunucu ayakta kalır ama **maliyeti ve gecikmesi** yüzünden kullanılamaz hale gelir.

**Yapılacak:** Veri kayıt bazlı gönderilsin (sadece değişen kayıt), tarayıcı sadece önbellek olsun. Bu hem maliyeti ~100 kat düşürür hem de 1.1'deki kota sorununu kökten çözer.

**Belge sayısını bilmiyorsun diye not:** Belge yükü hesaba **hiç** girmedi (yani yukarıdaki rakamlar belge içermiyor). Kliniklerde ölçek, form ve protokol belgeleri yoğun olur — belgeleri de eklediğinde maliyet ve kota **katlanarak** artar. Paket başına belge/kota tanımlamak bu yüzden şart.

---

---

## 📁 BELGE STRATEJİSİ KARARI (belgeler sunucuya bağlansın mı?)

**Karar: Belgeler sunucuya bağlanmalı.** "Sadece cihazda tutsam" seçeneği uygulamanın kendi kodunda zaten reddedilmiş — ve bu iyi haber değil, ciddi bir kısıt.

### Yerelde tutmanın pratik sonucu: en fazla 2 belge

Mevcut kodda sabitler açık (`lib/screens/tabs/pdfs_tab.dart:14-15`):

| Sabit | Değer | Anlamı |
|---|---|---|
| `_maxDocBytes` | **2 MB** | Dosya başına **sert** üst sınır |
| `_warnBytes` | **4,2 MB** | Toplamda uyarı eşiği |
| Ekranda yazan | "~5 MB" | Kullanıcıya gösterilen kota |

Yani **cihazda 2 adet 2 MB'lık PDF sığar**, üçüncüsü reddedilir. Hedefin **ayda 100 belge** ise bu, **50 kat** altındadır. Yerelde tutarsan ayda 2 belge yükleyebilirsin — 8 danışan/gün temposunda imkânsız.

### Yerelde tutmanın 4 ek riski (kapasite dışında)

1. **Cihaz kaybında belgeler kalıcı gider.** Telefon çalınır/bozulur, tarayıcı verisi temizlenir, iOS veriyi silerse → klinik kayıt **bir daha geri gelmez**. Şu an otomatik yedek de yok, yani sıfır yedeklilik.
2. **Cihazlar arası erişim yok.** Telefonda eklenen belge bilgisayarda görünmez. 8 danışan/gün + çok cihaz kullanımında iş akışı kırılır.
3. **KVKK riski.** Klinik kayıt kaybı, veri sorumlusu (psikolog/klinik) için sorumluluk doğurur; profesyonel maluliyet açısından da sorunludur.
4. **Paylaşılan cihazda veri kalıntısı** *(koddan doğrulandı)*: `clearSession()` yalnızca oturum anahtarını siliyor, veri anahtarını **silmiyor**. Yani klinik bilgisayarında görevden ayrılan psikoloğun tüm kayıtları diskte kalıyor. Yeni kişi aynı hesabı açarsa verilere erişebilir.

### İyi haber: Belgeler bant genişliği probleminin sadece %1-4'ü

Bu, kararı kolaylaştırıyor:

| Kalem | Psikolog başına aylık |
|---|---|
| **Belgeler** (100 belge × ~1 MB, yükleme + indirme) | **~200 MB** |
| **Metin senkronizasyonu** (mevcut mimari, yıl 1 → yıl 3) | **~5-30 GB** |
| Oran | Belgeler ≈ **%1-4**'ü |

**Yani "belgeleri sunucuya bağlasak mı" sorusu, problemin %2'sini optimize etmek.** Asıl maliyet kaynağı tek-satır mimarisi. **Önce senkronizasyon düzeltilmeli**, belgeler zaten o düzeltmenin doğal parçası olarak çözülür.

### Sunucuda tutmanın maliyeti (100 belge/ay/psikolog)

Ortalama belge boyutu için üç senaryo:

| Ortalama boyut | Aylık | Yıllık | 3 yıllık | 50 psikolog (3 yıl) |
|---|---|---|---|---|
| 300 KB (dijital PDF) | 30 MB | 360 MB | ~1,1 GB | ~54 GB |
| **1 MB (karışık — gerçekçi)** | **100 MB** | **1,2 GB** | **~3,6 GB** | **~180 GB** |
| 3 MB (telefon fotoğrafı) | 300 MB | 3,6 GB | ~10,8 GB | ~540 GB |

**Depolama ucuz, bant pahalı.** Supabase Pro'da 100 GB dahil, üstü ~$0,021/GB/ay civarı (fiyatlar doğrulanmalı). 180 GB senaryosunda aşım ~$1,7/ay — gelirin yanında önemsiz. Sorun **depolama maliyeti değil**, tek-satır senkronizasyonun bant maliyeti.

> ⚠️ **Asıl iş riski depolama değil, artan maliyet:** Depolama her yıl büyür ama gelir büyümez. Bu yüzden kotanın yanı sıra **saklama süresi politikası** şart.

### Önerilen mimari: sunucu tek doğruluk kaynağı, cihaz sadece önbellek

Bu, üç sorunu birden çözer:
- **Kota sorunu biter** — önbellek düşürülebilir/evrilebilir, sunucu kapasitesi büyük
- **Veri kaybı biter** — cihaz ölse de belge sunucuda
- **Bant maliyeti düşer** — sadece **açılan** belge indirilir (100 belgeden 1'i), geri kalanı hiç indirilmez

Yani: `documents`/`pdfFiles` için de `storagePath` deseni **düzeltilerek** uygulanmalı (bugün `pdfFiles`'ta yarım kalmış, `documents`'ta hiç yok).

---

### 📋 Belge kotası için verilmesi gereken kararlar

100 belge/ay senaryosunda ticari ve hukuki olarak şunlar netleşmeli:

| Soru | Neden önemli |
|---|---|
| 100 belge/ay **sert üst sınır** mı, ortalama mi? | Aşılırsa ne olacak? Engellensin mi, uyarı mı? |
| Kota dolunca **mevcut belgeler silinir mi?** | Silinirse klinik kayıt kaybı olur → kabul edilemez |
| **Dosya başına** üst sınır ne olacak? | Şu an 2 MB — **fazla düşük** (aşağıya bak) |
| **Toplam depolama** sınırı olacak mı? | Yoksa maliyet yıllar içinde sınırsız büyür |
| Belge **kaç yıl** saklanacak? | Saklama süresi = maliyet kontrolü + KVKK yükümlülüğü |
| Kota aşımı **ücretli mi** olacak? | Satış ve sözleşme metni gerekiyor |
| Depolama **99 TL'ye dahil mi**? | Sözleşmede "sınırsız" yazmayacaksan burası önemli |

> **Kota kuralı (öneri):** Kota **yükleme hızını** sınırlasın (ayda 100 belge), **mevcut belgelere dokunmasın.** Süresi dolan belgeler silinmez — silinirse klinik kayıt kaybı olur ve bu kabul edilemez. Maliyet kontrolü gerekiyorsa **saklama süresi** (örn. 3 yıl sonra soğuk arşiv) kullanılır.

### ⚠️ Mevcut 2 MB dosya sınırı klinik kullanım için fazla düşük

`_maxDocBytes = 2 MB` (2 MB üzeri reddediliyor). Ama telefona çekilmiş form fotoğrafları, taranmış protokoller ve kurum evrakı rutin olarak 2-8 MB. Yani psikolog belge yüklerken **sık sık reddedilme** yaşar — 8 danışan/gün temposunda bu iş akışını durdurur.

**Doğru sıra:** Önce **mimariyi düzelt** (sunucu tek kaynak, önbellek), **sonra** dosya sınırını yukarı çek. Sırayı tersine çevirirsen, yükselttiğin limit cihazda kota taşmasına ve veri kaybına yol açar.

# 🔴 BÖLÜM 1 — VERİ KAYBI ÜRETEN BLOKAJLAR

> Sunucu çökmez isteğinle de doğrudan ilgili: uygulama çökmez ama **veri** kaybolur. Klinik kayıt için bu daha kötüdür.

### 1.1 Tarayıcı Depolama Limiti — PDF'ler Uygulamayı Kilitler 🔴🔴
**En kritik bulgu. İş modelini doğrudan tehdit ediyor.**

- **Dosyalar:** `lib/models/pdf_library.dart`, `lib/models/document.dart`, `lib/data/data_store.dart:117`
- **Mevcut durum:**
  - Tüm veri `SharedPreferences`'a yazılıyor → web'de bu **`localStorage`**, kotası **~5 MB**.
  - PDF'ler **base64** olarak saklanıyor (base64, binary'yi ~%33 şişirir).
  - `_hydratePdfs()` her senkronizasyonda **tüm PDF'leri indirip** `dataUrl` olarak yazıyor.
- **Kritik hata 1:** `Document` (danışan dokümanları) modelinde `storagePath` **yok** → bu belgeler **hiçbir zaman** Storage'a çıkarılmıyor, kalıcı `localStorage`'da kalıyor.
- **Kritik hata 2:** `_slimForRemote()` sadece `pdfFiles` dizisini işliyor, `documents`a dokunmuyor → danışan dokümanları base64 olarak **jsonb'ye de gönderiliyor**.
- **Kritik hata 3:** Kota taşınca **hiçbir hata yakalama yok** (kod tabanında kota kontrolü sıfır eşleşme).

**Somut senaryo:** 2 MB'lık tarama formu → base64'te ~2,7 MB. İki PDF yüklendi → kota doldu → sonraki kayıt sessizce kaybolmaya başlıyor. Psikolog bunu **öğrenmiyor**.

**Ölçülmüş sonuç:** 8 danışan/gün temposunda sadece **metin** verisi ~7-8 MB/yıl → `localStorage` kotası (5 MB) **birinci yılın sonunda**, **hiç tek belge yüklenmeden** dolar. Belgeler eklendiğinde haftalar içinde biter. (Hesap: yukarıdaki İş Yükü bölümü.)

**Neden 99 TL modelini bozar:** "Sınırsız danışan" vaadi veriyorsun ama teknik olarak birkaç dosyada tıkanıyor. İlk büyük klinik kendiliğinden çöker.

**Yapılacak:**
1. `localStorage` → **`IndexedDB`** (web'de GB mertebesi kotası). En azından veri katmanını `shared_preferences`'tan ayır.
2. **Sunucu tek doğruluk kaynağı olsun**, tarayıcı sadece önbellek.
3. `Document` modeline `storagePath` ekle; `_slimForRemote` `documents`ı da kapsasın.
4. `_hydratePdfs` tümünü indirmesin — sadece açılan PDF indirilsin (lazy load).
5. Kota dolduğunda kullanıcıya uyarı göster, veri kaybını engelle.

### 1.2 Yazma Hataları Sessizce Yutuluyor — Kayıt Sunucuya Hiç Ulaşmıyor 🔴🔴
- **Dosya:** `lib/data/data_store.dart:178-205`
- **Sorun:** `_saveRemote()` içinde `catch (_) {}` var. Yorum diyor ki *"sonraki kullanıcı işleminde yeniden denenir"*.
- **Gerçek:** Yeniden deneme **yok**. `_pendingRemoteEncoded` sadece bellekte. Yazma başarısız olursa veri o cihazda kalır, kullanıcı başka işlem yapmazsa **bir daha asla denenmez**, kullanıcıya **hiçbir uyarı gösterilmez**.
- **Kritik senaryo:** Psikolog seans notu yazdı → ağ koptu → yazma sessizce başarısız → telefonu kapattı → ertesi hafta bilgisayardan açtı → **not yok**. Klinik kayıt kaybı, hiçbir iz yok.
- **"Sunucu çökmemeli" isteğinle bağlantısı:** Sunucu kısa düşse bile veri kaybolmamalı. Şu an düşüyor.

**Yapılacak:**
1. **Kalıcı yazma kuyruğu** (IndexedDB'de). Uygulama kapansa bile yeniden denensin.
2. **Üstel geri çekilme** + tekrar deneme sayacı.
3. **Kullanıcıya görünür göstergesi:** "☁️ Senkronize edildi / ⏳ Bekliyor (3) / ⚠️ Bağlantı yok — veriniz bu cihazda güvende".
4. Uygulama kapanırken bekleyen yazma varsa uyarı.

### 1.3 Son Yazan Kazanır — Telefon ve Bilgisayar Çakışınca Veri Silinir 🔴🔴
- **Dosyalar:** `lib/data/mindtrack_backend.dart:128-145`, `lib/data/data_store.dart:91`
- **Sorun:** Psikologun **tüm klinik kaydı tek bir jsonb satırında** (`psychologist_state`). Her değişiklikte **tüm veri** yeniden yazılıyor.
- **Sonuç:**
  - **Telefonda** not yazdı, **bilgisayarda** aynı anda randevu açtı → bilgisayarın yazması telefonun verisini **tümüyle** ezer.
  - Uzak veri geldiğinde `_applyRemoteState` yerel veriyi **koşulsuz** üzerine yazıyor — gönderilmemiş düzenlemeler de gidebilir.
- **Senin senaryonda kaçınılmaz:** "Telefonlarına kuracaklar" = herkes telefon + bilgisayar kullanacak.

**Yapılacak:**
1. **Veri tek satırdan çıkarılmalı** — danışanlar, notlar, form yanıtları, randevular ayrı tablolar.
2. **Kayıt bazlı senkronizasyon** — sadece değişen kayıt gitsin.
3. **Çakışma çözümü:** `updated_at` + revision. Çakışmada uyarı, kullanıcı seçsin.
4. **Yumuşak silme** (`deleted_at`) — bir cihaz silerse diğeri haber alsın.
5. Büyük veri (PDF/belge) gövdeden tamamen çıkarılmalı.

### 1.4 Çok Kiracı Yapı Hiç Yok — Klinik Kiralaması Yapılamaz 🔴🔴
- **Dosya:** `lib/models/user_account.dart:8` (`clinic` sadece bir metin alanı)
- **Sorun:** Her hesap = tek psikolog. Kurum hesabı, koltuk sistemi, rol, ortak veri, yönetici paneli **hiç yok**.
- **Eksik olan her şey:**
  - `organizations` (klinik/kurum kaydı), `memberships` (üye + rol)
  - Koltuk lisansı (99 TL × psikolog sayısı)
  - Asistanın tüm notları görmemesi (**hukuki olarak zorunlu**)
  - Yöneticinin tüm psikologların verisini görmesi (türetilmiş rapor)
  - Psikolog ayrılırsa veri devri
  - KlinIKler arası **veri sızıntısı olmaması** (RLS'te tenant izolasyonu şart)

**Asistan/sekreter kararı (henüz netleşmedi):** Sekreter ihtiyacı muhtemel — 8 danışan/gün temposunda randevu ve form takibi sekretersiz yapılamaz. Ama **beklemeden çözülebilir**: çok kiracı mimari zaten kurulacağı için `memberships.role` alanına `admin | psychologist | assistant` yazmak neredeyse **ücretsiz** (tek bir alan). Bu yüzden:
- **Şimdi ekle:** `role` alanı + RLS'te asistan için kısıtlı görünüm (danışan listesi + randevu görür, **seans notlarını görmez** — zaten hukuki olarak görmemesi gerekir).
- **Sonra ekle:** Asistan yönetim ekranı, rol atama arayüzü — sattığın klinik talep ederse yapılır.

### 1.5 PWA Güncellemesi Kaydedilmamış Notu Siliyor 🔴
- **Dosya:** `web/disable_flutter_service_worker.js:22-30`
- **Sorun:** Service worker `activate` olurken **açık tüm sekmeleri zorla yeniliyor** (`clients.navigate()`), `skipWaiting()` ile anında devreye giriyor.
- **Etki:** Psikolog seans notu yazarken güncelleme yaparsan → sekme yenilenir → **yarım not kaybolur**.
- **Ek:** Kod tabanında `beforeunload`, `PopScope`, "kaydedilmemiş" koruması **hiç yok** (doğrulandı, sıfır eşleşme).

**Yapılacak:** Zorla yenileme kaldır → "Yeni sürüm var, yenileyin" uyarısı. Kaydedilmemiş değişiklik varsa engelle. `skipWaiting` kullanıcı onayına bağlansın. Tüm formlara koruma eklensin.

---

# 🟠 BÖLÜM 2 — SUNUCUNUN ÇÖKMEMESİ İÇİN

Şu an tek kırılma noktası var ve izleme yok.

### 2.1 Tek Proje = Tek Kırılma Noktası
- Tüm müşteriler tek Supabase projesini kullanıyor. Proje düşerse **herkes** düşer.
- Hız limiti / plan limiti dolduğunda yine **herkes** etkilenir.
- **Yapılacak:** Prod/staging ayrımı, plan yükseltme, limit alarmı, yük testi.

### 2.2 Hata İzleme ve Uyarı Yok
- Sentry benzeri izleme yok. Kullanıcı "çalışmıyor" derse **neden olduğunu bilemezsin**.
- **Yapılacak:** Sentry veya eşdeğeri · **kritik hata → sana otomatik bildirim** · uptime izleme · yedekleme başarısız olursa anında uyarı.

### 2.3 Yedekleme ve Geri Yükleme Kanıtlanmamış
- **Yapılacak:** Günlük otomatik yedek, PITR, ve **periyodik geri yükleme provası** (ayda bir). Klinik verisi için kritik.

### 2.4 Kimlik Doğrulama Tek Başarısızlık Noktası
- Kilitlenirsen kimse giremez. Auth rate limit'leri ve plan kotaları kontrol edilmeli. Kendi SMTP'ne geç (aşağıda).

### 2.5 Ölçüm Yok
- **Yapılacak:** Gerçek kullanıcı izleme, aktif kullanıcı sayısı, senkronizasyon gecikmesi.

---

# 🟠 BÖLÜM 3 — MALİYET MODELİ (99 TL/ay)

Sabit giderleri karşılamak için kaç kiracıya ihtiyacın var — bunu bilmeden fiyat güvenli değil.

**Sabit aylık giderler (tahmini, doğrulanmalı):**

| Kalem | Tahmini |
|---|---|
| Supabase Pro | ~25 USD/ay |
| Vercel Pro | ~20 USD/ay |
| Alan adı | ~1 USD/ay |
| SMTP (e-posta) | 0-20 USD/ay |
| İzleme (Sentry) | 0-26 USD/ay |
| **TOPLAM** | **~46-92 USD/ay** |

**Başabaş hesabı:**
```
Başabaş psikolog sayısı = (sabit giderler USD × güncel kuruş) ÷ 99
```
Örnek: kur 40 TL/USD → ~19 psikolog · kur 45 TL/USD → ~21 psikolog
*(Güncel kuru seninle hesaplanmalı.)*

**Dikkat:**
1. **Depolama maliyeti sınırsız büyüyebilir.** Her psikolog sınırsız belge yüklerse maliyet artar. Paket başına **kota koy** (örn. 5 GB, aşımı uyar).
2. **Bant genişliği — en büyük maliyet kalemi.** Mevcut mimaride her kayıtta tüm veri gönderiliyor. 8 danışan/gün temposunda **psikolog başına aylık 5-30 GB** (yıl 1 → yıl 3). Bu normal SaaS kullanımının (ayda <100 MB) **100-300 katı**. 20 psikologda aylık 100-600 GB → plan limitini aşar. Mimari düzeltmeden (kayıt bazlı senkronizasyon) fiyatlamayı sabitleyemezsin.
3. **Ölü maliyet:** Müşteri ayrılınca veri durmaya devam eder → arşiv politikası + geri ödeme kuralı.
4. **Kur riski:** Gelirin TL, giderin USD. Kur artışı kârı eritir → kur payı veya yıllık peşin indirim düşün.

**Yapılacak:** Paket/plan tanımları (koltuk başına, depolama kotalı), fiyat listesi, aylık gider/gelir takip paneli.

---

# 🟠 BÖLÜM 4 — LİSANS SİSTEMİ (IBAN modeli)

Ödeme uygulamadan alınmayacak, ama **elle yönetim** şart. Klinik ve koltuk bazlı.

### 4.1 Şema
```sql
organizations (id, name, tax_no, contact_email, status, created_at)
licenses (
  id, organization_id, plan, seats_purchased,
  starts_at, ends_at, status,        -- active | expired | suspended | cancelled
  storage_quota_gb, grace_days, notes, created_at, updated_at
)
license_seats (id, license_id, psychologist_user_id, assigned_at, revoked_at)
payment_records (id, organization_id, amount, period_start, period_end,
                 paid_at, reference, note, created_at)
audit_log (id, organization_id, user_id, action, entity, entity_id, created_at, ip)
```

### 4.2 Lisans Davranışı
- **Aktif** → tam kullanım.
- **Dolmuş + ödemesiz dönem (grace)** → tam kullanım, uyarı.
- **Dolmuş** → **salt okunur mod** (veri görünür, düzenlenemez — veri kaybı yok), uyarı.
- **Askıya alınmış** → giriş engelli, ama **veri dışa aktarma seçeneği** (veri sahibinin hakkı).
- Koltuk dolduysa → yeni psikolog atanamaz, uyarı.

### 4.3 Yönetici Paneli
- Klinik ekle, lisans ata/uzat/askıya al/iptal et.
- IBAN tahsilatını elle kaydet.
- Koltuk ve depolama kullanımı, süresi dolanlar, aktif kiracı sayısı.
- Bu ekran **müşterilere açık olmamalı** (ayrı admin uygulaması veya korumalı route).

---

# 🟠 BÖLÜM 5 — PWA OLARAK KULLANILABİLİRLİK

Telefona kurulacağı için iOS/Android tarayıcı davranışları doğrudan müşteriyi etkiler.

### 5.1 iOS Safari Depolama Silme Risibi
- Ana ekrana **eklenmemiş** PWA'larda Safari, 7 gün etkileşimsizlik sonrası yerel verileri silebilir.
- Psikolog haftada bir bile açmazsa yerel veri kaybolabilir. (Sunucuyu tek doğruluk kaynağı yapınca bu risk **ortadan kalkar**.)
- **Yapılacak:** Ana ekrana eklemeyi teşvik eden ilk açılış ekranı; sunucu-öncelikli veri modeli.

### 5.2 Güncelleme ve Önbellek
- PWA'da kullanıcı yeni sürümü **kontrol edemez**. Mevcut zorla yenileme veri kaybı yaratıyor (1.5).
- **Yapılacak:** Sürüm kontrolü + kullanıcı onaylı yenileme + sürüm sabitleme stratejisi.

### 5.3 Çevrimdışı Davranış
- Uygulama çevrimdışıyken ne yapabiliyor, kaç süre veri tutuyor, kullanıcıya bildiriliyor mu? Net tanımlı değil.
- **Yapılacak:** Açık çevrimdışı göstergesi, çakışma çözümü.

### 5.4 Performans
- Büyük dosyalar, düşük uçlu telefonlarda akıcılık test edilmeli.

---

# 🟠 BÖLÜM 6 — GÜVENLİK VE KVKK

Veri Türkiye'de kalmayacak → yurt dışı aktarım riski düştü, ama dokümanlar şart:

- [ ] **KVKK Aydınlatma Metni** — yurt dışında işlendiğini açıkça belirtmeli
- [ ] **Gizlilik Politikası** web sayfası
- [ ] **Kullanım Koşulları / Hizmet Şartları**
- [ ] **Abonelik Sözleşmesi** (aylık kira, fesih, iade, koltuk iadesi)
- [ ] **Veri İşleme Sözleşmesi**
- [ ] **Açık rıza metni** (sağlık verisi = özel nitelikli, ayrı açık rıza zorunlu)
- [ ] **İade/iptal politikası**
- [ ] **Onay sürümü ve zaman damgası kaydı**

**Teknik açıklar:**

- **6.1 Yerel veri şifresiz** — web'de `localStorage` düz metin; tarayıcıya erişen biri tüm kayıtları okur. IndexedDB'ye geçişle birlikte duyarlı alanların şifrelenmesi değerlendirilmeli.
- **6.2 Zayıf hash** — `lib/data/crypto_utils.dart:14` tek tur SHA-256, maliyet faktörü yok. Argon2id veya bcrypt.
- **6.3 Web güvenlik başlıkları yok** — `scripts/vercel.json` sadece cache. CSP (XSS), HSTS, `X-Frame-Options` eklensin.
- **6.4 Denetim kaydı yok** — KVKK md. 12. Kim neye ne zaman baktı/değiştirdi kaydı tutulmuyor. Klinik müşterileri için de güven verir.
- **6.5 Hesap silme yok** — KVKK md. 11. Hiçbir silme fonksiyonu yok. Saklama süresi ve abonelik bitince ne olacağı kuralı gerekli.
- **6.6 Yumuşak silme yok** — silinen kayıt kalıcı gidiyor, kurtarma yok. `deleted_at` + geri dönüşüm kutusu.

---

# 🟡 BÖLÜM 7 — KOD KALİTESİ VE BAKIM

- [ ] `diagnosis_codes.dart` **5.040 satır** (muhtemelen salt veri → veritabanına taşı)
- [ ] `clients_tab.dart` 2.521 · `forms_tab.dart` 2.160 · `appointments_tab.dart` 1.768 · `main.dart` 1.482 → bileşenlere böl
- [ ] `main_psych.dart` → `main_psy_backup.dart`'i import ediyor ("backup" adı kafa karıştırıcı)
- [ ] State yönetimi sadece `ChangeNotifier`; ölçeklenirse `Riverpod`/`Bloc` değerlendir
- [ ] Testler zayıf (2 dosya). Eksik: **veri kaybı senkronizasyon testleri**, kota testleri, RLS/tenant izolasyon testleri
- [ ] `analysis_options.yaml` gevşek → `strict-casts`/`strict-raw-types` aç, `flutter analyze --fatal-infos` CI'da zorunlu
- [ ] **Bu ortamda Flutter SDK yok — `flutter analyze` çalıştırılamadı.** Başlamadan önce analiz temizliği yapılmalı.
- [ ] `CHANGELOG.md` yok; sürümleme disiplini yok (`1.0.0+1` sabit)
- [ ] İki giriş noktası (danışan / psikolog) ayrı domain altında sunulmalı

---

# 🟢 BÖLÜM 8 — SAĞLAM OLAN VE KORUNMASI GEREKENLER

- [x] RLS politikaları detaylı, sütun bazlı GRANT ile daraltılmış
- [x] Danışan tarafı `SECURITY DEFINER` RPC'lerle sınırlandırılmış
- [x] Eşleşme kodu tahmin edilemez, salt okunur RPC ile sahipleniliyor
- [x] `service_role` anahtarı istemciye verilmiyor
- [x] Anahtarlar `--dart-define` ile veriliyor (workflow hariç — düzeltilmeli)
- [x] Yerel-öncelikli mimari (ağ yokken de çalışır) — **v2'de sunucu-öncelikli olmalı**
- [x] Yazma kuyruğu var (dayanıklı değil ama mantık doğru)
- [x] Bozuk uzak veri yerelin üzerine yazılmıyor
- [x] Web'de SPA rewrite ve cache stratejisi düşünülmüş
- [x] Testler var, CI'da çalışıyor
- [x] Lisanslı ölçekler (BDI-II vb.) sorumlu şekilde placeholder bırakılmış

---

# 📋 ÖNERİLEN SIRALAMA

## Aşama 1 — Veri Kaybını Durdur (en acil)
> Bu bitmeden **tek bir müşteri bile alınmamalı**. Klinik kayıt kaybı hukuki ve itibari felakettir.

1. **Kalıcı yazma kuyruğu + senkron durum göstergesi** (1.2) — en kritik, en ucuz
2. **Kaydedilmemiş veri koruması + güvenli PWA güncellemesi** (1.5)
3. **`localStorage` → IndexedDB + akıllı PDF/doküman yönetimi** (1.1)
4. **Kayıt bazlı senkronizasyon + çakışma çözümü** (1.3)
5. Çakışma/veri kaybı testleri

## Aşama 2 — Erişilebilirlik
6. Hata izleme + kritik hata bildirimi (2.2)
7. Otomatik yedek + **geri yükleme provası** (2.3)
8. Prod/staging ayrımı, plan yükseltme, limit alarmı (2.1)
9. Kendi SMTP (OTP giriş için gerekli)
10. Yük testi + uptime izleme

## Aşama 3 — Çok Kiracı (Klinik Kiralama)
11. `organizations` + `memberships` şeması + **RLS tenant izolasyonu**
12. Üyelik/rol ekranı, asistan için kısmi erişim
13. Yönetici paneli (lisans, koltuk, ödeme kaydı, kullanım)
14. Psikolog ayrılırsa veri devri

## Aşama 4 — Lisans
15. Lisans/ödeme/denetim tabloları
16. Uygulamada lisans kontrolü + salt okunur mod
17. Koltuk ve depolama kotası kontrolü

## Aşama 5 — Hukuki (paralel, senin tarafında)
18. KVKK aydınlatma metni (**yurt dışı işleme belirtilmeli**)
19. Abonelik sözleşmesi + koltuk iadesi + iptal/iade politikası
20. Açık rıza metni, onay sürüm kaydı
21. Veri silme talebi ve saklama süresi politikası
22. E-fatura planı

## Aşama 6 — PWA ve Ürün
23. Ana ekrana eklemeyi teşvik, sürüm yönetimi
24. Tam JSON yedek al / geri yükle
25. Randevu hatırlatmaları (e-posta/SMS)
26. Genel arama
27. Kodun bölünmesi, test kapsamı

## Aşama 7 — Büyüme
28. Fiyat/plan yapısı ve depolama kotaları
29. Beyaz etiket (white-label) opsiyonu
30. Çoklu dil

---

# ❓ Hâlâ Netleşmesi Gerekenler

1. ~~Mevcut müşteri verisi~~ ✅ **Yok** — sadece kendi test verin. Temiz kırılma yapılabilir.
2. ~~Psikolog başına kaç danışan~~ ✅ **8/gün** — iş yükü hesabı yapıldı.
3. ~~Kurumda asistan olacak mı~~ ➖ **Henüz bilinmiyor** — `role` alanı şimdi ekleniyor, arayüz sonra.
4. **Psikolog başına ortalama kaç belge yükleniyor?** (Kota tanımı için gerekli — şu an bilinmiyor, varsayım kullandım)
5. **Fatura kesilecek mi, e-arşiv mi?** (Muhasebeciyle teyit)
6. **Hukukçu var mı?** (KVKK + abonelik sözleşmesi)
7. **99 TL'ye tek seferlik kurulum/destek ücreti eklenecek mi?** (8 danışan/gün + kurumsal müşteri = ciddi destek yükü; bu maliyetsiz değil)
8. **Kaç ay kazanması hedefleniyor?** (Altyapı yatırımının geri dönüş süresi)

---

*Bu liste canlı bir dokümandır. Onayladığında Aşama 1'den başlanacaktır.*
