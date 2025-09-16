import 'package:flutter/material.dart';
import 'package:workspace/screens/admin/placeholder_page.dart';
import 'package:workspace/screens/admin/products_page.dart';
import 'package:workspace/screens/admin/sales_page.dart';
import 'package:workspace/screens/admin/subscriptions_page.dart';
import 'package:workspace/screens/admin/CustomersBalancesPage.dart';
import 'dart:math';
import '../../core/db_helper_Subscribe.dart';
import '../../core/data_service.dart';
import '../../core/models.dart';
import 'discounts_page.dart';
import 'finance_page.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final AdminDataService ds = AdminDataService.instance;

  @override
  @override
  void initState() {
    super.initState();
    _seedData();
  }

  Future<void> _seedData() async {
    // Seed subscriptions
    final subs = await SubscriptionDb.getPlans();
    if (subs.isEmpty) {
      await SubscriptionDb.insertPlan(
        SubscriptionPlan(
          id: generateId(),
          name: 'باقة ساعة',
          durationType: 'hour',
          durationValue: 1,
          price: 15.0,
        ),
      );
      await SubscriptionDb.insertPlan(
        SubscriptionPlan(
          id: generateId(),
          name: 'باقة يوم',
          durationType: 'day',
          durationValue: 1,
          price: 10.0,
        ),
      );
    }

    // Seed products
 /*   final products = await ProductDb.getProducts();
    if (products.isEmpty) {
      await ProductDb.insertProduct(
        Product(id: generateId(), name: 'قهوة', price: 5.0, stock: 20),
      );
      await ProductDb.insertProduct(
        Product(id: generateId(), name: 'مياه', price: 2.0, stock: 50),
      );
    }*/
  }


  @override
  Widget build(BuildContext context) {
    final cards = [
      _AdminCardData(
        'اداره المنتجات',
        Icons.inventory,
        () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ProductsPage()),
        ),
      ),
      _AdminCardData(
        'نسبه الارباح',
        Icons.show_chart,
        () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => FinancePage()),
        ),
      ),
      _AdminCardData(
        'الفواتير المدفوعه',
        Icons.receipt_long,
        () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SalesPage()),
        ),
      ),
    /*  _AdminCardData(
        'الفواتير الاجله',
        Icons.pending_actions,
        () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PlaceholderPage(title: 'الفواتير الآجلة'),
          ),
        ),
      ),
      _AdminCardData(
        'المشتريات المدفوعه',
        Icons.shopping_bag,
        () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PlaceholderPage(title: 'المشتريات المدفوعة'),
          ),
        ),
      ),*/
      _AdminCardData(
        'الوقت العادي',
        Icons.hourglass_bottom,
        () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PricingSettingsPage(),
          ),
        ),
      ),
      _AdminCardData(
        'إدارة الاشتراكات',
        Icons.payment,
        () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SubscriptionsPage()),
        ),
      ),
      _AdminCardData(
        'الخصومات',
        Icons.discount,
        () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => DiscountsPage()),
        ),
      ),_AdminCardData("أرصدة العملاء", Icons.account_balance, () {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => CustomersBalancesPage()));
      }),

    ];
    Future<String?> _askForNewPassword(BuildContext context) async {
      final controller = TextEditingController();
      return showDialog<String>(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: const Text("أدخل كلمة السر الجديدة"),
              content: TextField(
                controller: controller,
                obscureText: true,
                decoration: const InputDecoration(
                  hintText: "كلمة السر الجديدة",
                ),
                onSubmitted: (_) => Navigator.pop(ctx, controller.text),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text("إلغاء"),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, controller.text),
                  child: const Text("حفظ"),
                ),
              ],
            ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة الأدمن'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.lock_reset),
            tooltip: "تغيير كلمة السر",
            onPressed: () async {
              final role = await showDialog<String>(
                context: context,
                builder: (ctx) => SimpleDialog(
                  title: const Text("اختر الحساب"),
                  children: [
                    SimpleDialogOption(
                      onPressed: () => Navigator.pop(ctx, "admin"),
                      child: const Text("الأدمن"),
                    ),
                    SimpleDialogOption(
                      onPressed: () => Navigator.pop(ctx, "cashier"),
                      child: const Text("الكاشير"),
                    ),
                  ],
                ),
              );

              if (role != null) {
                final newPass = await _askForNewPassword(context);
                if (newPass != null && newPass.isNotEmpty) {
                  if (role == "admin") {
                    AdminDataService.instance.updateAdminPassword(newPass);
                  } else {
                    AdminDataService.instance.updateCashierPassword(newPass);
                  }

                  setState(() {}); // لتحديث الواجهة لو مطلوب
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("تم تغيير كلمة سر $role")),
                  );
                }
              }
            },
          ),

          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {}),
            tooltip: 'تحديث',
          ),
        ],
      ),

      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, // شبكه 2 عمود
            mainAxisSpacing: 18,
            crossAxisSpacing: 18,
            childAspectRatio: 2.6,
          ),
          itemCount: cards.length,
          itemBuilder: (context, i) => AdminCard(data: cards[i]),
        ),
      ),
    );
  }
}

class _AdminCardData {
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  _AdminCardData(this.title, this.icon, this.onTap);
}

class AdminCard extends StatelessWidget {
  final _AdminCardData data;
  const AdminCard({required this.data, super.key});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: data.onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2A69FF), width: 2),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.transparent, Colors.white.withOpacity(0.02)],
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
        child: Row(
          children: [
            Icon(data.icon, size: 36, color: const Color(0xFF2A69FF)),
            const SizedBox(width: 18),
            Text(
              data.title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
            ),
            const Spacer(),
            const Icon(Icons.keyboard_arrow_left, size: 30),
          ],
        ),
      ),
    );
  }
}
