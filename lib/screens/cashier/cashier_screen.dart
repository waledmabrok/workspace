/*
import 'package:flutter/material.dart';
import '../../core/db_helper_cart.dart';
import '../../core/models.dart';
import '../../core/data_service.dart';
import '../../core/db_helper_sessions.dart';
import 'dart:async';

class CashierScreen extends StatefulWidget {
  const CashierScreen({super.key});

  @override
  State<CashierScreen> createState() => _CashierScreenState();
}

class _CashierScreenState extends State<CashierScreen> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _qtyCtrl = TextEditingController(text: '1');
  final TextEditingController _searchCtrl = TextEditingController();

  List<Session> _sessions = [];
  List<Session> _filteredSessions = [];

  Product? _selectedProduct;
  SubscriptionPlan? _selectedPlan;
  Session? _selectedSession;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadSessions();
    // يحدث الشاشة كل 30 ثانية عشان التوقيت يتجدد
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadSessions() async {
    final data = await SessionDb.getSessions();
    for (var s in data) {
      s.cart = await CartDb.getCartBySession(s.id);
      // ⬅️ تحميل الكارت
    }
    setState(() {
      _sessions = data;
      _filteredSessions = data;
    });
  }

  // ✅ حساب الدقايق للجلسة
  int getSessionMinutes(Session s) {
    if (s.isPaused) {
      return s.elapsedMinutes; // محفوظ مسبقاً
    } else {
      return s.elapsedMinutes + DateTime.now().difference(s.start).inMinutes;
    }
  }

  // ✅ حساب تكلفة الوقت
  double _calculateTimeChargeFromMinutes(int minutes) {
    final settings = AdminDataService.instance.pricingSettings;
    print(
      "PRICING SETTINGS: "
      "firstFreeMinutes=${settings.firstFreeMinutes}, "
      "firstHourFee=${settings.firstHourFee}, "
      "perHourAfterFirst=${settings.perHourAfterFirst}, "
      "dailyCap=${settings.dailyCap}",
    );

    if (minutes <= settings.firstFreeMinutes) return 0;
    if (minutes <= 60) return settings.firstHourFee;

    final extraHours = ((minutes - 60) / 60).ceil();
    double amount =
        settings.firstHourFee + extraHours * settings.perHourAfterFirst;
    if (amount > settings.dailyCap) amount = settings.dailyCap;

    print("  final amount: $amount");
    return amount;
  }

  void _startSession() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    final session = Session(
      id: generateId(),
      name: name,
      start: DateTime.now(),
      subscription: _selectedPlan,
      isActive: true,
      isPaused: false,
      elapsedMinutes: 0,
      cart: [],
    );

    await SessionDb.insertSession(session);
    setState(() {
      _sessions.insert(0, session);
      _filteredSessions = _sessions;
      _nameCtrl.clear();
    });
  }

  void _togglePauseSession(int index) async {
    final s = _filteredSessions[index];
    if (!s.isActive) return;

    setState(() {
      if (s.isPaused) {
        // استئناف
        s.isPaused = false;
        s.start = DateTime.now().subtract(Duration(minutes: s.elapsedMinutes));
      } else {
        // إيقاف مؤقت
        s.isPaused = true;
        s.elapsedMinutes += DateTime.now().difference(s.start).inMinutes;
      }
    });

    await SessionDb.updateSession(s);
  }

  // ✅ شاشة إضافة منتجات + الدفع
  Widget _buildAddProductsAndPay(Session s) {
    Product? selectedProduct;
    TextEditingController qtyCtrl = TextEditingController(text: '1');

    return StatefulBuilder(
      builder: (context, setSheetState) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // اختيار المنتج
              DropdownButton<Product>(
                value: selectedProduct,
                hint: const Text('اختر منتج/مشروب'),
                isExpanded: true,
                items:
                    AdminDataService.instance.products.map((p) {
                      return DropdownMenuItem(
                        value: p,
                        child: Text('${p.name} (${p.price} ج)'),
                      );
                    }).toList(),
                onChanged: (val) {
                  setSheetState(() => selectedProduct = val);
                },
              ),
              const SizedBox(height: 8),
              // إدخال الكمية + زر الإضافة
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: qtyCtrl,
                      decoration: const InputDecoration(labelText: 'عدد'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () async {
                      final qty = int.tryParse(qtyCtrl.text) ?? 1;
                      if (selectedProduct != null) {
                        final item = CartItem(
                          id: generateId(), // ← هنا
                          product: selectedProduct!,
                          qty: qty,
                        );

                        await CartDb.insertCartItem(item, s.id);

                        final updatedCart = await CartDb.getCartBySession(s.id);
                        setSheetState(() => s.cart = updatedCart);
                      }
                    },
                    child: const Text('اضف'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // عرض الكارت مع التحديث المباشر
              ...s.cart.map((item) {
                final qtyController = TextEditingController(
                  text: item.qty.toString(),
                );
                return Row(
                  children: [
                    Expanded(child: Text(item.product.name)),
                    SizedBox(
                      width: 50,
                      child: TextField(
                        controller: qtyController,
                        keyboardType: TextInputType.number,
                        onChanged: (val) async {
                          item.qty = int.tryParse(val) ?? item.qty;
                          await CartDb.updateCartItemQty(item.id, item.qty);
                          setSheetState(() {});
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () async {
                        await CartDb.deleteCartItem(item.id);
                        s.cart.remove(item);
                        setSheetState(() {});
                      },
                    ),
                  ],
                );
              }).toList(),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _completeAndPayForSession(s); // الدفع النهائي
                },
                child: const Text('إتمام ودفع'),
              ),
            ],
          ),
        );
      },
    );
  }

  // ✅ الدفع + إيصال
  void _completeAndPayForSession(Session s) async {
    int totalMinutes = getSessionMinutes(s);

    double timeCharge =
        s.subscription?.price ?? _calculateTimeChargeFromMinutes(totalMinutes);

    double productsTotal = s.cart.fold(0.0, (sum, item) => sum + item.total);

    await _showReceiptDialog(s, timeCharge, productsTotal);
  }

  Future<void> _showReceiptDialog(
    Session s,
    double timeCharge,
    double productsTotal,
  ) async {
    double discount = 0.0;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            double finalTotal =
                timeCharge +
                s.cart.fold(0.0, (sum, item) => sum + item.total) -
                discount;

            return AlertDialog(
              title: Text('إيصال الدفع - ${s.name}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('وقت الجلسة: ${timeCharge.toStringAsFixed(2)} ج'),
                    const SizedBox(height: 8),
                    ...s.cart.map((item) {
                      final qtyController = TextEditingController(
                        text: item.qty.toString(),
                      );
                      return Row(
                        children: [
                          Expanded(child: Text(item.product.name)),
                          SizedBox(
                            width: 50,
                            child: TextField(
                              controller: qtyController,
                              keyboardType: TextInputType.number,
                              onChanged: (val) {
                                setDialogState(() {
                                  item.qty = int.tryParse(val) ?? item.qty;
                                });
                              },
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () {
                              setDialogState(() {
                                s.cart.remove(item);
                              });
                            },
                          ),
                        ],
                      );
                    }).toList(),
                    const SizedBox(height: 8),
                    TextField(
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'أدخل خصم (ج)',
                      ),
                      onChanged: (val) {
                        setDialogState(() {
                          discount = double.tryParse(val) ?? 0.0;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'الإجمالي بعد الخصم: ${finalTotal.toStringAsFixed(2)} ج',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    setState(() {
                      s.isActive = false;
                      s.isPaused = false;
                      s.amountPaid = finalTotal;
                    });

                    await SessionDb.updateSession(s);

                    AdminDataService.instance.sales.add(
                      Sale(
                        id: generateId(),
                        description:
                            'جلسة ${s.name} | خطة: ${s.subscription?.name ?? "بدون"} | وقت: ${timeCharge.toStringAsFixed(2)} + منتجات: ${productsTotal.toStringAsFixed(2)} - خصم: ${discount.toStringAsFixed(2)}',
                        amount: finalTotal,
                      ),
                    );

                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'تم الدفع: ${finalTotal.toStringAsFixed(2)} ج',
                        ),
                      ),
                    );
                  },
                  child: const Text('تأكيد الدفع'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الكاشير'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_shopping_cart),
            tooltip: 'إضافة منتجات بدون اسم',
            onPressed: () async {
              // نعمل Session افتراضية
              final tempSession = Session(
                id: generateId(),
                name: 'بدون اسم',
                start: DateTime.now(),
                subscription: null,
                isActive: true,
                isPaused: false,
                elapsedMinutes: 0,
                cart: [],
              );

              // نفتح BottomSheet لإضافة المنتجات
              await showModalBottomSheet(
                context: context,
                builder: (_) => _buildAddProductsAndPay(tempSession),
              );

              // لو تمت عملية الدفع، ممكن تخزنها كجلسة فعلية أو لا حسب رغبتك
              if (tempSession.cart.isNotEmpty) {
                setState(() {
                  _sessions.insert(0, tempSession);
                  _filteredSessions = _sessions;
                });
              }
            },
          ),
        ],
      ),

      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ✅ البحث عن مشترك
            TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'ابحث عن مشترك',
                labelStyle: const TextStyle(color: Colors.white70),
                prefixIcon: const Icon(Icons.search, color: Colors.white70),
                filled: true,
                fillColor: Colors.grey[850], // خلفية داكنة
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (val) {
                setState(() {
                  _filteredSessions =
                      val.isEmpty
                          ? _sessions
                          : _sessions
                              .where(
                                (s) => s.name.toLowerCase().contains(
                                  val.toLowerCase(),
                                ),
                              )
                              .toList();
                });
              },
            ),
            const SizedBox(height: 12),

            // ✅ اختيار خطة
            DropdownButtonFormField<SubscriptionPlan>(
              value: _selectedPlan,
              dropdownColor: Colors.grey[850], // خلفية القائمة الداكنة
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: "اختر اشتراك (اختياري)",
                labelStyle: const TextStyle(color: Colors.white70),
                filled: true,
                fillColor: Colors.grey[850],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              items:
                  AdminDataService.instance.subscriptions
                      .map(
                        (s) => DropdownMenuItem(
                          value: s,
                          child: Text("${s.name} - ${s.price} ج"),
                        ),
                      )
                      .toList(),
              onChanged: (val) => setState(() => _selectedPlan = val),
            ),
            const SizedBox(height: 12),

            // ✅ إدخال اسم عميل + زر تسجيل
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'اسم العميل',
                      hintStyle: const TextStyle(color: Colors.white70),
                      filled: true,
                      fillColor: Colors.grey[850],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _startSession,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueGrey[700],
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                  child: const Text('ابدأ تسجيل'),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ✅ قائمة الجلسات
            Expanded(
              child: ListView.builder(
                itemCount: _filteredSessions.length,
                itemBuilder: (context, i) {
                  final s = _filteredSessions[i];

                  // ⬅️ اطبع كل القيم المهمة
                  print('--- Session ${s.name} ---');
                  print('isActive: ${s.isActive}');
                  print('isPaused: ${s.isPaused}');
                  print('start: ${s.start}');
                  print('elapsedMinutes: ${s.elapsedMinutes}');
                  print('subscription: ${s.subscription?.name ?? "None"}');
                  print(
                    'subscription price: ${s.subscription?.price ?? "N/A"}',
                  );

                  final spent = getSessionMinutes(s);
                  print('spentMinutes: $spent');

                  double currentCharge = _calculateTimeChargeFromMinutes(spent);
                  print('calculated time charge: $currentCharge');

                  String timeInfo;
                  if (s.subscription != null) {
                    final spentSub =
                        DateTime.now().difference(s.start).inMinutes;
                    timeInfo =
                        s.end != null
                            ? "من: ${s.start.toLocal()} ⇢ ينتهي: ${s.end!.toLocal()} ⇢ مضى: ${spentSub} دقيقة"
                            : "من: ${s.start.toLocal()} ⇢ غير محدود ⇢ مضى: ${spentSub} دقيقة";
                  } else {
                    timeInfo = "من: ${s.start.toLocal()} ⇢ مضى: ${spent} دقيقة";
                  }

                  return Card(
                    child: ListTile(
                      title: Text(s.name),
                      subtitle: Text(
                        '${s.isActive ? (s.isPaused ? "متوقف مؤقت" : "نشط") : "انتهت"} '
                        '- $timeInfo '
                        '- ${s.amountPaid > 0 ? s.amountPaid.toStringAsFixed(2) : currentCharge.toStringAsFixed(2)} ج',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (s.isActive)
                            ElevatedButton(
                              onPressed: () => _togglePauseSession(i),
                              child: Text(
                                s.isPaused ? 'استئناف' : 'ايقاف مؤقت',
                              ),
                            ),
                          const SizedBox(width: 4),
                          if (s.isActive && !s.isPaused)
                            ElevatedButton(
                              onPressed: () async {
                                setState(() => _selectedSession = s);
                                await showModalBottomSheet(
                                  context: context,
                                  builder: (_) => _buildAddProductsAndPay(s),
                                );
                              },
                              child: const Text('اضف & دفع'),
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
}

// ✅ Helper
extension FirstWhereOrNullExtension<E> on List<E> {
  E? firstWhereOrNull(bool Function(E) test) {
    for (var element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
*/

import 'package:flutter/material.dart';
import '../../core/FinanceDb.dart';
import '../../core/db_helper_cart.dart';
import '../../core/db_helper_discounts.dart';
import '../../core/models.dart';
import '../../core/data_service.dart';
import '../../core/db_helper_sessions.dart';
import 'dart:async';

import 'notification.dart';
import '../../core/db_helper_customer_balance.dart';

class CashierScreen extends StatefulWidget {
  const CashierScreen({super.key});

  @override
  State<CashierScreen> createState() => _CashierScreenState();
}

class _CashierScreenState extends State<CashierScreen> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _qtyCtrl = TextEditingController(text: '1');
  final TextEditingController _searchCtrl = TextEditingController();


// داخل class _CashierScreenState
  String get _currentCustomerName {
    // إذا فيه جلسة مختارة، استخدم اسمها، وإلا خذ الاسم من حقل الإدخال
    final fromSelected = _selectedSession?.name;
    if (fromSelected != null && fromSelected.isNotEmpty) return fromSelected;
    return _nameCtrl.text.trim();
  }

  List<Session> _sessions = [];
  List<Session> _filteredSessions = [];
  Timer? _autoStopTimer;
  Product? _selectedProduct;
  SubscriptionPlan? _selectedPlan;
  Session? _selectedSession;
  Timer? _timer;
  int _unseenExpiringCount = 0;

  // 🟢 الخصم
  Discount? _appliedDiscount;
  final TextEditingController _discountCodeCtrl = TextEditingController();

  DateTime? getSubscriptionEnd(Session s) {
    final plan = s.subscription;
    if (plan == null || plan.isUnlimited) return null;

    final start = s.start;

    switch (plan.durationType) {
      case "hour":
        return start.add(Duration(hours: plan.durationValue ?? 0));
      case "day":
        return start.add(Duration(days: plan.durationValue ?? 0));
      case "week":
        return start.add(Duration(days: (plan.durationValue ?? 0) * 7));
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
  double _drawerBalance = 0.0;

  Future<void> _loadDrawerBalance() async {
    try {
      final bal = await FinanceDb.getDrawerBalance();
      if (mounted) setState(() => _drawerBalance = bal);
    } catch (e, st) {
      // طبع الخطأ علشان تعرف لو في مشكلة في DB
      debugPrint('Failed to load drawer balance: $e\n$st');
      if (mounted) {
        // اختياري: تعرض snackbar للمستخدم لو حبيت
        // ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ في جلب رصيد الدرج')));
      }
    }
  }

  Customer? _currentCustomer;
  @override
  void initState() {
    super.initState();
    _currentCustomer = AdminDataService.instance.customers
        .firstWhereOrNull((c) => c.name == _currentCustomerName);
    if (mounted) {
      setState(() {});
      _loadDrawerBalance(); // نحافظ على تحديث الرصيد دوريًا
    }
    _startAutoStopChecker();
    _updateUnseenExpiringCount();
    _loadSessions();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _autoStopTimer?.cancel();
    _discountCodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSessions() async {
    final data = await SessionDb.getSessions();
    for (var s in data) {
      s.cart = await CartDb.getCartBySession(s.id);
    }
    setState(() {
      _sessions = data;
      _filteredSessions = data;
    });
  }

  int getSessionMinutes(Session s) {
    if (s.isPaused) {
      return s.elapsedMinutes;
    } else {
      return s.elapsedMinutes +
          DateTime.now().difference(s.pauseStart ?? s.start).inMinutes;
    }
  }

  double _calculateTimeChargeFromMinutes(int minutes) {
    final settings = AdminDataService.instance.pricingSettings;
    if (minutes <= settings.firstFreeMinutes) return 0;
    if (minutes <= 60) return settings.firstHourFee;

    final extraHours = ((minutes - 60) / 60).ceil();
    double amount =
        settings.firstHourFee + extraHours * settings.perHourAfterFirst;
    if (amount > settings.dailyCap) amount = settings.dailyCap;

    return amount;
  }

  // ✅ التحقق من الكود
  Future<String?> _applyDiscountByCode(String code) async {
    code = code.trim();
    if (code.isEmpty) return "أدخل كود أولاً";

    final disc = AdminDataService.instance.discounts.firstWhereOrNull(
      (d) => d.code.toLowerCase() == code.toLowerCase(),
    );

    if (disc == null) return "الكود غير موجود";

    final now = DateTime.now();

    // ✅ تحقق من الصلاحية
    if (disc.expiry != null && disc.expiry!.isBefore(now)) {
      return "الكود منتهي";
    }

    // ✅ تحقق من شرط الاستخدام لمرة واحدة
    if (disc.singleUse && disc.used) {
      return "الكود تم استخدامه بالفعل";
    }

    // 🟢 طبّق الخصم
    setState(() {
      _appliedDiscount = disc;
    });

    // ✅ لو الخصم لمرة واحدة → نعلّم انه استُخدم
    if (disc.singleUse) {
      final updated = Discount(
        id: disc.id,
        code: disc.code,
        percent: disc.percent,
        expiry: disc.expiry,
        singleUse: disc.singleUse,
        used: true, // 🟢 نعلّم انه اتطبق
      );
      await DiscountDb.update(updated);

      // كمان حدّث نسخة الميموري (AdminDataService)
      final idx = AdminDataService.instance.discounts.indexWhere(
        (d) => d.id == disc.id,
      );
      if (idx != -1) {
        AdminDataService.instance.discounts[idx] = updated;
      }
    }

    return null; // يعني ناجح
  }

  void _startSession() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    final now = DateTime.now();
    DateTime? end;

    SubscriptionPlan? currentPlan = _selectedPlan;

    if (currentPlan != null) {
      if (currentPlan.isUnlimited) {
        end = null;
      } else {
        switch (currentPlan.durationType) {
          case "hour":
            end = now.add(Duration(hours: currentPlan.durationValue ?? 0));
            break;
          case "day":
            end = now.add(Duration(days: currentPlan.durationValue ?? 0));
            break;
          case "week":
            end = now.add(Duration(days: 7 * (currentPlan.durationValue ?? 0)));
            break;
          case "month":
            end = DateTime(
              now.year,
              now.month + (currentPlan.durationValue ?? 0),
              now.day,
              now.hour,
              now.minute,
            );
            break;
        }
      }
    } else {
      // 🔴 جلسة حر
      end = null;
    }

    final session = Session(
      id: generateId(),
      name: name,
      start: now,
      end: end,
      subscription: currentPlan,
      isActive: true,
      isPaused: false,
      elapsedMinutes: 0,
      cart: [],
      amountPaid: 0.0,
      type: currentPlan != null ? "باقة" : "حر", // 🔹
    );

    // 🟢 لو فيه خطة اشتراك
    if (currentPlan != null) {
      final basePrice = currentPlan.price;
      final discountPercent = _appliedDiscount?.percent ?? 0.0;
      final discountValue = basePrice * (discountPercent / 100);
      final finalPrice = basePrice - discountValue;

      session.amountPaid = finalPrice;

      final sale = Sale(
        id: generateId(),
        description:
            'اشتراك ${currentPlan.name} للعميل $name'
            '${_appliedDiscount != null ? " (خصم ${_appliedDiscount!.percent}%)" : ""}',
        amount: finalPrice,
      );

      await AdminDataService.instance.addSale(
        sale,
        paymentMethod: 'cash',
        customer: _currentCustomer,
        updateDrawer: true, // سيضيف المبلغ إلى درج الكاشير تلقائيًا
      );


      if (_appliedDiscount?.singleUse == true) {
        AdminDataService.instance.discounts.removeWhere(
          (d) => d.id == _appliedDiscount!.id,
        );
        _appliedDiscount = null;
      }
      try {

        await _loadDrawerBalance();
      } catch (e, st) {
        debugPrint('Failed to update drawer after quick sale: $e\n$st');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم دفع اشتراك ${currentPlan.name} ($finalPrice ج)'),
        ),
      );
    }

    await SessionDb.insertSession(session);

    setState(() {
      _sessions.insert(0, session);
      if (_searchCtrl.text.isEmpty) {
        _filteredSessions = _sessions;
      } else {
        _filteredSessions =
            _sessions
                .where(
                  (s) => s.name.toLowerCase().contains(
                    _searchCtrl.text.toLowerCase(),
                  ),
                )
                .toList();
      }
      _nameCtrl.clear();
      _selectedPlan = null;
      _appliedDiscount = null;
      _discountCodeCtrl.clear();
    });
  }

  void _togglePauseSession(int index) async {
    final s = _filteredSessions[index];
    if (!s.isActive) return;

    setState(() {
      if (s.isPaused) {
        // استئناف
        s.isPaused = false;
        s.pauseStart = DateTime.now(); // سجل وقت الاستئناف
      } else {
        // إيقاف مؤقت
        s.isPaused = true;
        s.elapsedMinutes +=
            DateTime.now().difference(s.pauseStart ?? s.start).inMinutes;
      }
    });

    await SessionDb.updateSession(s);
  }

  Widget _buildAddProductsAndPay(Session s) {
    Product? selectedProduct;
    TextEditingController qtyCtrl = TextEditingController(text: '1');

    return StatefulBuilder(
      builder: (context, setSheetState) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<Product>(
                value: selectedProduct,
                hint: const Text('اختر منتج/مشروب'),
                isExpanded: true,
                items:
                    AdminDataService.instance.products.map((p) {
                      return DropdownMenuItem(
                        value: p,
                        child: Text('${p.name} (${p.price} ج)'),
                      );
                    }).toList(),
                onChanged: (val) {
                  setSheetState(() => selectedProduct = val);
                },
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: qtyCtrl,
                      decoration: const InputDecoration(labelText: 'عدد'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () async {
                      final qty = int.tryParse(qtyCtrl.text) ?? 1;
                      if (selectedProduct != null) {
                        final item = CartItem(
                          id: generateId(),
                          product: selectedProduct!,
                          qty: qty,
                        );

                        await CartDb.insertCartItem(item, s.id);

                        final updatedCart = await CartDb.getCartBySession(s.id);
                        setSheetState(() => s.cart = updatedCart);
                      }
                    },
                    child: const Text('اضف'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...s.cart.map((item) {
                final qtyController = TextEditingController(
                  text: item.qty.toString(),
                );
                return Row(
                  children: [
                    Expanded(child: Text(item.product.name)),
                    SizedBox(
                      width: 50,
                      child: TextField(
                        controller: qtyController,
                        keyboardType: TextInputType.number,
                        onChanged: (val) async {
                          item.qty = int.tryParse(val) ?? item.qty;
                          await CartDb.updateCartItemQty(item.id, item.qty);
                          setSheetState(() {});
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () async {
                        await CartDb.deleteCartItem(item.id);
                        s.cart.remove(item);
                        setSheetState(() {});
                      },
                    ),
                  ],
                );
              }).toList(),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _completeAndPayForSession(s);
                },
                child: const Text('إتمام ودفع'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _completeAndPayForSession(Session s) async {
    final totalMinutes = getSessionMinutes(s);

    // دقائق جديدة لم تُدفع بعد
    final minutesToCharge = (totalMinutes - s.paidMinutes).clamp(
      0,
      totalMinutes,
    );

    // رسوم الوقت فقط على الدقائق الجديدة
    final timeCharge = _calculateTimeChargeFromMinutes(minutesToCharge);

    final productsTotal = s.cart.fold(0.0, (sum, item) => sum + item.total);

    await _showReceiptDialog(s, timeCharge, productsTotal, minutesToCharge);
  }

  void _stopSession(Session s) async {
    setState(() {
      s.isActive = false;
    });

    await SessionDb.updateSession(s);

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text("انتهى الاشتراك للعميل ${s.name}")));
  }

  void _startAutoStopChecker() {
    _autoStopTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      for (var s in _sessions) {
        if (s.isActive && s.subscription != null && s.end != null) {
          final now = DateTime.now();
          if (now.isAfter(s.end!)) {
            _stopSession(s);
          } else if (s.end!.difference(now).inMinutes == 10) {
            _showExpiryWarning(s);
          }
        }
      }
    });
  }

  void _showExpiryWarning(Session s) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("⚠️ الاشتراك للعميل ${s.name} هينتهي بعد 10 دقائق"),
        backgroundColor: Colors.orange,
      ),
    );
  }

  Future<void> _showReceiptDialog(
      Session s,
      double timeCharge,
      double productsTotal,
      int minutesToCharge,
      ) async {
    double discountValue = 0.0;
    String? appliedCode;
    final codeCtrl = TextEditingController();

    String paymentMethod = "cash"; // 🟢 افتراضي: كاش
    final TextEditingController paidCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            double finalTotal = timeCharge + productsTotal - discountValue;

            return AlertDialog(
              title: Text('إيصال الدفع - ${s.name}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('وقت الجلسة: ${timeCharge.toStringAsFixed(2)} ج'),
                    const SizedBox(height: 8),
                    ...s.cart.map(
                          (item) => Text(
                        '${item.product.name} x${item.qty} = ${item.total} ج',
                      ),
                    ),

                    const SizedBox(height: 12),

                    // 🟢 اختيار وسيلة الدفع
                    Row(
                      children: [
                        const Text("طريقة الدفع: "),
                        const SizedBox(width: 8),
                        DropdownButton<String>(
                          value: paymentMethod,
                          items: const [
                            DropdownMenuItem(value: "cash", child: Text("كاش")),
                            DropdownMenuItem(value: "wallet", child: Text("محفظة")),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() => paymentMethod = val);
                            }
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // 🟢 المبلغ المطلوب
                    Text(
                      'المطلوب: ${finalTotal.toStringAsFixed(2)} ج',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),

                    const SizedBox(height: 8),

                    // 🟢 إدخال المبلغ المدفوع
                    TextField(
                      controller: paidCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "المبلغ المدفوع",
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    // ✅ المبلغ المطلوب
                    final requiredAmount = finalTotal;

                    // ✅ المبلغ المدفوع
                    final paidAmount = double.tryParse(paidCtrl.text) ?? 0.0;

                    // ✅ الفرق
                    final diff = paidAmount - requiredAmount;

                    // ✅ تحديث دقائق الدفع
                    s.paidMinutes += minutesToCharge;
                    s.amountPaid += paidAmount;

                    // ✅ تحديث رصيد العميل
                    if (s.name.isNotEmpty) {
                      final oldBalance =
                      AdminDataService.instance.customerBalances.firstWhere(
                            (b) => b.customerId == s.name,
                        orElse: () =>
                            CustomerBalance(customerId: s.name, balance: 0),
                      );

                      final newBalance = oldBalance.balance + diff;

                      final updated = CustomerBalance(
                        customerId: s.name,
                        balance: newBalance,
                      );

                      await CustomerBalanceDb.upsert(updated);

                      final idx = AdminDataService.instance.customerBalances
                          .indexWhere((b) => b.customerId == s.name);
                      if (idx >= 0) {
                        AdminDataService.instance.customerBalances[idx] = updated;
                      } else {
                        AdminDataService.instance.customerBalances.add(updated);
                      }
                    }

                    // ✅ قفل الجلسة
                    setState(() {
                      s.isActive = false;
                      s.isPaused = false;
                    });
                    await SessionDb.updateSession(s);

                    // ✅ حفظ كـ Sale
                    final sale = Sale(
                      id: generateId(),
                      description:
                      'جلسة ${s.name} | وقت: ${minutesToCharge} دقيقة + منتجات: ${s.cart.fold(0.0, (sum, item) => sum + item.total)}'
                          '${appliedCode != null ? " (بكود $appliedCode)" : ""}',
                      amount: paidAmount,
                    );

                    await AdminDataService.instance.addSale(
                      sale,
                      paymentMethod: paymentMethod,
                      customer: _currentCustomer,
                      updateDrawer: paymentMethod == "cash",
                    );

                    try {
                      await _loadDrawerBalance();
                    } catch (e, st) {
                      debugPrint('Failed to update drawer: $e\n$st');
                    }

                    Navigator.pop(context);

                    // ✅ رسالة توضح الفلوس
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          diff == 0
                              ? '✅ دفع كامل: ${paidAmount.toStringAsFixed(2)} ج'
                              : diff > 0
                              ? '✅ دفع ${paidAmount.toStringAsFixed(2)} ج — باقي له ${diff.toStringAsFixed(2)} ج عندك'
                              : '✅ دفع ${paidAmount.toStringAsFixed(2)} ج — باقي عليك ${(diff.abs()).toStringAsFixed(2)} ج',
                        ),
                      ),
                    );
                  },
                  child: const Text('تأكيد الدفع'),
                ),
              ],
            );
          },
        );
      },
    );
  }


  List<Session> getExpiringSessions() {
    final now = DateTime.now();
    return _sessions.where((s) {
      if (s.subscription != null && s.end != null && s.isActive) {
        final minutesLeft = s.end!.difference(now).inMinutes;
        return minutesLeft <= 10; // قربت تنتهي خلال 10 دقائق
      }
      return false;
    }).toList();
  }

  List<Session> getExpiredSessions() {
    final now = DateTime.now();
    return _sessions.where((s) {
      return s.subscription != null && s.end != null && now.isAfter(s.end!);
    }).toList();
  }

  void _updateUnseenExpiringCount() {
    _unseenExpiringCount =
        getExpiringSessions().length + getExpiredSessions().length;
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الكاشير'),

          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [// داخل AppBar.actions: ضع هذا قبل الأيقونات الأخرى أو بعدهم
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 1),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('رصيد الدرج', style: TextStyle(fontSize: 11, color: Colors.white70)),
                  Text('${_drawerBalance.toStringAsFixed(2)} ج', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                ],
              ),
            ),

            IconButton(
              icon: const Icon(Icons.add_shopping_cart),
              tooltip: 'إضافة منتجات بدون اسم',
              onPressed: () async {
                // ✅ هات كل المشتركين اللي عندهم باقات
                final subscribers =
                    _sessions
                        .where((s) => s.subscription != null && s.isActive)
                        .toList();

                String? selectedName;

                if (subscribers.isNotEmpty) {
                  selectedName = await showDialog<String>(
                    context: context,
                    builder: (context) {
                      return AlertDialog(
                        title: const Text('اختر مشترك'),
                        content: SizedBox(
                          width: double.maxFinite,
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: subscribers.length,
                            itemBuilder: (context, i) {
                              final sub = subscribers[i];
                              return ListTile(
                                title: Text(sub.name),
                                subtitle: Text(
                                  "باقة: ${sub.subscription?.name ?? ''}",
                                ),
                                onTap: () => Navigator.pop(context, sub.name),
                              );
                            },
                          ),
                        ),
                      );
                    },
                  );
                }

                // لو المستخدم ما اختارش حاجة → Cancel
                if (selectedName == null) return;

                final tempSession = Session(
                  id: generateId(),
                  name: selectedName, // الاسم من المشترك
                  start: DateTime.now(),
                  end: null,
                  subscription: null,
                  isActive: true,
                  isPaused: false,
                  elapsedMinutes: 0,
                  cart: [],
                  type: "حر", // 🔹 حددنا النوع
                );

                await showModalBottomSheet(
                  context: context,
                  builder: (_) => _buildAddProductsAndPay(tempSession),
                );

                if (tempSession.cart.isNotEmpty) {
                  setState(() {
                    _sessions.insert(0, tempSession);
                    _filteredSessions = _sessions;
                  });
                }
              },
            ),
            Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications),
                  tooltip: 'الاشتراكات المنتهية والقريبة من الانتهاء',
                  onPressed: () {
                    final expiring = getExpiringSessions();
                    final expired = getExpiredSessions();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (_) => ExpiringSessionsPage(
                              expiring: expiring,
                              expired: expired,
                            ),
                      ),
                    );
                  },
                ),
                // Badge
                if (getExpiringSessions().isNotEmpty ||
                    getExpiredSessions().isNotEmpty)
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${getExpiringSessions().length + getExpiredSessions().length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],

        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // ---------------- البحث ----------------
              TextField(
                controller: _searchCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'ابحث عن مشترك',
                  labelStyle: const TextStyle(color: Colors.white70),
                  prefixIcon: const Icon(Icons.search, color: Colors.white70),
                  filled: true,
                  fillColor: Colors.grey[850],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (val) {
                  setState(() {
                    _filteredSessions =
                        val.isEmpty
                            ? _sessions
                            : _sessions
                                .where(
                                  (s) => s.name.toLowerCase().contains(
                                    val.toLowerCase(),
                                  ),
                                )
                                .toList();
                  });
                },
              ),
              const SizedBox(height: 12),

              // ---------------- اختيار باقة ----------------
              DropdownButtonFormField<SubscriptionPlan>(
                value: _selectedPlan,
                dropdownColor: Colors.grey[850],
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: "اختر اشتراك (اختياري)",
                  labelStyle: const TextStyle(color: Colors.white70),
                  filled: true,
                  fillColor: Colors.grey[850],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
                items:
                    AdminDataService.instance.subscriptions
                        .map(
                          (s) => DropdownMenuItem(
                            value: s,
                            child: Text("${s.name} - ${s.price} ج"),
                          ),
                        )
                        .toList(),
                onChanged: (val) => setState(() => _selectedPlan = val),
              ),
              const SizedBox(height: 12),

              // ---------------- اسم العميل + زر التسجيل ----------------
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nameCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'اسم العميل',
                        hintStyle: const TextStyle(color: Colors.white70),
                        filled: true,
                        fillColor: Colors.grey[850],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _startSession,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueGrey[700],
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                    child: const Text('ابدأ تسجيل'),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ---------------- Tabs ----------------
              Expanded(
                child: DefaultTabController(
                  length: 3,
                  child: Column(
                    children: [
                      const TabBar(
                        tabs: [
                          Tab(text: "مشتركين باقات"),
                          Tab(text: "مشتركين حر"),
                          Tab(text: "المنتجات"),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _buildSubscribersList3(
                              withPlan: true,
                            ), // المشتركين باقات
                            _buildSubscribersList(withPlan: false),

                            _buildSalesList(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        /*  body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: _searchCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'ابحث عن مشترك',
                  labelStyle: const TextStyle(color: Colors.white70),
                  prefixIcon: const Icon(Icons.search, color: Colors.white70),
                  filled: true,
                  fillColor: Colors.grey[850],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (val) {
                  setState(() {
                    _filteredSessions =
                        val.isEmpty
                            ? _sessions
                            : _sessions
                                .where(
                                  (s) => s.name.toLowerCase().contains(
                                    val.toLowerCase(),
                                  ),
                                )
                                .toList();
                  });
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<SubscriptionPlan>(
                value: _selectedPlan,
                dropdownColor: Colors.grey[850],
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: "اختر اشتراك (اختياري)",
                  labelStyle: const TextStyle(color: Colors.white70),
                  filled: true,
                  fillColor: Colors.grey[850],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
                items:
                    AdminDataService.instance.subscriptions
                        .map(
                          (s) => DropdownMenuItem(
                            value: s,
                            child: Text("${s.name} - ${s.price} ج"),
                          ),
                        )
                        .toList(),
                onChanged: (val) => setState(() => _selectedPlan = val),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nameCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'اسم العميل',
                        hintStyle: const TextStyle(color: Colors.white70),
                        filled: true,
                        fillColor: Colors.grey[850],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _startSession,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueGrey[700],
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                    child: const Text('ابدأ تسجيل'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: _filteredSessions.length,
                  itemBuilder: (context, i) {
                    final s = _filteredSessions[i];
                    final spentMinutes = getSessionMinutes(s);
                    final endTime = getSubscriptionEnd(s);

                    String timeInfo;
                    if (s.subscription != null) {
                      timeInfo =
                          endTime != null
                              ? "من: ${s.start.toLocal()} ⇢ ينتهي: ${endTime.toLocal()} ⇢ مضى: ${spentMinutes} دقيقة"
                              : "من: ${s.start.toLocal()} ⇢ غير محدود ⇢ مضى: ${spentMinutes} دقيقة";
                    } else {
                      timeInfo =
                          "من: ${s.start.toLocal()} ⇢ مضى: ${spentMinutes} دقيقة";
                    }

                    double currentCharge = _calculateTimeChargeFromMinutes(
                      spentMinutes,
                    );

                    return Card(
                      child: ListTile(
                        title: Text(s.name),
                        subtitle: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${s.isActive ? (s.isPaused ? "متوقف مؤقت" : "نشط") : "انتهت"} - $timeInfo',
                              ),
                            ),
                            if (s.end != null &&
                                s.end!.difference(DateTime.now()).inMinutes <=
                                    10 &&
                                s.isActive)
                              const Icon(
                                Icons.notification_important,
                                color: Colors.orange,
                              ),
                          ],
                        ),

                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (s.isActive)
                              ElevatedButton(
                                onPressed: () => _togglePauseSession(i),
                                child: Text(
                                  s.isPaused ? 'استئناف' : 'ايقاف مؤقت',
                                ),
                              ),
                            const SizedBox(width: 4),
                            if (s.isActive && !s.isPaused)
                              ElevatedButton(
                                onPressed: () async {
                                  setState(() => _selectedSession = s);
                                  await showModalBottomSheet(
                                    context: context,
                                    builder: (_) => _buildAddProductsAndPay(s),
                                  );
                                },
                                child: const Text('اضف & دفع'),
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
        ),*/
      ),
    );
  }

  /// 🔹 دالة تبني لستة المشتركين
  Widget _buildSubscribersList2({required bool withPlan}) {
    final filtered =
        _filteredSessions.where((s) {
          if (withPlan) {
            // مشترك باقة: عنده subscription ومعاه end أو Unlimited plan
            return s.subscription != null &&
                (s.end != null || s.subscription!.isUnlimited);
          } else {
            // حر: أي جلسة مفيهاش اشتراك
            return s.subscription == null;
          }
        }).toList();

    if (filtered.isEmpty) {
      return const Center(child: Text("لا يوجد بيانات"));
    }

    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (context, i) {
        final s = filtered[i];
        final spentMinutes = getSessionMinutes(s);
        final endTime = getSubscriptionEnd(s);

        String timeInfo;
        if (s.subscription != null) {
          timeInfo =
              endTime != null
                  ? "من: ${s.start.toLocal()} ⇢ ينتهي: ${endTime.toLocal()} ⇢ مضى: ${spentMinutes} دقيقة"
                  : "من: ${s.start.toLocal()} ⇢ غير محدود ⇢ مضى: ${spentMinutes} دقيقة";
        } else {
          timeInfo = "من: ${s.start.toLocal()} ⇢ مضى: ${spentMinutes} دقيقة";
        }

        return Card(
          child: ListTile(
            title: Text(s.name),
            subtitle: Text(
              '${s.isActive ? (s.isPaused ? "متوقف مؤقت" : "نشط") : "انتهت"} - $timeInfo',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (s.isActive)
                  ElevatedButton(
                    onPressed: () => _togglePauseSession(i),
                    child: Text(s.isPaused ? 'استئناف' : 'ايقاف مؤقت'),
                  ),
                const SizedBox(width: 4),
                if (s.isActive && !s.isPaused)
                  ElevatedButton(
                    onPressed: () async {
                      setState(() => _selectedSession = s);
                      await showModalBottomSheet(
                        context: context,
                        builder: (_) => _buildAddProductsAndPay(s),
                      );
                    },
                    child: const Text('اضف & دفع'),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSubscribersList({required bool withPlan}) {
    // فلترة مباشرة من _sessions
    /* final filtered =
        _sessions.where((s) {
          if (withPlan) return s.type == "باقة";
          return s.type == "حر";
        }).toList();*/
    final searchText = _searchCtrl.text.toLowerCase();
    final filtered =
        _sessions.where((s) {
          final matchesType = withPlan ? s.type == "باقة" : s.type == "حر";
          final matchesSearch = s.name.toLowerCase().contains(searchText);
          return matchesType && matchesSearch;
        }).toList();

    if (filtered.isEmpty) return const Center(child: Text("لا يوجد بيانات"));

    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (context, i) {
        final s = filtered[i];
        final spentMinutes = getSessionMinutes(s);
        final endTime = getSubscriptionEnd(s);

        String timeInfo =
            s.subscription != null
                ? (endTime != null
                    ? "من: ${s.start.toLocal()} ⇢ ينتهي: ${endTime.toLocal()} ⇢ مضى: ${spentMinutes} دقيقة"
                    : "من: ${s.start.toLocal()} ⇢ غير محدود ⇢ مضى: ${spentMinutes} دقيقة")
                : "من: ${s.start.toLocal()} ⇢ مضى: ${spentMinutes} دقيقة";

        return Card(
          child: ListTile(
            title: Text(s.name),
            subtitle: Text(
              '${s.isActive ? (s.isPaused ? "متوقف مؤقت" : "نشط") : "انتهت"} - $timeInfo',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (s.isActive)
                  ElevatedButton(
                    onPressed: () => _togglePauseSession(i),
                    child: Text(s.isPaused ? 'استئناف' : 'ايقاف مؤقت'),
                  ),
                const SizedBox(width: 4),
                if (s.isActive && !s.isPaused)
                  ElevatedButton(
                    onPressed: () async {
                      setState(() => _selectedSession = s);
                      await showModalBottomSheet(
                        context: context,
                        builder: (_) => _buildAddProductsAndPay(s),
                      );
                    },
                    child: const Text('اضف & دفع'),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSubscribersList3({required bool withPlan}) {
    // فلترة مباشرة من _sessions
    /* final filtered =
        _sessions.where((s) {
          if (withPlan) return s.type == "باقة";
          return s.type == "حر";
        }).toList();*/
    final searchText = _searchCtrl.text.toLowerCase();
    final filtered =
        _sessions.where((s) {
          final matchesType = withPlan ? s.type == "باقة" : s.type == "حر";
          final matchesSearch = s.name.toLowerCase().contains(searchText);
          return matchesType && matchesSearch;
        }).toList();

    if (filtered.isEmpty) return const Center(child: Text("لا يوجد بيانات"));

    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (context, i) {
        final s = filtered[i];
        final spentMinutes = getSessionMinutes(s);
        final endTime = getSubscriptionEnd(s);

        String timeInfo =
            s.subscription != null
                ? (endTime != null
                    ? "من: ${s.start.toLocal()} ⇢ ينتهي: ${endTime.toLocal()} ⇢ مضى: ${spentMinutes} دقيقة"
                    : "من: ${s.start.toLocal()} ⇢ غير محدود ⇢ مضى: ${spentMinutes} دقيقة")
                : "من: ${s.start.toLocal()} ⇢ مضى: ${spentMinutes} دقيقة";

        return Card(
          child: ListTile(
            title: Text(s.name),
            subtitle: Text(
              '${s.isActive ? (s.isPaused ? "متوقف مؤقت" : "نشط") : "انتهت"} - $timeInfo',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (s.isActive)
                  ElevatedButton(
                    onPressed: () => _togglePauseSession(i),
                    child: Text(s.isPaused ? 'استئناف' : 'ايقاف مؤقت'),
                  ),
                const SizedBox(width: 4),
                if (s.isActive && !s.isPaused)
                  ElevatedButton(
                    onPressed: () async {
                      double totalAmount = 0.0;

                      final minutesToCharge = getSessionMinutes(s);

                      // ✅ إذا الجلسة ضمن باقة → فقط المنتجات
                      if (s.subscription != null) {
                        totalAmount = s.cart.fold(
                          0.0,
                          (sum, item) => sum + item.total,
                        );
                      }
                      // ✅ إذا جلسة حر → الوقت + المنتجات
                      else {
                        totalAmount =
                            _calculateTimeChargeFromMinutes(minutesToCharge) +
                            s.cart.fold(0.0, (sum, item) => sum + item.total);
                      }

                      setState(() {
                        s.isActive = false;
                        s.isPaused = false;
                        s.amountPaid += totalAmount; // فقط نضيف المبلغ الجديد
                      });

                      await SessionDb.updateSession(s);

                      final sale = Sale(
                        id: generateId(),
                        description:
                            'جلسة ${s.name} | ${s.subscription != null ? "منتجات فقط" : "وقت + منتجات"}',
                        amount: totalAmount,
                      );

                      await AdminDataService.instance.addSale(
                        sale,
                        paymentMethod: 'cash',
                        customer: _currentCustomer,
                        updateDrawer: true, // سيضيف المبلغ إلى درج الكاشير تلقائيًا
                      );
                      try {

                        await _loadDrawerBalance();
                      } catch (e, st) {
                        debugPrint('Failed to update drawer after quick sale: $e\n$st');
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '✅ تم الدفع: ${totalAmount.toStringAsFixed(2)} ج',
                          ),
                        ),
                      );
                    },
                    child: const Text('تأكيد الدفع'),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /*  Widget _buildSubscribersList({String? type}) {
    // type = "باقة" → فقط المشتركين بالباقة
    // type = "حر" → المشتركين الحر
    // null → كل المشتركين

    final filtered =
        _filteredSessions.where((s) {
          if (type == "باقة") return s.subscription != null;
          if (type == "حر") return s.subscription == null;
          return true; // كل المشتركين
        }).toList();

    if (filtered.isEmpty) return const Center(child: Text("لا يوجد بيانات"));

    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (context, i) {
        final s = filtered[i];
        final spentMinutes = getSessionMinutes(s);
        final endTime = getSubscriptionEnd(s);

        String timeInfo =
            s.subscription != null
                ? (endTime != null
                    ? "من: ${s.start.toLocal()} ⇢ ينتهي: ${endTime.toLocal()} ⇢ مضى: ${spentMinutes} دقيقة"
                    : "من: ${s.start.toLocal()} ⇢ غير محدود ⇢ مضى: ${spentMinutes} دقيقة")
                : "من: ${s.start.toLocal()} ⇢ مضى: ${spentMinutes} دقيقة";

        return Card(
          child: ListTile(
            title: Text(s.name),
            subtitle: Text(
              '${s.isActive ? (s.isPaused ? "متوقف مؤقت" : "نشط") : "انتهت"} - $timeInfo',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (s.isActive)
                  ElevatedButton(
                    onPressed: () => _togglePauseSession(i),
                    child: Text(s.isPaused ? 'استئناف' : 'ايقاف مؤقت'),
                  ),
                const SizedBox(width: 4),
                if (s.isActive && !s.isPaused)
                  ElevatedButton(
                    onPressed: () async {
                      setState(() => _selectedSession = s);
                      await showModalBottomSheet(
                        context: context,
                        builder: (_) => _buildAddProductsAndPay(s),
                      );
                    },
                    child: const Text('اضف & دفع'),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }*/

  /// 🔹 دالة المنتجات المباعة
  Widget _buildSalesList() {
    final sales = AdminDataService.instance.sales;

    if (sales.isEmpty) {
      return const Center(child: Text("لا يوجد منتجات مباعة"));
    }

    return ListView.builder(
      itemCount: sales.length,
      itemBuilder: (context, i) {
        final sale = sales[i];
        return Card(
          child: ListTile(
            title: Text(sale.description),
            subtitle: Text("المبلغ: ${sale.amount} ج"),
          ),
        );
      },
    );
  }
}

extension FirstWhereOrNullExtension<E> on List<E> {
  E? firstWhereOrNull(bool Function(E) test) {
    for (var element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
