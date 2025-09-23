import 'package:flutter/material.dart';
import '../../core/FinanceDb.dart';
import '../../core/data_service.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Center(child: const Text("📊 Dashboard")),
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
              children: [
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

            FutureBuilder<List<Map<String, dynamic>>>(
              future:
                  _selectedDate != null
                      ? FinanceDb.getShiftsByDate(_selectedDate!)
                      : FinanceDb.getShifts(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text("لا توجد شيفتات"));
                }

                final shifts = snapshot.data!;
                return Column(
                  children:
                      shifts.map((shift) => _buildShiftCard(shift)).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShiftCard(Map<String, dynamic> shift) {
    final totalExpenses = (shift["totalExpenses"] as num?)?.toDouble() ?? 0.0;
    final openingBalance = (shift["openingBalance"] as num?)?.toDouble() ?? 0.0;
    final closingBalance = (shift["closingBalance"] as num?)?.toDouble() ?? 0.0;
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
