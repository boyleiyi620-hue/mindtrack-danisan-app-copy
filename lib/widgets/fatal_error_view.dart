import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Flutter'ın üretim varsayılan boş/gri hata görünümünün yerine kullanılan
/// güvenli ekran. Teknik ayrıntı kullanıcıya sızdırılmaz; ayrıntı yalnızca
/// debug modunda loglanır.
class FatalErrorView extends StatelessWidget {
  const FatalErrorView({super.key, required this.details});

  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    if (kDebugMode) FlutterError.presentError(details);
    return Material(
      color: const Color(0xFFF5FAFA),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                color: Color(0xFFB54848),
                size: 42,
              ),
              const SizedBox(height: 14),
              const Text(
                'Bu ekran yüklenemedi.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF194643),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Verileriniz korunuyor. Sayfayı yenileyip tekrar deneyin.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF52716D)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
