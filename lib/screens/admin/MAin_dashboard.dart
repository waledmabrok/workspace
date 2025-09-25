import 'package:flutter/material.dart';
import '../../core/FinanceDb.dart';
import '../../core/data_service.dart';
import '../../core/Db_helper.dart';

class DashboardPagee extends StatefulWidget {
  const DashboardPagee({Key? key}) : super(key: key);

  @override
  State<DashboardPagee> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPagee> {
  final admin = AdminDataService.instance;
  DateTime? _selectedDate; // اختيار التاريخ

  @override
  void initState() {
    super.initState();
    admin.init(); // تحميل البيانات أول مرة
  }
  Future<void> printAllShifts() async {
    final shifts = await DbHelper.instance.getAllShifts();
    for (var row in shifts) {
      debugPrint(
        "🟢 شيفت رقم ${row['id']} | فتح: ${row['opened_at']} | إغلاق: ${row['closed_at']} | كاشير: ${row['cashier_name']} | الرصيد: ${row['drawer_balance']} | المبيعات: ${row['total_sales']}",
      );
    }

    if (shifts.isEmpty) {
      debugPrint("⚠️ مفيش أي شيفتات محفوظة");
      return;
    }

    debugPrint("📋 قائمة الشيفتات:");
    for (var row in shifts) {
      final id = row['id'];
      final closedAt = row['closed_at'];
      final signers = row['signers'];
      final balance = row['drawer_balance'];
      final totalSales = row['total_sales'];

      debugPrint(
        "🟢 شيفت رقم $id | إغلاق: $closedAt | كاشير: $signers | الرصيد: $balance | المبيعات: $totalSales",
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("📊 Dashboard"),
        forceMaterialTransparency: true,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await admin.init();
          setState(() {});
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // اختيار التاريخ
            Row(
              children: [ElevatedButton(
                onPressed: () async {
                  await printAllShifts();
                },
                child: const Text("عرض كل الشيفتات"),
              ),

                const Text("اختر تاريخ: "),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setState(() {
                        _selectedDate = picked;
                      });
                    }
                  },
                  icon: const Icon(Icons.calendar_today),
                  label: Text(
                    _selectedDate != null
                        ? "${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}"
                        : "كل الأيام",
                  ),
                ),
                const SizedBox(width: 12),
                if (_selectedDate != null)
                  ElevatedButton(
                    onPressed: () => setState(() => _selectedDate = null),
                    child: const Text("عرض الكل"),
                  ),
              ],
            ),
            const SizedBox(height: 20),

            // 🟡 كروت المبيعات والمصاريف والأرباح
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatCard(
                  "مبيعات",
                  _selectedDate != null
                      ? admin.getSalesByDate(_selectedDate!)
                      : admin.getAllSales(),
                  Colors.green,
                ),
                _buildStatCard(
                  "مصروفات",
                  _selectedDate != null
                      ? admin.getExpensesByDate(_selectedDate!)
                      : admin.getAllExpenses(),
                  Colors.red,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatCard(
                  "الأرباح",
                  _selectedDate != null
                      ? admin.getProfitByDate(_selectedDate!)
                      : admin.getAllProfit(),
                  Colors.blue,
                ),
                _buildStatCard(
                  "رصيد الدرج",
                  admin.drawerBalance,
                  Colors.orange,
                ),
              ],
            ),
            const SizedBox(height: 20),

            const Text(
              "الشيفتات",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),

            // قائمة الشيفتات
            FutureBuilder<List<Map<String, dynamic>>>(
              future: DbHelper.instance.getAllShifts(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text("لا توجد شيفتات"));
                }

                final shifts = snapshot.data!;
                return Column(
                  children: shifts.map((s) {

                    final openedAt = s['opened_at']?.toString() ?? "-";
                    final closedAt = s['closed_at']?.toString() ?? "-";
                    final shiftId = s['id']?.toString() ?? "-"; // بدل shiftId
                    final cashierName = s['cashier_name']?.toString() ?? "-"; // بدل signers أو null
                    final openingBalance = (s['openingBalance'] as num?)?.toDouble() ?? 0.0;
                 //   final finalClosingBalance = (s['finalClosingBalance'] as num?)?.toDouble() ?? 0.0;
                    final totalSales = (s['totalSales'] as num?)?.toDouble() ?? 0.0;
                 //   final finalClosingBalance = (s['finalClosingBalance'] as num?)?.toDouble() ?? 0.0;
                    final finalClosingBalance =totalSales+openingBalance;
                    // final finalClosingBalance = (s['drawer_balance'] as num?)?.toDouble() ?? 0.0;

                   //final openingBalance = (s['openingBalance'] as num?)?.toDouble()
                     //   ?? ((s['finalClosingBalance'] as num?)?.toDouble() ?? 0.0) - ((s['totalSales'] as num?)?.toDouble() ?? 0.0);

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      child: ListTile(
                        title: Text("شيفت رقم $shiftId"),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("فتح: $openedAt"),
                            Text("قفل: $closedAt"),
                            Text("رصيد البداية: ${openingBalance.toStringAsFixed(2)}"),
                            Text("رصيد النهاية: ${finalClosingBalance.toStringAsFixed(2)}"),
                            Text("مبيعات: ${totalSales.toStringAsFixed(2)}"),
                          ],
                        ),
                        trailing: Text(
                          "صافي ${totalSales.toStringAsFixed(2)}",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ),
                    )
                    ;
                  }).toList(),
                );
              },
            )
          ],
        ),
      ),
    );
  }

  Widget _buildShiftCard(Map<String, dynamic> shift) {
    final totalExpenses = (shift["totalExpenses"] as num?)?.toDouble() ?? 0.0;
    final cashierName = shift["cashier_name"]?.toString() ?? "-";
    final openedAt = shift["opened_at"]?.toString() ?? "-";
    final closedAt = shift["closed_at"]?.toString() ?? "-";
    final openingBalance = (shift["drawer_balance"] as num?)?.toDouble() ?? 0.0;
    final closingBalance = (shift["total_sales"] as num?)?.toDouble() ?? 0.0;

    final totalSales = closingBalance - openingBalance + totalExpenses;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        title: Text(shift["cashierName"] ?? "-"),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("فتح: ${shift["openedAt"] ?? "-"}"),
            Text("قفل: ${shift["closedAt"] ?? "-"}"),
            Text("رصيد البداية: ${openingBalance.toStringAsFixed(2)}"),
            Text("رصيد النهاية: ${closingBalance.toStringAsFixed(2)}"),
            Text("مبيعات: ${totalSales.toStringAsFixed(2)}"),
            Text("مصروفات: ${totalExpenses.toStringAsFixed(2)}"),
          ],
        ),
        trailing: Text(
          "صافي ${(totalSales - totalExpenses).toStringAsFixed(2)}",
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.green,
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, double value, Color color) {
    return Card(
      color: color.withOpacity(0.1),
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              "${value.toStringAsFixed(2)} ج",
              style: TextStyle(fontSize: 18, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
