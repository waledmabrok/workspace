import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_file.dart';
import 'package:intl/intl.dart';
import 'package:workspace/widget/buttom.dart';
import 'package:workspace/widget/form.dart';
import '../../core/FinanceDb.dart';
import '../../core/data_service.dart';
import '../../core/Db_helper.dart';
import '../../utils/colors.dart';

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

  String formatDateTime(DateTime? dateTime) {
    if (dateTime == null) return "-";
    // initializeDateFormatting('ar'); // لضمان اللغة العربية
    String date = DateFormat.yMMMMd('ar').format(dateTime); // 25 سبتمبر 2025
    String time = DateFormat.Hm('ar').format(dateTime); // 13:11
    return "الساعة $time  -  يوم $date ";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Center(
          child: const Text(
            "تقفيل الشيفت",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
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
                const Text(
                  "اختر تاريخ: ",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                CustomButton(
                  infinity: false,
                  text: _selectedDate != null
                      ? "${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}"
                      : "كل الأيام",
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
                ),
                /*     ElevatedButton.icon(
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
           */
                const SizedBox(width: 12),
                if (_selectedDate != null)
                  CustomButton(
                    infinity: false,
                    border: true,
                    text: "عرض الكل",
                    onPressed: () => setState(() => _selectedDate = null),
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
                InkWell(
                  onTap: () async {
                    final controller = TextEditingController(
                      text: admin.drawerBalance
                          .toStringAsFixed(2), // الرصيد الحالي الإجمالي
                    );

                    final result = await showDialog<double>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text("تعديل رصيد الدرج"),
                        content: CustomFormField(
                          hint: "الرصيد الجديد",
                          controller: controller,
                        ),
                        actions: [
                          CustomButton(
                            text: "إلغاء",
                            onPressed: () => Navigator.pop(ctx),
                            infinity: false,
                            border: true,
                          ),
                          const SizedBox(width: 10),
                          CustomButton(
                            text: "حفظ",
                            onPressed: () {
                              final value = double.tryParse(controller.text);
                              Navigator.pop(ctx, value);
                            },
                            infinity: false,
                          ),
                        ],
                      ),
                    );

                    if (result != null) {
                      await admin
                          .setDrawerBalance(result); // تحديث الرصيد الكلي
                      setState(() {}); // إعادة بناء الشاشة
                    }
                  },
                  child: _buildStatCard(
                    "رصيد الدرج",
                    admin.drawerBalance, // اعرض الرصيد الكلي دائمًا
                    Colors.orange,
                  ),
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

                var shifts = snapshot.data!;

                // ✅ فلترة حسب التاريخ لو مستخدم اختار تاريخ
                if (_selectedDate != null) {
                  shifts = shifts.where((s) {
                    final openedAtStr = s['opened_at']?.toString();
                    if (openedAtStr == null) return false;
                    final openedAt = DateTime.tryParse(openedAtStr);
                    if (openedAt == null) return false;

                    return openedAt.year == _selectedDate!.year &&
                        openedAt.month == _selectedDate!.month &&
                        openedAt.day == _selectedDate!.day;
                  }).toList();
                }

                if (shifts.isEmpty) {
                  return const Center(
                    child: Text("لا توجد شيفتات في هذا التاريخ"),
                  );
                }

                //  final shifts = snapshot.data!;
                return Column(
                  children: shifts.map((s) {
                    final openedAt = s['opened_at']?.toString() ?? "-";
                    final closedAt = s['closed_at']?.toString() ?? "-";
                    final shiftId = s['id']?.toString() ?? "-"; // بدل shiftId
                    final cashierName = s['cashier_name']?.toString() ??
                        "-"; // بدل signers أو null
                    final openingBalance =
                        (s['openingBalance'] as num?)?.toDouble() ?? 0.0;
                    //   final finalClosingBalance = (s['finalClosingBalance'] as num?)?.toDouble() ?? 0.0;
                    final totalSales =
                        (s['totalSales'] as num?)?.toDouble() ?? 0.0;
                    final finalClosingBalance =
                        (s['closingBalance'] as num?)?.toDouble() ?? 0.0;
                    final totalExpenses =
                        (s['totalExpenses'] as num?)?.toDouble() ?? 0.0;
                    //   final finalClosingBalance = totalSales + openingBalance;
                    // final finalClosingBalance = (s['drawer_balance'] as num?)?.toDouble() ?? 0.0;

                    //final openingBalance = (s['openingBalance'] as num?)?.toDouble()
                    //   ?? ((s['finalClosingBalance'] as num?)?.toDouble() ?? 0.0) - ((s['totalSales'] as num?)?.toDouble() ?? 0.0);

                    return Card(
                      color: AppColorsDark.bgCardColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(
                          color: AppColorsDark.mainColor.withOpacity(0.4),
                          width: 1.5,
                        ),
                      ),
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: ListTile(
                          title: Text("شيفت رقم $shiftId"),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(height: 8),
                              Text(
                                "فتح: ${formatDateTime(DateTime.parse(openedAt))}",
                              ),
                              SizedBox(height: 8),
                              Text(
                                "قفل: ${closedAt != "-" ? formatDateTime(DateTime.parse(closedAt)) : "-"}",
                              ),
                              SizedBox(height: 8),
                              Text(
                                "مبيعات: ${totalSales.toStringAsFixed(2)}",
                              ),
                              SizedBox(height: 8),
                              Text(
                                "مصروفات: ${totalExpenses.toStringAsFixed(2)}",
                              ),
                              SizedBox(height: 8),
                              Text(
                                "رصيد البداية: ${openingBalance.toStringAsFixed(2)}",
                              ),
                              SizedBox(height: 8),
                              Text(
                                "رصيد النهاية: ${finalClosingBalance.toStringAsFixed(2)}",
                              ),
                              SizedBox(height: 8),
                            ],
                          ),
                          trailing: Text(
                            "صافي ${(totalSales - totalExpenses).toStringAsFixed(2)}",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: (totalSales - totalExpenses) >= 0
                                  ? Colors.green
                                  : Colors.red,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
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
        width: 250,
        height: 100,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
