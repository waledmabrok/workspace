/*
import 'package:flutter/material.dart';
import 'dart:math';

import '../../core/data_service.dart';
import '../../core/models.dart';

// ------------------------- Finance Page (Expenses & Profit) -------------------------
class FinancePage extends StatefulWidget {
  @override
  State<FinancePage> createState() => _FinancePageState();
}

class _FinancePageState extends State<FinancePage> {
  final AdminDataService ds = AdminDataService.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المصاريف و الأرباح')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _addExpense,
                  icon: const Icon(Icons.add),
                  label: const Text('اضف مصروف'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _recordSale,
                  icon: const Icon(Icons.point_of_sale),
                  label: const Text('سجل بيع'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Card(
              color: const Color(0xFF071022),
              child: ListTile(
                title: const Text('ملخص'),
                subtitle: Text(
                  'إجمالي المبيعات: ${ds.totalSales.toStringAsFixed(2)}  |  إجمالي المصاريف: ${ds.totalExpenses.toStringAsFixed(2)}',
                ),
                trailing: Text('الربح: ${ds.profit.toStringAsFixed(2)}'),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  const Text(
                    'قائمة المصاريف',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  ...ds.expenses.map(
                    (e) => Card(
                      color: const Color(0xFF071022),
                      child: ListTile(
                        title: Text(e.title),
                        subtitle: Text('${e.date.toLocal()}'),
                        trailing: Text(e.amount.toStringAsFixed(2)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'سجل المبيعات',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  ...ds.sales.map(
                    (s) => Card(
                      color: const Color(0xFF071022),
                      child: ListTile(
                        title: Text(s.description),
                        subtitle: Text('${s.date.toLocal()}'),
                        trailing: Text(s.amount.toStringAsFixed(2)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addExpense() async {
    final res = await showDialog<Expense?>(
      context: context,
      builder: (_) => ExpenseDialog(),
    );
    if (res != null) setState(() => ds.expenses.add(res));
  }

  Future<void> _recordSale() async {
    final res = await showDialog<Sale?>(
      context: context,
      builder: (_) => SaleDialog(),
    );
    if (res != null) setState(() => ds.sales.add(res));
  }
}

class ExpenseDialog extends StatefulWidget {
  @override
  State<ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends State<ExpenseDialog> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _amount = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('اضف مصروف'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'الاسم'),
          ),
          TextField(
            controller: _amount,
            decoration: const InputDecoration(labelText: 'المبلغ'),
            keyboardType: TextInputType.number,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('الغاء'),
        ),
        ElevatedButton(
          onPressed: () {
            final title = _title.text.trim();
            final amount = double.tryParse(_amount.text) ?? 0.0;
            if (title.isEmpty) return;
            Navigator.pop(
              context,
              Expense(id: generateId(), title: title, amount: amount),
            );
          },
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}

class SaleDialog extends StatefulWidget {
  @override
  State<SaleDialog> createState() => _SaleDialogState();
}

class _SaleDialogState extends State<SaleDialog> {
  final TextEditingController _desc = TextEditingController();
  final TextEditingController _amount = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('سجل بيع'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _desc,
            decoration: const InputDecoration(labelText: 'وصف'),
          ),
          TextField(
            controller: _amount,
            decoration: const InputDecoration(labelText: 'المبلغ'),
            keyboardType: TextInputType.number,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('الغاء'),
        ),
        ElevatedButton(
          onPressed: () {
            final d = _desc.text.trim();
            final a = double.tryParse(_amount.text) ?? 0.0;
            if (d.isEmpty) return;
            Navigator.pop(
              context,
              Sale(id: generateId(), description: d, amount: a),
            );
          },
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}
*/

import 'package:flutter/material.dart';
import '../../core/FinanceDb.dart';
import '../../core/data_service.dart';
import '../../core/models.dart';
import '../../core/db_helper.dart';

// ===================== Finance Page Daily =====================
class FinancePage extends StatefulWidget {
  @override
  State<FinancePage> createState() => _FinancePageDailyState();
}

class _FinancePageDailyState extends State<FinancePage> {
  final AdminDataService ds = AdminDataService.instance;

  @override
  void initState() {
    super.initState();
    _loadTodayData();
  }

  // -------------------- دوال مساعدة --------------------
  bool isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  DateTime selectedDate = DateTime.now(); // اليوم الافتراضي

  // دالة لاختيار اليوم
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null && picked != selectedDate) {
      setState(() {
        selectedDate = picked;
        _loadDataForDate(selectedDate); // إعادة تحميل البيانات لليوم الجديد
      });
    }
  }

  // تعديل دالة التحميل لتأخذ التاريخ
  Future<void> _loadDataForDate(DateTime date) async {
    final allExpenses = await FinanceDb.getExpenses();
    final allSales = await FinanceDb.getSales();

    ds.expenses =
        allExpenses
            .where(
              (e) =>
                  e.date.year == date.year &&
                  e.date.month == date.month &&
                  e.date.day == date.day,
            )
            .toList();

    ds.sales =
        allSales
            .where(
              (s) =>
                  s.date.year == date.year &&
                  s.date.month == date.month &&
                  s.date.day == date.day,
            )
            .toList();

    setState(() {});
  }

  Future<void> _loadTodayData() async {
    final allExpenses = await FinanceDb.getExpenses();
    final allSales = await FinanceDb.getSales();

    ds.expenses = allExpenses.where((e) => isToday(e.date)).toList();
    ds.sales = allSales.where((s) => isToday(s.date)).toList();

    setState(() {});
  }

  double get totalSales => ds.sales.fold(0.0, (sum, s) => sum + s.amount);

  double get totalExpenses => ds.expenses.fold(0.0, (sum, e) => sum + e.amount);

  double get profit => totalSales - totalExpenses;

  // -------------------- واجهة المستخدم --------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        forceMaterialTransparency: true,
        title: const Text('المصاريف و الأرباح اليومية'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // أزرار إضافة مصروف وبيع
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today),
                  label: Text(
                    "${selectedDate.day}/${selectedDate.month}/${selectedDate.year}",
                  ),
                ),
                const SizedBox(width: 12),

                ElevatedButton.icon(
                  onPressed: _addExpense,
                  icon: const Icon(Icons.add),
                  label: const Text('اضف مصروف'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _recordSale,
                  icon: const Icon(Icons.point_of_sale),
                  label: const Text('سجل بيع'),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // الملخص اليومي
            Card(
              color: const Color(0xFF071022),
              child: ListTile(
                title: const Text('ملخص اليوم'),
                subtitle: Text(
                  'إجمالي المبيعات: ${totalSales.toStringAsFixed(2)}  |  إجمالي المصاريف: ${totalExpenses.toStringAsFixed(2)}',
                ),
                trailing: Text('الربح: ${profit.toStringAsFixed(2)}'),
              ),
            ),
            const SizedBox(height: 12),

            // قائمة المصاريف والمبيعات اليوم
            Expanded(
              child: ListView(
                children: [
                  const Text(
                    'قائمة المصاريف اليوم',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  ...ds.expenses.map(
                    (e) => Card(
                      color: const Color(0xFF071022),
                      child: ListTile(
                        title: Text(e.title),
                        subtitle: Text('${e.date.toLocal()}'),
                        trailing: Text(e.amount.toStringAsFixed(2)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'سجل المبيعات اليوم',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  ...ds.sales.map(
                    (s) => Card(
                      color: const Color(0xFF071022),
                      child: ListTile(
                        title: Text(s.description),
                        subtitle: Text('${s.date.toLocal()}'),
                        trailing: Text(s.amount.toStringAsFixed(2)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------- Dialogs --------------------
  Future<void> _addExpense() async {
    final res = await showDialog<Expense?>(
      context: context,
      builder: (_) => ExpenseDialog(),
    );
    if (res != null) {
      await FinanceDb.insertExpense(res); // تخزين في DB
      ds.expenses.add(res);
      setState(() {});
    }
  }

  Future<void> _recordSale() async {
    final res = await showDialog<Sale?>(
      context: context,
      builder: (_) => SaleDialog(),
    );
    if (res != null) {
      await FinanceDb.insertSale(res); // تخزين في DB
      ds.sales.add(res);
      setState(() {});
    }
  }
}

// -------------------- Dialogs --------------------
class ExpenseDialog extends StatefulWidget {
  @override
  State<ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends State<ExpenseDialog> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _amount = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('اضف مصروف'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'الاسم'),
          ),
          TextField(
            controller: _amount,
            decoration: const InputDecoration(labelText: 'المبلغ'),
            keyboardType: TextInputType.number,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('الغاء'),
        ),
        ElevatedButton(
          onPressed: () {
            final title = _title.text.trim();
            final amount = double.tryParse(_amount.text) ?? 0.0;
            if (title.isEmpty) return;
            Navigator.pop(
              context,
              Expense(
                id: generateId(),
                title: title,
                amount: amount,
                date: DateTime.now(),
              ),
            );
          },
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}

class SaleDialog extends StatefulWidget {
  @override
  State<SaleDialog> createState() => _SaleDialogState();
}

class _SaleDialogState extends State<SaleDialog> {
  final TextEditingController _desc = TextEditingController();
  final TextEditingController _amount = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('سجل بيع'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _desc,
            decoration: const InputDecoration(labelText: 'وصف'),
          ),
          TextField(
            controller: _amount,
            decoration: const InputDecoration(labelText: 'المبلغ'),
            keyboardType: TextInputType.number,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('الغاء'),
        ),
        ElevatedButton(
          onPressed: () {
            final d = _desc.text.trim();
            final a = double.tryParse(_amount.text) ?? 0.0;
            if (d.isEmpty) return;
            Navigator.pop(
              context,
              Sale(
                id: generateId(),
                description: d,
                amount: a,
                date: DateTime.now(),
              ),
            );
          },
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}
