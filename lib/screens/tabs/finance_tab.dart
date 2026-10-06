import 'package:flutter/material.dart';
import '../../data/data_store.dart';
import '../../models/finance.dart' as mt;
import '../../models/appointment.dart';
import '../../models/client.dart';
import '../../theme/app_theme.dart';
import '../../utils/formats.dart';

class FinanceTab extends StatefulWidget {
  const FinanceTab({super.key, required this.data});
  final DataStore data;

  @override
  State<FinanceTab> createState() => _FinanceTabState();
}

class _FinanceTabState extends State<FinanceTab> {
  String _filterType = 'all'; // all, income, expense
  
  double get _totalIncome => widget.data.data.transactions
      .where((t) => t.type == 'income')
      .fold(0.0, (sum, t) => sum + t.amount);

  double get _totalExpense => widget.data.data.transactions
      .where((t) => t.type == 'expense')
      .fold(0.0, (sum, t) => sum + t.amount);

  double get _totalTax => widget.data.data.transactions
      .where((t) => t.type == 'income')
      .fold(0.0, (sum, t) => sum + t.taxAmount);

  double get _netIncome => _totalIncome - _totalTax;
  double get _balance => _netIncome - _totalExpense;

  mt.FinanceGoal? get _currentGoal {
    final now = DateTime.now();
    final monthStr = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    for (final g in widget.data.data.financeGoals) {
      if (g.month == monthStr) return g;
    }
    return null;
  }

  List<Appointment> get _uncollectedAppointments {
    final doneAppts = widget.data.data.appointments.where((a) => a.status == 'done').toList();
    final txs = widget.data.data.transactions.where((t) => t.type == 'income' && t.category == 'Seans').toList();
    
    return doneAppts.where((a) {
      final hasTx = txs.any((t) => t.clientId == a.clientId && t.date == a.date);
      return !hasTx;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final txs = widget.data.data.transactions.where((t) {
      if (_filterType == 'all') return true;
      return t.type == _filterType;
    }).toList()..sort((a, b) => b.date.compareTo(a.date));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context),
              const SizedBox(height: 20),
              _goalProgressCard(context),
              const SizedBox(height: 12),
              _summaryCards(context),
              const SizedBox(height: 24),
              if (_uncollectedAppointments.isNotEmpty) ...[
                _uncollectedSection(context),
                const SizedBox(height: 24),
              ],
              _filters(context),
              const SizedBox(height: 12),
              if (txs.isEmpty)
                _emptyState()
              else
                for (final tx in txs) _transactionRow(context, tx),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Kasa ve Muhasebe',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              Text('Gelir, gider, vergi ve hedeflerinizi yönetin.',
                  style: TextStyle(fontSize: 13, color: AppColors.muted)),
            ],
          ),
        ),
        FilledButton.icon(
          onPressed: () => _openTransactionEditor(context),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('İşlem Ekle'),
        ),
      ],
    );
  }

  Widget _goalProgressCard(BuildContext context) {
    final goal = _currentGoal;
    if (goal == null) {
      return Card(
        color: AppColors.primary.withValues(alpha: .05),
        child: InkWell(
          onTap: () => _editGoal(context),
          borderRadius: BorderRadius.circular(12),
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.flag_outlined, color: AppColors.primary),
                SizedBox(width: 12),
                Expanded(child: Text('Bu ay için henüz bir gelir hedefi belirlemediniz.', style: TextStyle(fontSize: 13))),
                Text('Hedef Belirle', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
          ),
        ),
      );
    }

    final progress = goal.target > 0 ? (_totalIncome / goal.target).clamp(0.0, 1.0) : 0.0;
    final percent = (progress * 100).toStringAsFixed(0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Aylık Gelir Hedefi (%$percent)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                InkWell(
                  onTap: () => _editGoal(context),
                  child: const Text('Düzenle', style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: progress,
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation<Color>(progress >= 1.0 ? Colors.green : AppColors.primary),
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('₺${_totalIncome.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primary)),
                Text('Hedef: ₺${goal.target.toStringAsFixed(0)}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCards(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth > 600;
      return GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: wide ? 4 : 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: wide ? 2.0 : 1.8,
        children: [
          _summaryCard('Brüt Gelir', _totalIncome, Colors.green, Icons.trending_up),
          _summaryCard('Tahmini Vergi', _totalTax, Colors.orange, Icons.pie_chart_outline),
          _summaryCard('Toplam Gider', _totalExpense, Colors.red, Icons.trending_down),
          _summaryCard('Net Bakiye', _balance, AppColors.primary, Icons.account_balance_wallet),
        ],
      );
    });
  }

  Widget _summaryCard(String title, double amount, Color color, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 6),
                Expanded(child: Text(title, style: const TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
              ],
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('₺${amount.toStringAsFixed(amount == amount.toInt() ? 0 : 2)}',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filters(BuildContext context) {
    return Row(
      children: [
        _filterChip('all', 'Tümü'),
        const SizedBox(width: 8),
        _filterChip('income', 'Gelirler'),
        const SizedBox(width: 8),
        _filterChip('expense', 'Giderler'),
      ],
    );
  }

  Widget _filterChip(String type, String label) {
    final active = _filterType == type;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: active,
      onSelected: (v) => setState(() => _filterType = type),
      showCheckmark: false,
    );
  }

  Widget _transactionRow(BuildContext context, mt.Transaction tx) {
    final isIncome = tx.type == 'income';
    final client = tx.clientId != null ? widget.data.data.clientById(tx.clientId!) : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isIncome ? Colors.green.withValues(alpha: .1) : Colors.red.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isIncome ? Icons.add_circle_outline : Icons.remove_circle_outline,
              color: isIncome ? Colors.green : Colors.red,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  client != null ? '${client.name} - ${tx.category}' : tx.category,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                Text(
                  '${tx.date} ${tx.taxRate > 0 ? '· %${tx.taxRate.toStringAsFixed(0)} Vergi' : ''} ${tx.notes.isNotEmpty ? '· ${tx.notes}' : ''}',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${isIncome ? '+' : '-'} ₺${tx.amount.toStringAsFixed(2)}',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  color: isIncome ? Colors.green : Colors.red,
                ),
              ),
              if (isIncome && tx.taxAmount > 0)
                Text('Net: ₺${tx.netAmount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 10, color: AppColors.muted)),
            ],
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.muted),
            onPressed: () => _confirmDelete(context, tx),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            const Icon(Icons.receipt_long_outlined, size: 40, color: AppColors.muted),
            const SizedBox(height: 12),
            const Text('Henüz işlem kaydı yok', style: TextStyle(color: AppColors.muted)),
            const SizedBox(height: 12),
            TextButton(onPressed: () => _openTransactionEditor(context), child: const Text('İlk İşlemi Ekle')),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, mt.Transaction tx) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('İşlemi Sil'),
        content: const Text('Bu finansal kaydı silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
          TextButton(
            onPressed: () {
              setState(() => widget.data.data.transactions.remove(tx));
              widget.data.save();
              Navigator.pop(context);
            },
            child: const Text('Sil', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }

  void _openTransactionEditor(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _TransactionEditor(data: widget.data),
    ).then((v) {
      if (v == true) setState(() {});
    });
  }

  void _editGoal(BuildContext context) {
    final current = _currentGoal;
    final controller = TextEditingController(text: current?.target.toStringAsFixed(0) ?? '5000');
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Aylık Gelir Hedefi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Bu ay ulaşmak istediğiniz toplam brüt gelir hedefini girin.', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Hedef Tutar (₺)', prefixText: '₺'),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
          FilledButton(
            onPressed: () {
              final target = double.tryParse(controller.text) ?? 0.0;
              final now = DateTime.now();
              final monthStr = '${now.year}-${now.month.toString().padLeft(2, '0')}';
              
              setState(() {
                widget.data.data.financeGoals.removeWhere((g) => g.month == monthStr);
                widget.data.data.financeGoals.add(mt.FinanceGoal(month: monthStr, target: target));
              });
              widget.data.save();
              Navigator.pop(context);
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  Widget _uncollectedSection(BuildContext context) {
    final appts = _uncollectedAppointments;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.notification_important_outlined, color: Colors.orange, size: 18),
            const SizedBox(width: 8),
            Text('Tahsil Edilmeyen Seanslar (${appts.length})', 
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.orange)),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 110,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: appts.length,
            itemBuilder: (context, i) {
              final a = appts[i];
              final c = widget.data.data.clientById(a.clientId);
              return Container(
                width: 200,
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: .05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.withValues(alpha: .2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c?.name ?? 'Bilinmeyen', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(a.date, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                    const Spacer(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('₺${c?.sessionFee.toStringAsFixed(0) ?? '0'}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Colors.orange)),
                        InkWell(
                          onTap: () => _quickCollectFromAppt(context, a, c),
                          child: const Text('Tahsil Et', style: TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _quickCollectFromAppt(BuildContext context, Appointment a, Client? c) {
    if (c == null) return;
    final amount = c.sessionFee;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Seans Tahsilatı'),
        content: Text('${c.name} isimli danışanın ${a.date} tarihli seansı için ₺${amount.toStringAsFixed(2)} ödeme kaydedilsin mi?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
          FilledButton(
            onPressed: () {
              final tx = mt.Transaction(
                id: widget.data.newId(),
                clientId: c.id,
                amount: amount,
                date: a.date,
                type: 'income',
                category: 'Seans',
                notes: 'Tamamlanan randevudan otomatik tahsilat',
                taxRate: 20.0, // Varsayılan vergi oranı
              );
              setState(() => widget.data.data.transactions.add(tx));
              widget.data.save();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ödeme kaydedildi.')));
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }
}

class _TransactionEditor extends StatefulWidget {
  const _TransactionEditor({required this.data});
  final DataStore data;

  @override
  State<_TransactionEditor> createState() => _TransactionEditorState();
}

class _TransactionEditorState extends State<_TransactionEditor> {
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  final _tax = TextEditingController(text: '0');
  String _type = 'income';
  String _category = 'Seans';
  String? _clientId;
  final String _date = todayIso();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Yeni İşlem Ekle'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'income', label: Text('Gelir'), icon: Icon(Icons.add)),
                ButtonSegment(value: 'expense', label: Text('Gider'), icon: Icon(Icons.remove)),
              ],
              selected: {_type},
              onSelectionChanged: (v) => setState(() => _type = v.first),
            ),
            const SizedBox(height: 16),
            if (_type == 'income')
              DropdownButtonFormField<String>(
                initialValue: _clientId,
                decoration: const InputDecoration(labelText: 'Danışan (Opsiyonel)'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Genel Gelir')),
                  ...widget.data.data.clients.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
                ],
                onChanged: (v) {
                  setState(() {
                    _clientId = v;
                    if (v != null) {
                      final c = widget.data.data.clientById(v);
                      if (c != null && c.sessionFee > 0) {
                        _amount.text = c.sessionFee.toStringAsFixed(0);
                      } else {
                        final defaultFee = widget.data.accounts.current?.defaultSessionFee ?? 0.0;
                        if (defaultFee > 0) {
                          _amount.text = defaultFee.toStringAsFixed(0);
                        }
                      }
                    }
                  });
                },
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Tutar (₺)', prefixText: '₺'),
            ),
            const SizedBox(height: 12),
            if (_type == 'income')
              TextField(
                controller: _tax,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Vergi Oranı (%)', suffixText: '%'),
              ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Kategori'),
              items: (_type == 'income' 
                ? ['Seans', 'Test/Envanter', 'Eğitim/Seminer', 'Diğer Gelir']
                : ['Kira', 'Fatura', 'Maaş', 'Yazılım/Abonelik', 'Pazarlama', 'Diğer Gider']
              ).map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (v) => setState(() => _category = v ?? 'Diğer'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notlar (Opsiyonel)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
        FilledButton(
          onPressed: () {
            final amt = double.tryParse(_amount.text) ?? 0.0;
            final tx = mt.Transaction(
              id: widget.data.newId(),
              clientId: _clientId,
              amount: amt,
              date: _date,
              type: _type,
              category: _category,
              notes: _notes.text,
              taxRate: double.tryParse(_tax.text) ?? 0.0,
            );
            widget.data.data.transactions.add(tx);
            widget.data.save();
            Navigator.pop(context, true);
          },
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}
