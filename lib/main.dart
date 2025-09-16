/*
// main.dart
// Flutter desktop app (Windows/Mac/Linux) - واجهة أدمن مكتملة (CRUD لكل صفحات الأدمن)
// تصميم مستوحى من الصورة: ثيم داكن، بطاقات كبيرة بحدود زرقاء، اتجاه RTL

import 'package:flutter/material.dart';
import 'dart:math';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() {
  runApp(const WorkspaceCashierApp());
}

class WorkspaceCashierApp extends StatelessWidget {
  const WorkspaceCashierApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'WorkSpace Cashier',
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B0F1A),
        cardTheme: const CardTheme(elevation: 0, color: Colors.transparent),
        textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Roboto'),
      ),
      home: const Directionality(
        textDirection: TextDirection.rtl, // واجهة عربية
        child: HomeRouter(),
      ),
    );
  }
}
class PricingSettings {
  final int firstFreeMinutes;   // أول ربع ساعة مجانا
  final double firstHourFee;    // أول ساعة بـ 15ج
  final double perHourAfterFirst; // بعد أول ساعة 10ج
  final double dailyCap;        // الحد الأقصى 90ج باليوم

  PricingSettings({
    required this.firstFreeMinutes,
    required this.firstHourFee,
    required this.perHourAfterFirst,
    required this.dailyCap,
  });
}

// ------------------------- Simple in-memory admin data service -------------------------
class AdminDataService {
  // Singleton
  AdminDataService._privateConstructor();
  static final AdminDataService instance =
      AdminDataService._privateConstructor();

  final List<SubscriptionPlan> subscriptions = [];
  final List<Product> products = [];
  final List<Expense> expenses = [];
  final List<Sale> sales = [];
  final List<Discount> discounts = [];
  final PricingSettings settings = PricingSettings(
    firstFreeMinutes: 15,
    firstHourFee: 15,
    perHourAfterFirst: 10,
    dailyCap: 90,
  );
  // helpers
  double get totalSales => sales.fold(0.0, (p, e) => p + e.amount);
  double get totalExpenses => expenses.fold(0.0, (p, e) => p + e.amount);
  double get profit => totalSales - totalExpenses;
}

class SubscriptionPlan {
  final String id;
  String name;
  double pricePerHour;

  SubscriptionPlan({
    required this.id,
    required this.name,
    required this.pricePerHour,
  });
}

class Product {
  final String id;
  String name;
  double price;
  int stock;
  Product({
    required this.id,
    required this.name,
    required this.price,
    this.stock = 0,
  });
}

class Expense {
  final String id;
  String title;
  double amount;
  DateTime date;
  Expense({
    required this.id,
    required this.title,
    required this.amount,
    DateTime? date,
  }) : date = date ?? DateTime.now();
}

class Sale {
  final String id;
  String description;
  double amount;
  DateTime date;
  Sale({
    required this.id,
    required this.description,
    required this.amount,
    DateTime? date,
  }) : date = date ?? DateTime.now();
}

class Discount {
  final String id;
  String code;
  double percent; // 0-100
  DateTime? expiry;
  bool singleUse;
  Discount({
    required this.id,
    required this.code,
    required this.percent,
    this.expiry,
    this.singleUse = false,
  });
}

String _randId() => Random().nextInt(1000000).toString();

// ------------------------- Home Router -------------------------
class HomeRouter extends StatelessWidget {
  const HomeRouter({super.key});

  @override
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
                    ),
                    const SizedBox(width: 24),
                    _roleButton(
                      context,
                      'واجهة الكاشير',
                      Icons.point_of_sale,
                      const CashierScreen(),
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
    Widget route,
  ) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF0E1624),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      onPressed:
          () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => route)),
      child: Row(
        children: [
          Icon(icon, size: 36),
          const SizedBox(width: 12),
          Text(title, style: const TextStyle(fontSize: 18)),
        ],
      ),
    );
  }
}

// ------------------------- Admin Dashboard with navigation to full pages -------------------------
class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final AdminDataService ds = AdminDataService.instance;

  @override
  void initState() {
    super.initState();
    // Seed some demo data if empty
    if (ds.subscriptions.isEmpty) {
      ds.subscriptions.addAll([
        SubscriptionPlan(id: _randId(), name: 'باقة ساعة', pricePerHour: 15.0),
        SubscriptionPlan(id: _randId(), name: 'باقة يوم', pricePerHour: 10.0),
      ]);
    }
    if (ds.products.isEmpty) {
      ds.products.addAll([
        Product(id: _randId(), name: 'قهوة', price: 5.0, stock: 20),
        Product(id: _randId(), name: 'مياه', price: 2.0, stock: 50),
      ]);
    }
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
      _AdminCardData(
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
      ),
      _AdminCardData(
        'المشتريات الاجله',
        Icons.hourglass_bottom,
        () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PlaceholderPage(title: 'المشتريات الآجلة'),
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
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة الأدمن'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
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

// ------------------------- Products Page (CRUD) -------------------------
class ProductsPage extends StatefulWidget {
  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  final AdminDataService ds = AdminDataService.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('اداره المنتجات')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ElevatedButton.icon(
              onPressed: _addProduct,
              icon: const Icon(Icons.add),
              label: const Text('اضف منتج جديد'),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: ds.products.length,
                itemBuilder: (context, i) {
                  final p = ds.products[i];
                  return Card(
                    color: const Color(0xFF071022),
                    child: ListTile(
                      title: Text(p.name),
                      subtitle: Text(
                        'سعر: ${p.price.toStringAsFixed(2)} - مخزون: ${p.stock}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => _editProduct(p),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () => _deleteProduct(p),
                          ),
                        ],
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

  Future<void> _addProduct() async {
    final res = await showDialog<Product?>(
      context: context,
      builder: (_) => ProductDialog(),
    );
    if (res != null) {
      setState(() => ds.products.add(res));
    }
  }

  Future<void> _editProduct(Product p) async {
    final res = await showDialog<Product?>(
      context: context,
      builder: (_) => ProductDialog(product: p),
    );
    if (res != null) {
      setState(() {
        p.name = res.name;
        p.price = res.price;
        p.stock = res.stock;
      });
    }
  }

  void _deleteProduct(Product p) {
    setState(() => ds.products.remove(p));
  }
}

class ProductDialog extends StatefulWidget {
  final Product? product;
  ProductDialog({this.product});
  @override
  State<ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<ProductDialog> {
  late TextEditingController _name;
  late TextEditingController _price;
  late TextEditingController _stock;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.product?.name ?? '');
    _price = TextEditingController(
      text: widget.product?.price.toString() ?? '0',
    );
    _stock = TextEditingController(
      text: widget.product?.stock.toString() ?? '0',
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.product == null ? 'اضف منتج' : 'تعديل المنتج'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'الاسم'),
          ),
          TextField(
            controller: _price,
            decoration: const InputDecoration(labelText: 'السعر'),
            keyboardType: TextInputType.number,
          ),
          TextField(
            controller: _stock,
            decoration: const InputDecoration(labelText: 'المخزون'),
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
            final name = _name.text.trim();
            final price = double.tryParse(_price.text) ?? 0.0;
            final stock = int.tryParse(_stock.text) ?? 0;
            if (name.isEmpty) return;
            final p = Product(
              id: widget.product?.id ?? _randId(),
              name: name,
              price: price,
              stock: stock,
            );
            Navigator.pop(context, p);
          },
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}

// ------------------------- Subscriptions Page (CRUD) -------------------------
class SubscriptionsPage extends StatefulWidget {
  @override
  State<SubscriptionsPage> createState() => _SubscriptionsPageState();
}

class _SubscriptionsPageState extends State<SubscriptionsPage> {
  final AdminDataService ds = AdminDataService.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('اداره الاشتراكات')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ElevatedButton.icon(
              onPressed: _addPlan,
              icon: const Icon(Icons.add),
              label: const Text('اضف باقه'),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: ds.subscriptions.length,
                itemBuilder: (context, i) {
                  final s = ds.subscriptions[i];
                  return Card(
                    color: const Color(0xFF071022),
                    child: ListTile(
                      title: Text(s.name),
                      subtitle: Text(
                        'سعر الساعة: ${s.pricePerHour.toStringAsFixed(2)}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => _editPlan(s),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () => _deletePlan(s),
                          ),
                        ],
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

  Future<void> _addPlan() async {
    final res = await showDialog<SubscriptionPlan?>(
      context: context,
      builder: (_) => SubscriptionDialog(),
    );
    if (res != null) setState(() => ds.subscriptions.add(res));
  }

  Future<void> _editPlan(SubscriptionPlan p) async {
    final res = await showDialog<SubscriptionPlan?>(
      context: context,
      builder: (_) => SubscriptionDialog(plan: p),
    );
    if (res != null)
      setState(() {
        p.name = res.name;
        p.pricePerHour = res.pricePerHour;
      });
  }

  void _deletePlan(SubscriptionPlan p) {
    setState(() => ds.subscriptions.remove(p));
  }
}

class SubscriptionDialog extends StatefulWidget {
  final SubscriptionPlan? plan;
  SubscriptionDialog({this.plan});
  @override
  State<SubscriptionDialog> createState() => _SubscriptionDialogState();
}

class _SubscriptionDialogState extends State<SubscriptionDialog> {
  late TextEditingController _name;
  late TextEditingController _price;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.plan?.name ?? '');
    _price = TextEditingController(
      text: widget.plan?.pricePerHour.toString() ?? '0',
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.plan == null ? 'اضف باقة' : 'تعديل الباقة'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'اسم الباقة'),
          ),
          TextField(
            controller: _price,
            decoration: const InputDecoration(labelText: 'سعر الساعة'),
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
            final name = _name.text.trim();
            final price = double.tryParse(_price.text) ?? 0.0;
            if (name.isEmpty) return;
            final plan = SubscriptionPlan(
              id: widget.plan?.id ?? _randId(),
              name: name,
              pricePerHour: price,
            );
            Navigator.pop(context, plan);
          },
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}

// ------------------------- Finance Page (Expenses & Profit) -------------------------
class FinancePage extends StatefulWidget {
  @override
  State<FinancePage> createState() => _FinancePageState();
}

class _FinancePageState extends State<FinancePage> {
  final AdminDataService ds = AdminDataService.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المصاريف و الأرباح')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _addExpense,
                  icon: const Icon(Icons.add),
                  label: const Text('اضف مصروف'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _recordSale,
                  icon: const Icon(Icons.point_of_sale),
                  label: const Text('سجل بيع'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Card(
              color: const Color(0xFF071022),
              child: ListTile(
                title: const Text('ملخص'),
                subtitle: Text(
                  'إجمالي المبيعات: ${ds.totalSales.toStringAsFixed(2)}  |  إجمالي المصاريف: ${ds.totalExpenses.toStringAsFixed(2)}',
                ),
                trailing: Text('الربح: ${ds.profit.toStringAsFixed(2)}'),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  const Text(
                    'قائمة المصاريف',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  ...ds.expenses.map(
                    (e) => Card(
                      color: const Color(0xFF071022),
                      child: ListTile(
                        title: Text(e.title),
                        subtitle: Text('${e.date.toLocal()}'),
                        trailing: Text(e.amount.toStringAsFixed(2)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'سجل المبيعات',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  ...ds.sales.map(
                    (s) => Card(
                      color: const Color(0xFF071022),
                      child: ListTile(
                        title: Text(s.description),
                        subtitle: Text('${s.date.toLocal()}'),
                        trailing: Text(s.amount.toStringAsFixed(2)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addExpense() async {
    final res = await showDialog<Expense?>(
      context: context,
      builder: (_) => ExpenseDialog(),
    );
    if (res != null) setState(() => ds.expenses.add(res));
  }

  Future<void> _recordSale() async {
    final res = await showDialog<Sale?>(
      context: context,
      builder: (_) => SaleDialog(),
    );
    if (res != null) setState(() => ds.sales.add(res));
  }
}

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
              Expense(id: _randId(), title: title, amount: amount),
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
              Sale(id: _randId(), description: d, amount: a),
            );
          },
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}

// ------------------------- Sales Page (view & export) -------------------------
class SalesPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ds = AdminDataService.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('الفواتير المدفوعه')),
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
              child: ListView.builder(
                itemCount: ds.sales.length,
                itemBuilder: (context, i) {
                  final s = ds.sales[i];
                  return Card(
                    color: const Color(0xFF071022),
                    child: ListTile(
                      title: Text(s.description),
                      subtitle: Text('${s.date.toLocal()}'),
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

// ------------------------- Discounts Page (CRUD) -------------------------
class DiscountsPage extends StatefulWidget {
  @override
  State<DiscountsPage> createState() => _DiscountsPageState();
}

class _DiscountsPageState extends State<DiscountsPage> {
  final AdminDataService ds = AdminDataService.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الخصومات')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ElevatedButton.icon(
              onPressed: _addDiscount,
              icon: const Icon(Icons.add),
              label: const Text('اضف خصم'),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: ds.discounts.length,
                itemBuilder: (context, i) {
                  final d = ds.discounts[i];
                  return Card(
                    color: const Color(0xFF071022),
                    child: ListTile(
                      title: Text(d.code),
                      subtitle: Text(
                        'خصم: ${d.percent}% - صلاحية: ${d.expiry?.toLocal().toString().split(' ').first ?? 'غير محددة'}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => _editDiscount(d),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () => _deleteDiscount(d),
                          ),
                        ],
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

  Future<void> _addDiscount() async {
    final res = await showDialog<Discount?>(
      context: context,
      builder: (_) => DiscountDialog(),
    );
    if (res != null) setState(() => ds.discounts.add(res));
  }

  Future<void> _editDiscount(Discount d) async {
    final res = await showDialog<Discount?>(
      context: context,
      builder: (_) => DiscountDialog(discount: d),
    );
    if (res != null)
      setState(() {
        d.code = res.code;
        d.percent = res.percent;
        d.expiry = res.expiry;
        d.singleUse = res.singleUse;
      });
  }

  void _deleteDiscount(Discount d) {
    setState(() => ds.discounts.remove(d));
  }
}

class DiscountDialog extends StatefulWidget {
  final Discount? discount;
  DiscountDialog({this.discount});
  @override
  State<DiscountDialog> createState() => _DiscountDialogState();
}

class _DiscountDialogState extends State<DiscountDialog> {
  late TextEditingController _code;
  late TextEditingController _percent;
  DateTime? _expiry;
  bool _single = false;

  @override
  void initState() {
    super.initState();
    _code = TextEditingController(text: widget.discount?.code ?? '');
    _percent = TextEditingController(
      text: widget.discount?.percent.toString() ?? '0',
    );
    _expiry = widget.discount?.expiry;
    _single = widget.discount?.singleUse ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.discount == null ? 'اضف خصم' : 'تعديل الخصم'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _code,
            decoration: const InputDecoration(labelText: 'كود الخصم'),
          ),
          TextField(
            controller: _percent,
            decoration: const InputDecoration(labelText: 'نسبة الخصم'),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                _expiry == null
                    ? 'لا توجد صلاحية'
                    : 'صلاحية حتى: ${_expiry!.toLocal().toString().split(' ').first}',
              ),
              const Spacer(),
              TextButton(
                onPressed: _pickExpiry,
                child: const Text('اختيار تاريخ'),
              ),
            ],
          ),
          Row(
            children: [
              const Text('استخدام مرة واحدة'),
              Checkbox(
                value: _single,
                onChanged: (v) => setState(() => _single = v ?? false),
              ),
            ],
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
            final code = _code.text.trim();
            final percent = double.tryParse(_percent.text) ?? 0.0;
            if (code.isEmpty) return;
            Navigator.pop(
              context,
              Discount(
                id: widget.discount?.id ?? _randId(),
                code: code,
                percent: percent,
                expiry: _expiry,
                singleUse: _single,
              ),
            );
          },
          child: const Text('حفظ'),
        ),
      ],
    );
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiry ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 3650)),
    );
    if (picked != null) setState(() => _expiry = picked);
  }
}

// ------------------------- Placeholder Page for not-yet-implemented lists -------------------------
class PlaceholderPage extends StatelessWidget {
  final String title;
  const PlaceholderPage({required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(child: Text('$title - سيتم اضافته قريبًا')),
    );
  }
}

// ------------------------- Cashier Screen (simple) -------------------------
// ------------------------- Cashier Screen -------------------------
class CashierScreen extends StatefulWidget {
  const CashierScreen({super.key});

  @override
  State<CashierScreen> createState() => _CashierScreenState();
}

class _CashierScreenState extends State<CashierScreen> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _qtyCtrl = TextEditingController(text: '1');

  final List<_Session> _sessions = [];
  final List<CartItem> cart = [];

  Product? _selectedProduct;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('واجهة الكاشير')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // تسجيل جلسة جديدة
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      hintText: 'اسم العميل',
                      filled: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _startSession,
                  child: const Text('ابدأ تسجيل'),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // قائمة الجلسات
            Expanded(
              child: ListView.builder(
                itemCount: _sessions.length,
                itemBuilder: (context, i) {
                  final s = _sessions[i];
                  return Card(
                    child: ListTile(
                      title: Text(s.name),
                      subtitle: Text(
                        s.isActive
                            ? 'قيد الاستخدام - ${s.start}'
                            : 'انتهت - ${s.amountPaid.toStringAsFixed(2)} ج',
                      ),
                      trailing: s.isActive
                          ? ElevatedButton(
                        onPressed: () => _stopSession(i),
                        child: const Text('انهاء'),
                      )
                          : const Icon(Icons.check_circle_outline),
                    ),
                  );
                },
              ),
            ),

            const Divider(),
            // إضافة منتجات للفاتورة
            if (_sessions.any((s) => s.isActive)) ...[
              Row(
                children: [
                  Expanded(
                    child: DropdownButton<Product>(
                      value: _selectedProduct,
                      hint: const Text('اختر منتج'),
                      isExpanded: true,
                      items: AdminDataService.instance.products
                          .map((p) => DropdownMenuItem(
                        value: p,
                        child: Text('${p.name} (${p.price} ج)'),
                      ))
                          .toList(),
                      onChanged: (val) {
                        setState(() => _selectedProduct = val);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 60,
                    child: TextField(
                      controller: _qtyCtrl,
                      decoration: const InputDecoration(labelText: 'عدد'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _addProductToCart,
                    child: const Text('اضف'),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // عرض الفاتورة
              SizedBox(
                height: 150,
                child: ListView(
                  children: cart
                      .map((c) => ListTile(
                    title: Text(c.product.name),
                    subtitle: Text(
                        '${c.qty} × ${c.product.price} = ${c.total.toStringAsFixed(2)} ج'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () {
                        setState(() => cart.remove(c));
                      },
                    ),
                  ))
                      .toList(),
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _completeAndPay,
                child: const Text('إتمام ودفع'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _startSession() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اكتب اسم العميل')),
      );
      return;
    }
    setState(() {
      _sessions.insert(
        0,
        _Session(name: name, start: DateTime.now()),
      );
      _nameCtrl.clear();
    });
  }

  void _stopSession(int index) {
    setState(() {
      final s = _sessions[index];
      if (!s.isActive) return;

      final minutes = DateTime.now().difference(s.start).inMinutes;
      final settings = AdminDataService.instance.settings;

      double amount = 0;
      if (minutes <= settings.firstFreeMinutes) {
        amount = 0;
      } else if (minutes <= 60) {
        amount = settings.firstHourFee;
      } else {
        final extraHours = ((minutes - 60) / 60).ceil();
        amount = settings.firstHourFee +
            extraHours * settings.perHourAfterFirst;
      }
      if (amount > settings.dailyCap) amount = settings.dailyCap;

      s.isActive = false;
      s.amountPaid = amount;
    });
  }

  void _addProductToCart() {
    if (_selectedProduct == null) return;
    final qty = int.tryParse(_qtyCtrl.text) ?? 1;
    setState(() {
      cart.add(CartItem(product: _selectedProduct!, qty: qty));
    });
  }

  void _completeAndPay() {
    if (!_sessions.any((s) => s.isActive)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد جلسة فعالة')),
      );
      return;
    }
    final s = _sessions.firstWhere((s) => s.isActive);

    // احسب وقت الجلسة
    final minutes = DateTime.now().difference(s.start).inMinutes;
    final settings = AdminDataService.instance.settings;
    double timeCharge = 0;
    if (minutes <= settings.firstFreeMinutes) {
      timeCharge = 0;
    } else if (minutes <= 60) {
      timeCharge = settings.firstHourFee;
    } else {
      final extraHours = ((minutes - 60) / 60).ceil();
      timeCharge = settings.firstHourFee +
          extraHours * settings.perHourAfterFirst;
    }
    if (timeCharge > settings.dailyCap) timeCharge = settings.dailyCap;

    // اجمالي المنتجات
    final productsTotal = cart.fold(
      0.0,
          (sum, item) => sum + item.total,
    );

    final total = timeCharge + productsTotal;

    setState(() {
      s.isActive = false;
      s.amountPaid = total;
      cart.clear();
    });

    AdminDataService.instance.sales.add(
      Sale(
        id: _randId(),
        description:
        'جلسة ${s.name} | وقت: ${timeCharge.toStringAsFixed(2)} + منتجات: ${productsTotal.toStringAsFixed(2)}',
        amount: total,
      ),
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم الدفع: ${total.toStringAsFixed(2)} ج')),
    );
  }
}

class _Session {
  final String name;
  final DateTime start;
  bool isActive;
  double amountPaid;
  _Session({
    required this.name,
    required this.start,
    this.isActive = true,
    this.amountPaid = 0,
  });
}

class CartItem {
  final Product product;
  final int qty;
  CartItem({required this.product, required this.qty});
  double get total => product.price * qty;
}
*/
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/data_service.dart';
import 'screens/home_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'core/product_db.dart'; // للوصول إلى ProductDb
import 'core/db_helper_Subscribe.dart'; // للوصول إلى SubscriptionDb

void main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  WidgetsFlutterBinding.ensureInitialized();
  await AdminDataService.instance.init();

  //  await AdminDataService.instance.loadAll();
  await loadData();
  //  await AdminDataService.instance.loadPasswords();
  runApp(const WorkspaceCashierApp());
}

Future<void> loadData() async {
  final products = await ProductDb.getProducts();
  final subscriptions = await SubscriptionDb.getPlans();

  AdminDataService.instance.products
    ..clear()
    ..addAll(products);

  AdminDataService.instance.subscriptions
    ..clear()
    ..addAll(subscriptions);
}

class WorkspaceCashierApp extends StatelessWidget {
  const WorkspaceCashierApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'WorkSpace Cashier',
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B0F1A),
        textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Roboto'),

        // تخصيص الـ Dialog
        dialogTheme: DialogTheme(
          backgroundColor: const Color(0xFF1A2233), // لون خلفية الدايلوج
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          titleTextStyle: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          contentTextStyle: const TextStyle(
            fontSize: 16,
            color: Colors.white70,
          ),
        ),

        // تخصيص أزرار TextButton زي اللي جوه SimpleDialogOption
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFFFF2A2A), // لون النص + الأيقونة
            textStyle: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        // تخصيص أزرار ElevatedButton (زي زرار الدخول)
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF5387FF),
            foregroundColor: Colors.white,
            textStyle: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),

      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: HomeRouter(),
      ),
    );
  }
}

////كدا واقف ان الاشتراكات ملهاش نهايه هو بيحسب سعرها وخلاص
