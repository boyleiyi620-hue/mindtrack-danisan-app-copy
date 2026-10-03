-- Kullanıcının açıkça istediği sunucu sıfırlaması kapsamında, önceki hatalı
-- sürümlerin bıraktığı tüm bekleyen talepleri kaldır. Planlanmış/geçmiş
-- randevulara dokunulmaz.
delete from public.appointments where status = 'pending';
