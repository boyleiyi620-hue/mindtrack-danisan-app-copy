import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindtrack_danisan_app/main.dart';

Widget _streamErrorBuilder(
  BuildContext context,
  Object error,
  VoidCallback onRetry,
) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text('Liste yüklenemedi.'),
      FilledButton(onPressed: onRetry, child: const Text('Yeniden Dene')),
    ],
  );
}

Future<void> _openUnsavedForm(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const ClientFormDialog(
                taskId: 'task-discard',
                taskData: <String, dynamic>{},
                draft: <String, dynamic>{
                  'title': 'Deneme formu',
                  'questions': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'id': 'answer',
                      'type': 'text',
                      'text': 'Yanıtınız',
                    },
                  ],
                },
              ),
            ),
            child: const Text('Formu Aç'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Formu Aç'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('olmayan danışan profili yükleme ekranında takılı kalmaz', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ClientPatientDataGate(
          streamFactory: () => Stream<Map<String, dynamic>?>.value(null),
          builder: (patient) =>
              Text(patient == null ? 'Eşleşme akışı' : 'Beklenmeyen danışan'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Eşleşme akışı'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('sessiz kalan akışta hata ve yeniden deneme sunulur', (
    tester,
  ) async {
    var subscriptions = 0;
    Stream<Map<String, dynamic>?> neverRespondingStream() {
      subscriptions += 1;
      return Stream<Map<String, dynamic>?>.multi((_) {});
    }

    await tester.pumpWidget(
      MaterialApp(
        home: ClientPatientDataGate(
          streamFactory: neverRespondingStream,
          timeout: const Duration(seconds: 2),
          builder: (_) => const Text('Danışan hazır'),
        ),
      ),
    );
    expect(subscriptions, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(find.text('Danışan bilgileri yüklenemedi.'), findsOneWidget);
    expect(find.text('Yeniden Dene'), findsOneWidget);
    expect(find.textContaining('TimeoutException'), findsNothing);

    await tester.tap(find.text('Yeniden Dene'));
    await tester.pump();

    expect(subscriptions, 2);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('ilk yanıt sonrası sessiz canlı akışta yükleme hatası çıkmaz', (
    tester,
  ) async {
    Stream<Map<String, dynamic>?> streamWithInitialNull() =>
        Stream<Map<String, dynamic>?>.multi((controller) {
          controller.add(null);
        });

    await tester.pumpWidget(
      MaterialApp(
        home: ClientPatientDataGate(
          streamFactory: streamWithInitialNull,
          timeout: const Duration(seconds: 2),
          builder: (patient) =>
              Text(patient == null ? 'Eşleşme akışı' : 'Beklenmeyen danışan'),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Eşleşme akışı'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(find.text('Eşleşme akışı'), findsOneWidget);
    expect(find.text('Danışan bilgileri yüklenemedi.'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'liste akışının ilk yanıtı zaman aşımına uğrayınca yeniden dene sunulur',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ClientInitialStreamGate<List<int>>(
            streamFactory: () => Stream<List<int>>.multi((_) {}),
            timeout: const Duration(seconds: 2),
            errorBuilder: _streamErrorBuilder,
            builder: (_, values) => Text('Veri: ${values.join(', ')}'),
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      expect(find.text('Liste yüklenemedi.'), findsOneWidget);
      expect(find.text('Yeniden Dene'), findsOneWidget);
    },
  );

  testWidgets(
    'yeniden deneme liste akışına yeniden abone olup veriyi getirir',
    (tester) async {
      var subscriptions = 0;
      Stream<List<int>> streamFactory() {
        subscriptions += 1;
        if (subscriptions == 1) return Stream<List<int>>.multi((_) {});
        return Stream<List<int>>.value([42]);
      }

      await tester.pumpWidget(
        MaterialApp(
          home: ClientInitialStreamGate<List<int>>(
            streamFactory: streamFactory,
            timeout: const Duration(seconds: 2),
            errorBuilder: _streamErrorBuilder,
            builder: (_, values) => Text('Veri: ${values.join(', ')}'),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.text('Yeniden Dene'), findsOneWidget);

      await tester.tap(find.text('Yeniden Dene'));
      await tester.pump();
      await tester.pump();

      expect(subscriptions, 2);
      expect(find.text('Veri: 42'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('ilk liste yanıtından sonra sessizlik zaman aşımı oluşturmaz', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ClientInitialStreamGate<List<int>>(
          streamFactory: () => Stream<List<int>>.multi((controller) {
            controller.add([7]);
          }),
          timeout: const Duration(seconds: 2),
          errorBuilder: _streamErrorBuilder,
          builder: (_, values) => Text('Veri: ${values.join(', ')}'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Veri: 7'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(find.text('Veri: 7'), findsOneWidget);
    expect(find.text('Liste yüklenemedi.'), findsNothing);
    expect(find.text('Yeniden Dene'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('girişte eksik alanlar kullanıcıya açıklanır', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    await tester.tap(find.widgetWithText(ElevatedButton, 'Giriş Yap'));
    await tester.pump();

    expect(find.text('E-posta ve şifre alanları gereklidir.'), findsOneWidget);
  });

  testWidgets('geçersiz e-posta giriş isteği başlatmadan bildirilir', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.enterText(find.byType(TextField).at(0), 'gecersiz-adres');
    await tester.enterText(find.byType(TextField).at(1), 'bir-sifre');

    await tester.tap(find.widgetWithText(ElevatedButton, 'Giriş Yap'));
    await tester.pump();

    expect(find.text('Geçerli bir e-posta adresi girin.'), findsOneWidget);
  });

  testWidgets('boş soru listeli form tamamlanamaz', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ClientFormDialog(
            taskId: 'task-1',
            taskData: <String, dynamic>{},
            draft: <String, dynamic>{'title': 'Boş form'},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('yanıtlanabilir soru bulunmuyor'),
      findsOneWidget,
    );
    final submit = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Formu Tamamla ve Gönder'),
    );
    expect(submit.onPressed, isNull);
  });

  testWidgets('geçersiz ölçek sınırı ve metinsel yanıt uygulamayı çökertmez', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ClientFormDialog(
            taskId: 'task-2',
            taskData: <String, dynamic>{
              'structuredAnswers': <String, dynamic>{'scale-question': '4'},
            },
            draft: <String, dynamic>{
              'title': 'Ölçek formu',
              'questions': <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'scale-question',
                  'type': 'scale',
                  'scaleMax': 1,
                },
              ],
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Slider), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('yanıtı değişen form dışarı tıklamayla sessizce kaybolmaz', (
    tester,
  ) async {
    await _openUnsavedForm(tester);
    await tester.enterText(find.byType(TextFormField), 'Önemli yanıt');
    await tester.pump();

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.text('Yanıtlar kaydedilmedi'), findsOneWidget);
    expect(find.text('Forma Dön'), findsOneWidget);

    await tester.tap(find.text('Forma Dön'));
    await tester.pumpAndSettle();
    expect(find.text('Deneme formu'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Yanıtlar kaydedilmedi'), findsOneWidget);
    await tester.tap(find.text('Forma Dön'));
    await tester.pumpAndSettle();
    expect(find.text('Deneme formu'), findsOneWidget);

    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(find.text('Yanıtlar kaydedilmedi'), findsOneWidget);
    await tester.tap(find.text('Değişiklikleri At'));
    await tester.pumpAndSettle();
    expect(find.byType(ClientFormDialog), findsNothing);
  });

  testWidgets('hızlı çift randevu gönderimi tek istek üretir', (tester) async {
    final pendingSubmit = Completer<void>();
    var submissions = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => AppointmentRequestDialog(
                  onSubmit: (_) {
                    submissions += 1;
                    return pendingSubmit.future;
                  },
                ),
              ),
              child: const Text('Randevu dialogunu aç'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Randevu dialogunu aç'));
    await tester.pumpAndSettle();

    final submit = tester
        .widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Randevu Talebi Gönder'),
        )
        .onPressed!;
    submit();
    submit();

    expect(submissions, 1);
    await tester.pump();
    pendingSubmit.complete();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
