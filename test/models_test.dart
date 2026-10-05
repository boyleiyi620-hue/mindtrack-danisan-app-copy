import 'package:flutter_test/flutter_test.dart';
import 'package:mindtrack_danisan_app/data/appointment_sync.dart';
import 'package:mindtrack_danisan_app/data/client_deduplication.dart';
import 'package:mindtrack_danisan_app/models/app_data.dart';
import 'package:mindtrack_danisan_app/models/appointment.dart';
import 'package:mindtrack_danisan_app/models/assessment.dart';
import 'package:mindtrack_danisan_app/models/client.dart';
import 'package:mindtrack_danisan_app/models/document.dart';
import 'package:mindtrack_danisan_app/models/form_entry.dart';
import 'package:mindtrack_danisan_app/models/note.dart';
import 'package:mindtrack_danisan_app/models/pdf_library.dart';
import 'package:mindtrack_danisan_app/models/plan.dart';
import 'package:mindtrack_danisan_app/models/task.dart';
import 'package:mindtrack_danisan_app/models/user_account.dart';

void main() {
  test('eski hesaplar klinik alanları olmadan da açılır', () {
    final account = UserAccount.fromJson({
      'id': 'u1',
      'name': 'Psikolog',
      'email': 'p@example.com',
      'salt': 's',
      'pwdHash': 'h',
      'createdAt': 1,
    });

    expect(account.organizationId, isNull);
    expect(account.organizationRole, 'psychologist');
    expect(UserAccount.fromJson(account.toJson()).organizationRole,
        'psychologist');
  });

  test('uzak ve yerel kayıtlar birleştirilirken kayıt kaybı olmaz', () {
    final remote = AppData(
      clients: [Client(id: 'remote', name: 'Uzak')],
      notes: [Note(id: 'same', clientId: 'remote', title: 'Uzak başlık')],
    );
    final local = AppData(
      clients: [Client(id: 'local', name: 'Yerel')],
      notes: [Note(id: 'same', clientId: 'remote', title: 'Yerel başlık')],
    );

    final merged = AppData.mergePreservingLocal(remote, local);

    expect(merged.clients.map((c) => c.id), containsAll(['remote', 'local']));
    expect(merged.notes.single.title, 'Yerel başlık');
  });

  test('AppData JSON gidiş-dönüş kayıpsız çalışır', () {
    final form = FormEntry(
      id: 'f1',
      title: 'Kaygı Ölçeği',
      questions: [
        FormQuestion(id: 'q1', type: 'scale', text: 'Kaygı?', scaleMax: 7),
        FormQuestion(
          id: 'q2',
          type: 'multiple_choice',
          text: 'Uyku?',
          options: ['İyi', 'Kötü'],
        ),
      ],
    );
    final client = Client(
      id: 'c1',
      name: 'Ayşe',
      email: 'a@x.com',
      phone: '555',
      birthDate: '1990-01-01',
      gender: 'Kadın',
      tags: ['Kaygı'],
      notes: 'not',
    );
    final assessment = Assessment(
      id: 'a1',
      clientId: 'c1',
      formId: 'f1',
      answers: {'q1': 4, 'q2': 'İyi'},
      score: 12,
    );
    final appointment = Appointment(
      id: 'ap1',
      date: '2026-08-16',
      time: '10:00',
      clientId: 'c1',
      type: 'therapy',
      status: 'planned',
      durationMin: 50,
      notes: 'n',
      repeatGroup: 'rg',
    );
    final note = Note(
      id: 'n1',
      clientId: 'c1',
      title: 'S1',
      subjective: 's',
      objective: 'o',
      assessment: 'a',
      plan: 'p',
      mood: 'Orta',
    );
    final plan = Plan(id: 'p1', clientId: 'c1', title: 'TP');
    plan.goals.add(
      Goal(id: 'g1', text: 'hedef', category: 'short', status: 'achieved'),
    );
    final task = Task(
      id: 't1',
      text: 'görev',
      clientId: 'c1',
      priority: 'high',
      done: false,
    );
    final doc = Document(
      id: 'd1',
      clientId: 'c1',
      name: 'rapor.pdf',
      dataUrl: 'BASE64',
      size: 10,
    );
    final cat = PdfCategory(id: 'pc1', name: 'Raporlar');
    final pdf = PdfFile(
      id: 'pf1',
      catId: 'pc1',
      name: 'x.pdf',
      dataUrl: 'B64',
      size: 5,
    );

    final original = AppData(
      forms: [form],
      clients: [client],
      assessments: [assessment],
      appointments: [appointment],
      notes: [note],
      plans: [plan],
      tasks: [task],
      documents: [doc],
      pdfCats: [cat],
      pdfFiles: [pdf],
    );

    final restored = AppData.fromJson(original.toJson());

    expect(restored.forms.length, 1);
    expect(restored.forms.first.questions.length, 2);
    expect(restored.forms.first.questions[0].scaleMax, 7);
    expect(restored.forms.first.questions[1].options, ['İyi', 'Kötü']);
    expect(restored.clients.first.tags, ['Kaygı']);
    expect(restored.clients.first.gender, 'Kadın');
    expect(restored.assessments.first.answers['q1'], 4);
    expect(restored.assessments.first.score, 12);
    expect(restored.appointments.first.repeatGroup, 'rg');
    expect(restored.appointments.first.durationMin, 50);
    expect(restored.notes.first.subjective, 's');
    expect(restored.plans.first.goals.first.status, 'achieved');
    expect(restored.tasks.first.priority, 'high');
    expect(restored.documents.first.dataUrl, 'BASE64');
    expect(restored.pdfCats.first.name, 'Raporlar');
    expect(restored.pdfFiles.first.catId, 'pc1');
    expect(restored.clientById('c1')?.name, 'Ayşe');
    expect(restored.formById('f1')?.title, 'Kaygı Ölçeği');
  });

  test('Datetime alanları boş veride güvenli', () {
    final d = AppData.empty().toJson();
    expect(d['clients'], isEmpty);
    expect(AppData.fromJson(d).clients, isEmpty);
  });

  test('ortak randevu kimliği yalnızca talep bağlantısından çözülür', () {
    final shared = Appointment(
      id: 'local-1',
      date: '2026-09-30',
      time: '10:00',
      notes: 'request:remote-uuid',
    );
    final local = Appointment(
      id: 'local-2',
      date: '2026-09-30',
      time: '11:00',
      notes: 'klinik içi not',
    );

    expect(sharedAppointmentId(shared), 'remote-uuid');
    expect(sharedAppointmentId(local), isNull);
  });

  test('aynı e-posta adresli danışanları teke indirip randevuyu taşır', () {
    final data = AppData(
      clients: [
        Client(id: 'c1', name: 'İlk Kayıt', email: '  SAME@gmail.com '),
        Client(
          id: 'c2',
          name: 'İkinci Kayıt',
          email: 'same@gmail.com',
          clientUserId: 'patient-uid',
        ),
      ],
      appointments: [
        Appointment(
          id: 'a1',
          date: '2026-10-03',
          time: '10:00',
          clientId: 'c2',
        ),
      ],
    );

    expect(deduplicateClientsByEmail(data), isTrue);
    expect(data.clients, hasLength(1));
    expect(data.clients.single.id, 'c1');
    expect(data.clients.single.clientUserId, 'patient-uid');
    expect(data.appointments.single.clientId, 'c1');
    expect(deduplicateClientsByEmail(data), isFalse);
  });
}
