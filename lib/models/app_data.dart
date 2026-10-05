import 'appointment.dart';
import 'assessment.dart';
import 'client.dart';
import 'document.dart';
import 'form_entry.dart';
import 'note.dart';
import 'pdf_library.dart';
import 'plan.dart';
import 'task.dart';
import 'finance.dart';

/// Uygulamanın tamamı — tek kullanıcıya ait tüm kayıtlar.
/// Web sürümündeki `emptyData()` yapısıyla birebir uyumlu.
class AppData {
  List<FormEntry> forms;
  List<Client> clients;
  List<Assessment> assessments;
  List<Appointment> appointments;
  List<Note> notes;
  List<Plan> plans;
  List<Task> tasks;
  List<Document> documents;
  List<PdfCategory> pdfCats;
  List<PdfFile> pdfFiles;
  List<Transaction> transactions;
  List<Training> trainings;
  List<FinanceGoal> financeGoals;

  AppData({
    List<FormEntry>? forms,
    List<Client>? clients,
    List<Assessment>? assessments,
    List<Appointment>? appointments,
    List<Note>? notes,
    List<Plan>? plans,
    List<Task>? tasks,
    List<Document>? documents,
    List<PdfCategory>? pdfCats,
    List<PdfFile>? pdfFiles,
    List<Transaction>? transactions,
    List<Training>? trainings,
    List<FinanceGoal>? financeGoals,
  })  : forms = forms ?? [],
        clients = clients ?? [],
        assessments = assessments ?? [],
        appointments = appointments ?? [],
        notes = notes ?? [],
        plans = plans ?? [],
        tasks = tasks ?? [],
        documents = documents ?? [],
        pdfCats = pdfCats ?? [],
        pdfFiles = pdfFiles ?? [],
        transactions = transactions ?? [],
        trainings = trainings ?? [],
        financeGoals = financeGoals ?? [];

  AppData.empty() : this();

  factory AppData.fromJson(Map<String, dynamic> j) => AppData(
        forms: (j['forms'] as List?)
                ?.map((e) => FormEntry.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        clients: (j['clients'] as List?)
                ?.map((e) => Client.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        assessments: (j['assessments'] as List?)
                ?.map((e) => Assessment.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        appointments: (j['appointments'] as List?)
                ?.map((e) => Appointment.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        notes: (j['notes'] as List?)
                ?.map((e) => Note.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        plans: (j['plans'] as List?)
                ?.map((e) => Plan.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        tasks: (j['tasks'] as List?)
                ?.map((e) => Task.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        documents: (j['documents'] as List?)
                ?.map((e) => Document.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        pdfCats: (j['pdfCats'] as List?)
                ?.map((e) => PdfCategory.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        pdfFiles: (j['pdfFiles'] as List?)
                ?.map((e) => PdfFile.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        transactions: (j['transactions'] as List?)
                ?.map((e) => Transaction.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        trainings: (j['trainings'] as List?)
                ?.map((e) => Training.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        financeGoals: (j['financeGoals'] as List?)
                ?.map((e) => FinanceGoal.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );

  Map<String, dynamic> toJson() => {
        'forms': forms.map((e) => e.toJson()).toList(),
        'clients': clients.map((e) => e.toJson()).toList(),
        'assessments': assessments.map((e) => e.toJson()).toList(),
        'appointments': appointments.map((e) => e.toJson()).toList(),
        'notes': notes.map((e) => e.toJson()).toList(),
        'plans': plans.map((e) => e.toJson()).toList(),
        'tasks': tasks.map((e) => e.toJson()).toList(),
        'documents': documents.map((e) => e.toJson()).toList(),
        'pdfCats': pdfCats.map((e) => e.toJson()).toList(),
        'pdfFiles': pdfFiles.map((e) => e.toJson()).toList(),
        'transactions': transactions.map((e) => e.toJson()).toList(),
        'trainings': trainings.map((e) => e.toJson()).toList(),
        'financeGoals': financeGoals.map((e) => e.toJson()).toList(),
      };

  /// Merges a remote snapshot without dropping records created on this
  /// device. Existing IDs remain local-wins until record-level revisions are
  /// available; records present on only one side are preserved from both.
  static AppData mergePreservingLocal(AppData remote, AppData local) {
    final merged = remote.toJson();
    final localJson = local.toJson();
    for (final key in const [
      'forms', 'clients', 'assessments', 'appointments', 'notes', 'plans',
      'tasks', 'documents', 'pdfCats', 'pdfFiles', 'transactions',
      'trainings', 'financeGoals',
    ]) {
      merged[key] = _mergeRecords(
        (merged[key] as List?) ?? const [],
        (localJson[key] as List?) ?? const [],
      );
    }
    return AppData.fromJson(merged);
  }

  static List<Map<String, dynamic>> _mergeRecords(List remote, List local) {
    final result = <Map<String, dynamic>>[
      for (final item in remote)
        if (item is Map) Map<String, dynamic>.from(item),
    ];
    final indexes = <String, int>{};
    for (var i = 0; i < result.length; i++) {
      final key = _recordKey(result[i]);
      if (key != null) indexes[key] = i;
    }
    for (final item in local) {
      if (item is! Map) continue;
      final record = Map<String, dynamic>.from(item);
      final key = _recordKey(record);
      if (key == null) {
        result.add(record);
      } else if (indexes.containsKey(key)) {
        result[indexes[key]!] = record;
      } else {
        indexes[key] = result.length;
        result.add(record);
      }
    }
    return result;
  }

  static String? _recordKey(Map<String, dynamic> record) {
    final value = (record['id'] ?? record['month'])?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }

  Client? clientById(String id) {
    for (final c in clients) {
      if (c.id == id) return c;
    }
    return null;
  }

  FormEntry? formById(String id) {
    for (final f in forms) {
      if (f.id == id) return f;
    }
    return null;
  }

  List<Assessment> assessmentsOf(String clientId) =>
      assessments
          .where((a) => a.clientId == clientId)
          .toList()
        ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));

  List<Note> notesOf(String clientId) => notes
      .where((n) => n.clientId == clientId)
      .toList()
    ..sort((a, b) => b.date.compareTo(a.date));

  List<Appointment> appointmentsOf(String clientId) => appointments
      .where((a) => a.clientId == clientId)
      .toList()
    ..sort((a, b) {
      final c = a.date.compareTo(b.date);
      return c != 0 ? c : a.time.compareTo(b.time);
    });

  List<Plan> plansOf(String clientId) =>
      plans.where((p) => p.clientId == clientId).toList();

  List<Document> documentsOf(String clientId) =>
      documents.where((d) => d.clientId == clientId).toList();
}
