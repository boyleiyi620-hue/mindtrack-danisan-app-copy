==============================================================
  MindTrack — Windows PC'de Flutter ile APK Derleme Rehberi
  (Adım Adım · Tamamen Çalışır Yol)
==============================================================

Bu rehberde, psikolog uygulamasının Flutter kaynak kodunu Windows
bilgisayarında derleyip telefonuna KURULUM dosyası olarak APK
çıkaracaksın. Tüm adımları sırayla uygula.

----------------------------------------------------------------
BÖLÜM 0 — ELİNDEKİ DOSYALAR
----------------------------------------------------------------
- MindTrack-FLUTTER-KAYNAK.zip  -> Flutter kaynak kodu
  ZIP'i açınca:  flutter\mindtrack\  klasörü çıkacak.
  Bu klasör projedir; aşağıda hep bu klasörü kullanacağız.
  Örnek konum:  C:\src\mindtrack\flutter\mindtrack
  (Yolun içinde TÜRKÇE KARAKTER VE BOŞLUK OLMASIN: "Yeni klasör" değil,
   "mindtrack" gibi basit bir yol kullan.)

----------------------------------------------------------------
----------------------------------------------------------------
----------------------------------------------------------------
BÖLÜM 0.5 — SUPABASE BİLGİLERİNİ HAZIRLA (ÖNCE BU)
----------------------------------------------------------------
ÖNEMLİ: Uygulama artık Firebase değil, Supabase kullanıyor. Verilerinin
bulutta saklanması için bir Supabase projesi gerekiyor. Bu kurulum
proje klasöründeki  SUPABASE-KURULUM.md  dosyasında anlatılıyor.
Önce o dosyayı aç ve BÖLÜM 0 → 4 arasını tamamla.

Ardından şu iki değeri bul ve bir yere not et:

  SUPABASE_URL       =  https://aqswdmhwqhrsempoiqfv.supabase.co
  SUPABASE_PUBLISHABLE_KEY  =  panelde verilen "sb_publishable_…" publishable anahtar
  SUPABASE_PUBLISHABLE_KEY  =  panelde verilen "sb_publishable_…" publishable anahtar

  DİKKAT: "service_role" veya "secret" yazan anahtarı BURAYA YAZMA.
  O anahtar veritabanının tamamını açar; sizde olmamalıdır.

Bu iki değeri BÖLÜM 3'teki derleme komutuna yazacaksın.

BÖLÜM 1 — BİLGİSAYARA FLUTTER'İ KUR
----------------------------------------------------------------
1) Flutter SDK indir:
   - https://docs.flutter.dev/get-started/install/windows adresini aç
   - "Flutter SDK" zip dosyasını indir (büyüktür, yaklaşık 1 GB açılışı)
   - ZIP'i aç ve klasörü C:\src\flutter olarak taşı (örnek)
     Yani:  C:\src\flutter\bin\flutter.bat  şeklinde görünsün.

2) Flutter'i Windows'a tanıt (PATH):
   - Windows arama çubuğuna: "ortam değişkenlerini düzenle" yaz, aç
   - "Ortam Değişkenleri..." butonuna bas
   - Üstteki "Kullanıcı değişkenleri"nden "Path"i seç -> "Düzenle"
   - "Yeni" -> şunu ekle:  C:\src\flutter\bin   -> Tamam
   - Yeni bir Komut İstemi (cmd) penceresi AÇ (eski pencerelerde geçerli olmaz)
   - `flutter --version` yaz. Sürüm bilgisi gelirse kurulum tamam.

3) Android Studio kur:
   - https://developer.android.com/studio adresinden "Android Studio" indir ve kur
   - Kurulum sihirbazında "Android SDK", "Android SDK Command-line Tools",
     "Android SDK Platform-Tools", "Android SDK Platform" seçenekleri
     işaretli gelsin (varsayılan işaretlidir)
   - İlk açılışta "SDK bileşenlerini indir" diye sorarsa kabul et.
   - Android Studio'yu ilk kez açıp kapat (SDK'yı hazırlasın diye).

4) Kontrol:
   - cmd'de:  `flutter doctor`
   - Android Studio ve Android SDK satırlarında "✓" işareti görene kadar
     düzeltmeleri yap:
       - Eksikse:  `flutter doctor --android-licenses`  çalıştır,
         karşısına çıkan her lisans için "y" yaz ve Enter'a bas.
   - "✓" işaretleri varsa devam et.

----------------------------------------------------------------
BÖLÜM 2 — PROJEYİ AÇ VE HAZIRLA
----------------------------------------------------------------
5) ZIP'i aç. Şu klasörü bul:  flutter\mindtrack
   - Örnek:  C:\src\mindtrack\flutter\mindtrack
   - İçinde pubspec.yaml dosyası olduğundan emin ol.

6) O klasörde komut penceresi aç:
   - Windows Gezgini'nde klasöre gir
   - Üstteki adres çubuğuna "cmd" yaz, Enter'a bas
   - (veya klasörün içinde Shift + sağ tık -> "Terminali burada aç")

7) Paketleri indir:
   - Şu komutu yaz:          flutter pub get
   - "Got dependencies!" yazarsa tamam. (İnternet gerekir)

8) Hata kontrolü:
   - Şu komutu yaz:          flutter analyze
   - "No issues found!" görmelisin. Eğer uyarılar çıkarsa devam edebilirsin;
     "error" satırı varsa bana ilet.

----------------------------------------------------------------
BÖLÜM 3 — APK DERLE (EN ÖNEMLİ ADIM)
----------------------------------------------------------------
9) Önce BÖLÜM 0.5'teki iki değeri yerine koy, sonra komutu çalıştır.

   PSİKOLOG APK'sı için şu komutu yaz:

     flutter build apk --release --flavor psychologist --dart-define=SUPABASE_URL="https://aqswdmhwqhrsempoiqfv.supabase.co" --dart-define=SUPABASE_PUBLISHABLE_KEY="sb_publishable_ugqE_bZ_IyNedJMk1I_saA_-eMtQAjE"

   - Tırnak işaretlerini de yazmayı unutma.
   - --dart-define=... KISMı OLMAZSA APK AÇILIR AMA GİRİŞ YAPAMAZSIN.
   - İLK ÇALIŞTIRMADA GRADLE VE MOTOR DOSYALARI İNER; 5-20 DK SÜREBİLİR.
     İnternet açık olsun, pencereyi kapatma, beklet.
   - En sonda şuna benzer bir satır çıkmalı:
     "✓ Built build\app\outputs\flutter-apk\psychologist-release.apk"

   (DANİŞAN APK'sı istiyorsan --flavor psychologist yerine
    --flavor client yaz.)

10) APK'nın yeri:
   -  flutter\mindtrack\build\app\outputs\flutter-apk\psychologist-release.apk
   - Bu dosya telefona kuracağın kurulum dosyasıdır (~50-90 MB olur,
     internetten çekilen normal Flutter motoruyla).

    İstersen daha küçük dosya (isteğe bağlı):
    - flutter build apk --release --flavor psychologist --split-per-abi
      (--dart-define=... kısımlarını da yine eklemeyi unutma)
    - Çıkışta 3 ayrı APK olur; telefonların çoğu arm64-v8a kullanır:
      psychologist-arm64-v8a-release.apk  (bunu kur)

----------------------------------------------------------------
BÖLÜM 4 — TELEFONA KURULUM (İKİ YOLDAN BİRİ)
----------------------------------------------------------------
YOL A — USB KABLO İLE (EN GARANTİLİ, İZİN SORDURMAZ)
----------------------------------------------------
11) Telefonda Geliştirici seçeneklerini aç:
    - Ayarlar -> Telefon hakkında -> "Derleme numarası"na 7 KEZ dokun
    - "Geliştirici oldunuz" yazısı çıkar
12) Ayarlar -> Sistem -> Geliştirici seçenekleri:
    - "USB hata ayıklama"yı AÇ
13) Telefonu USB kabloyla bilgisayara bağla:
    - Bildirimde "USB ile hata ayıklamaya izin ver?" -> İzin ver
      (her zaman işaretli gelsin)
14) PC'de komut penceresinde yaz:
    - adb devices
    - Telefon "device" olarak listelenmeli. Listelenmezse:
      adb'in yolu: %LOCALAPPDATA%\Android\Sdk\platform-tools
      (Android Studio kurunca adb otomatik gelir; cmd'de adb yoksa
       o klasörü de Path'e ekle)
15) Kurulum komutu:
    - adb install -r "C:\src\mindtrack\flutter\mindtrack\build\app\outputs\flutter-apk\psychologist-release.apk"
    - En sonda "Success" yazarsa KURULDU.
    - Telefon ana ekranında "MindTrack" ikonunu bul ve AÇ.

YOL B — APK'YI TELEFONA TAŞIYIP KUR
-----------------------------------
16) psychologist-release.apk dosyasını telefona taşı:
    - USB ile bağlayıp "Dosya aktarımı" modunu seç, APK'yı
      "İndirilenler" klasörüne kopyala
    - VEYA Google Drive / kendine mesaj ile telefona indir
17) Telefonda: Dosyalar (Files by Google) -> İndirilenler
    -> psychologist-release.apk dosyasına dokun
    - İlk seferde "Bu kaynaktan izin ver" sorarsa: anahtarı AÇ
      (Ayarlar -> Uygulamalar -> Dosyalar -> Bilinmeyen uygulamaları
       yükle -> "Bu kaynağa izin ver")
    - "Yükle" -> kurulunca "Aç"

----------------------------------------------------------------
BÖLÜM 5 — SIK KARŞILAŞILAN SORUNLAR
----------------------------------------------------------------
- "cmdline-tools component is missing":
    Android Studio'yu güncelle / SDK Manager'dan Command-line Tools kur,
    sonra: flutter doctor --android-licenses
- Gradle yavaş veya indirme hatası:
    İnternetin açık olduğundan emin ol; virüs programı/güvenlik duvarı
    engelliyorsa izin ver; sonra tekrar: flutter build apk --release --flavor psychologist --dart-define=...
- "INSTALL_FAILED_USER_RESTRICTED" hatası:
    Telefonda "Bilinmeyen kaynaklar" izni kapalı demektir.
    YOL A (adb) bunu hiç sormaz; YOL B'de ilgili uygulamaya izin ver.
- "App not installed / paket analiz edilemedi":
    APK'yi yeniden derle; telefona kopyaladığın dosyanın bozuk
    olmadığından emin ol.
- Hata mesajlarını bana yazışırsan çözmene yardım ederim.

----------------------------------------------------------------
BÖLÜM 6 — ÖNEMLİ NOTLAR
----------------------------------------------------------------
- Uygulama varsayılan olarak "debug" anahtarıyla imzalıdır.
  Kendi telefonun için sorun değildir.
- Verilerin önce telefonda tutulur; oturum açtığında Supabase ile
  senkronize edilir. Bu yüzden ilk kullanımda İNTERNET BAĞLANTISI gerekir.
- Supabase ÜCRETSİZ planda çalışır; ücret/abonelik gerekmez. Proje 7 gün
  hareketsiz kalınca duraklatılır; tekrar kullandığında panelden "Restore"
  ile ayağa kalkar.
- E-posta + şifre ile hesap oluşturulur. Parola uygulamada saklanmaz,
  Supabase doğrular. Parolanı unutursan hesabına bir daha erişemezsin.
- Başka psikologlara dağıtacaksan aynı imza anahtarını kullanman
  gerekir (ileride istenirse kendi keystore'unu oluşturmayı da
  adım adım anlatırım).
==============================================================
