/*
import 'db_helper_discounts.dart';
import 'db_helper_main_time.dart';
import 'FinanceDb.dart';
import 'models.dart';

class AdminDataService {
  AdminDataService._();
  static final AdminDataService instance = AdminDataService._();

  // 👤 الباسوردات
  String adminPassword = "1234";
  String cashierPassword = "0000";

  // 📦 البيانات الحية في الذاكرة
  final List<SubscriptionPlan> subscriptions = [];
  final List<Product> products = [];
  List<Expense> expenses = [];
  List<Sale> sales = [];
  final List<Discount> discounts = [];

  // ⚙️ إعدادات التسعير
  late PricingSettings pricingSettings;

  // ------------------- Init -------------------
  Future<void> init() async {
    pricingSettings = await PricingDb.loadSettings();

    // تحميل البيانات من قاعدة البيانات
    expenses = await FinanceDb.getExpenses();
    sales = await FinanceDb.getSales();
    discounts.clear();
    discounts.addAll(await DiscountDb.getAll()); // 🟢 تحميل الخصومات
  }

  // ------------------- تحديث الباسوردات -------------------
  void updateAdminPassword(String newPassword) {
    adminPassword = newPassword;
  }

  void updateCashierPassword(String newPassword) {
    cashierPassword = newPassword;
  }

  // ------------------- CRUD للاشتراكات -------------------
  void addSubscription(SubscriptionPlan plan) => subscriptions.add(plan);

  void updateSubscription(SubscriptionPlan plan) {
    final index = subscriptions.indexWhere((s) => s.id == plan.id);
    if (index != -1) subscriptions[index] = plan;
  }

  void deleteSubscription(String id) =>
      subscriptions.removeWhere((s) => s.id == id);

  // ------------------- CRUD للمنتجات -------------------
  void addProduct(Product p) => products.add(p);

  void updateProduct(Product p) {
    final index = products.indexWhere((prod) => prod.id == p.id);
    if (index != -1) products[index] = p;
  }

  void deleteProduct(String id) => products.removeWhere((p) => p.id == id);

  // ------------------- المبيعات والمصاريف -------------------
  Future<void> addExpense(Expense e) async {
    await FinanceDb.insertExpense(e);
    expenses.add(e);
  }

  Future<void> addSale(Sale s) async {
    await FinanceDb.insertSale(s);
    sales.add(s);
  }

  // ------------------- الخصومات -------------------
  Future<void> addDiscount(Discount d) async {
    await DiscountDb.insert(d);
    discounts.add(d);
  }

  Future<void> updateDiscount(Discount d) async {
    await DiscountDb.update(d);
    final index = discounts.indexWhere((x) => x.id == d.id);
    if (index != -1) discounts[index] = d;
  }

  Future<void> deleteDiscount(String id) async {
    await DiscountDb.delete(id);
    discounts.removeWhere((d) => d.id == id);
  }

  // ------------------- الإحصائيات -------------------
  double get totalSales => sales.fold(0.0, (p, e) => p + e.amount);
  double get totalExpenses => expenses.fold(0.0, (p, e) => p + e.amount);
  double get profit => totalSales - totalExpenses;
}

// ⚙️ إعدادات التسعير
class PricingSettings {
  final int firstFreeMinutes;
  final double firstHourFee;
  final double perHourAfterFirst;
  final double dailyCap;

  PricingSettings({
    required this.firstFreeMinutes,
    required this.firstHourFee,
    required this.perHourAfterFirst,
    required this.dailyCap,
  });
}
*/
import 'dart:convert';

import 'Db_helper.dart';
import 'db_helper_discounts.dart';
import 'db_helper_main_time.dart';
import 'FinanceDb.dart';
import 'models.dart';

class AdminDataService {
  AdminDataService._();
  static final AdminDataService instance = AdminDataService._();

  // 👤 الباسوردات
  String adminPassword = "1234";
  String cashierPassword = "0000";
  int? currentShiftId;

  // 📦 البيانات الحية في الذاكرة
  final List<SubscriptionPlan> subscriptions = [];
  final List<Product> products = [];
  List<Expense> expenses = [];
  List<Sale> sales = [];
  final List<Discount> discounts = [];
  List<Customer> customers = [];
  List<CustomerBalance> customerBalances = [];
  // ⚙️ إعدادات التسعير
  late PricingSettings pricingSettings;

  // ===== رصيد درج الكاشير (مخزن بالذاكرة للعرض السريع) =====
  double drawerBalance = 0.0;
  // رصيد درج الكاشير

  // ------------------- تعديل رصيد الدرج يدويًا
  Future<void> setDrawerBalance(double newBalance) async {
    final delta = newBalance - drawerBalance; // الفرق بين القديم والجديد
    drawerBalance = newBalance;

    try {
      await FinanceDb.setDrawerBalance(newBalance);

      if (delta > 0) {
        // فرق موجب = زيادة في الأرباح (سجلها كمبيعة بدون عميل)
        await addSale(
          Sale(amount: delta, date: DateTime.now(), id: '', description: ''),
          updateDrawer: false, // مش نضيفها تاني للدرج
        );
      } else if (delta < 0) {
        // فرق سلبي = مصروف إضافي
        await addExpense(
          Expense(amount: -delta, date: DateTime.now(), id: '', title: ''),
          deductFromDrawer: false, // مش نخصمها تاني من الدرج
        );
      }
    } catch (e) {
      await refreshDrawerBalance();
    }
  }

  // تعديل الرصيد بـ delta
  Future<void> adjustDrawerBalance(double delta) async {
    try {
      await FinanceDb.updateDrawerBalanceBy(delta);
      drawerBalance += delta;
    } catch (err) {
      await refreshDrawerBalance();
    }
  }

  // إجمالي اليوم
  double getTodaySales() {
    final now = DateTime.now();
    return sales
        .where(
          (s) =>
              s.date.year == now.year &&
              s.date.month == now.month &&
              s.date.day == now.day,
        )
        .fold(0.0, (p, e) => p + e.amount);
  }

  double getSalesByDate(DateTime date) {
    return sales
        .where(
          (s) =>
              s.date.year == date.year &&
              s.date.month == date.month &&
              s.date.day == date.day,
        )
        .fold(0.0, (sum, s) => sum + s.amount);
  }

  double getDrawerBalanceByDate(DateTime date) {
    final salesForDay = getSalesByDate(date);
    final expensesForDay = getExpensesByDate(date);
    return salesForDay - expensesForDay;
  }

  double getAllSales() {
    return sales.fold(0.0, (sum, s) => sum + s.amount);
  }

  double getExpensesByDate(DateTime date) {
    return expenses
        .where(
          (e) =>
              e.date.year == date.year &&
              e.date.month == date.month &&
              e.date.day == date.day,
        )
        .fold(0.0, (sum, e) => sum + e.amount);
  }

  double getAllExpenses() {
    return expenses.fold(0.0, (sum, e) => sum + e.amount);
  }

  double getProfitByDate(DateTime date) {
    return getSalesByDate(date) - getExpensesByDate(date);
  }

  double getAllProfit() {
    return getAllSales() - getAllExpenses();
  }

  double getTodayExpenses() {
    final now = DateTime.now();
    return expenses
        .where(
          (e) =>
              e.date.year == now.year &&
              e.date.month == now.month &&
              e.date.day == now.day,
        )
        .fold(0.0, (p, e) => p + e.amount);
  }

  double getTodayProfit() {
    return getTodaySales() - getTodayExpenses();
  }

  // ------------------- Init -------------------
  Future<void> init() async {
    pricingSettings = await PricingDb.loadSettings();

    // تحميل البيانات من قاعدة البيانات
    expenses = await FinanceDb.getExpenses();
    sales = await FinanceDb.getSales();
    discounts.clear();
    discounts.addAll(await DiscountDb.getAll()); // 🟢 تحميل الخصومات

    // جديد: تحميل رصيد درج الكاشير
    try {
      drawerBalance = await FinanceDb.getDrawerBalance();
    } catch (e) {
      // تجاهل أو لوج إذا لازم
      drawerBalance = 0.0;
    }
  }

  // تحديث رصيد الدرج من DB (يمكن استدعاؤها بعد أي تغيير أو دورياً)
  Future<void> refreshDrawerBalance() async {
    try {
      drawerBalance = await FinanceDb.getDrawerBalance();
    } catch (e) {
      drawerBalance = 0.0;
    }
  }

  //-----------------shift========================
  // ------ تواصل بين DbHelper وذاكرة التطبيق عند تقفيل الشيفت ------
  /// يغلق الشيفت باستخدام DbHelper.closeShiftDetailed ثم يحدث الذاكرة المحلية
  Future<Map<String, dynamic>> closeShiftAndRefresh({
    required String shiftId,
    double? countedClosingBalance,
    String? cashierName,
  }) async {
    // نفّذ إغلاق الشيفت وحفظ التقرير في DB
    final report = await DbHelper.instance.closeShiftDetailed(
      shiftId,
      countedClosingBalance: countedClosingBalance,
      cashierName: cashierName,
    );

    // حدِّث الذاكرة: المبيعات/المصاريف/رصيد الدرج
    try {
      sales = await FinanceDb.getSales();
      expenses = await FinanceDb.getExpenses();
      drawerBalance = await FinanceDb.getDrawerBalance();
    } catch (e) {
      // لو حصل خطأ في استرجاع القيم من FinanceDb، نعتمد على refreshDrawerBalance كنسخة احتياطية
      await refreshDrawerBalance();
    }

    return report;
  }

  // ------ دوال للوصول للتقارير المحفوظة (shift_reports) ------
  /// جلب كل تقارير الشيفت (اختياريًا فلترة على shiftId)
  Future<List<Map<String, dynamic>>> getShiftReports({String? shiftId}) async {
    final db = await DbHelper.instance.database;

    List<Map<String, dynamic>> rows;
    if (shiftId != null) {
      rows = await db.query(
        'shift_reports',
        where: 'shiftId = ?',
        whereArgs: [shiftId],
        orderBy: 'createdAt DESC',
      );
    } else {
      rows = await db.query('shift_reports', orderBy: 'createdAt DESC');
    }

    // فك الـ JSON وارجاع هيكل مرتب
    return rows.map((r) {
      final createdAt =
          r['createdAt'] is int
              ? DateTime.fromMillisecondsSinceEpoch(r['createdAt'] as int)
              : (r['createdAt'] != null
                  ? DateTime.tryParse(r['createdAt'].toString())
                  : null);
      Map<String, dynamic> reportJson = {};
      try {
        reportJson =
            jsonDecode(r['reportJson']?.toString() ?? '{}')
                as Map<String, dynamic>;
      } catch (_) {
        reportJson = {};
      }
      return {
        'id': r['id'],
        'shiftId': r['shiftId'],
        'report': reportJson,
        'createdAt': createdAt,
      };
    }).toList();
  }

  /// جلب تقرير واحد بحسب id
  Future<Map<String, dynamic>?> getShiftReportById(String id) async {
    final db = await DbHelper.instance.database;
    final rows = await db.query(
      'shift_reports',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    Map<String, dynamic> reportJson = {};
    try {
      reportJson =
          jsonDecode(r['reportJson']?.toString() ?? '{}')
              as Map<String, dynamic>;
    } catch (_) {
      reportJson = {};
    }
    final createdAt =
        r['createdAt'] is int
            ? DateTime.fromMillisecondsSinceEpoch(r['createdAt'] as int)
            : (r['createdAt'] != null
                ? DateTime.tryParse(r['createdAt'].toString())
                : null);
    return {
      'id': r['id'],
      'shiftId': r['shiftId'],
      'report': reportJson,
      'createdAt': createdAt,
    };
  }

  // ------------------- تحديث الباسوردات -------------------
  void updateAdminPassword(String newPassword) {
    adminPassword = newPassword;
  }

  void updateCashierPassword(String newPassword) {
    cashierPassword = newPassword;
  }

  // ------------------- CRUD للاشتراكات -------------------
  void addSubscription(SubscriptionPlan plan) => subscriptions.add(plan);

  void updateSubscription(SubscriptionPlan plan) {
    final index = subscriptions.indexWhere((s) => s.id == plan.id);
    if (index != -1) subscriptions[index] = plan;
  }

  void deleteSubscription(String id) =>
      subscriptions.removeWhere((s) => s.id == id);

  // ------------------- CRUD للمنتجات -------------------
  void addProduct(Product p) => products.add(p);

  void updateProduct(Product p) {
    final index = products.indexWhere((prod) => prod.id == p.id);
    if (index != -1) products[index] = p;
  }

  void deleteProduct(String id) => products.removeWhere((p) => p.id == id);

  // ------------------- المبيعات والمصاريف -------------------
  // ------------------- إضافة مصروف مع خصم من الدرج
  Future<void> addExpense(Expense e, {bool deductFromDrawer = true}) async {
    await FinanceDb.insertExpense(e);
    expenses.add(e);

    if (deductFromDrawer) {
      try {
        await FinanceDb.updateDrawerBalanceBy(-e.amount); // خصم من الدرج
        drawerBalance -= e.amount;
      } catch (err) {
        await refreshDrawerBalance(); // fallback لو فيه خطأ
      }
    }
  }

  /// أضف مبيعة إلى DB + ذاكرة البرنامج.
  ///
  /// اختياريًا يمكنك تمرير:
  /// - paymentMethod: 'cash' | 'wallet' | ...
  /// - customerName: اسم العميل (لو متوفر)
  /// - discount: قيمة الخصم المسجلة
  /// - updateDrawer: لو true و paymentMethod == 'cash' سيُضاف المبلغ إلى درج الكاشير
  /// - drawerDelta: لو عايز تضيف مقدار مختلف للمخزن بدل s.amount
  Future<void> addSale(
    Sale s, {
    String? paymentMethod,
    Customer? customer,
    double? discount,
    bool updateDrawer = false,
    double? drawerDelta,
  }) async {
    await FinanceDb.insertSale(
      s,
      paymentMethod: paymentMethod,
      customerId: customer?.id,
      customerName: customer?.name,
      discount: discount,
    );

    sales.add(s);

    if (updateDrawer && (paymentMethod ?? 'cash') == 'cash') {
      final delta = drawerDelta ?? s.amount;
      try {
        await FinanceDb.updateDrawerBalanceBy(delta);
        drawerBalance += delta;
      } catch (e) {
        await refreshDrawerBalance();
      }
    }
  }

  // ------------------- أرصدة العملاء (مساعدين) -------------------
  Future<double> getCustomerBalance(String customerName) async {
    return await FinanceDb.getCustomerBalance(customerName);
  }

  Future<void> setCustomerBalance(
    String customerName,
    double newBalance,
  ) async {
    await FinanceDb.setCustomerBalance(customerName, newBalance);
  }

  Future<void> adjustCustomerBalance(String customerName, double delta) async {
    await FinanceDb.adjustCustomerBalance(customerName, delta);
  }

  // ------------------- الخصومات -------------------
  Future<void> addDiscount(Discount d) async {
    await DiscountDb.insert(d);
    discounts.add(d);
  }

  Future<void> updateDiscount(Discount d) async {
    await DiscountDb.update(d);
    final index = discounts.indexWhere((x) => x.id == d.id);
    if (index != -1) discounts[index] = d;
  }

  Future<void> deleteDiscount(String id) async {
    await DiscountDb.delete(id);
    discounts.removeWhere((d) => d.id == id);
  }

  //=============room

  // ------------------- الإحصائيات -------------------
  double get totalSales => sales.fold(0.0, (p, e) => p + e.amount);
  double get totalExpenses => expenses.fold(0.0, (p, e) => p + e.amount);
  double get profit => totalSales - totalExpenses;
}

// ⚙️ إعدادات التسعير
class PricingSettings {
  final int firstFreeMinutes;
  final double firstHourFee;
  final double perHourAfterFirst;
  final double dailyCap;

  PricingSettings({
    required this.firstFreeMinutes,
    required this.firstHourFee,
    required this.perHourAfterFirst,
    required this.dailyCap,
  });
}
