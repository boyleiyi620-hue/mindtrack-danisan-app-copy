import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/blob_store.dart';
import '../../data/crypto_utils.dart';
import '../../models/user_account.dart';
import '../../theme/app_theme.dart';

/// PIN kilidi kurma / kaldırma penceresi.
/// `onChanged` hesap kaydedildiğinde, `onLockRequest` kilit istendiğinde çağrılır.
class PinSetupDialog extends StatefulWidget {
  const PinSetupDialog({
    super.key,
    required this.account,
    required this.onChanged,
    this.onLockRequest,
  });

  final UserAccount account;
  final FutureOr<void> Function() onChanged;
  final VoidCallback? onLockRequest;

  @override
  State<PinSetupDialog> createState() => _PinSetupDialogState();

  static Future<void> show(
    BuildContext context, {
    required UserAccount account,
    required FutureOr<void> Function() onChanged,
    VoidCallback? onLockRequest,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => PinSetupDialog(
        account: account,
        onChanged: onChanged,
        onLockRequest: onLockRequest,
      ),
    );
  }
}

class _PinSetupDialogState extends State<PinSetupDialog> {
  final _pin = TextEditingController();
  int _timeout = 5;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final pin = _pin.text.trim();
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      setState(() => _error = 'PIN 4-6 haneli olmalıdır.');
      return;
    }

    final previousHash = widget.account.pinHash;
    final previousTimeout = widget.account.lockTimeout;
    if (!kIsWeb) {
      widget.account.pinHash = hashPassword(pin, widget.account.salt);
      widget.account.lockTimeout = _timeout;
      widget.onChanged();
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      widget.account.pinHash = await BlobStore.instance.hashWebPin(pin);
      widget.account.lockTimeout = _timeout;
      await widget.onChanged();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      widget.account.pinHash = previousHash;
      widget.account.lockTimeout = previousTimeout;
      if (mounted) {
        setState(
          () => _error = 'PIN güvenli biçimde kaydedilemedi. Yeniden deneyin.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _disable() async {
    if (_saving) return;
    final previousHash = widget.account.pinHash;
    final previousTimeout = widget.account.lockTimeout;
    widget.account.pinHash = null;
    widget.account.lockTimeout = 0;

    if (!kIsWeb) {
      widget.onChanged();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Uygulama kilidi kapatıldı.', style: TextStyle()),
        ),
      );
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onChanged();
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Uygulama kilidi kapatıldı.', style: TextStyle()),
          ),
        );
      }
    } catch (_) {
      widget.account.pinHash = previousHash;
      widget.account.lockTimeout = previousTimeout;
      if (mounted) {
        setState(
          () => _error =
              'PIN ayarı güvenli biçimde kaydedilemedi. Yeniden deneyin.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasPin = widget.account.hasPin;
    return AlertDialog(
      title: Row(
        children: [
          const Icon(
            Icons.shield_outlined,
            color: AppColors.primaryDark,
            size: 22,
          ),
          const SizedBox(width: 10),
          const Text('Uygulama Kilidi (PIN)', style: TextStyle(fontSize: 17)),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: hasPin ? _statusView() : _setupView(),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Vazgeç', style: TextStyle()),
        ),
      ],
    );
  }

  Widget _statusView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.check_circle, size: 18, color: AppColors.success),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'PIN aktif — ${widget.account.lockTimeout} dk otomatik kilit',
                style: const TextStyle(fontSize: 14, color: AppColors.text2),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _saving
                  ? null
                  : () {
                      Navigator.of(context).pop();
                      widget.onLockRequest?.call();
                    },
              icon: const Icon(Icons.lock, size: 17),
              label: const Text('Şimdi Kilitle', style: TextStyle()),
            ),
            TextButton(
              onPressed: _saving ? null : _disable,
              child: const Text('PIN\'i Kaldır', style: TextStyle()),
            ),
          ],
        ),
      ],
    );
  }

  Widget _setupView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Belirlenen süre işlem yapılmazsa veya uygulama arka plana alınırsa otomatik kilitlenir.',
          style: TextStyle(fontSize: 13, color: AppColors.muted, height: 1.5),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _pin,
          enabled: !_saving,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          style: const TextStyle(letterSpacing: 6),
          decoration: const InputDecoration(
            labelText: 'PIN (4-6 hane)',
            hintText: '••••',
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _timeout,
          decoration: const InputDecoration(labelText: 'Otomatik kilit süresi'),
          items: const [
            DropdownMenuItem(
              value: 1,
              child: Text('1 dakika', style: TextStyle()),
            ),
            DropdownMenuItem(
              value: 5,
              child: Text('5 dakika', style: TextStyle()),
            ),
            DropdownMenuItem(
              value: 15,
              child: Text('15 dakika', style: TextStyle()),
            ),
            DropdownMenuItem(
              value: 30,
              child: Text('30 dakika', style: TextStyle()),
            ),
          ],
          onChanged: _saving ? null : (v) => setState(() => _timeout = v ?? 5),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: const TextStyle(fontSize: 13, color: AppColors.danger),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(
            _saving ? 'Güvenli kaydediliyor…' : 'PIN Kilidini Kaydet',
            style: const TextStyle(),
          ),
        ),
      ],
    );
  }
}
