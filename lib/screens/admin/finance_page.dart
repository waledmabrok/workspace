import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workspace/utils/colors.dart';
import 'package:workspace/widget/buttom.dart';
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

    ds.expenses = allExpenses
        .where(
          (e) =>
              e.date.year == date.year &&
              e.date.month == date.month &&
              e.date.day == date.day,
        )
        .toList();

    ds.sales = allSales
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

  String formatDateArabic(DateTime date) {
    final formatter = DateFormat('yyyy/MM/dd – HH:mm', 'ar'); // عربي
    String formatted = formatter.format(date);
    // تحويل الأرقام للعربية
    const english = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    const arabic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    for (int i = 0; i < 10; i++) {
      formatted = formatted.replaceAll(english[i], arabic[i]);
    }
    return formatted;
  }

  // -------------------- واجهة المستخدم --------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        forceMaterialTransparency: true,
        title: Center(child: const Text('المصاريف و الأرباح اليومية')),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // أزرار إضافة مصروف وبيع
            Row(
              children: [
                CustomButton(
                  text:
                      "${selectedDate.day}/${selectedDate.month}/${selectedDate.year}",
                  onPressed: _pickDate,
                  infinity: false,
                  border: true,
                ),
                const SizedBox(width: 12),
                CustomButton(
                  text: "اضف مصروف",
                  onPressed: _addExpense,
                  infinity: false,
                ),
                /* ElevatedButton.icon(
                  onPressed: _addExpense,
                  icon: const Icon(Icons.add),
                  label: const Text('اضف مصروف'),
                ),*/
                const SizedBox(width: 12),
                CustomButton(
                  text: 'سجل بيع',
                  onPressed: _recordSale,
                  infinity: false,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // الملخص اليومي
            Card(
              color: AppColorsDark.bgCardColor,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: ListTile(
                  title: const Text(
                    'ملخص اليوم',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  subtitle: Text(
                    'إجمالي المبيعات: ${totalSales.toStringAsFixed(2)}  |  إجمالي المصاريف: ${totalExpenses.toStringAsFixed(2)}',
                  ),
                  trailing: Text(
                    'الربح: ${profit.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 15),
                  ),
                ),
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
                      color: AppColorsDark.bgCardColor,
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: ListTile(
                          title: Text(
                            e.title,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(formatDateArabic(e.date.toLocal())),
                          trailing: Text(
                            e.amount.toStringAsFixed(2),
                            style: TextStyle(fontSize: 15),
                          ),
                        ),
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
                      color: AppColorsDark.bgCardColor,
                      child: ExpansionTile(
                        title: Text(s.description),
                        subtitle: Text(formatDateArabic(s.date.toLocal())),
                        trailing: Text(s.amount.toStringAsFixed(2)),
                        children: s.items.isEmpty
                            ? [ListTile(title: Text(""))]
                            : s.items
                                .where((item) => !item.product.id
                                    .startsWith("اشتراك")) // 🚫 اخفي الباقات
                                .map(
                                  (item) => ListTile(
                                    title: Text(
                                        '${item.product.name} × ${item.qty}'),
                                    trailing:
                                        Text(item.total.toStringAsFixed(2)),
                                  ),
                                )
                                .toList(),
                      ),
                    ),
                  )
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
