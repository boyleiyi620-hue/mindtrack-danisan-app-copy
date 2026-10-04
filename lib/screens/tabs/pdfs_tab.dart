import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../data/data_store.dart';
import '../../models/app_data.dart';
import '../../models/pdf_library.dart';
import '../../theme/app_theme.dart';
import '../../utils/formats.dart';
import '../pdfs/pdf_platform.dart';
import '../pdfs/pdf_viewer_screen.dart';

/// Tek dosya üst sınırı. Klinikte telefonla çekilmiş form fotoğrafları ve
/// taranmış protokoller 2-8 MB'a ulaşabildiği için 2 MB sınırı çok düşüktü.
/// Veri artık `localStorage` yerine IndexedDB'de tutulduğundan bu sınır
/// güvenli bir tavan olarak işlev görür.
const _maxDocBytes = 10 * 1024 * 1024;
const _warnBytes = 8 * 1024 * 1024;

/// PDF Kütüphanesi — kategoriler, PDF yükleme ve görüntüleme.
class PdfsTab extends StatefulWidget {
  const PdfsTab({super.key, required this.data});

  final DataStore data;

  @override
  State<PdfsTab> createState() => _PdfsTabState();
}

class _PdfsTabState extends State<PdfsTab> {
  String? _openCatId;
  bool _busy = false;

  AppData get _d => widget.data.data;

  @override
  Widget build(BuildContext context) {
    final cats = _d.pdfCats;
    final files = _d.pdfFiles;
    final totalSize = files.fold<int>(
      0,
      (s, f) => s + (f.size > 0 ? f.size : 0),
    );
    final openCat = _openCatId == null
        ? null
        : _d.pdfCats.where((c) => c.id == _openCatId).firstOrNull;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(cats.length, files.length, totalSize),
              const SizedBox(height: 12),
              _privacyBanner(),
              const SizedBox(height: 16),
              if (cats.isEmpty)
                _emptyState()
              else ...[
                _categoryGrid(cats),
                if (openCat != null) ...[
                  const SizedBox(height: 16),
                  _catFilesSection(openCat),
                ],
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(int catCount, int fileCount, int totalSize) {
    return LayoutBuilder(
      builder: (context, bc) {
        final wide = bc.maxWidth >= 720;
        final head = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'PDF Kütüphanesi',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$catCount kategori · $fileCount dosya · ${fmtBytes(totalSize)} · '
              'Toplam kayıt ${widget.data.sizeLabel}',
              style: const TextStyle(fontSize: 13.5, color: AppColors.muted),
            ),
          ],
        );
        final btn = FilledButton.icon(
          onPressed: _openCatEditor,
          icon: const Icon(Icons.create_new_folder_outlined, size: 17),
          label: const Text('Yeni Kategori', style: TextStyle()),
        );
        if (!wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              head,
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: btn),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: head),
            btn,
          ],
        );
      },
    );
  }

  Widget _privacyBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primarySofter,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border2),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, size: 16, color: AppColors.primaryDark),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              "PDF'ler bağlı sunucu hesabında saklanır ve bu cihazda görüntüleme için önbelleğe alınır. "
              'Bir dosyaya tıkladığınızda içeriği açılır; kategori kartına tıklayarak dosya listesini genişletebilirsiniz.',
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.text2,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppSizes.radius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.folder_open_outlined,
            size: 44,
            color: AppColors.muted,
          ),
          const SizedBox(height: 12),
          const Text(
            'Henüz kategori yok',
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Dokümanlarınızı düzenlemek için önce "Yeni Kategori" ile bir kategori oluşturun, ardından içine PDF yükleyin.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.muted),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _openCatEditor,
            icon: const Icon(Icons.add, size: 17),
            label: const Text('Yeni Kategori', style: TextStyle()),
          ),
        ],
      ),
    );
  }

  Widget _categoryGrid(List<PdfCategory> cats) {
    return LayoutBuilder(
      builder: (context, bc) {
        final cols = bc.maxWidth >= 960
            ? 3
            : bc.maxWidth >= 640
            ? 2
            : 1;
        final cardW = (bc.maxWidth - 14.0 * (cols - 1)) / cols;
        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final c in cats)
              SizedBox(width: cardW, child: _categoryCard(c)),
          ],
        );
      },
    );
  }

  Widget _categoryCard(PdfCategory c) {
    final files = _d.pdfFiles.where((f) => f.catId == c.id).toList();
    final size = files.fold<int>(0, (s, f) => s + (f.size > 0 ? f.size : 0));
    final active = _openCatId == c.id;
    return Container(
      key: Key('pdf-cat-card-${c.id}'),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppSizes.radius),
        border: Border.all(
          color: active ? AppColors.primary : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() {
              _openCatId = active ? null : c.id;
            }),
            borderRadius: BorderRadius.circular(AppSizes.radius),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.accentSoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.folder_outlined,
                      size: 19,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.text,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${files.length} dosya · ${fmtBytes(size)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    active ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: AppColors.muted,
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: Key('pdf-upload-${c.id}'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 38),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      side: const BorderSide(color: AppColors.primary),
                    ),
                    onPressed: _busy ? null : () => _pickPdf(c.id),
                    icon: const Icon(
                      Icons.upload_file_outlined,
                      size: 15,
                      color: AppColors.primary,
                    ),
                    label: const Text(
                      'PDF Yükle',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  key: Key('pdf-rename-cat-${c.id}'),
                  tooltip: 'Yeniden Adlandır',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _openCatEditor(cat: c),
                  icon: const Icon(
                    Icons.edit_outlined,
                    size: 16,
                    color: AppColors.muted,
                  ),
                ),
                IconButton(
                  key: Key('pdf-del-cat-${c.id}'),
                  tooltip: 'Kategoriyi Sil',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _confirmDeleteCat(c),
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 16,
                    color: AppColors.danger,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _catFilesSection(PdfCategory c) {
    final files = _d.pdfFiles.where((f) => f.catId == c.id).toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppSizes.radius),
        border: Border.all(color: AppColors.primary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                const Icon(
                  Icons.folder_outlined,
                  size: 17,
                  color: AppColors.primaryDark,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${files.length} dosya',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  key: Key('pdf-upload-section-${c.id}'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    side: const BorderSide(color: AppColors.primary),
                  ),
                  onPressed: _busy ? null : () => _pickPdf(c.id),
                  icon: const Icon(
                    Icons.upload_file_outlined,
                    size: 14,
                    color: AppColors.primary,
                  ),
                  label: const Text(
                    'PDF Yükle',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (files.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Icon(
                    Icons.description_outlined,
                    size: 34,
                    color: AppColors.muted,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Bu kategoride henüz PDF yok',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '"PDF Yükle" butonuyla bu kategoriye dosya ekleyin.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                  ),
                ],
              ),
            )
          else
            for (var i = 0; i < files.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: 66),
              _fileRow(files[i], c),
            ],
        ],
      ),
    );
  }

  Widget _fileRow(PdfFile f, PdfCategory cat) {
    return InkWell(
      key: Key('pdf-file-row-${f.id}'),
      onTap: () => _openPdf(f),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.dangerSoft,
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(
                Icons.picture_as_pdf_outlined,
                size: 18,
                color: AppColors.danger,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    f.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${cat.name} · ${fmtDateTime(f.addedAt)} · ${fmtBytes(f.size)}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              key: Key('pdf-open-${f.id}'),
              tooltip: 'Görüntüle',
              visualDensity: VisualDensity.compact,
              onPressed: () => _openPdf(f),
              icon: const Icon(
                Icons.visibility_outlined,
                size: 17,
                color: AppColors.primary,
              ),
            ),
            if (pdfInlineSupported) ...[
              IconButton(
                key: Key('pdf-newtab-${f.id}'),
                tooltip: 'Yeni Sekmede Aç',
                visualDensity: VisualDensity.compact,
                onPressed: () => _openExternal(f),
                icon: const Icon(
                  Icons.open_in_new,
                  size: 16,
                  color: AppColors.muted,
                ),
              ),
              IconButton(
                key: Key('pdf-download-${f.id}'),
                tooltip: 'İndir',
                visualDensity: VisualDensity.compact,
                onPressed: () => _download(f),
                icon: const Icon(
                  Icons.download_outlined,
                  size: 16,
                  color: AppColors.muted,
                ),
              ),
            ],
            IconButton(
              key: Key('pdf-del-${f.id}'),
              tooltip: 'Sil',
              visualDensity: VisualDensity.compact,
              onPressed: () => _confirmDeleteFile(f),
              icon: const Icon(
                Icons.delete_outline,
                size: 16,
                color: AppColors.danger,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- Aksiyonlar ----------------

  Future<void> _pickPdf(String catId) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final f = await FilePicker.pickFile(
        dialogTitle: 'PDF Seç',
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (f == null) return;
      final name = f.name.trim().isEmpty ? 'belge.pdf' : f.name.trim();
      final bytes = await f.readAsBytes();
      if (bytes.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Dosya okunamadı.', style: TextStyle()),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      if (!name.toLowerCase().endsWith('.pdf')) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Yalnızca PDF dosyası yüklenebilir.',
              style: TextStyle(),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      if (bytes.length > _maxDocBytes) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Dosya başına en fazla 10 MB olabilir.',
              style: TextStyle(),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      final rec = PdfFile(
        id: widget.data.newId(),
        catId: catId,
        name: name,
        size: bytes.length,
        dataUrl: base64Encode(bytes),
      );
      _d.pdfFiles.add(rec);
      widget.data.save();
      if (mounted) setState(() => _openCatId = catId);
      if (widget.data.sizeBytes > _warnBytes) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Dikkat: Depolama alanı dolmak üzere. Eski PDF dosyalarını gözden geçirin.',
              style: TextStyle(),
            ),
            duration: Duration(seconds: 6),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.warning,
          ),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('PDF yüklendi.', style: TextStyle()),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on Exception {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Dosya seçilemedi.', style: TextStyle()),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Dosyayı açar; bu cihazda yoksa sunucudan indirir.
  Future<void> _openPdf(PdfFile f) async {
    final messenger = ScaffoldMessenger.of(context);
    final fetching = needsRemoteFetch(f);
    if (fetching) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('${f.name} indiriliyor…', style: const TextStyle()),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 900),
        ),
      );
    }
    final bytes = await widget.data.pdfBytes(f);
    if (!mounted) return;
    if (bytes.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Dosya indirilemedi. Bağlantınızı kontrol edip tekrar deneyin.',
            style: TextStyle(),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PdfViewerScreen(name: f.name, bytes: bytes),
      ),
    );
  }

  /// Dosya hâlâ sunucuda mı, yoksa bu cihazda mı?
  bool needsRemoteFetch(PdfFile f) =>
      f.dataUrl.isEmpty && f.storagePath.isNotEmpty;

  Future<void> _openExternal(PdfFile f) async {
    final messenger = ScaffoldMessenger.of(context);
    final bytes = await widget.data.pdfBytes(f);
    if (!mounted) return;
    if (bytes.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Dosya indirilemedi. Bağlantınızı kontrol edip tekrar deneyin.',
            style: TextStyle(),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final ok = await pdfOpenExternal(bytes, f.name);
    if (!ok && mounted) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Dosya açılamadı. Tarayıcı yeni sekmeyi engelledi.',
            style: TextStyle(),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _download(PdfFile f) async {
    final messenger = ScaffoldMessenger.of(context);
    final bytes = await widget.data.pdfBytes(f);
    if (!mounted) return;
    if (bytes.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Dosya indirilemedi. Bağlantınızı kontrol edip tekrar deneyin.',
            style: TextStyle(),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final ok = await pdfDownload(bytes, f.name);
    if (!ok && mounted) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Dosya indirilemedi.', style: TextStyle()),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _openCatEditor({PdfCategory? cat}) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => _CatEditorDialog(
        cat: cat,
        existing: _d.pdfCats,
        onSave: (name) {
          if (cat == null) {
            final c = PdfCategory(id: widget.data.newId(), name: name);
            _d.pdfCats.add(c);
            _openCatId = c.id;
          } else {
            cat.name = name;
          }
          widget.data.save();
        },
      ),
    );
    if (result != null && mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(result, style: const TextStyle()),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _confirmDeleteCat(PdfCategory c) async {
    final messenger = ScaffoldMessenger.of(context);
    final n = _d.pdfFiles.where((f) => f.catId == c.id).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kategoriyi Sil', style: TextStyle()),
        content: Text(
          '"${c.name}" silinecek.${n > 0 ? ' Kategori içindeki $n PDF dosyası da kalıcı olarak silinecek.' : ''} Bu işlem geri alınamaz.',
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç', style: TextStyle()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Evet, Sil', style: TextStyle()),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final paths = _d.pdfFiles
        .where((x) => x.catId == c.id)
        .map((x) => x.storagePath)
        .toList();
    _d.pdfCats.removeWhere((x) => x.id == c.id);
    _d.pdfFiles.removeWhere((x) => x.catId == c.id);
    if (_openCatId == c.id) _openCatId = null;
    widget.data.save();
    // Kayıttan çıkarılan belgelerin ikilisi de depodan silinir; silinen
    // kategori sonrası depoda öksüz dosya kalmaz (KVKK + maliyet).
    unawaited(widget.data.purgeBlobs(paths));
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Kategori silindi.', style: TextStyle()),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _confirmDeleteFile(PdfFile f) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('PDF Silinsin mi?', style: TextStyle()),
        content: Text(
          '"${f.name}" kalıcı olarak silinecek.',
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç', style: TextStyle()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sil', style: TextStyle()),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final path = f.storagePath;
    _d.pdfFiles.removeWhere((x) => x.id == f.id);
    widget.data.save();
    unawaited(widget.data.purgeBlobs([path]));
    messenger.showSnackBar(
      const SnackBar(
        content: Text('PDF silindi.', style: TextStyle()),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// Kategori oluşturma / yeniden adlandırma iletişim kutusu.
class _CatEditorDialog extends StatefulWidget {
  const _CatEditorDialog({
    required this.cat,
    required this.existing,
    required this.onSave,
  });

  final PdfCategory? cat;
  final List<PdfCategory> existing;
  final ValueChanged<String> onSave;

  @override
  State<_CatEditorDialog> createState() => _CatEditorDialogState();
}

class _CatEditorDialogState extends State<_CatEditorDialog> {
  late final TextEditingController _name;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.cat?.name ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String _normalize(String s) => s.trim().toLowerCase();

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Kategori adı gereklidir.');
      return;
    }
    if (name.length > 60) {
      setState(() => _error = 'En fazla 60 karakter kullanılabilir.');
      return;
    }
    final dup = widget.existing.any(
      (c) =>
          c.id != (widget.cat?.id ?? '') &&
          _normalize(c.name) == _normalize(name),
    );
    if (dup) {
      setState(() => _error = 'Bu isimde bir kategori zaten var.');
      return;
    }
    final wasNew = widget.cat == null;
    widget.onSave(name);
    Navigator.of(context)
        .pop(wasNew ? 'Kategori oluşturuldu.' : 'Kategori güncellendi.');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.cat == null ? 'Yeni PDF Kategorisi' : 'Kategoriyi Düzenle',
        style: const TextStyle(),
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              maxLength: 60,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                labelText: 'Kategori Adı *',
                hintText: 'Örn: Raporlar, Test Çıktıları, Epikrizler',
                errorText: _error,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Kategoriler dokümanlarınızı düzenlemenize yardımcı olur (örn. "Raporlar", "Ölçek Çıktıları").',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('İptal', style: TextStyle()),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_outlined, size: 17),
          label: const Text('Kaydet', style: TextStyle()),
        ),
      ],
    );
  }
}
