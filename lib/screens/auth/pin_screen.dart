import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/account_store.dart';
import '../../data/blob_store.dart';
import '../../data/crypto_utils.dart';
import '../../data/data_store.dart';
import '../../data/mindtrack_backend.dart';
import '../../theme/app_theme.dart';

/// PIN kilidi ekranı — kilitliyken tüm uygulamanın yerini alır.
class PinScreen extends StatefulWidget {
  const PinScreen({
    super.key,
    required this.store,
    required this.data,
    required this.onUnlock,
  });

  final AccountStore store;
  final DataStore data;
  final VoidCallback onUnlock;

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  final _pin = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _tryUnlock() async {
    if (!kIsWeb) {
      final account = widget.store.current;
      if (account == null) {
        widget.store.clearSession();
        Navigator.of(context).pushNamedAndRemoveUntil('/auth', (r) => false);
        return;
      }
      if (checkPin(_pin.text.trim(), account.pinHash, account.salt)) {
        widget.store.setLocked(false);
        widget.onUnlock();
      } else {
        setState(() => _error = 'PIN hatalı. Tekrar deneyin.');
        _pin.clear();
      }
      return;
    }
    if (_busy) return;
    final u = widget.store.current;
    if (u == null) {
      widget.store.clearSession();
      Navigator.of(context).pushNamedAndRemoveUntil('/auth', (r) => false);
      return;
    }
    final pin = _pin.text.trim();
    if (pin.isEmpty) {
      setState(() => _error = 'PIN kodunuzu girin.');
      return;
    }
    if (kIsWeb) {
      final remaining = widget.store.pinLockRemaining(u);
      if (remaining > Duration.zero) {
        final seconds = (remaining.inMilliseconds + 999) ~/ 1000;
        setState(
          () => _error =
              'Çok fazla yanlış deneme. $seconds saniye sonra tekrar deneyin.',
        );
        return;
      }
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final accepted = kIsWeb
          ? await BlobStore.instance.verifyWebPin(pin, u.pinHash, u.salt)
          : checkPin(pin, u.pinHash, u.salt);
      if (accepted) {
        if (kIsWeb) {
          await widget.store.resetPinFailures(u);
          // Existing SHA-256 PIN records stay usable for one successful unlock,
          // then are upgraded to a salted, versioned PBKDF2 hash.
          if (!(u.pinHash?.startsWith(r'pbkdf2-sha256$') ?? false)) {
            u.pinHash = await BlobStore.instance.hashWebPin(pin);
            widget.store.updateUser(u);
            await widget.store.flushUserWrites();
          }
        }
        widget.store.setLocked(false);
        widget.onUnlock();
      } else {
        var error = 'PIN hatalı. Tekrar deneyin.';
        if (kIsWeb) {
          final delay = await widget.store.recordPinFailure(u);
          if (delay > Duration.zero) {
            error =
                'Çok fazla yanlış deneme. ${delay.inSeconds} saniye bekleyin.';
          }
        }
        _pin.clear();
        if (mounted) setState(() => _error = error);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = kIsWeb
              ? 'PIN güvenli biçimde doğrulanamadı. Yeniden deneyin.'
              : 'PIN doğrulanamadı. Yeniden deneyin.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    if (!kIsWeb) {
      widget.store.clearSession();
      Navigator.of(context).pushNamedAndRemoveUntil('/auth', (r) => false);
      return;
    }
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (kIsWeb) {
        // Never discard an unsynced clinical snapshot: this operation only
        // returns after a confirmed remote save and encrypted-cache removal.
        await widget.data.prepareForLogout();
        try {
          await MindTrackBackend.instance.signOut();
        } catch (_) {
          // Local data is already safely synced and removed from this browser.
        }
      }
      widget.store.clearSession();
      widget.data.load();
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/auth', (r) => false);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Senkronizasyon tamamlanamadı; kayıtlar silinmedi ve çıkış yapılmadı. Bağlantıyı kontrol edip yeniden deneyin.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    Icons.lock_outline,
                    color: AppColors.primary,
                    size: 30,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'MindTrack Kilitli',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Devam etmek için PIN\'inizi girin.',
                  style: TextStyle(fontSize: 13.5, color: AppColors.muted),
                ),
                const SizedBox(height: 22),
                TextField(
                  controller: _pin,
                  obscureText: true,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [_DigitsOnlyFormatter()],
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22, letterSpacing: 10),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '••••',
                    hintStyle: TextStyle(
                      color: AppColors.muted.withValues(alpha: .5),
                    ),
                  ),
                  onSubmitted: (_) => _tryUnlock(),
                ),
                const SizedBox(height: 10),
                if (_error != null)
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.danger,
                    ),
                  ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: _busy ? null : _tryUnlock,
                  child: Text(
                    _busy ? 'Kontrol ediliyor…' : 'Aç',
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _busy ? null : _logout,
                  child: const Text('Çıkış Yap', style: TextStyle()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DigitsOnlyFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.text.isEmpty
        ? newValue
        : newValue.copyWith(
            text: newValue.text.replaceAll(RegExp('[^0-9]'), ''),
          );
  }
}
