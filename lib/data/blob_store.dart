/// Büyük yerel veri parçalarının deposu.
///
/// Psikologun klinik kaydı yılda onlarca megabayta ulaşabilir. Tarayıcının
/// `localStorage` alanı ~5 MB ile sınırlı olduğu için bu kayıt web'de
/// IndexedDB'de tutulur; diğer platformlarda SharedPreferences aynı işi görür.
///
/// Okuma senkron çalışır (depo belleğe yüklendiği için), yazma arka planda
/// tamamlanır. Böylece ekranların mevcut senkron okuma alışkanlığı bozulmaz.
///
/// Kullanım:
/// ```dart
/// await BlobStore.instance.init();   // uygulama açılışında bir kez
/// BlobStore.instance.set('anahtar', 'değer');
/// ```
library;

export 'blob_store_stub.dart'
    if (dart.library.js_interop) 'blob_store_web.dart';
