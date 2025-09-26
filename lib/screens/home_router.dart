import 'package:flutter/material.dart';
import 'package:workspace/widget/form.dart';
import 'dart:math';

import '../core/data_service.dart';
import '../core/Db_helper.dart';
import 'admin/admin_dashboard.dart' show AdminDashboard;
import 'cashier/cashier_screen.dart';

class HomeRouter extends StatefulWidget {
  const HomeRouter({super.key});

  @override
  State<HomeRouter> createState() => _HomeRouterState();
}

class _HomeRouterState extends State<HomeRouter> {
  int? currentShiftId;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _openShiftOnStart() async {
    // جلب الشيفت المفتوح حالياً
    final currentShift = await DbHelper.instance.getCurrentShift();
    if (currentShift != null) {
      debugPrint("⚠️ يوجد شيفت مفتوح بالفعل برقم ${currentShift['id']}");
      return; // لا نفعل شيء، يوجد شيفت مفتوح
    }

    // جلب آخر شيفت مغلق لحساب الرصيد الافتتاحي
    final lastClosedShift = await DbHelper.instance.getLastClosedShift();
    double openingBalance = 0.0;

    if (lastClosedShift != null) {
      openingBalance =
          (lastClosedShift['closingBalance'] as num?)?.toDouble() ?? 0.0;
    }

    // فتح شيفت جديد
    final id = await DbHelper.instance.openShift(
      'DefaultCashier',
      openingBalance: openingBalance,
    );

    setState(() {
      currentShiftId = id;
    });

    AdminDataService.instance.currentShiftId = id;
    AdminDataService.instance.drawerBalance = openingBalance;

    debugPrint("💰 رصيد البداية للشيفت الجديد: $openingBalance");
    debugPrint("✅ تم فتح شيفت جديد تلقائي برقم $id");
  }

  /*
  Future<void> _openShiftOnStart() async {
    final lastClosedShift = await DbHelper.instance.getLastClosedShift();
    double openingBalance = 0.0;

    if (lastClosedShift != null) {
      openingBalance = (lastClosedShift['closingBalance'] as num?)?.toDouble() ?? 0.0;
    }

    final id = await DbHelper.instance.openShift(
      'DefaultCashier',
      openingBalance: openingBalance,
    );

    setState(() {
      currentShiftId = id;
    });

    AdminDataService.instance.currentShiftId = id;
    AdminDataService.instance.drawerBalance = openingBalance;

    debugPrint("💰 رصيد البداية للشيفت الجديد: $openingBalance");
    debugPrint("✅ تم فتح شيفت جديد تلقائي برقم $id");
  }
*/

  /*  Future<void> _loadPasswords() async {
    await AdminDataService.instance.loadPasswords();
    setState(() {}); // يعمل تحديث عشان يتحدث الباسورد في الواجهة
  }*/

  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'XSpace System',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _roleButton(
                      context,
                      'لوحة الأدمن',
                      Icons.admin_panel_settings,
                      const AdminDashboard(),
                      correctPassword: AdminDataService.instance.adminPassword,
                    ),
                    const SizedBox(width: 24),
                    _roleButton(
                      context,
                      'واجهة الكاشير',
                      Icons.point_of_sale,
                      const CashierScreen(),
                      correctPassword:
                          AdminDataService.instance.cashierPassword,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _roleButton(
    BuildContext context,
    String title,
    IconData icon,
    Widget route, {
    required String correctPassword,
  }) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF0E1624),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      onPressed: () async {
        final ok = await _askForPassword(context, correctPassword);
        if (ok) {
          _openShiftOnStart();
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => route));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("كلمة المرور غير صحيحة")),
          );
        }
      },
      child: Row(
        children: [
          Icon(icon, size: 36),
          const SizedBox(width: 12),
          Text(title, style: const TextStyle(fontSize: 18)),
        ],
      ),
    );
  }

  Future<bool> _askForPassword(
    BuildContext context,
    String correctPassword,
  ) async {
    final controller = TextEditingController();
    void submit(BuildContext ctx) {
      final input = controller.text.trim();
      Navigator.pop(ctx, input == correctPassword);
    }

    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("أدخل كلمة المرور"),
            content: CustomFormField(
              hint: "كلمة المرور",
              controller: controller,
              isPassword: true,
            ),
            /*TextField(
                  controller: controller,
                  obscureText: true,
                  decoration: const InputDecoration(hintText: "كلمة المرور"),
                  onSubmitted: (_) => submit(ctx), // هنا Enter هيشتغل
                ),*/
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("إلغاء"),
              ),
              ElevatedButton(
                onPressed: () => submit(ctx),
                child: const Text("دخول"),
              ),
            ],
          ),
        ) ??
        false;
  }
}
