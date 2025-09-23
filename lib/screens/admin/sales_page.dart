import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workspace/utils/colors.dart';
import 'package:workspace/widget/buttom.dart';
import '../../core/data_service.dart';
import '../../core/FinanceDb.dart';
import '../../core/models.dart';

class SalesPage extends StatefulWidget {
  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  final ds = AdminDataService.instance;
  DateTime selectedDate = DateTime.now(); // اليوم الافتراضي

  @override
  void initState() {
    super.initState();
    _loadSalesForDate(selectedDate);
  }

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
        _loadSalesForDate(selectedDate);
      });
    }
  }

  Future<void> _loadSalesForDate(DateTime date) async {
    final allSales = await FinanceDb.getSales();
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

  String formatDateTimeArabic(DateTime dt) {
    // تحويل الوقت المحلي
    final local = dt.toLocal();
    // تنسيق التاريخ والوقت بالعربي
    final formatter = DateFormat('EEEE d MMMM yyyy – HH:mm', 'ar');
    return formatter.format(local);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        forceMaterialTransparency: true,
        title: Center(child: const Text('الفواتير المدفوعه')),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // اختيار التاريخ
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CustomButton(
                  text:
                      "${selectedDate.day}/${selectedDate.month}/${selectedDate.year}",
                  onPressed: _pickDate,
                  infinity: false,
                  border: true,
                ),
                /*    ElevatedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today),
                  label: Text(
                    "${selectedDate.day}/${selectedDate.month}/${selectedDate.year}",
                  ),
                ),*/
                Text(
                  'إجمالي المبيعات: ${ds.totalSales.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child:
                  ds.sales.isEmpty
                      ? const Center(child: Text("لا توجد مبيعات مسجلة"))
                      : ListView.builder(
                        itemCount: ds.sales.length,
                        itemBuilder: (context, i) {
                          final s = ds.sales[i];
                          return Card(
                            color: AppColorsDark.bgCardColor,
                            child: ListTile(
                              title: Text(
                                s.description,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                              subtitle: Text(formatDateTimeArabic(s.date)),

                              trailing: Text(
                                s.amount.toStringAsFixed(2),
                                style: TextStyle(fontSize: 18),
                              ),
                            ),
                          );
                        },
                      ),
            ),
          ],
        ),
      ),
    );
  }
}
