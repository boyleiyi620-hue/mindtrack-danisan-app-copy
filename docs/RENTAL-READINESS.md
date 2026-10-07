# Kiralama öncesi yayın kontrolü

Bu uygulama içinde abonelik veya otomatik ödeme bulunmaz. Aylık bedel IBAN ile tahsil edilecekse her klinik için lisans kaydı ve ödeme dekontu platform yöneticisi tarafından tutulmalıdır.

## Yayından önce zorunlu işlemler

1. `supabase/migrations/20261007140000_privacy_storage_audit.sql` migration'ını üretim Supabase projesinde çalıştırın.
2. `mindtrack-pdfs` bucket'ının **public olmadığını** ve Storage politikalarının yalnızca oturum sahibinin UUID klasörüne izin verdiğini test edin.
3. İki ayrı psikolog hesabıyla danışan, kayıt, PDF ve audit kayıtlarının birbirine görünmediğini test edin.
4. Bir danışan hesabında bilgilendirme/onam metninin gerçek klinik metinle değiştirilmiş olduğunu, sürüm ve zaman damgasının kaydedildiğini doğrulayın.
5. Üretim ve staging için ayrı Supabase projeleri ve Vercel ortam değişkenleri kullanın. Preview ortamına gerçek klinik veri koymayın.
6. Lisans başlangıç/bitiş tarihlerini ve IBAN ödeme kaydını yönetici tarafından doğrulayın; süresi biten lisansın erişim politikasını canlıda test edin.

## Veri sorumlusu tarafından sağlanacak metinler

Her kiracı kendi veri sorumlusu bilgilerini, işleme amaçlarını ve hukuki sebepleri, alıcı/aktarımı, saklama süresini, başvuru kanalını ve özel nitelikli veri açıklamasını hukukçu onayıyla uygulamaya eklemelidir. Aydınlatma metni ile açık rıza metni ayrı tutulmalıdır. Uygulamadaki onam ekranı bu metnin sürüm ve zaman kaydını tutar; hukuki metnin yerine geçmez.

## Operasyon

- Supabase yedek/PITR, alarm, SMTP ve erişim kayıtlarını üretimde etkinleştirin.
- Kullanıcı silme, veri dışa aktarma ve saklama süresi dolan kayıtların imhası için işletim prosedürü belirleyin.
- Tarayıcı önbelleğinin cihaz güvenliğine bağlı olduğunu kabul edin; ortak cihazlarda oturumu kapatın ve cihaz şifrelemesi kullanın.
