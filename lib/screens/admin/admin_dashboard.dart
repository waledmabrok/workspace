import 'package:flutter/material.dart';
import 'package:workspace/screens/admin/placeholder_page.dart';
import 'package:workspace/screens/admin/products_page.dart';
import 'package:workspace/screens/admin/sales_page.dart';
import 'package:workspace/screens/admin/subscriptions_page.dart';
import 'package:workspace/screens/admin/CustomersBalancesPage.dart';
import 'package:workspace/widget/buttom.dart';
import 'dart:math';
import '../../core/db_helper_Subscribe.dart';
import '../../core/data_service.dart';
import '../../core/models.dart';
import '../../utils/colors.dart';
import 'CustomerSubscribe.dart';
import 'MAin_dashboard.dart';
import 'discounts_page.dart';
import 'finance_page.dart';
import 'Room.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

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
          price: 90.0,
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
        'غرف',
        Icons.laptop,
        () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => RoomsPage()),
        ),
      ),
      _AdminCardData(
        'الوقت العادي',
        Icons.hourglass_bottom,
        () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PricingSettingsPage()),
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
        'اداره المنتجات',
        Icons.inventory,
        () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ProductsPage()),
        ),
      ),
      _AdminCardData(
        'شيفتات',
        Icons.inventory,
        () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => DashboardPagee()),
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

      /*  _AdminCardData(
        'الخصومات',
        Icons.discount,
        () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => DiscountsPage()),
        ),
      ),*/
      _AdminCardData("أرصدة العملاء", Icons.account_balance, () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => CustomersBalancesPage()),
        );
      }),
      _AdminCardData("المشتركين", Icons.account_balance, () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AdminSubscribersPage()),
        );
      }),
    ];

    Future<String?> _askForNewPassword(BuildContext context) async {
      final controller = TextEditingController();
      return showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
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
        forceMaterialTransparency: true,
        title: Center(
          child: const Text(
            'لوحة الأدمن',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 25),
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.delete),
            color: Colors.red,
            tooltip: "مسح البيانات",
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: Text('تأكيد'),
                  content: Text('هل أنت متأكد أنك تريد مسح جميع البيانات؟'),
                  actions: [
                    CustomButton(
                      onPressed: () => Navigator.pop(context, false),
                      text: 'إلغاء',
                      infinity: false,
                      border: true,
                    ),
                    CustomButton(
                      onPressed: () => Navigator.pop(context, true),
                      text: 'مسح',
                      infinity: false,
                    ),
                  ],
                ),
              );

              if (confirm == true) {
                await AdminDataService.instance.clearAllData();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('تم مسح جميع البيانات ✅')),
                );
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
          child: ListView.builder(
            itemCount: (cards.length / 2).ceil(),
            padding: const EdgeInsets.all(12), // مسافة من الحواف لو عايز
            itemBuilder: (context, i) {
              final first = cards[i * 2];
              final second =
                  (i * 2 + 1 < cards.length) ? cards[i * 2 + 1] : null;

              return Padding(
                padding:
                    const EdgeInsets.only(bottom: 25), // المسافة بين الصفوف
                child: Row(
                  children: [
                    Expanded(child: AdminCard(data: first)),
                    if (second != null) ...[
                      SizedBox(width: 25), // المسافة بين الأعمدة
                      Expanded(child: AdminCard(data: second)),
                    ],
                  ],
                ),
              );
            },
          )),
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
        height: 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColorsDark.mainColor,
            width: 2,
          ), // اللون الأزرق كما في الصورة
          color: Colors.transparent, // خلفية داكنة مشابهة للصورة
        ),
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              data.icon,
              size: 50,
              color: AppColorsDark.mainColor.withOpacity(
                0.4,
              ), // نفس اللون للأيقونة
            ),
            const SizedBox(height: 16), // مسافة بين الأيقونة والنص
            Text(
              data.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 25,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
