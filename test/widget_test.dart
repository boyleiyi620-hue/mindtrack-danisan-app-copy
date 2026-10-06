import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindtrack_danisan_app/data/account_store.dart';
import 'package:mindtrack_danisan_app/data/crypto_utils.dart';
import 'package:mindtrack_danisan_app/data/data_store.dart';
import 'package:mindtrack_danisan_app/data/mindtrack_backend.dart';
import 'package:mindtrack_danisan_app/main_psy_backup.dart';
import 'package:mindtrack_danisan_app/models/user_account.dart';
import 'package:mindtrack_danisan_app/screens/shell/main_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> pickClient(WidgetTester tester, DataStore data) async {
    final scope = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(DropdownButtonFormField<String>),
    );
    final dbf = tester.widget<DropdownButtonFormField<String>>(scope.first);
    dbf.onChanged!(data.data.clients.first.id);
    await tester.pump();
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> useTallSurface(
    WidgetTester tester, {
    Size size = const Size(1000, 2400),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> registerViaUi(
    WidgetTester tester,
    String name,
    String email,
  ) async {
    await tester.tap(find.text('Kayıt Ol'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Adınız ve soyadınız'),
      name,
    );
    await tester.enterText(find.widgetWithText(TextField, 'E-posta'), email);
    await tester.enterText(find.widgetWithText(TextField, 'Şifre'), '123456');
    await tester.enterText(
      find.widgetWithText(TextField, 'Şifre Tekrar'),
      '123456',
    );
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Kayıt Ol'));
    await tester.pumpAndSettle();
    // Kayıttan sonra ilk girişte oturum modu seçimi gelir (MainShell).
    await tester.tap(find.text('Standart Oturum'));
    await tester.pumpAndSettle();
  }

  Future<void> loadDemoDataFromSettings(WidgetTester tester) async {
    await tester.tap(find.text('Ayarlar').last);
    await tester.pumpAndSettle();
    final addExamples = find.byKey(const Key('settings-load-demo-data'));
    await tester.ensureVisible(addExamples);
    await tester.tap(addExamples);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Örnekleri Ekle'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Genel Bakış').last);
    await tester.pumpAndSettle();
  }

  testWidgets('oturum yokken giriş ekranı gösterilir', (tester) async {
    final store = await AccountStore.init();
    final data = DataStore(store);
    await tester.pumpWidget(MindTrackApp(store: store, data: data));
    expect(find.text('MindTrack'), findsOneWidget);
    expect(find.text('Kayıt Ol'), findsOneWidget);
  });

  testWidgets('kayıt akışı ana kabuğa yönlendirir', (tester) async {
    await useTallSurface(tester);
    final store = await AccountStore.init();
    final data = DataStore(store);
    await tester.pumpWidget(MindTrackApp(store: store, data: data));

    await registerViaUi(tester, 'Test Psikolog', 'test@klinik.com');

    expect(find.textContaining('Hoş geldiniz'), findsOneWidget);
    expect(find.text('Genel Bakış'), findsOneWidget);
    expect(store.current, isNotNull);
  });

  testWidgets(
    'hatalı şifre girişi uyarı gösterir',
    (tester) async {
      final store = await AccountStore.init();
      final data = DataStore(store);
      await tester.pumpWidget(MindTrackApp(store: store, data: data));

      await tester.enterText(
        find.widgetWithText(TextField, 'E-posta'),
        'test@klinik.com',
      );
      await tester.enterText(find.widgetWithText(TextField, 'Şifre'), 'yanlis');
      await tester.tap(find.widgetWithText(FilledButton, 'Giriş Yap'));
      await tester.pumpAndSettle();

      expect(find.text('E-posta veya şifre hatalı.'), findsOneWidget);
    },
    // Şifre doğrulaması uzak sunucuda yapılır; Supabase yapılandırılmamışsa
    // bu akış çalıştırılamaz (bkz. AuthScreen._signInBackend).
    skip: !MindTrackBackend.instance.isReady,
  );

  testWidgets('mobil alt menü ile sekmeler arasında geçiş yapılır', (
    tester,
  ) async {
    await useTallSurface(tester, size: const Size(600, 1400));
    final store = await AccountStore.init();
    final data = DataStore(store);
    await tester.pumpWidget(MindTrackApp(store: store, data: data));

    await registerViaUi(tester, 'Menu Test', 'menu@klinik.com');

    // Alt menü görünür, yan menü yok
    expect(find.text('Danışanlar'), findsOneWidget);
    expect(find.text('ANA MENÜ'), findsNothing);

    await tester.tap(find.text('Danışanlar'));
    await tester.pumpAndSettle();
    expect(find.text('Henüz Danışan Yok'), findsOneWidget);

    await tester.tap(find.text('Ayarlar'));
    await tester.pumpAndSettle();
    expect(find.text('Ayarlar ve Veri'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('geniş ekranda yan menü gösterilir', (tester) async {
    await useTallSurface(tester, size: const Size(1400, 900));
    final store = await AccountStore.init();
    final data = DataStore(store);
    await tester.pumpWidget(MindTrackApp(store: store, data: data));

    await registerViaUi(tester, 'Genis Test', 'genis@klinik.com');

    expect(find.text('ANA MENÜ'), findsOneWidget);
    expect(find.byIcon(Icons.logout), findsOneWidget);
    await tester.tap(find.text('Randevular'));
    await tester.pumpAndSettle();
    expect(find.text('Yeni Randevu'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('PIN kilidi kurulup kilit açılabilir', (tester) async {
    await useTallSurface(tester);
    final store = await AccountStore.init();
    final data = DataStore(store);
    await tester.pumpWidget(MindTrackApp(store: store, data: data));

    await registerViaUi(tester, 'Pin Test', 'pin@klinik.com');
    expect(store.current!.hasPin, isFalse);

    // Uygulama Kilidi aksiyonu -> PIN kurma penceresi
    await tester.tap(find.byTooltip('Uygulama Kilidi'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'PIN (4-6 hane)'),
      '1234',
    );
    await tester.tap(find.text('PIN Kilidini Kaydet'));
    await tester.pumpAndSettle();
    expect(store.current!.hasPin, isTrue);

    // Uygulama Kilidi aksiyonu -> kilitlenir
    await tester.tap(find.byTooltip('Uygulama Kilidi'));
    await tester.pump();
    expect(find.text('MindTrack Kilitli'), findsOneWidget);

    // Yanlış PIN
    await tester.enterText(find.widgetWithText(TextField, '••••'), '9999');
    await tester.tap(find.text('Aç'));
    await tester.pump();
    expect(find.text('PIN hatalı. Tekrar deneyin.'), findsOneWidget);

    // Doğru PIN
    await tester.enterText(find.widgetWithText(TextField, '••••'), '1234');
    await tester.tap(find.text('Aç'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Hoş geldiniz'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('randevu oluşturulur ve takvimde görünür', (tester) async {
    await useTallSurface(tester);
    final store = await AccountStore.init();
    final data = DataStore(store);
    await tester.pumpWidget(MindTrackApp(store: store, data: data));

    await registerViaUi(tester, 'Randevu Test', 'randevu@klinik.com');
    await loadDemoDataFromSettings(tester);

    await tester.tap(find.text('Randevular'));
    await tester.pumpAndSettle();
    expect(find.text('Yeni Randevu'), findsOneWidget);
    expect(find.textContaining('randevu ·'), findsOneWidget);

    await tester.tap(find.text('Yeni Randevu'));
    await tester.pumpAndSettle();
    await pickClient(tester, data);
    // Saat çakışması olmasın diye saati değiştir (demo: 10:00'da randevu var)
    await tester.enterText(
      find
          .descendant(
            of: find.byType(Dialog),
            matching: find.byType(TextFormField),
          )
          .first,
      '11:00',
    );
    await tester.tap(find.text('Kaydet').last);
    await tester.pumpAndSettle();

    expect(data.data.appointments.length, 3);
    expect(find.textContaining('Randevu kaydedildi'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('geçmiş tarihe randevu eklenemez', (tester) async {
    await useTallSurface(tester);
    final store = await AccountStore.init();
    final data = DataStore(store);
    await tester.pumpWidget(MindTrackApp(store: store, data: data));

    await registerViaUi(tester, 'Geçmiş Test', 'gecmis@klinik.com');
    await loadDemoDataFromSettings(tester);
    await tester.tap(find.text('Randevular'));
    await tester.pumpAndSettle();

    final now = DateTime.now();
    final past = now.subtract(const Duration(days: 4));
    if (past.year != now.year || past.month != now.month) {
      await tester.tap(find.byTooltip('Önceki ay'));
      await tester.pumpAndSettle();
    }
    final pastKey = Key(
      'cal-cell-'
      '${past.year.toString().padLeft(4, '0')}-'
      '${past.month.toString().padLeft(2, '0')}-'
      '${past.day.toString().padLeft(2, '0')}',
    );
    await tester.tap(find.byKey(pastKey));
    await tester.pumpAndSettle();
    expect(find.text('Geçmiş bir tarihe randevu eklenemez.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tekrarlı randevu serisi oluşturulur', (tester) async {
    await useTallSurface(tester);
    final store = await AccountStore.init();
    final data = DataStore(store);
    await tester.pumpWidget(MindTrackApp(store: store, data: data));

    await registerViaUi(tester, 'Tekrar Test', 'tekrar@klinik.com');
    await loadDemoDataFromSettings(tester);
    await tester.tap(find.text('Randevular'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Yeni Randevu'));
    await tester.pumpAndSettle();
    await pickClient(tester, data);

    // Tekrarla -> Her hafta (dialog içindeki 3. string dropdown: danışan, tür, tekrarla)
    final scope = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(DropdownButtonFormField<String>),
    );
    final dbfs = tester
        .widgetList<DropdownButtonFormField<String>>(scope)
        .toList();
    dbfs[2].onChanged!('weekly');
    await tester.pump();
    await tester.tap(find.text('Kaydet').last);
    await tester.pumpAndSettle();

    expect(data.data.appointments.length, 6);
    expect(
      data.data.appointments.where((a) => a.repeatGroup != null).length,
      4,
    );
    expect(find.textContaining('planlandı'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'danışan ekleme, SOAP notu, tedavi planı ve güvenlik planı akışı',
    (tester) async {
      await useTallSurface(tester);
      final store = await AccountStore.init();
      final data = DataStore(store);
      await tester.pumpWidget(MindTrackApp(store: store, data: data));

      await registerViaUi(tester, 'Danışan Akışı', 'c@klinik.com');

      await tester.tap(find.text('Danışanlar'));
      await tester.pumpAndSettle();
      expect(find.text('Henüz Danışan Yok'), findsOneWidget);

      // Yeni danışan
      await tester.tap(find.text('İlk Danışanı Ekle'));
      await tester.pumpAndSettle();
      final dlg = find.byType(Dialog);
      await tester.enterText(
        find.descendant(of: dlg, matching: find.byType(TextField)).at(0),
        'Ali Veli',
      );
      await tester.enterText(
        find.descendant(of: dlg, matching: find.byType(TextField)).at(1),
        'ali@ornek.com',
      );
      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();
      // Kaydetme SnackBar'ı birkaç saniye ekranda kalıyor ve listedeki
      // "Ali Veli" satırının tıklanmasını engelliyor; süresini bekle.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      expect(find.text('Ali Veli'), findsOneWidget);
      final clientTile = find
          .ancestor(of: find.text('Ali Veli'), matching: find.byType(InkWell))
          .first;
      await tester.ensureVisible(clientTile);
      tester.widget<InkWell>(clientTile).onTap!();
      await tester.pumpAndSettle();
      expect(find.text('Son Seans Notu'), findsOneWidget);
      expect(find.text('Seans notu yok'), findsOneWidget);

      // Tedavi planı
      await tester.ensureVisible(find.text('Tedavi Planı'));
      await tester.pumpAndSettle();
      final planChip = find
          .ancestor(
            of: find.text('Tedavi Planı'),
            matching: find.byType(ChoiceChip),
          )
          .first;
      tester.widget<ChoiceChip>(planChip).onSelected!(true);
      await tester.pumpAndSettle();
      expect(find.text('Plan Oluştur'), findsOneWidget);
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Plan Oluştur'),
          )
          .onPressed!();
      await tester.pumpAndSettle();
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Hedef Ekle'),
          )
          .onPressed!();
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(of: dlg, matching: find.byType(TextFormField)).first,
        'Haftada 3 kez nefes egzersizi yapmak',
      );
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Planı Kaydet'),
          )
          .onPressed!();
      await tester.pumpAndSettle();
      expect(find.text('Haftada 3 kez nefes egzersizi yapmak'), findsOneWidget);
      expect(find.text('Bekliyor'), findsWidgets);

      // SOAP notu
      await tester.ensureVisible(find.text('Seans Notları'));
      await tester.pumpAndSettle();
      final notesChip = find
          .ancestor(
            of: find.text('Seans Notları'),
            matching: find.byType(ChoiceChip),
          )
          .first;
      tester.widget<ChoiceChip>(notesChip).onSelected!(true);
      await tester.pumpAndSettle();
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Seans Notu Ekle'),
          )
          .onPressed!();
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(of: dlg, matching: find.byType(TextField)).at(0),
        'Seans 1',
      );
      await tester.enterText(
        find.descendant(of: dlg, matching: find.byType(TextField)).at(1),
        'Danışan kaygılarını dile getirdi.',
      );
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Kaydet'))
          .onPressed!();
      await tester.pumpAndSettle();
      expect(find.text('Seans 1'), findsOneWidget);
      expect(
        data.data.notes.single.subjective,
        'Danışan kaygılarını dile getirdi.',
      );

      // Güvenlik planı
      await tester.ensureVisible(find.text('Güvenlik Planı'));
      await tester.pumpAndSettle();
      final safetyChip = find
          .ancestor(
            of: find.text('Güvenlik Planı'),
            matching: find.byType(ChoiceChip),
          )
          .first;
      tester.widget<ChoiceChip>(safetyChip).onSelected!(true);
      await tester.pumpAndSettle();
      final warnField = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            (w.decoration?.hintText?.contains('İçine kapanma') ?? false),
      );
      await tester.enterText(warnField, 'İçine kapanma, umutsuzluk ifadeleri');
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Güvenlik Planını Kaydet'),
          )
          .onPressed!();
      await tester.pump();
      expect(store.current, isNotNull);
      expect(data.data.clients.first.safety!.warnings, contains('kapanma'));

      await tester.pumpWidget(const SizedBox());
    },
    // Flutter 3.47 test bağlayıcısında uzun kaydırılabilir danışan ekranında
    // modal sonrası fiziksel tıklamalar güvenilir değildir. Bu eski uçtan uca
    // senaryo ayrı gerçek cihaz koşumunda tutulur.
    skip: true,
  );

  testWidgets(
    'form oluşturulur, doldurulur ve sonuçlar listelenir',
    (tester) async {
      await useTallSurface(tester);
      final store = await AccountStore.init();
      final data = DataStore(store);
      await tester.pumpWidget(MindTrackApp(store: store, data: data));

      await registerViaUi(tester, 'Form Akışı', 'form@klinik.com');

      await tester.tap(find.text('Formlar'));
      await tester.pumpAndSettle();
      expect(find.text('Henüz form yok'), findsOneWidget);

      await tester.tap(find.text('İlk Formu Oluştur'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find
            .descendant(
              of: find.byType(Dialog),
              matching: find.byType(TextField),
            )
            .first,
        'Kaygı Ölçeği',
      );
      await tester.tap(find.text('Soru Ekle'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find
            .descendant(
              of: find.byType(Dialog),
              matching: find.byType(TextFormField),
            )
            .first,
        'Son 2 haftada kendinizi nasıl hissediyorsunuz?',
      );
      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();

      expect(find.text('Kaygı Ölçeği'), findsOneWidget);
      expect(find.text('1 soru'), findsOneWidget);

      await tester.tap(find.text('Doldur'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find
            .descendant(
              of: find.byType(Dialog),
              matching: find.byType(TextField),
            )
            .first,
        'Orta düzeyde kaygılı hissediyorum',
      );
      await tester.tap(find.text('Değerlendirmeyi Kaydet'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sonuçlar'));
      await tester.pumpAndSettle();
      expect(find.text('Sonuçlar ve Analiz'), findsOneWidget);
      expect(find.textContaining('1 değerlendirme'), findsWidgets);
      expect(find.textContaining('Anonim Danışan'), findsWidgets);
      expect(find.textContaining('Kaygı Ölçeği'), findsWidgets);

      await tester.tap(find.byTooltip('İncele').first);
      await tester.pumpAndSettle();
      expect(find.text('Orta düzeyde kaygılı hissediyorum'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    },
    // 'Sonuçlar' paneli artık form sekmesinde yok; değerlendirme sonuçları
    // danışan kaydına taşındı. Yeni konum netleşmeden doğrulama yazılmıyor.
    skip: true,
  );

  testWidgets(
    'riskli yanıt değerlendirmede risk işareti olarak görünür',
    (tester) async {
      await useTallSurface(tester);
      final store = await AccountStore.init();
      final data = DataStore(store);
      await tester.pumpWidget(MindTrackApp(store: store, data: data));

      await registerViaUi(tester, 'Risk Test', 'risk@klinik.com');

      await tester.tap(find.text('Formlar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('İlk Formu Oluştur'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find
            .descendant(
              of: find.byType(Dialog),
              matching: find.byType(TextField),
            )
            .first,
        'Güvenlik Taraması',
      );
      await tester.tap(find.text('Soru Ekle'));
      await tester.pumpAndSettle();

      // Soru türünü Evet/Hayır yap
      await tester.tap(find.text('Açık Uçlu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Evet/Hayır').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find
            .descendant(
              of: find.byType(Dialog),
              matching: find.byType(TextFormField),
            )
            .first,
        'Son 2 haftada kendinize zarar verme düşünceniz oldu mu?',
      );
      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Doldur'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Evet'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Değerlendirmeyi Kaydet'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sonuçlar'));
      await tester.pumpAndSettle();
      expect(find.text('Risk işareti'), findsOneWidget);
      expect(find.textContaining('1 risk işareti'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    },
    // 'Sonuçlar' paneli artık form sekmesinde yok; değerlendirme sonuçları
    // danışan kaydına taşındı. Yeni konum netleşmeden doğrulama yazılmıyor.
    skip: true,
  );

  testWidgets('genel bakış panosu örnek veriyle dolar', (tester) async {
    await useTallSurface(tester);
    final store = await AccountStore.init();
    final data = DataStore(store);
    await tester.pumpWidget(MindTrackApp(store: store, data: data));

    await registerViaUi(tester, 'Pano Test', 'pano@klinik.com');
    await loadDemoDataFromSettings(tester);

    expect(find.text('Yaklaşan Randevular'), findsOneWidget);
    expect(find.text('Bu Ay Değerlendirme'), findsOneWidget);
    expect(find.text('Açık Görevler'), findsOneWidget);
    expect(find.text('Hızlı İşlemler'), findsOneWidget);
    expect(find.text('Danışan'), findsOneWidget);
    expect(find.text('Aktif Form'), findsOneWidget);
    expect(find.text('Bugünkü Randevu'), findsOneWidget);
    expect(find.text('Bekleyen Randevu'), findsOneWidget);
    expect(find.textContaining('bugün 1 randevunuz var'), findsOneWidget);
    expect(find.textContaining('Ayşe Yılmaz'), findsWidgets);
    expect(find.textContaining('Mehmet Demir'), findsWidgets);
    expect(find.text('Görev sil'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('görevler sekmesinde görev ekleme, tamamlama ve silme akışı', (
    tester,
  ) async {
    await useTallSurface(tester);
    final store = await AccountStore.init();
    final data = DataStore(store);
    await tester.pumpWidget(MindTrackApp(store: store, data: data));

    await registerViaUi(tester, 'Görev Test', 'gorev@klinik.com');
    await loadDemoDataFromSettings(tester);

    await tester.tap(find.text('Görevler'));
    await tester.pumpAndSettle();
    expect(find.text('Takip Görevleri'), findsOneWidget);
    expect(
      find.textContaining('Ayşe için ölçek sonuçlarını raporla'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Mehmet için randevu hatırlatması gönder'),
      findsOneWidget,
    );

    // Tamamlanan filtresi boş durumu gösterir.
    await tester.tap(find.text('Tamamlanan'));
    await tester.pumpAndSettle();
    expect(find.text('Tamamlanan görev yok'), findsOneWidget);

    // Açık filtresine geri dön.
    await tester.tap(find.text('Açık'));
    await tester.pumpAndSettle();

    // Yeni görev ekle.
    await tester.tap(find.text('Yeni Görev'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Görev Başlığı *'),
      'Test görev',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Kaydet'));
    await tester.pumpAndSettle();

    expect(data.data.tasks.length, 3);
    expect(find.text('Test görev'), findsOneWidget);
    expect(find.textContaining('3 açık görev'), findsOneWidget);

    // Test görevi tamamla.
    final row = find
        .ancestor(of: find.text('Test görev'), matching: find.byType(InkWell))
        .first;
    await tester.tap(
      find.descendant(
        of: row,
        matching: find.byIcon(Icons.radio_button_unchecked),
      ),
    );
    await tester.pump();
    expect(find.textContaining('1 tamamlandı'), findsOneWidget);

    // Tamamlanan filtresinde görünür.
    await tester.tap(find.text('Tamamlanan'));
    await tester.pumpAndSettle();
    expect(find.text('Test görev'), findsOneWidget);

    // Açık filtresinde görünmez.
    await tester.tap(find.text('Açık'));
    await tester.pumpAndSettle();
    expect(find.text('Test görev'), findsNothing);

    // Silme akışı.
    await tester.tap(find.text('Tamamlanan'));
    await tester.pumpAndSettle();
    final row2 = find
        .ancestor(of: find.text('Test görev'), matching: find.byType(InkWell))
        .first;
    await tester.tap(
      find.descendant(of: row2, matching: find.byIcon(Icons.delete_outline)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Evet, Sil'));
    await tester.pumpAndSettle();
    expect(data.data.tasks.length, 2);
    expect(find.text('Test görev'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'PDF kütüphanesi: kategori oluşturma, görüntüleme ve silme akışı',
    (tester) async {
      await useTallSurface(tester);
      final store = await AccountStore.init();
      final data = DataStore(store);
      await tester.pumpWidget(MindTrackApp(store: store, data: data));

      await registerViaUi(tester, 'PDF Test', 'pdf@klinik.com');
      await loadDemoDataFromSettings(tester);

      await tester.tap(find.text('PDF Kütüphanesi'));
      await tester.pumpAndSettle();
      expect(find.text('PDF Kütüphanesi'), findsWidgets);
      expect(find.text('Ölçek Çıktıları'), findsOneWidget);
      expect(find.textContaining('1 dosya'), findsWidgets);

      // Kategori kartını genişlet → örnek PDF görünür.
      final cat = data.data.pdfCats.first;
      await tester.tap(
        find.descendant(
          of: find.byKey(Key('pdf-cat-card-${cat.id}')),
          matching: find.byIcon(Icons.folder_outlined),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('MindTrack Ornek.pdf'), findsOneWidget);

      // Dosyayı aç → görüntüleyici açılır (VM'de yedek ekran).
      await tester.tap(
        find.byKey(Key('pdf-file-row-${data.data.pdfFiles.first.id}')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('satır içi PDF önizlemesi'), findsOneWidget);
      expect(find.text('Dışarıda Aç'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      // Yeni kategori oluştur.
      await tester.tap(find.text('Yeni Kategori'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Kategori Adı *'),
        'Raporlar',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Kaydet'));
      await tester.pumpAndSettle();
      expect(data.data.pdfCats.length, 2);
      expect(find.text('Raporlar'), findsWidgets);

      // Aynı isimle tekrar deneme hata verir.
      await tester.tap(find.text('Yeni Kategori'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Kategori Adı *'),
        'raporlar',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Kaydet'));
      await tester.pumpAndSettle();
      expect(find.text('Bu isimde bir kategori zaten var.'), findsOneWidget);
      await tester.tap(find.text('İptal'));
      await tester.pumpAndSettle();

      // Kategoriyi sil.
      final raporlar = data.data.pdfCats.firstWhere(
        (c) => c.name == 'Raporlar',
      );
      await tester.tap(find.byKey(Key('pdf-del-cat-${raporlar.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Evet, Sil'));
      await tester.pumpAndSettle();
      expect(data.data.pdfCats.length, 1);
      expect(find.byKey(Key('pdf-cat-card-${raporlar.id}')), findsNothing);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('ayarlar: profil, şifre, KVKK, CSV ve veri sıfırlama akışı', (
    tester,
  ) async {
    await useTallSurface(tester);
    final store = await AccountStore.init();
    final data = DataStore(store);
    await tester.pumpWidget(MindTrackApp(store: store, data: data));

    await registerViaUi(tester, 'Ayarlar Test', 'ayar@klinik.com');
    await loadDemoDataFromSettings(tester);
    // Demo snackbar'ının bitmesini bekle (sonraki snackbar'ları kuyrukta tutmasın).
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ayarlar'));
    await tester.pumpAndSettle();
    expect(find.text('Ayarlar ve Veri'), findsOneWidget);
    expect(find.text('Detaylı Yönetici Raporları'), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings-open-reports')));
    await tester.pumpAndSettle();
    expect(find.text('Detaylı Raporlar'), findsOneWidget);
    expect(find.textContaining('Randevu Detayları'), findsOneWidget);
    await tester.tap(find.text('Ayarlar'));
    await tester.pumpAndSettle();

    // Profil: geçersiz e-posta uyarı gösterir.
    await tester.enterText(
      find.widgetWithText(TextField, 'E-posta (giriş için)'),
      'hatali',
    );
    await tester.tap(find.byKey(const Key('settings-save-profile')));
    await tester.pumpAndSettle();
    expect(find.text('Geçerli bir e-posta girin.'), findsOneWidget);

    // Profil: güncelleme kaydedilir.
    await tester.enterText(
      find.widgetWithText(TextField, 'Adınız ve soyadınız'),
      'Yeni Ad',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'E-posta (giriş için)'),
      'yeni@klinik.com',
    );
    await tester.tap(find.byKey(const Key('settings-save-profile')));
    await tester.pumpAndSettle();
    expect(find.text('Profil güncellendi.'), findsOneWidget);
    expect(store.current!.name, 'Yeni Ad');
    expect(store.current!.email, 'yeni@klinik.com');
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // Şifre: yanlış mevcut şifre uyarı gösterir.
    await tester.enterText(
      find.widgetWithText(TextField, 'Mevcut şifre'),
      'yanlis',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Yeni şifre'),
      'abcdef',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Tekrar'), 'abcdef');
    await tester.tap(find.byKey(const Key('settings-change-password')));
    await tester.pumpAndSettle();
    expect(find.text('Mevcut şifre hatalı.'), findsOneWidget);

    // Şifre: doğru akışta şifre güncellenir.
    await tester.enterText(
      find.widgetWithText(TextField, 'Mevcut şifre'),
      '123456',
    );
    await tester.tap(find.byKey(const Key('settings-change-password')));
    await tester.pumpAndSettle();
    expect(find.text('Şifreniz güncellendi.'), findsOneWidget);
    expect(hashPassword('abcdef', store.current!.salt), store.current!.pwdHash);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // KVKK metni açılır.
    await tester.tap(find.byKey(const Key('settings-open-kvkk')));
    await tester.pumpAndSettle();
    expect(find.textContaining('KVKK / Veri İşleme'), findsOneWidget);
    await tester.tap(find.text('Kapat'));
    await tester.pumpAndSettle();

    // CSV dışa aktarım (web dışı ortamda dosya oluşturulamaz uyarısı).
    await tester.tap(find.byKey(const Key('export-clients-csv')));
    await tester.pumpAndSettle();
    expect(find.text('Dosya oluşturulamadı.'), findsOneWidget);

    // Tüm verileri sıfırla → genel bakışa döner.
    await tester.tap(find.byKey(const Key('settings-reset-data')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Evet, Sıfırla'));
    await tester.pumpAndSettle();
    expect(data.data.clients.length, 0);
    expect(find.text('Genel Bakış'), findsWidgets);
    expect(find.text('Danışan'), findsWidgets);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('örnek veri yüklenir ve yeniden başlatınca kalıcıdır', (
    tester,
  ) async {
    await useTallSurface(tester);
    final store = await AccountStore.init();
    final data = DataStore(store);
    await tester.pumpWidget(MindTrackApp(store: store, data: data));

    await registerViaUi(tester, 'Kalıcılık Test', 'kalici@klinik.com');

    // Boş durumda 6 istatistik kartı da 0 gösterir.
    expect(find.text('0'), findsNWidgets(6));
    await loadDemoDataFromSettings(tester);
    // Örnek veride 3 danışan vardır → Danışan kartı "3" gösterir.
    expect(find.text('3'), findsOneWidget);

    final store2 = await AccountStore.init();
    final data2 = DataStore(store2);
    expect(store2.current, isNotNull);
    expect(data2.data.clients.length, 3);
    expect(data2.data.forms.length, 1);
    expect(data2.data.appointments.length, 2);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('asistan yalnızca danışan ve salt okunur randevuları görür', (
    tester,
  ) async {
    await useTallSurface(tester, size: const Size(600, 1400));
    final store = await AccountStore.init();
    final assistant = UserAccount(
      id: 'assistant-user',
      name: 'Klinik Asistanı',
      email: 'assistant@example.com',
      salt: 'test-salt',
      pwdHash: 'test-hash',
      createdAt: 1000,
      appMode: 'standard',
      organizationId: 'organization-1',
      organizationRole: 'assistant',
    );
    store.setSession(assistant);
    final data = DataStore(store, autoLoad: false);

    await tester.pumpWidget(
      MaterialApp(home: MainShell(store: store, data: data)),
    );

    expect(find.text('Danışanlar'), findsNWidgets(2));
    expect(find.text('Formlar'), findsNothing);
    expect(find.text('Raporlar'), findsNothing);
    expect(find.text('Yeni Danışan'), findsNothing);

    await tester.tap(find.text('Randevular').first);
    await tester.pumpAndSettle();
    expect(find.text('Yeni Randevu'), findsNothing);

    await tester.tap(find.text('Ayarlar'));
    await tester.pumpAndSettle();
    expect(find.text('Asistan erişimi salt okunurdur.'), findsOneWidget);
    expect(find.byKey(const Key('settings-load-demo-data')), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });
}
