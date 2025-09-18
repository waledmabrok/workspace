import 'package:flutter/material.dart';
import '../../core/data_service.dart';
import '../../core/FinanceDb.dart';
import '../../core/models.dart';

class SalesPage extends StatefulWidget {
  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  final ds = AdminDataService.instance;

  @override
  void initState() {
    super.initState();
    _loadSales();
  }

  Future<void> _loadSales() async {
    ds.sales = await FinanceDb.getSales(); // تحميل من DB
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        forceMaterialTransparency: true,
        title: const Text('الفواتير المدفوعه'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              'إجمالي المبيعات: ${ds.totalSales.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 16),
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
                            color: const Color(0xFF071022),
                            child: ListTile(
                              title: Text(s.description),
                              subtitle: Text(
                                "${s.date.toLocal()}"
                                    .split(".")
                                    .first, // تنسيق التاريخ
                              ),
                              trailing: Text(s.amount.toStringAsFixed(2)),
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
