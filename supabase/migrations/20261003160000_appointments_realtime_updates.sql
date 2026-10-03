-- UPDATE olaylarının eski ve yeni satır bilgileriyle yayınlanmasını sağlar.
-- Böylece danışan ve psikolog ekranları ortak randevu satırındaki onay/iptal
-- değişikliklerini filtreli websocket kanallarına bağlı kalmadan alabilir.
alter table public.appointments replica identity full;
