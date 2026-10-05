import 'dart:convert';

/// MindTrack hesabı — kayıtlı psikolog kullanıcısı.
class UserAccount {
  final String id;
  String name;
  String email;
  String clinic;
  String salt;
  String pwdHash;
  String? pinHash;
  int lockTimeout; // dakika; 0 = kapalı
  double lastBackupAt;
  double createdAt;
  String appMode; // 'standard', 'commercial', 'training'
  double defaultSessionFee;
  /// Klinik tenant bağlantısı; eski tek-kullanıcı hesaplarında boş kalabilir.
  String? organizationId;
  String organizationRole; // 'admin', 'psychologist', 'assistant'

  UserAccount({
    required this.id,
    required this.name,
    required this.email,
    this.clinic = '',
    required this.salt,
    required this.pwdHash,
    this.pinHash,
    this.lockTimeout = 0,
    this.lastBackupAt = 0,
    required this.createdAt,
    this.appMode = 'standard',
    this.defaultSessionFee = 0.0,
    this.organizationId,
    this.organizationRole = 'psychologist',
  });

  bool get hasPin => pinHash != null && pinHash!.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'clinic': clinic,
        'salt': salt,
        'pwdHash': pwdHash,
        'pinHash': pinHash,
        'lockTimeout': lockTimeout,
        'lastBackupAt': lastBackupAt,
        'createdAt': createdAt,
        'appMode': appMode,
        'defaultSessionFee': defaultSessionFee,
        'organizationId': organizationId,
        'organizationRole': organizationRole,
      };

  factory UserAccount.fromJson(Map<String, dynamic> j) => UserAccount(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        email: j['email'] as String? ?? '',
        clinic: j['clinic'] as String? ?? '',
        salt: j['salt'] as String? ?? '',
        pwdHash: j['pwdHash'] as String? ?? '',
        pinHash: j['pinHash'] as String?,
        lockTimeout: (j['lockTimeout'] as num?)?.toInt() ?? 0,
        lastBackupAt: (j['lastBackupAt'] as num?)?.toDouble() ?? 0,
        createdAt: (j['createdAt'] as num?)?.toDouble() ?? 0,
        appMode: j['appMode'] as String? ?? 'standard',
        defaultSessionFee: (j['defaultSessionFee'] as num?)?.toDouble() ?? 0.0,
        organizationId: j['organizationId'] as String?,
        organizationRole: j['organizationRole'] as String? ?? 'psychologist',
      );

  String toJsonString() => jsonEncode(toJson());
}
