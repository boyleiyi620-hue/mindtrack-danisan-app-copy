/// Uzak senkronizasyonun görünür durumu.
///
/// Psikolog hangi anda verinin sunucuya güvenle gittiğini görebilmelidir:
/// senkronizasyon sessizce başarısız olduğunda fark edilemezse, yazılan
/// kayıtlar cihazda kalır ve başka bir cihazdan açıldığında kaybolmuş görünür.
enum SyncPhase {
  /// Her şey sunucuda; bekleyen değişiklik yok.
  idle,

  /// Şu anda sunucuya yazılıyor.
  syncing,

  /// Değişiklik yapıldı, yazma sıraya alındı veya sırada.
  pending,

  /// Cihaz çevrimdışı; veri güvenle bu cihazda duruyor.
  offline,

  /// Yazma denendi ve başarısız oldu; tekrar denenecek.
  error,
}

/// Senkronizasyonun anlık görüntüsü — arayüz bunu dinleyip gösterir.
class SyncStatus {
  const SyncStatus({
    this.phase = SyncPhase.idle,
    this.failures = 0,
    this.lastSyncedAt,
    this.lastErrorAt,
    this.message,
  });

  final SyncPhase phase;

  /// Üst üste başarısız deneme sayısı. Sıfırlandıkça hata mesajı temizlenir.
  final int failures;

  /// Başarılı son yazmanın zamanı.
  final DateTime? lastSyncedAt;

  /// Son başarısız denemenin zamanı.
  final DateTime? lastErrorAt;

  /// Hata veya uyarı metni (sunucudan gelen veya yerel açıklama).
  final String? message;

  /// Bekleyen iş var mı (yazılıyor, sırada ya da hata verdi).
  bool get hasPendingWork =>
      phase == SyncPhase.pending ||
      phase == SyncPhase.syncing ||
      phase == SyncPhase.error;

  /// Kullanıcıya gösterilecek kısa etiket.
  String get label {
    switch (phase) {
      case SyncPhase.idle:
        return 'Sunucuda';
      case SyncPhase.syncing:
        return 'Kaydediliyor…';
      case SyncPhase.pending:
        return 'Bekliyor…';
      case SyncPhase.offline:
        return 'Çevrimdışı';
      case SyncPhase.error:
        return 'Tekrar denenecek';
    }
  }
}
