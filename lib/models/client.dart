/// Danışan kaydı — web sürümü veri yapısıyla uyumlu.
class Client {
  final String id;

  /// Danışan uygulamasındaki Supabase kullanıcısının UUID'si.
  /// Eski yerel kayıtlar için boş kalabilir.
  String clientUserId;
  String name;
  String email;
  String phone;
  String birthDate;
  String gender;
  List<String> tags;

  /// Danışana atanan DSM-5-TR / ICD-10-CM tanı kodları.
  List<String> diagnosisCodes;
  String notes;
  String status; // active | paused | archived
  double sessionFee; // Varsayılan seans ücreti
  SafetyPlan? safety;
  double createdAt;
  double updatedAt;

  Client({
    required this.id,
    this.clientUserId = '',
    required this.name,
    this.email = '',
    this.phone = '',
    this.birthDate = '',
    this.gender = '',
    List<String>? tags,
    List<String>? diagnosisCodes,
    this.notes = '',
    this.status = 'active',
    this.sessionFee = 0.0,
    this.safety,
    double? createdAt,
    double? updatedAt,
  }) : tags = tags ?? [],
       diagnosisCodes = diagnosisCodes ?? [],
       createdAt =
           createdAt ?? DateTime.now().millisecondsSinceEpoch.toDouble(),
       updatedAt =
           updatedAt ??
           createdAt ??
           DateTime.now().millisecondsSinceEpoch.toDouble();

  bool get hasSafety =>
      safety != null &&
      (safety!.warnings.isNotEmpty ||
          safety!.coping.isNotEmpty ||
          safety!.contacts.isNotEmpty ||
          safety!.emergency.isNotEmpty);

  Map<String, dynamic> toJson() => {
    'id': id,
    'clientUserId': clientUserId,
    'name': name,
    'email': email,
    'phone': phone,
    'birthDate': birthDate,
    'gender': gender,
    'tags': tags,
    'diagnosisCodes': diagnosisCodes,
    'notes': notes,
    'status': status,
    'sessionFee': sessionFee,
    'safety': safety?.toJson(),
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };

  factory Client.fromJson(Map<String, dynamic> j) => Client(
    id: j['id'] as String,
    clientUserId: j['clientUserId'] as String? ?? '',
    name: j['name'] as String? ?? '',
    email: j['email'] as String? ?? '',
    phone: j['phone'] as String? ?? '',
    birthDate: j['birthDate'] as String? ?? '',
    gender: j['gender'] as String? ?? '',
    tags: (j['tags'] as List?)?.map((e) => e.toString()).toList() ?? [],
    diagnosisCodes:
        (j['diagnosisCodes'] as List?)?.map((e) => e.toString()).toList() ?? [],
    notes: j['notes'] as String? ?? '',
    status: j['status'] as String? ?? 'active',
    sessionFee: (j['sessionFee'] as num?)?.toDouble() ?? 0.0,
    safety: j['safety'] == null
        ? null
        : SafetyPlan.fromJson(j['safety'] as Map<String, dynamic>),
    createdAt: (j['createdAt'] as num?)?.toDouble() ?? 0,
    updatedAt: (j['updatedAt'] as num?)?.toDouble() ?? 0,
  );

  String get initials {
    final parts = name
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

/// Kriz / Güvenlik planı — web sürümü `safety` alanıyla uyumlu.
class SafetyPlan {
  String warnings;
  String coping;
  String contacts;
  String emergency;
  double updatedAt;

  SafetyPlan({
    this.warnings = '',
    this.coping = '',
    this.contacts = '',
    this.emergency = '',
    double? updatedAt,
  }) : updatedAt =
           updatedAt ?? DateTime.now().millisecondsSinceEpoch.toDouble();

  Map<String, dynamic> toJson() => {
    'warnings': warnings,
    'coping': coping,
    'contacts': contacts,
    'emergency': emergency,
    'updatedAt': updatedAt,
  };

  factory SafetyPlan.fromJson(Map<String, dynamic> j) => SafetyPlan(
    warnings: j['warnings'] as String? ?? '',
    coping: j['coping'] as String? ?? '',
    contacts: j['contacts'] as String? ?? '',
    emergency: j['emergency'] as String? ?? '',
    updatedAt: (j['updatedAt'] as num?)?.toDouble() ?? 0,
  );
}
