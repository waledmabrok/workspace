import 'package:flutter/material.dart';
import 'dart:math';

import '../core/data_service.dart';
import '../core/db_helper_shifts.dart';
import 'admin/admin_dashboard.dart' show AdminDashboard;
import 'cashier/cashier_screen.dart';

class HomeRouter extends StatefulWidget {
  const HomeRouter({super.key});

  @override
  State<HomeRouter> createState() => _HomeRouterState();
}

class _HomeRouterState extends State<HomeRouter> {
  @override
  void initState() {
    super.initState();
    // _loadPasswords();
  }

  String? cashierPassword;

  Future<void> loadPasswords() async {
    final cashiers = await CashierDb.getAll();
    if (cashiers.isNotEmpty) {
      cashierPassword = cashiers.first["password"];
    }
  }

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
                  'WorkSpace System',
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
          builder:
              (ctx) => AlertDialog(
                title: const Text("أدخل كلمة المرور"),
                content: TextField(
                  controller: controller,
                  obscureText: true,
                  decoration: const InputDecoration(hintText: "كلمة المرور"),
                  onSubmitted: (_) => submit(ctx), // هنا Enter هيشتغل
                ),
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
