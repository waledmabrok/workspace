import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:workspace/utils/colors.dart';
import 'package:workspace/widget/buttom.dart';
import '../../core/Db_helper.dart';
import '../../core/db_helper_cart.dart';
import '../../core/db_helper_sessions.dart';
import '../../core/models.dart';
import '../../core/receipt_db.dart';

enum FilterType { all, subscribers, payg }

class AdminSubscribersPage extends StatefulWidget {
  const AdminSubscribersPage({super.key});

  @override
  State<AdminSubscribersPage> createState() => _AdminSubscribersPageState();
}

class _AdminSubscribersPageState extends State<AdminSubscribersPage> {
  DateTime _selectedDate = DateTime.now();
  List<Session> _sessions = [];
  bool _loading = true;
  bool _showOnlyWithSubs = true;

  FilterType _currentFilter = FilterType.all;
  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() => _loading = true);

    // جلب كل الجلسات
    final data = await SessionDb.getSessions();

    for (var s in data) {
      try {
        s.cartCopy = await CartDb.getCartCopyBySession(s.id);
        s.receipts = await ReceiptDb.getReceiptsBySession(
            s.id); // لو ضفت receipts للـ Session
      } catch (e) {
        s.cartCopy = [];
        s.receipts = [];
        debugPrint("Failed to load cart/receipts for session ${s.id}: $e");
      }
    }

    setState(() {
      _sessions = data;
      _loading = false;
    });
  }

  // ===== مساعدات زمنية =====
  int _minutesOverlapWithDate(Session s, DateTime date) {
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final sessStart = s.start.isBefore(dayStart) ? dayStart : s.start;
    final sessEndCandidate = s.end ?? DateTime.now();
    final sessEnd =
        sessEndCandidate.isAfter(dayEnd) ? dayEnd : sessEndCandidate;
    if (sessEnd.isBefore(dayStart) || sessStart.isAfter(dayEnd)) return 0;
    return sessEnd.difference(sessStart).inMinutes;
  }

  int _totalMinutesSoFar(Session s) {
    // لو الجلسة متقفلة
    if (!s.isActive) {
      final end = s.end ?? s.start;
      return end.difference(s.start).inMinutes;
    }

    // لو الجلسة متوقفة مؤقتاً
    if (s.isPaused) {
      return s.elapsedMinutes;
    }

    // لو شغالة دلوقتي
    final now = DateTime.now();
    final since = s.pauseStart ?? s.start;
    return s.elapsedMinutes + now.difference(since).inMinutes;
  }

  DateTime? _getSubscriptionEnd(Session s) {
    final plan = s.subscription;
    if (plan == null || plan.isUnlimited) return null;
    final start = s.start;
    switch (plan.durationType) {
      case "hour":
        return start.add(Duration(hours: plan.durationValue ?? 0));
      case "day":
        return start.add(Duration(days: plan.durationValue ?? 0));
      case "week":
        return start.add(Duration(days: 7 * (plan.durationValue ?? 0)));
      case "month":
        return DateTime(
          start.year,
          start.month + (plan.durationValue ?? 0),
          start.day,
          start.hour,
          start.minute,
        );
      default:
        return null;
    }
  }

  String _formatMinutes(int minutes) {
    if (minutes <= 0) return "0د";
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0) return "${h}س ${m}د";
    return "${m}د";
  }

  @override
  Widget build(BuildContext context) {
    final filteredSessions = _sessions.where((s) {
      final start = s.start;
      final end = s.end ?? DateTime.now();
      final dayStart = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      );
      final dayEnd = dayStart.add(const Duration(days: 1));
      final overlaps = start.isBefore(dayEnd) && end.isAfter(dayStart);

      if (!overlaps) return false;

      switch (_currentFilter) {
        case FilterType.all:
          return true;
        case FilterType.subscribers:
          return s.subscription != null;
        case FilterType.payg:
          return s.subscription == null;
      }
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return Scaffold(
      appBar: AppBar(
        forceMaterialTransparency: true,
        title: Center(child: const Text('المشتركين - باقات')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث',
            onPressed: _loadSessions,
          ),
          Row(
            children: [
              // عرض المشتركين فقط
              if (_currentFilter != FilterType.subscribers)
                IconButton(
                  icon: Icon(Icons.person),
                  tooltip: "عرض المشتركين فقط",
                  onPressed: () => setState(
                    () => _currentFilter = FilterType.subscribers,
                  ),
                ),
              // عرض الحر فقط
              if (_currentFilter != FilterType.payg)
                IconButton(
                  icon: Icon(Icons.person_outline),
                  tooltip: "عرض الحر فقط",
                  onPressed: () =>
                      setState(() => _currentFilter = FilterType.payg),
                ),
              // عرض الكل
              if (_currentFilter != FilterType.all)
                IconButton(
                  icon: Icon(Icons.filter_alt),
                  tooltip: "عرض الكل",
                  onPressed: () =>
                      setState(() => _currentFilter = FilterType.all),
                ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ===== فلترة بالتاريخ =====
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      const Text("عرض ليوم:", style: TextStyle(fontSize: 18)),
                      const SizedBox(width: 8),
                      CustomButton(
                        infinity: false,
                        border: true,
                        text:
                            "${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}",
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _selectedDate,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null)
                            setState(() => _selectedDate = picked);
                        },
                      ),
                      /*   ElevatedButton.icon(
                          icon: const Icon(Icons.calendar_today),
                          label: Text(
                            "${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}",
                          ),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _selectedDate,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null)
                              setState(() => _selectedDate = picked);
                          },
                        ),*/
                      const SizedBox(width: 12),
                      CustomButton(
                        text: "اليوم",
                        border: true,
                        infinity: false,
                        onPressed: () => setState(
                          () => _selectedDate = DateTime.now(),
                        ),
                      ),
                      /*     ElevatedButton(
                          onPressed:
                              () => setState(
                                () => _selectedDate = DateTime.now(),
                              ),
                          child: const Text("اليوم"),
                        ),*/
                    ],
                  ),
                ),
                Expanded(
                  child: filteredSessions.isEmpty
                      ? const Center(child: Text('لا يوجد سجلات'))
                      : ListView.builder(
                          itemCount: filteredSessions.length,
                          itemBuilder: (ctx, i) {
                            final s = filteredSessions[i];
                            final plan = s.subscription;
                            final spentToday = _minutesOverlapWithDate(
                              s,
                              _selectedDate,
                            );
                            final totalSoFar = _totalMinutesSoFar(s);
                            final allowedToday = (plan != null &&
                                    plan.dailyUsageType == 'limited' &&
                                    plan.dailyUsageHours != null)
                                ? plan.dailyUsageHours! * 60
                                : -1;
                            final remainingToday = (allowedToday > 0)
                                ? (allowedToday - spentToday).clamp(
                                    0,
                                    allowedToday,
                                  )
                                : -1;
                            final overallEnd = _getSubscriptionEnd(s);

                            return Card(
                              color: AppColorsDark.bgCardColor,
                              shape: plan == null
                                  ? null
                                  : RoundedRectangleBorder(
                                      side: BorderSide(
                                        color: AppColorsDark.mainColor,
                                        width: 2,
                                      ), // اللون والسمك
                                      borderRadius: BorderRadius.circular(
                                        12,
                                      ), // تقوس الحواف
                                    ),
                              margin: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              elevation: 0,
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: ListTile(
                                    isThreeLine: true,
                                    title: Text(
                                      s.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (plan != null)
                                          Text(
                                            "باقة: ${plan.name} • نوع: ${plan.durationType}",
                                            style: const TextStyle(
                                              color: Colors.white70,
                                            ),
                                          ),
                                        if (plan == null)
                                          const Text(
                                            "❌ بدون اشتراك",
                                            style: TextStyle(
                                              color: Colors.redAccent,
                                            ),
                                          ),
                                        const SizedBox(height: 4),
                                        Text(
                                          "اليوم: ${_formatMinutes(spentToday)} • المتبقي اليوم: ${remainingToday >= 0 ? _formatMinutes(remainingToday) : 'غير محدد'}",
                                          style: const TextStyle(
                                            color: Colors.white70,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          "مضى كلي: ${_formatMinutes(totalSoFar)} • تنتهي: ${overallEnd != null ? overallEnd.toLocal().toString().split('.').first : 'غير محدد'}",
                                          style: const TextStyle(
                                            color: Colors.white70,
                                          ),
                                        ),
                                      ],
                                    ),
                                    trailing: CustomButton(
                                      text: "تفاصيل",
                                      onPressed: () => _showSessionDetails(s),
                                      infinity: false,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  void _showSessionDetails(Session s) async {
    // 1️⃣ تحميل الفواتير
    final receiptList = await ReceiptDb.getReceiptsBySession(s.id);

    // 2️⃣ جلب الكارت الحالي للجلسة
    s.cart = await CartDb.getCartBySession(s.id, session: s);

    // ===== إعداد المتغيرات =====
    double totalPrice = 0.0;
    List<Widget> itemsList = [];

    final plan = s.subscription;

    if (plan == null) {
      // ===== جلسة حر =====
      // مجموع المنتجات الحالي + فواتير سابقة
      double productsTotal = 0.0;

      // 🛒 المنتجات الحالية
      if (s.cart.isNotEmpty) {
        itemsList.add(const Text('🛒 المنتجات الحالية:',
            style: TextStyle(fontWeight: FontWeight.bold)));
        for (var item in s.cart) {
          productsTotal += item.total;
          itemsList.add(Text(
              '${item.product.name} × ${item.qty} = ${item.total.toStringAsFixed(2)}'));
        }
      }

      // 📜 منتجات الفواتير السابقة
      if (receiptList.isNotEmpty) {
        itemsList.add(const Divider());
        itemsList.add(const Text('📜 منتجات الفواتير السابقة:',
            style: TextStyle(fontWeight: FontWeight.bold)));

        for (var receipt in receiptList) {
          final items = (jsonDecode(receipt['itemsJson']) as List).map((j) {
            return CartItem(
              id: j["id"].toString(),
              product: Product(
                id: j["id"].toString(),
                name: j["name"] ?? "بدون اسم",
                price: (j["price"] ?? 0).toDouble(),
                stock: 0,
              ),
              qty: j["qty"] ?? 1,
            );
          }).toList();

          for (var item in items) {
            productsTotal += item.total;
            itemsList.add(
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                    '${item.product.name} × ${item.qty} = ${item.total.toStringAsFixed(2)}'),
              ),
            );
          }
        }
      }

      // خلي productsTotal ثابت
      final double fixedProductsTotal = productsTotal;
      totalPrice += fixedProductsTotal;

      // الوقت المدفوع فقط (بعد خصم قيمة المنتجات)
      double paidForTimeOnly = s.amountPaid - fixedProductsTotal;
      if (paidForTimeOnly > 0) {
        itemsList.add(const Divider());
        itemsList.add(Text(
            '⏱️ الوقت المدفوع: ${paidForTimeOnly.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.bold)));
        totalPrice += paidForTimeOnly;
      }

      // لو ما فيش منتجات ولا وقت
      if (fixedProductsTotal == 0 && paidForTimeOnly <= 0) {
        itemsList.add(const Text('❌ بدون اشتراك'));
      }
    } else {
      // ===== جلسة باقة =====
      totalPrice += plan.price;
      itemsList.add(Text(
          '📦 باقة: ${plan.name} — ${plan.price.toStringAsFixed(2)}',
          style: const TextStyle(fontWeight: FontWeight.bold)));

      // منتجات إضافية (الكارت الحالي فقط بدون منتجات الباقة)
      final extraItems = s.cart
          .where((item) => !item.product.id.toString().startsWith("package-"))
          .toList();
      if (extraItems.isNotEmpty) {
        itemsList.add(const Divider());
        itemsList.add(const Text('🛒 منتجات إضافية:',
            style: TextStyle(fontWeight: FontWeight.bold)));

        for (var item in extraItems) {
          totalPrice += item.total;
          itemsList.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                  '${item.product.name} × ${item.qty} = ${item.total.toStringAsFixed(2)}'),
            ),
          );
        }
      }

      // منتجات الفواتير السابقة (بدون الباقة)
      for (var receipt in receiptList) {
        final items = (jsonDecode(receipt['itemsJson']) as List)
            .map((j) => CartItem(
                  id: j["id"].toString(),
                  product: Product(
                    id: j["id"].toString(),
                    name: j["name"] ?? "بدون اسم",
                    price: (j["price"] ?? 0).toDouble(),
                    stock: 0,
                  ),
                  qty: j["qty"] ?? 1,
                ))
            .where((item) => !item.product.id.toString().startsWith("package-"))
            .toList();

        if (items.isNotEmpty) {
          itemsList.add(const Divider());
          itemsList.add(const Text('📜 منتجات الفواتير السابقة:',
              style: TextStyle(fontWeight: FontWeight.bold)));

          for (var item in items) {
            totalPrice += item.total;
            itemsList.add(
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                    '${item.product.name} × ${item.qty} = ${item.total.toStringAsFixed(2)}'),
              ),
            );
          }
        }
      }
    }

    // ===== عرض Dialog =====
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('تفاصيل ${s.name}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('بدأ: ${s.start.toLocal()}'),
              Text('انتهى: ${s.end?.toLocal() ?? 'مازال مستمر'}'),
              const SizedBox(height: 12),
              ...itemsList,
              const Divider(),
              Text('💰 الإجمالي: ${totalPrice.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }
}

/*
  void _showSessionDetails(Session s) async {
    // 1️⃣ تحميل الفواتير
    final receiptList = await ReceiptDb.getReceiptsBySession(s.id);

    // 2️⃣ جلب الكارت الحالي للجلسة
    s.cart = await CartDb.getCartBySession(s.id, session: s);

    double totalPrice = 0.0;
    List<Widget> itemsList = [];

    // ===== جلسة حر =====
    if (s.subscription == null) {
      // ===== قسم المنتجات الحالية =====
      if (s.cart.isNotEmpty) {
        itemsList.add(
          const Text('🛒 المنتجات الحالية:',
              style: TextStyle(fontWeight: FontWeight.bold)),
        );
        for (var item in s.cart) {
          itemsList.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                  '${item.product.name} × ${item.qty} = ${item.total.toStringAsFixed(2)}'),
            ),
          );
          totalPrice += item.total;
        }
      }

      // ===== قسم منتجات الفواتير السابقة =====
      if (receiptList.isNotEmpty) {
        itemsList.add(const SizedBox(height: 8));
        itemsList.add(
          const Text('📜 منتجات الفواتير السابقة:',
              style: TextStyle(fontWeight: FontWeight.bold)),
        );

        for (var receipt in receiptList) {
          final items = (jsonDecode(receipt['itemsJson']) as List).map((j) {
            return CartItem(
              id: j["id"].toString(),
              product: Product(
                id: j["id"].toString(),
                name: j["name"] ?? "بدون اسم",
                price: (j["price"] ?? 0).toDouble(),
                stock: 0,
              ),
              qty: j["qty"] ?? 1,
            );
          }).toList();

          for (var item in items) {
            itemsList.add(
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                    '${item.product.name} × ${item.qty} = ${item.total.toStringAsFixed(2)}'),
              ),
            );
            totalPrice += item.total;
          }
        }
      }

      // ===== قسم الوقت المدفوع (لو فيه متبقي بعد المنتجات) =====
      double paidForTimeOnly = s.amountPaid - totalPrice;
      if (paidForTimeOnly > 0) {
        itemsList.add(const Divider());
        itemsList.add(
          Text('⏱️ الوقت المدفوع: ${paidForTimeOnly.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
        );
        totalPrice += paidForTimeOnly;
      }

      // ===== حالة بدون منتجات ولا وقت =====
      if (s.cart.isEmpty && receiptList.isEmpty && paidForTimeOnly <= 0) {
        itemsList.add(const Text('❌ بدون اشتراك'));
      }
    }

    // ===== عرض Dialog =====
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('تفاصيل ${s.name}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('بدأ: ${s.start.toLocal()}'),
              Text('انتهى: ${s.end?.toLocal() ?? 'مازال مستمر'}'),
              const SizedBox(height: 12),
              ...itemsList,
              const Divider(),
              Text('💰 الإجمالي: ${totalPrice.toStringAsFixed(2)}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }*/
//=================================

/*
  void _showSessionDetails(Session s) async {
    s.cart = await CartDb.getCartBySession(s.id, session: s);

    final plan = s.subscription;
    final allowedToday = (plan != null &&
            plan.dailyUsageType == 'limited' &&
            plan.dailyUsageHours != null)
        ? plan.dailyUsageHours! * 60
        : -1;
    final spentToday = _minutesOverlapWithDate(s, DateTime.now());
    final totalSoFar = _totalMinutesSoFar(s);
    final end = _getSubscriptionEnd(s);

    // ===== حساب السعر =====
    double totalPrice = 0.0;
    List<Widget> itemsList = [];

    double productsTotal = s.cart.fold(0.0, (sum, item) => sum);
    if (plan != null) {
      // مشترك: نضيف الباقة
      totalPrice += plan.price;
      itemsList.add(
        Text('باقة: ${plan.name} — السعر: ${plan.price.toStringAsFixed(2)}'),
      );

      // نضيف المنتجات بجانب الباقة
      for (var item in s.cart) {
        // لو المنتج هو الباقة (بيبدأ بـ package-) → تجاهله
        if (item.product.id.toString().startsWith("package-")) continue;

        totalPrice += item.total;
        itemsList.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              '${item.product.name} × ${item.qty} = ${item.total.toStringAsFixed(2)}',
            ),
          ),
        );
      }
    } else {
      // منتجات الكارت (سعر المنتجات فقط)
      for (var item in s.cart) {
        totalPrice += item.total;
        itemsList.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
                '${item.product.name} × ${item.qty} = ${item.total.toStringAsFixed(2)}'),
          ),
        );
      }
      // حر: نضيف عنصر افتراضي للباقة الحر
      if (s.amountPaid > 0) {
        double productsTotal =
            s.cart.fold(0.0, (sum, item) => sum + item.total);
        double paidForTimeOnly = s.amountPaid - productsTotal;

        if (paidForTimeOnly < 0) paidForTimeOnly = 0; // لا تسمح بالسالب

        itemsList.add(
          Text('الوقت: ${paidForTimeOnly.toStringAsFixed(2)}'),
        );
        totalPrice += paidForTimeOnly;
      } else {
        itemsList.add(const Text('❌ بدون اشتراك'));
      }
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('تفاصيل ${s.name}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (plan != null) Text('باقة: ${plan.name}'),
              if (plan == null) const Text("❌ بدون اشتراك"),
              Text('بدأ: ${s.start.toLocal()}'),
              Text('انتهى: ${s.end?.toLocal() ?? 'مازال مستمر'}'),
              const SizedBox(height: 8),
              Text('مضى اليوم: ${_formatMinutes(spentToday)}'),
              Text(
                'الحد اليومي: ${allowedToday > 0 ? _formatMinutes(allowedToday) : 'غير محدد'}',
              ),
              Text(
                'متبقي اليوم: ${allowedToday > 0 ? _formatMinutes((allowedToday - spentToday).clamp(0, allowedToday)) : 'غير محدد'}',
              ),
              const SizedBox(height: 8),
              Text('مضى كلي: ${_formatMinutes(totalSoFar)}'),
              Text(
                'ينتهي: ${end != null ? end.toLocal().toString().split('.').first : 'غير محدد'}',
              ),
              const SizedBox(height: 12),
              Text('المنتجات/السعر:',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              if (s.cart.isEmpty && plan != null && s.amountPaid <= 0)
                Text('سعر الباقة: ${plan.price.toStringAsFixed(2)}'),
              ...s.cart.map(
                (item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '${item.product.name} × ${item.qty} = ${item.total.toStringAsFixed(2)}',
                  ),
                ),
              ),
              if (s.cart.isNotEmpty || (plan != null && s.amountPaid <= 0))
                const Divider(),
              Text('الإجمالي: ${totalPrice.toStringAsFixed(2)}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }*/

//==============================

/* void _showSessionDetails(Session s) async {
    // 1️⃣ تحميل الفواتير
    final receiptList = await ReceiptDb.getReceiptsBySession(s.id);

    // 2️⃣ جلب الكارت الحالي للجلسة
    s.cart = await CartDb.getCartBySession(s.id, session: s);

    // ===== إعداد المتغيرات =====
    double totalPrice = 0.0;
    List<Widget> itemsList = [];

    final plan = s.subscription;

    if (plan == null) {
      // ===== جلسة حر =====
      double totalProducts = 0.0;

      // منتجات الكارت الحالي
      // 🛒 المنتجات الحالية
      if (s.cart.isNotEmpty) {
        itemsList.add(const Text('🛒 المنتجات الحالية:',
            style: TextStyle(fontWeight: FontWeight.bold)));
        for (var item in s.cart) {
          totalPrice += item.total;
          itemsList.add(Text(
              '${item.product.name} × ${item.qty} = ${item.total.toStringAsFixed(2)}'));
        }
      }

      // منتجات الفواتير السابقة
      if (receiptList.isNotEmpty) {
        itemsList.add(const Divider());
        itemsList.add(const Text('📜 منتجات الفواتير السابقة:',
            style: TextStyle(fontWeight: FontWeight.bold)));

        for (var receipt in receiptList) {
          final items = (jsonDecode(receipt['itemsJson']) as List).map((j) {
            return CartItem(
              id: j["id"].toString(),
              product: Product(
                id: j["id"].toString(),
                name: j["name"] ?? "بدون اسم",
                price: (j["price"] ?? 0).toDouble(),
                stock: 0,
              ),
              qty: j["qty"] ?? 1,
            );
          }).toList();

          for (var item in items) {
            totalProducts += item.total;
            itemsList.add(
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                    '${item.product.name} × ${item.qty} = ${item.total.toStringAsFixed(2)}'),
              ),
            );
          }
        }
      }
// اجمع قيمة المنتجات داخل الـ cart
      double productsTotal = s.cart.fold(0.0, (sum, item) => sum + item.total);
      totalPrice += totalProducts;

      // الوقت المدفوع فقط (لو باقي مبلغ بعد المنتجات)
      double paidForTimeOnly = s.amountPaid - productsTotal;
      if (paidForTimeOnly > 0) {
        itemsList.add(const Divider());
        itemsList.add(Text(
            '⏱️ الوقت المدفوع: ${paidForTimeOnly.toStringAsFixed(2)}',
            style: TextStyle(fontWeight: FontWeight.bold)));
        totalPrice += paidForTimeOnly;
      }

      // لو ما فيش منتجات ولا وقت
      if (totalProducts == 0 && paidForTimeOnly <= 0) {
        itemsList.add(const Text('❌ بدون اشتراك'));
      }
    } else {
      // ===== جلسة باقة =====
      totalPrice += plan.price;
      itemsList.add(Text(
          '📦 باقة: ${plan.name} — ${plan.price.toStringAsFixed(2)}',
          style: const TextStyle(fontWeight: FontWeight.bold)));

      // منتجات إضافية (الكارت الحالي فقط بدون منتجات الباقة)
      final extraItems = s.cart
          .where((item) => !item.product.id.toString().startsWith("package-"))
          .toList();
      if (extraItems.isNotEmpty) {
        itemsList.add(const Divider());
        itemsList.add(const Text('🛒 منتجات إضافية:',
            style: TextStyle(fontWeight: FontWeight.bold)));

        for (var item in extraItems) {
          totalPrice += item.total;
          itemsList.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                  '${item.product.name} × ${item.qty} = ${item.total.toStringAsFixed(2)}'),
            ),
          );
        }
      }

      // منتجات الفواتير السابقة (بدون الباقة)
      for (var receipt in receiptList) {
        final items = (jsonDecode(receipt['itemsJson']) as List)
            .map((j) => CartItem(
                  id: j["id"].toString(),
                  product: Product(
                    id: j["id"].toString(),
                    name: j["name"] ?? "بدون اسم",
                    price: (j["price"] ?? 0).toDouble(),
                    stock: 0,
                  ),
                  qty: j["qty"] ?? 1,
                ))
            .where((item) => !item.product.id.toString().startsWith("package-"))
            .toList();

        if (items.isNotEmpty) {
          itemsList.add(const Divider());
          itemsList.add(const Text('📜 منتجات الفواتير السابقة:',
              style: TextStyle(fontWeight: FontWeight.bold)));

          for (var item in items) {
            totalPrice += item.total;
            itemsList.add(
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                    '${item.product.name} × ${item.qty} = ${item.total.toStringAsFixed(2)}'),
              ),
            );
          }
        }
      }
    }

    // ===== عرض Dialog =====
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('تفاصيل ${s.name}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('بدأ: ${s.start.toLocal()}'),
              Text('انتهى: ${s.end?.toLocal() ?? 'مازال مستمر'}'),
              const SizedBox(height: 12),
              ...itemsList,
              const Divider(),
              Text('💰 الإجمالي: ${totalPrice.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }
*/
