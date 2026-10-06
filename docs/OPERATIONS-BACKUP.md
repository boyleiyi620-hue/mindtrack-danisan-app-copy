# MindTrack yedekleme ve geri yükleme operasyonu

Bu depodaki `psychologist_record_history` migration'ı her kayıt güncelleme veya
silme işleminden önce eski sürümü append-only geçmişe alır. Bu, yanlış silme ve
son değişikliği geri alma için uygulama seviyesinde ek korumadır; tek başına
veritabanı felaket yedeği değildir.

## Canlı Supabase kurulumu

1. Migration'ları staging Supabase projesine uygula.
2. Bir test hesabı ile danışan ve randevu oluştur, güncelle, sil.
3. `psychologist_record_history` satırlarının oluştuğunu doğrula.
4. `restore_psychologist_record(history_id)` RPC'si ile yalnızca test kaydını
   geri yükle ve istemcinin yeni `record_version` aldığını doğrula.
5. Supabase projesinde PITR/günlük yedekleme planını etkinleştir ve saklama
   süresini klinik veri politikasına göre belirle.
6. Ayda en az bir kez ayrı bir staging projesine geri yükleme provası yap;
   kayıt sayısı, erişim politikaları ve uygulama açılışı kontrol edilmeden
   provayı başarılı sayma.

## Sınırlar

- Uygulama istemcisi PITR'ı etkinleştiremez veya veritabanı yedeğini kendi
  başına geri yükleyemez; bu işlem Supabase yönetim yetkisi gerektirir.
- PDF/Belge dosyaları Storage yedeği kapsamı içinde ayrıca doğrulanmalıdır.
- Geçmiş tablo büyüdükçe saklama ve arşivleme politikası uygulanmalıdır.
