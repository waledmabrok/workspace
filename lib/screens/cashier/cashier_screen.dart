import 'package:flutter/material.dart';
import 'package:workspace/screens/cashier/user_Subscripe.dart';
import '../../core/FinanceDb.dart';
import '../../core/db_helper_cart.dart';
import '../../core/db_helper_customers.dart';
import '../../core/db_helper_discounts.dart';
import '../../core/models.dart';
import '../../core/data_service.dart';
import '../../core/db_helper_sessions.dart';
import 'dart:async';

import '../../widget/dialog.dart';
import '../admin/CustomerSubscribe.dart';
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
    _currentCustomer = AdminDataService.instance.customers.firstWhereOrNull(
      (c) => c.name == _currentCustomerName,
    );
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
    // invariant:
    // - s.elapsedMinutes = مجموع دقائق الفترات المنتهية سابقاً
    // - s.pauseStart != null فقط عندما تكون الجلسة "تشغّل" (running)
    if (s.isPaused) {
      return s.elapsedMinutes;
    } else {
      final since = s.pauseStart ?? s.start;
      return s.elapsedMinutes + DateTime.now().difference(since).inMinutes;
    }
  }

  /*int getSessionMinutes(Session s) {
    if (s.isPaused) {
      return s.elapsedMinutes;
    } else {
      return s.elapsedMinutes +
          DateTime.now().difference(s.pauseStart ?? s.start).inMinutes;
    }
  }*/

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

  final TextEditingController _phoneCtrl = TextEditingController();

  // مساعد: احصل على عميل موجود أو أنشئ واحد جديد
  Future<Customer> _getOrCreateCustomer(String name, String? phone) async {
    final all = await CustomerDb.getAll();
    Customer? found;
    for (final c in all) {
      if (c.name == name ||
          (phone != null && phone.isNotEmpty && c.phone == phone)) {
        found = c;
        break;
      }
    }

    if (found != null) return found;

    final newCustomer = Customer(
      id: generateId(),
      name: name,
      phone: phone,
      notes: null,
    );

    await CustomerDb.insert(newCustomer);
    // لو عندك AdminDataService.instance.customers ممكن تضيفه هناك علطول:
    try {
      AdminDataService.instance.customers.add(newCustomer);
    } catch (_) {}
    return newCustomer;
  }

  // الدالة المحسنة _startSession
  void _startSession() async {
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();

    if (name.isEmpty) {
      // ممكن تعرض Snackbar أو تحط فوكاس على الحقل
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('رجاءً ضع اسم العميل')));
      return;
    }

    // === تأكد/انشئ العميل ===
    Customer? customer;
    try {
      customer = await _getOrCreateCustomer(name, phone.isEmpty ? null : phone);
      _currentCustomer = customer;
    } catch (e, st) {
      debugPrint('Failed to get/create customer: $e\n$st');
      // نمطياً نكمل بدون عميل مسجل (جلسة حر) لكن نعلّم المستخدم
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'فشل حفظ بيانات العميل، سيتم متابعة الجلسة بدون ربط عميل.',
          ),
        ),
      );
      customer = null;
      _currentCustomer = null;
    }

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
      // جلسة حر
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
      type: currentPlan != null ? "باقة" : "حر",
      // لو موديل Session عنده customerId أو customer حطّه هنا لو متاح:
      // customerId: customer?.id,
    );

    // لو فيه خطة اشتراك — اعمل عملية بيع سريعة
    if (currentPlan != null) {
      final basePrice = currentPlan.price;
      final discountPercent = _appliedDiscount?.percent ?? 0.0;
      final discountValue = basePrice * (discountPercent / 100);
      final finalPrice = basePrice - discountValue;

      session.amountPaid = finalPrice;

      final sale = Sale(
        id: generateId(),
        description:
            'اشتراك ${currentPlan.name} للعميل ${name}'
            '${_appliedDiscount != null ? " (خصم ${_appliedDiscount!.percent}%)" : ""}',
        amount: finalPrice,
      );

      try {
        await AdminDataService.instance.addSale(
          sale,
          paymentMethod: 'cash',
          customer: customer,
          updateDrawer: true,
        );

        // 🟢 هنا نطبع/نعرض تفاصيل الباقة
        final nowStr = now.toLocal().toString();
        final endStr = end?.toLocal().toString() ?? "غير محدود";

        String durationInfo;
        switch (currentPlan.durationType) {
          case "hour":
            durationInfo = "تنتهي بعد ${currentPlan.durationValue} ساعة";
            break;
          case "day":
            durationInfo = "تنتهي بعد ${currentPlan.durationValue} يوم";
            break;
          case "week":
            durationInfo = "تنتهي بعد ${currentPlan.durationValue} أسبوع";
            break;
          case "month":
            durationInfo = "تنتهي بعد ${currentPlan.durationValue} شهر";
            break;
          default:
            durationInfo = currentPlan.isUnlimited ? "غير محدودة" : "غير معروف";
        }

        // لو عندك حد يومي
        String dailyLimitInfo = "";
        if (currentPlan.dailyUsageType == "limited") {
          dailyLimitInfo =
              "\nحد الاستخدام اليومي: ${currentPlan.dailyUsageHours} دقيقة";
        }

        debugPrint("""
====== تفاصيل الاشتراك ======
العميل: $name
الباقة: ${currentPlan.name}
السعر الأساسي: $basePrice ج
الخصم: $discountPercent% ($discountValue ج)
المطلوب: $finalPrice ج
بدأت: $nowStr
${durationInfo != "" ? "المدة: $durationInfo" : ""}
تنتهي: $endStr
$dailyLimitInfo
=============================
""");

        // ممكن تعرضها كـ Dialog بدل الطباعة:
        await showDialog(
          context: context,
          builder:
              (_) => AlertDialog(
                title: Text("تفاصيل اشتراك ${currentPlan.name}"),
                content: Text(
                  "العميل: $name\n"
                  "السعر: ${finalPrice.toStringAsFixed(2)} ج\n"
                  "بدأت: $nowStr\n"
                  "تنتهي: $endStr\n"
                  "$durationInfo\n"
                  "$dailyLimitInfo",
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("تمام"),
                  ),
                ],
              ),
        );

        // 🔻 باقي الكود كما هو
        if (_appliedDiscount?.singleUse == true) {
          AdminDataService.instance.discounts.removeWhere(
            (d) => d.id == _appliedDiscount!.id,
          );
          _appliedDiscount = null;
        }

        await _loadDrawerBalance();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم دفع اشتراك ${currentPlan.name} (${finalPrice.toStringAsFixed(2)} ج)',
            ),
          ),
        );
      } catch (e, st) {
        debugPrint('Failed to process quick sale: $e\n$st');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فشل تسجيل الدفعة — حاول مرة أخرى')),
        );
      }
    }

    // حفظ الجلسة في DB و تحديث الواجهة
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
      _phoneCtrl.clear();
      _selectedPlan = null;
      _appliedDiscount = null;
      _discountCodeCtrl.clear();
    });
  }

  Future<void> _togglePauseSessionFor(Session s) async {
    if (!s.isActive) return;

    setState(() {
      if (s.isPaused) {
        // استئناف: نبدأ العد من الآن
        s.isPaused = false;
        s.pauseStart = DateTime.now();
      } else {
        // إيقاف مؤقت: نجمع الدقائق منذ آخر resume (أو start) ونوقف
        final since = s.pauseStart ?? s.start;
        s.elapsedMinutes += DateTime.now().difference(since).inMinutes;
        s.isPaused = true;
        s.pauseStart = null; // نفضّل تعيينه null عند الإيقاف
      }
    });

    try {
      await SessionDb.updateSession(s);
    } catch (e, st) {
      debugPrint('Failed to update session pause toggle: $e\n$st');
    }
  }

  /*  Widget _buildAddProductsAndPay(Session s) {
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
  }*/
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
              // Dropdown لاختيار المنتج
              DropdownButtonFormField<Product>(
                value: selectedProduct,
                hint: const Text(
                  'اختر منتج/مشروب',
                  style: TextStyle(color: Colors.white70),
                ),
                dropdownColor: Colors.grey[850],
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.grey[800],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                ),
                items:
                    AdminDataService.instance.products.map((p) {
                      return DropdownMenuItem(
                        value: p,
                        child: Text(
                          '${p.name} (${p.price} ج)',
                          style: const TextStyle(color: Colors.white),
                        ),
                      );
                    }).toList(),
                onChanged: (val) {
                  setSheetState(() => selectedProduct = val);
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: qtyCtrl,
                      style: const TextStyle(color: Colors.white),
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'عدد',
                        labelStyle: const TextStyle(color: Colors.white70),
                        filled: true,
                        fillColor: Colors.grey[800],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                      ),
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
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'اضف',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // قائمة العناصر المضافة
              ...s.cart.map((item) {
                final qtyController = TextEditingController(
                  text: item.qty.toString(),
                );
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.product.name,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      SizedBox(
                        width: 60,
                        child: TextField(
                          controller: qtyController,
                          style: const TextStyle(color: Colors.white),
                          keyboardType: TextInputType.number,
                          onChanged: (val) async {
                            item.qty = int.tryParse(val) ?? item.qty;
                            await CartDb.updateCartItemQty(item.id, item.qty);
                            setSheetState(() {});
                          },
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.grey[800],
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.redAccent),
                        onPressed: () async {
                          await CartDb.deleteCartItem(item.id);
                          s.cart.remove(item);
                          setSheetState(() {});
                        },
                      ),
                    ],
                  ),
                );
              }).toList(),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _completeAndPayForSession(s);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent.shade700,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'إتمام ودفع',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
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

  /// دقائق الجلسة داخل نفس اليوم (من بداية اليوم حتى الآن أو end إذا أسبق)
  int getSessionMinutesToday(Session s) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));

    final sessionStart = s.start.isBefore(todayStart) ? todayStart : s.start;
    // لو الجلسة لها end داخل اليوم خده، وإلا خُد الآن
    final sessionEnd = (s.end != null && s.end!.isBefore(now)) ? s.end! : now;

    if (sessionEnd.isBefore(todayStart)) return 0;
    if (sessionStart.isAfter(todayEnd)) return 0;

    return sessionEnd.difference(sessionStart).inMinutes;
  }

  int allowedMinutesTodayForPlan(SubscriptionPlan? plan) {
    if (plan == null) return -1;
    if (plan.dailyUsageType != 'limited' || plan.dailyUsageHours == null)
      return -1;
    return plan.dailyUsageHours! * 60; // تحويل ساعات إلى دقائق
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
    final customerId = s.customerId;
    double customerBalance = 0.0;

    if (customerId != null && customerId.isNotEmpty) {
      customerBalance = await CustomerBalanceDb.getBalance(customerId);
    }

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            double finalTotal = timeCharge + productsTotal - discountValue;

            return AlertDialog(
              title: Text(
                'إيصال الدفع - ${s.name} (الرصيد: ${customerBalance.toStringAsFixed(2)} ج)',
              ),
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

                    // طريقة الدفع
                    Row(
                      children: [
                        const Text("طريقة الدفع: "),
                        const SizedBox(width: 8),
                        DropdownButton<String>(
                          value: paymentMethod,
                          items: const [
                            DropdownMenuItem(value: "cash", child: Text("كاش")),
                            DropdownMenuItem(
                              value: "wallet",
                              child: Text("محفظة"),
                            ),
                          ],
                          onChanged: (val) {
                            if (val != null)
                              setDialogState(() => paymentMethod = val);
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // المبلغ المطلوب
                    Text(
                      'المطلوب: ${finalTotal.toStringAsFixed(2)} ج',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),

                    const SizedBox(height: 8),

                    // إدخال المبلغ المدفوع
                    TextField(
                      controller: paidCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "المبلغ المدفوع",
                      ),
                      onChanged: (val) {
                        setDialogState(
                          () {},
                        ); // كل مرة يتغير فيها المبلغ، يحدث الـ dialog
                      },
                    ),
                    const SizedBox(height: 8),
                    // عرض الباقي أو الفائض
                    Builder(
                      builder: (_) {
                        final paidAmount =
                            double.tryParse(paidCtrl.text) ?? 0.0;
                        final diff = paidAmount - finalTotal;
                        String diffText;
                        if (diff == 0) {
                          diffText = '✅ دفع كامل';
                        } else if (diff > 0) {
                          diffText =
                              '💰 الباقي للعميل: ${diff.toStringAsFixed(2)} ج';
                        } else {
                          diffText =
                              '💸 على العميل: ${(diff.abs()).toStringAsFixed(2)} ج';
                        }
                        return Text(
                          diffText,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        );
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                // داخل actions: []
                ElevatedButton(
                  onPressed: () async {
                    final paidAmount = double.tryParse(paidCtrl.text) ?? 0.0;
                    final diff = paidAmount - finalTotal;
                    if (paidAmount < finalTotal) {
                      // رسالة تحذير: المبلغ أقل من المطلوب
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('⚠️ المبلغ المدفوع أقل من المطلوب.'),
                        ),
                      );
                      return; // لا يتم تنفيذ أي شيء
                    }
                    if (diff > 0) {
                      // خصم الفائض من الدرج
                      await AdminDataService.instance.addSale(
                        Sale(
                          id: generateId(),
                          description: 'سداد الباقي كاش للعميل',
                          amount: diff,
                        ),
                        paymentMethod: 'cash',
                        updateDrawer: true,
                        drawerDelta: -diff, // خصم من الدرج بدل الإضافة
                      );

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '💵 أخذ العميل باقي ${diff.toStringAsFixed(2)} ج كاش من الدرج',
                          ),
                        ),
                      );
                    }

                    // تحديث دقائق الدفع
                    s.paidMinutes += minutesToCharge;
                    s.amountPaid += paidAmount;

                    // ---- قفل الجلسة وتحديث DB ----
                    setState(() {
                      s.isActive = false;
                      s.isPaused = false;
                    });
                    await SessionDb.updateSession(s);

                    // حفظ المبيعة كما هي
                    final sale = Sale(
                      id: generateId(),
                      description:
                          'جلسة ${s.name} | وقت: ${minutesToCharge} دقيقة + منتجات: ${s.cart.fold(0.0, (sum, item) => sum + item.total)}',
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

                    // إشعار للمستخدم بأن الباقي أخذ كاش
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '💵 الباقي ${diff > 0 ? diff.toStringAsFixed(2) : 0} ج أخذ كاش',
                        ),
                      ),
                    );
                  },
                  child: const Text('تأكيد الدفع بالكامل'),
                ),

                ElevatedButton(
                  onPressed: () async {
                    // required / paid / diff
                    final requiredAmount = finalTotal;
                    final paidAmount = double.tryParse(paidCtrl.text) ?? 0.0;
                    final diff = paidAmount - requiredAmount;

                    // تحديث دقائق الدفع داخل الجلسة
                    s.paidMinutes += minutesToCharge;
                    s.amountPaid += paidAmount;

                    // ---- تحديث رصيد العميل بشكل صحيح ----
                    // 1) نحدد customerId الهدف: نفضل s.customerId ثم _currentCustomer
                    String? targetCustomerId =
                        s.customerId ?? _currentCustomer?.id;

                    // 2) لو لسه فاضي حاول نبحث عن العميل بالاسم، وإن لم يوجد - ننشئ واحد جديد
                    if (targetCustomerId == null || targetCustomerId.isEmpty) {
                      // حاول إيجاد العميل في DB بحسب الاسم
                      final found = await CustomerDb.getByName(s.name);
                      if (found != null) {
                        targetCustomerId = found.id;
                      } else {
                        // لو اسم موجود في الحقل ونفّذنا إنشاء: ننشئ عميل جديد ونتخزن
                        if (s.name.trim().isNotEmpty) {
                          final newCustomer = Customer(
                            id: generateId(),
                            name: s.name,
                            phone: null,
                            notes: null,
                          );
                          await CustomerDb.insert(newCustomer);
                          // حدث الذاكرة المحلية إن وُجد (AdminDataService)
                          try {
                            AdminDataService.instance.customers.add(
                              newCustomer,
                            );
                          } catch (_) {}
                          targetCustomerId = newCustomer.id;
                        }
                      }
                    }

                    if (targetCustomerId != null &&
                        targetCustomerId.isNotEmpty) {
                      // احصل الرصيد القديم من الذاكرة (أو استخدم 0)
                      final oldBalance = AdminDataService
                          .instance
                          .customerBalances
                          .firstWhere(
                            (b) => b.customerId == targetCustomerId,
                            orElse:
                                () => CustomerBalance(
                                  customerId: targetCustomerId!,
                                  balance: 0.0,
                                ),
                          );

                      final newBalance = oldBalance.balance + diff;
                      final updated = CustomerBalance(
                        customerId: targetCustomerId,
                        balance: newBalance,
                      );

                      // اكتب للـ DB
                      await CustomerBalanceDb.upsert(updated);

                      // حدّث الذاكرة (AdminDataService)
                      final idx = AdminDataService.instance.customerBalances
                          .indexWhere((b) => b.customerId == targetCustomerId);
                      if (idx >= 0) {
                        AdminDataService.instance.customerBalances[idx] =
                            updated;
                      } else {
                        AdminDataService.instance.customerBalances.add(updated);
                      }
                    } else {
                      // لم نتمكن من إيجاد/إنشاء عميل --> تسجّل ملاحظۀ debug
                      debugPrint(
                        'No customer id for session ${s.id}; balance not updated.',
                      );
                    }

                    // ---- قفل الجلسة وتحديث DB ----
                    setState(() {
                      s.isActive = false;
                      s.isPaused = false;
                    });
                    await SessionDb.updateSession(s);

                    // ---- حفظ المبيعة ----
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

                    // إشعار للمستخدم (باقي/له/عليه)
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
                  child: const Text('علي الحساب'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إلغاء'),
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
        return minutesLeft <= 50; // قربت تنتهي خلال 10 دقائق
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

  Future<void> _closeShift() async {
    // 1. احسب المبيعات للشيفت فقط للجلسات اللي خلصت أو المنتجات اللي مدفوعة
    final cashSales = AdminDataService.instance.sales
        .where((s) => s.paymentMethod == 'cash')
        .fold(0.0, (sum, s) => sum + s.amount);

    final walletSales = AdminDataService.instance.sales
        .where((s) => s.paymentMethod == 'wallet')
        .fold(0.0, (sum, s) => sum + s.amount);

    // 2. احسب المصاريف
    final expenses = AdminDataService.instance.expenses.fold(
      0.0,
      (sum, e) => sum + e.amount,
    );

    // 3. الرصيد الحالي للدرج
    final drawer = AdminDataService.instance.drawerBalance;

    // 4. عرض ملخص للمستخدم
    await showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('ملخص الشيفت'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('إجمالي مبيعات كاش: ${cashSales.toStringAsFixed(2)} ج'),
                Text(
                  'إجمالي مبيعات محفظة: ${walletSales.toStringAsFixed(2)} ج',
                ),
                Text('إجمالي مصاريف: ${expenses.toStringAsFixed(2)} ج'),
                Text('رصيد الدرج الحالي: ${drawer.toStringAsFixed(2)} ج'),
                Text(
                  'الربح: ${(cashSales + walletSales - expenses).toStringAsFixed(2)} ج',
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إغلاق'),
              ),
            ],
          ),
    );

    // 5. تهيئة الشيفت الجديد بدون حذف الجلسات النشطة
    setState(() {
      _sessions = _sessions.where((s) => s.isActive).toList();

      // مسح المبيعات والمصاريف للشيفت السابق فقط
      AdminDataService.instance.sales.clear();
      AdminDataService.instance.expenses.clear();

      // تحديث رصيد الدرج للبدء من الصفر أو حسب رغبتك
      //   AdminDataService.instance.drawerBalance = 0.0;
    });

    // 6. احفظ التغييرات في DB
    // await FinanceDb.setDrawerBalance(0.0);
  }

  int get badgeCount =>
      getExpiringSessions().length + getExpiredSessions().length;
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الكاشير'),

          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'تحديث الجلسات',
              onPressed: () {
                _loadSessions();
                _loadDrawerBalance(); // دالة تحميل الجلسات
                if (mounted) setState(() {}); // حدث الـ UI بعد التحديث
              },
            ),
            // داخل AppBar.actions: ضع هذا قبل الأيقونات الأخرى أو بعدهم
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  'رصيد الدرج',
                  style: TextStyle(fontSize: 11, color: Colors.white70),
                ),
                Text(
                  '${_drawerBalance.toStringAsFixed(2)} ج',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.subscriptions),
              tooltip: 'الباقات',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => AdminSubscribersPagee()),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.lock_clock),
              tooltip: 'تقفيل الشيفت',
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder:
                      (_) => AlertDialog(
                        title: const Text('تأكيد تقفيل الشيفت'),
                        content: const Text(
                          'هل تريد إنهاء الشيفت وحساب كل الإيرادات؟',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('إلغاء'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('تأكيد'),
                          ),
                        ],
                      ),
                );

                if (confirm != true) return;

                // استدعاء دالة تقفيل الشيفت
                await _closeShift();
              },
            ),
            IconButton(
              icon: const Icon(Icons.add_shopping_cart),
              tooltip: 'إضافة منتجات بدون اسم',
              /* onPressed: () async {
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
              },*/
              onPressed: () async {
                final subscribers =
                    _sessions
                        .where((s) => s.subscription != null && s.isActive)
                        .toList();

                Session? selectedSession;

                if (subscribers.isNotEmpty) {
                  selectedSession = await showDialog<Session>(
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
                                onTap:
                                    () => Navigator.pop(
                                      context,
                                      sub,
                                    ), // ✅ رجع السيشن نفسه
                              );
                            },
                          ),
                        ),
                      );
                    },
                  );
                }

                // لو المستخدم ما اختارش → Cancel
                if (selectedSession == null) return;

                await showModalBottomSheet(
                  context: context,
                  builder: (_) => _buildAddProductsAndPay(selectedSession!),
                );

                setState(() {
                  _filteredSessions = _sessions; // تحديث العرض بعد الإضافة
                });
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
                              allSessions: _sessions,
                              // expiring: expiring,
                              //  expired: expired,
                            ),
                      ),
                    );
                  },
                ),
                // Badge
                if /* (getExpiringSessions().isNotEmpty ||
                    getExpiredSessions().isNotEmpty)|| */ (badgeCount > 0)
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
                        '$badgeCount',
                        // '${getExpiringSessions().length + getExpiredSessions().length}',
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
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              // ---------------- البحث ----------------
              TextField(
                controller: _searchCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                cursorColor: Colors.blueAccent,
                decoration: InputDecoration(
                  hintText: 'ابحث عن مشترك',
                  hintStyle: TextStyle(color: Colors.white70),
                  prefixIcon: const Icon(Icons.search, color: Colors.white70),
                  filled: true,
                  fillColor: Colors.grey[900],
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 12,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade700),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: Colors.blueAccent,
                      width: 2,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ---------------- اختيار باقة ----------------
              // Dropdown
              DropdownButtonFormField<SubscriptionPlan>(
                value: _selectedPlan,
                dropdownColor: Colors.grey[900],
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: InputDecoration(
                  labelText: "اختر اشتراك (اختياري)",
                  labelStyle: const TextStyle(color: Colors.white70),
                  filled: true,
                  fillColor: Colors.grey[900],
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 12,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade700),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                    borderSide: BorderSide(color: Colors.blueAccent, width: 2),
                  ),
                ),
                items:
                    AdminDataService.instance.subscriptions.map((s) {
                      return DropdownMenuItem(
                        value: s,
                        child: Text(
                          "${s.name} - ${s.price} ج",
                          style: const TextStyle(color: Colors.white),
                        ),
                      );
                    }).toList(),
                onChanged: (val) => setState(() => _selectedPlan = val),
              ),

              const SizedBox(height: 12),

              // اسم العميل + زر التسجيل
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nameCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                      cursorColor: Colors.blueAccent,
                      decoration: InputDecoration(
                        hintText: 'اسم العميل',
                        hintStyle: const TextStyle(color: Colors.white70),
                        filled: true,
                        fillColor: Colors.grey[900],
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 16,
                          horizontal: 12,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade700),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                          borderSide: BorderSide(
                            color: Colors.blueAccent,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _startSession,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'ابدأ تسجيل',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
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
                      Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey[850], // خلفية الـ TabBar
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: TabBar(
                          indicatorPadding: EdgeInsets.zero,
                          indicatorSize: TabBarIndicatorSize.label,
                          indicator: BoxDecoration(
                            color: Colors.blueAccent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          labelColor: Colors.white,
                          unselectedLabelColor: Colors.white70,
                          tabs: const [
                            Tab(
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                                child: Text("مشتركين باقات"),
                              ),
                            ),
                            Tab(
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                                child: Text("مشتركين حر"),
                              ),
                            ),
                            Tab(
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                                child: Text("المنتجات"),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: TabBarView(
                          children: [
                            AdminSubscribersPagee(), // المشتركين باقات
                            _buildSubscribersList(
                              withPlan: false,
                            ), // المشتركين حر
                            _buildSalesList(), // المنتجات
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
  Widget _buildSubscribersList({required bool withPlan}) {
    final searchText = _searchCtrl.text.toLowerCase();
    final filtered =
        _sessions.where((s) {
          final matchesType = withPlan ? s.type == "باقة" : s.type == "حر";
          final matchesSearch = s.name.toLowerCase().contains(searchText);
          return matchesType && matchesSearch;
        }).toList();

    if (filtered.isEmpty)
      return const Center(
        child: Text("لا يوجد بيانات", style: TextStyle(color: Colors.white70)),
      );

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
          color: Colors.grey[850],
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${s.isActive ? (s.isPaused ? "متوقف مؤقت" : "نشط") : "انتهت"} - $timeInfo',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed:
                            s.isActive ? () => _togglePauseSessionFor(s) : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueGrey[700], // زر رئيسي
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(s.isPaused ? 'استئناف' : 'ايقاف مؤقت'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed:
                            s.isActive && !s.isPaused
                                ? () async {
                                  setState(() => _selectedSession = s);
                                  await showModalBottomSheet(
                                    context: context,
                                    builder: (_) => _buildAddProductsAndPay(s),
                                  );
                                }
                                : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue[700], // زر الدفع
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('اضف & دفع'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /* Widget _buildSubscribersList({required bool withPlan}) {
    // فلترة مباشرة من _sessions
    */ /* final filtered =
        _sessions.where((s) {
          if (withPlan) return s.type == "باقة";
          return s.type == "حر";
        }).toList();*/ /*
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
                    onPressed: () => _togglePauseSessionFor(s),

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

  Widget _buildSubscribersList3({required bool withPlan}) {
    final searchText = _searchCtrl.text.toLowerCase();
    final filtered =
        _sessions.where((s) {
          final matchesType = withPlan ? s.type == "باقة" : s.type == "حر";
          final matchesSearch = s.name.toLowerCase().contains(searchText);
          return matchesType && matchesSearch;
        }).toList();

    if (filtered.isEmpty) return const Center(child: Text("لا يوجد بيانات"));

    String _formatHoursMinutes(int minutes) {
      final h = minutes ~/ 60;
      final m = minutes % 60;
      if (h > 0) return "${h}س ${m}د";
      return "${m}د";
    }

    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (context, i) {
        final s = filtered[i];

        final totalMinutes = getSessionMinutes(
          s,
        ); // إجمالي دقائق الجلسة حتى الآن
        final spentToday = getSessionMinutesToday(s); // دقائق اليوم فقط

        // حساب الحد اليومي (مخزن بالساعات في SubscriptionPlan)
        int allowedToday = -1; // -1 يعني غير محدود أو لا باقة
        if (s.subscription != null &&
            s.subscription!.dailyUsageType == 'limited' &&
            s.subscription!.dailyUsageHours != null) {
          allowedToday = s.subscription!.dailyUsageHours! * 60;
        }

        // دقائق زائدة بالفعل الآن (بحدود اليوم)
        final extraNow =
            (allowedToday > 0)
                ? (spentToday - allowedToday).clamp(0, double.infinity).toInt()
                : 0;

        // دقائق جديدة لم تُدفع بعد (قد تكون مغطاة جزئياً بالباقة)
        final minutesToCharge =
            (totalMinutes - s.paidMinutes).clamp(0, totalMinutes).toInt();

        // حساب كم من minutesToCharge سيغطيه الباقه وكم سيكون اضافي
        int coveredByPlan = 0;
        int extraIfPayNow = minutesToCharge;
        if (allowedToday > 0) {
          // قبل دقائق الجديدة كان spentToday - minutesToCharge
          final priorSpentToday =
              (spentToday - minutesToCharge).clamp(0, spentToday).toInt();
          final remainingAllowanceBefore = (allowedToday - priorSpentToday)
              .clamp(0, allowedToday);
          coveredByPlan =
              (minutesToCharge <= remainingAllowanceBefore)
                  ? minutesToCharge
                  : remainingAllowanceBefore;
          extraIfPayNow = minutesToCharge - coveredByPlan;
        } else {
          coveredByPlan = 0;
          extraIfPayNow = minutesToCharge;
        }

        final extraChargeEstimate = _calculateTimeChargeFromMinutes(
          extraIfPayNow,
        );

        // منتجات الجلسة
        final productsTotal = s.cart.fold(0.0, (sum, item) => sum + item.total);

        // نص العرض
        final startStr = s.start.toLocal().toString().split('.').first;
        final endTime = getSubscriptionEnd(s);
        final endStr =
            endTime != null
                ? endTime.toLocal().toString().split('.').first
                : 'غير محدود';

        String timeInfo;
        if (s.subscription != null) {
          String dailyInfo =
              (allowedToday > 0)
                  ? 'حد اليوم: ${_formatHoursMinutes(allowedToday)} • مضى اليوم: ${_formatHoursMinutes(spentToday)} • متبقي: ${_formatHoursMinutes((allowedToday - spentToday).clamp(0, allowedToday))}'
                  : 'حد اليوم: غير محدود';
          timeInfo =
              'من: $startStr ⇢ ينتهي: $endStr\nمضى الكلي: ${_formatHoursMinutes(totalMinutes)} — $dailyInfo';
          if (extraNow > 0) {
            timeInfo +=
                '\n⛔ دقائق زائدة الآن: ${_formatHoursMinutes(extraNow)}';
          }
        } else {
          timeInfo =
              'من: $startStr\nمضى الكلي: ${_formatHoursMinutes(totalMinutes)}';
        }

        return Card(
          child: ListTile(
            title: Text(s.name),
            subtitle: Text(
              '${s.isActive ? (s.isPaused ? "متوقف مؤقت" : "نشط") : "انتهت"}\n$timeInfo',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (s.isActive)
                  ElevatedButton(
                    onPressed: () => _togglePauseSessionFor(s),

                    child: Text(s.isPaused ? 'استئناف' : 'ايقاف مؤقت'),
                  ),
                const SizedBox(width: 6),
                // استدعاء Dialog قبل الدفع
                if (s.isActive && !s.isPaused)
                  ElevatedButton(
                    onPressed: () async {
                      await _showReceiptDialog(
                        s,
                        productsTotal,
                        extraChargeEstimate,
                        extraIfPayNow,
                      );
                    },
                    child: const Text('ادفع الآن'),
                  ),

                /*  if (s.isActive && !s.isPaused)
                  ElevatedButton(
                    onPressed: () async {
                      // حساب المبلغ المطلوب الآن كما في الكود الحالي
                      final minutesToCharge =
                          (getSessionMinutes(s) - s.paidMinutes)
                              .clamp(0, getSessionMinutes(s))
                              .toInt();
                      final coveredByPlan =
                          (() {
                            // نفس منطق الحساب الذي استخدمته قبلًا لاستخراج coveredByPlan
                            int allowedToday = -1;
                            if (s.subscription != null &&
                                s.subscription!.dailyUsageType == 'limited' &&
                                s.subscription!.dailyUsageHours != null) {
                              allowedToday =
                                  s.subscription!.dailyUsageHours! * 60;
                            }
                            if (allowedToday > 0) {
                              final spentToday = getSessionMinutesToday(s);
                              final priorSpentToday =
                                  (spentToday - minutesToCharge)
                                      .clamp(0, spentToday)
                                      .toInt();
                              final remainingAllowanceBefore = (allowedToday -
                                      priorSpentToday)
                                  .clamp(0, allowedToday);
                              return minutesToCharge <= remainingAllowanceBefore
                                  ? minutesToCharge
                                  : remainingAllowanceBefore;
                            }
                            return 0;
                          })();

                      final extraIfPayNow = minutesToCharge - coveredByPlan;
                      final extraChargeEstimate =
                          _calculateTimeChargeFromMinutes(extraIfPayNow);
                      final productsTotal = s.cart.fold(
                        0.0,
                        (sum, item) => sum + item.total,
                      );
                      final requiredNow = extraChargeEstimate + productsTotal;

                      if (requiredNow <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('لا يوجد مستحقات للدفع الآن.'),
                          ),
                        );
                        return;
                      }

                      // حاول نلاقي العميل المسجل بالجلسة (أولوية: customerId داخل الجلسة ثم _currentCustomer ثم DB by name)
                      Customer? cust;
                      try {
                        // لو عندك customerId في Session استخدمها (مثال: s.customerId)
                        if ((s.customerId ?? '').isNotEmpty) {
                          // مثال: CustomerDb.getById موجود؟ لو لا استعمل getAll/getByName كما عندك
                          cust = await CustomerDb.getById(s.customerId!);
                        }
                      } catch (_) {}

                      // لو ما لقيناش عن طريق id جرب _currentCustomer أو البحث بالاسم
                      if (cust == null) {
                        cust = _currentCustomer;
                      }
                      if (cust == null) {
                        try {
                          final found = await CustomerDb.getByName(s.name);
                          if (found != null) cust = found;
                        } catch (_) {}
                      }

                      double balance = 0.0;
                      if (cust != null) {
                        // جرب من الذاكرة أولا
                        final cb = AdminDataService.instance.customerBalances
                            .firstWhere(
                              (b) => b.customerId == cust!.id,
                              orElse:
                                  () => CustomerBalance(
                                    customerId: cust!.id,
                                    balance: 0.0,
                                  ),
                            );
                        balance = cb.balance;
                        // لو القيمة صفر في الذاكرة، نحاول جلبها من DB كـ fallback
                        if (balance == 0.0) {
                          try {
                            balance = await AdminDataService.instance
                                .getCustomerBalance(cust.name);
                          } catch (_) {}
                        }
                      }

                      // لو فيه رصيد > 0، اعرض خيارات: استخدم الرصيد / كاش / مِكس
                      if (cust != null && balance > 0) {
                        final choice = await showDialog<String?>(
                          context: context,
                          builder:
                              (_) => AlertDialog(
                                title: const Text('طريقة الدفع'),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'رصيد العميل: ${balance.toStringAsFixed(2)} ج',
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'المطلوب الآن: ${requiredNow.toStringAsFixed(2)} ج',
                                    ),
                                    const SizedBox(height: 8),
                                    const Text('اختر كيف تريد تحصيل المبلغ:'),
                                  ],
                                ),
                                actions: [
                                  TextButton(
                                    onPressed:
                                        () => Navigator.pop(context, 'cash'),
                                    child: const Text('كاش فقط'),
                                  ),
                                  TextButton(
                                    onPressed:
                                        () => Navigator.pop(context, 'balance'),
                                    child: const Text('من رصيد العميل'),
                                  ),
                                  TextButton(
                                    onPressed:
                                        () => Navigator.pop(context, 'mixed'),
                                    child: const Text('رصيد + كاش (إن لزم)'),
                                  ),
                                ],
                              ),
                        );

                        if (choice == null) return;

                        if (choice == 'balance') {
                          // استخدم من الرصيد فقط (نفرض أنه يكفي أو نأخذ ما هو متاح كليًا)
                          final use =
                              balance >= requiredNow ? requiredNow : balance;
                          // خصم من رصيد العميل
                          await AdminDataService.instance.adjustCustomerBalance(
                            cust.name,
                            -use,
                          );
                          // حدّث الذاكرة سريعاً
                          final idx = AdminDataService.instance.customerBalances
                              .indexWhere((b) => b.customerId == cust!.id);
                          if (idx >= 0) {
                            AdminDataService
                                .instance
                                .customerBalances[idx] = CustomerBalance(
                              customerId: cust!.id,
                              balance:
                                  (AdminDataService
                                          .instance
                                          .customerBalances[idx]
                                          .balance -
                                      use),
                            );
                          } else {
                            AdminDataService.instance.customerBalances.add(
                              CustomerBalance(
                                customerId: cust!.id,
                                balance: 0.0,
                              ),
                            );
                          }

                          // سجّل مبيعة على أنها من رصيد العميل
                          final saleBalance = Sale(
                            id: generateId(),
                            description:
                                'دفعة من رصيد العميل ${cust.name} لجلسة ${s.name}',
                            amount: use,
                            paymentMethod: 'balance',
                            customerId: cust.id,
                          );
                          await AdminDataService.instance.addSale(
                            saleBalance,
                            paymentMethod: 'balance',
                            customer: cust,
                            updateDrawer: false,
                          );

                          // لو الرصيد لم يغطي المطلوب و requiredNow > use (نادر هنا لأن choice == 'balance' لكن نتحصّن)
                          final remaining = (requiredNow - use).clamp(
                            0.0,
                            double.infinity,
                          );
                          if (remaining > 0) {
                            // خُذ الباقي ككاش
                            final saleCash = Sale(
                              id: generateId(),
                              description: 'باقي دفعة كاش لجلسة ${s.name}',
                              amount: remaining,
                              paymentMethod: 'cash',
                              customerId: cust.id,
                            );
                            await AdminDataService.instance.addSale(
                              saleCash,
                              paymentMethod: 'cash',
                              customer: cust,
                              updateDrawer: true,
                            );
                          }

                          // حدّث الجلسة
                          s.paidMinutes += minutesToCharge;
                          s.amountPaid += requiredNow;
                          await SessionDb.updateSession(s);
                          await _loadDrawerBalance();
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'تم خصم ${use.toStringAsFixed(2)} ج من رصيد العميل.',
                              ),
                            ),
                          );
                          return;
                        }

                        if (choice == 'mixed') {
                          // استعمل أقصى ما يمكن من الرصيد ثم كاش للباقي
                          final useFromBalance =
                              balance >= requiredNow ? requiredNow : balance;
                          final cashNeeded = (requiredNow - useFromBalance)
                              .clamp(0.0, double.infinity);

                          if (useFromBalance > 0) {
                            await AdminDataService.instance
                                .adjustCustomerBalance(
                                  cust.name,
                                  -useFromBalance,
                                );
                            final idx = AdminDataService
                                .instance
                                .customerBalances
                                .indexWhere((b) => b.customerId == cust!.id);
                            if (idx >= 0) {
                              AdminDataService
                                  .instance
                                  .customerBalances[idx] = CustomerBalance(
                                customerId: cust!.id,
                                balance:
                                    (AdminDataService
                                            .instance
                                            .customerBalances[idx]
                                            .balance -
                                        useFromBalance),
                              );
                            } else {
                              AdminDataService.instance.customerBalances.add(
                                CustomerBalance(
                                  customerId: cust!.id,
                                  balance: 0.0,
                                ),
                              );
                            }
                            final saleBalance = Sale(
                              id: generateId(),
                              description:
                                  'دفعة من رصيد العميل ${cust.name} لجلسة ${s.name}',
                              amount: useFromBalance,
                              paymentMethod: 'balance',
                              customerId: cust.id,
                            );
                            await AdminDataService.instance.addSale(
                              saleBalance,
                              paymentMethod: 'balance',
                              customer: cust,
                              updateDrawer: false,
                            );
                          }

                          if (cashNeeded > 0) {
                            final saleCash = Sale(
                              id: generateId(),
                              description:
                                  'دفع كاش لباقي المبلغ لجلسة ${s.name}',
                              amount: cashNeeded,
                              paymentMethod: 'cash',
                              customerId: cust.id,
                            );
                            await AdminDataService.instance.addSale(
                              saleCash,
                              paymentMethod: 'cash',
                              customer: cust,
                              updateDrawer: true,
                            );
                          }

                          // حدّث الجلسة
                          s.paidMinutes += minutesToCharge;
                          s.amountPaid += requiredNow;
                          await SessionDb.updateSession(s);
                          await _loadDrawerBalance();
                          setState(() {});

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'تم الدفع: ${requiredNow.toStringAsFixed(2)} ج (منها ${useFromBalance.toStringAsFixed(2)} ج من الرصيد)',
                              ),
                            ),
                          );
                          return;
                        }

                        // choice == 'cash' falls through to normal cash handling
                      }

                      // إذا مافيش رصيد أو المستخدم اختار كاش:
                      // نفذ الدفع كاش كامل
                      // (نفس منطقك السابق)
                      final paidAmount = requiredNow;
                      s.paidMinutes += minutesToCharge;
                      s.amountPaid += paidAmount;
                      await SessionDb.updateSession(s);

                      final sale = Sale(
                        id: generateId(),
                        description:
                            'جلسة ${s.name} | دقائق مدفوعة: $minutesToCharge + منتجات: ${productsTotal.toStringAsFixed(2)}',
                        amount: paidAmount,
                        paymentMethod: 'cash',
                      );

                      await AdminDataService.instance.addSale(
                        sale,
                        paymentMethod: 'cash',
                        customer: cust,
                        updateDrawer: true,
                      );

                      try {
                        await _loadDrawerBalance();
                      } catch (e, st) {
                        debugPrint(
                          'Failed to update drawer after quick sale: $e\n$st',
                        );
                      }

                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '✅ تم الدفع ${paidAmount.toStringAsFixed(2)} ج',
                          ),
                        ),
                      );
                    },

                    child: const Text('ادفع الآن'),
                  ),*/
              ],
            ),
          ),
        );
      },
    );
  }

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

/*  Future<void> _showReceiptDialog(
    Session s,
    double timeCharge,
    double productsTotal,
    int minutesToCharge,
  ) async {
    double discountValue = 0.0;
    String? appliedCode;
    final codeCtrl = TextEditingController();
    String paymentMethod = "cash";
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
                    const SizedBox(height: 12), // 🟢 اختيار وسيلة الدفع
                    Row(
                      children: [
                        const Text("طريقة الدفع: "),
                        const SizedBox(width: 8),
                        DropdownButton<String>(
                          value: paymentMethod,
                          items: const [
                            DropdownMenuItem(value: "cash", child: Text("كاش")),
                            DropdownMenuItem(
                              value: "wallet",
                              child: Text("محفظة"),
                            ),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() => paymentMethod = val);
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12), // 🟢
                    // المبلغ المطلوب
                    Text(
                      'المطلوب: ${finalTotal.toStringAsFixed(2)} ج',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8), // 🟢 إدخال المبلغ المدفوع
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
                    final requiredAmount = finalTotal; // ✅ المبلغ المدفوع
                    final paidAmount =
                        double.tryParse(paidCtrl.text) ?? 0.0; // ✅ الفرق
                    final diff =
                        paidAmount - requiredAmount; // ✅ تحديث دقائق الدفع
                    s.paidMinutes += minutesToCharge;
                    s.amountPaid += paidAmount; // ✅ تحديث رصيد العميل
                    if (s.name.isNotEmpty) {
                      final oldBalance = AdminDataService
                          .instance
                          .customerBalances
                          .firstWhere(
                            (b) => b.customerId == s.name,
                            orElse:
                                () => CustomerBalance(
                                  customerId: s.name,
                                  balance: 0,
                                ),
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
                        AdminDataService.instance.customerBalances[idx] =
                            updated;
                      } else {
                        AdminDataService.instance.customerBalances.add(updated);
                      }
                    } // ✅ قفل الجلسة
                    setState(() {
                      s.isActive = false;
                      s.isPaused = false;
                    });
                    await SessionDb.updateSession(s); // ✅ حفظ كـ
                    Sale;
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
                    Navigator.pop(context); // ✅ رسالة توضح الفلوس
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
  }*/

///subscrip paid
///if (currentPlan != null) {
//       // 🟢 افتح Dialog الدفع
//       final paid = await showDialog<bool>(
//         context: context,
//         builder:
//             (_) => ReceiptDialog(
//               session: session,
//               fixedAmount:
//                   currentPlan.price -
//                   (_appliedDiscount?.percent ?? 0.0) * currentPlan.price / 100,
//               description: 'اشتراك ${currentPlan.name}',
//             ),
//       );
//
//       if (paid == true) {
//         final basePrice = currentPlan.price;
//         final discountPercent = _appliedDiscount?.percent ?? 0.0;
//         final discountValue = basePrice * (discountPercent / 100);
//         final finalPrice = basePrice - discountValue;
//         debugPrint('basePrice: $basePrice');
//         debugPrint('discountPercent: $discountPercent');
//         debugPrint('discountValue: $discountValue');
//         debugPrint('finalPrice: $finalPrice');
//
//         session.amountPaid = finalPrice;
//
//         final sale = Sale(
//           id: generateId(),
//           description:
//               'اشتراك ${currentPlan.name} للعميل $name'
//               '${_appliedDiscount != null ? " (خصم ${_appliedDiscount!.percent}%)" : ""}',
//           amount: finalPrice,
//         );
//
//         try {
//           await AdminDataService.instance.addSale(
//             sale,
//             paymentMethod: 'cash',
//             customer: customer,
//             updateDrawer: true,
//           );
//
//           // 🔹 حساب معلومات الاشتراك للعرض
//           final nowStr = now.toLocal().toString();
//           final endStr = end?.toLocal().toString() ?? "غير محدود";
//
//           String durationInfo;
//           switch (currentPlan.durationType) {
//             case "hour":
//               durationInfo = "تنتهي بعد ${currentPlan.durationValue} ساعة";
//               break;
//             case "day":
//               durationInfo = "تنتهي بعد ${currentPlan.durationValue} يوم";
//               break;
//             case "week":
//               durationInfo = "تنتهي بعد ${currentPlan.durationValue} أسبوع";
//               break;
//             case "month":
//               durationInfo = "تنتهي بعد ${currentPlan.durationValue} شهر";
//               break;
//             default:
//               durationInfo =
//                   currentPlan.isUnlimited ? "غير محدودة" : "غير معروف";
//           }
//
//           String dailyLimitInfo = "";
//           if (currentPlan.dailyUsageType == "limited") {
//             dailyLimitInfo =
//                 "\nحد الاستخدام اليومي: ${currentPlan.dailyUsageHours} ساعة";
//           }
//
//           // 🔹 عرض Dialog بتفاصيل الاشتراك
//           await showDialog(
//             context: context,
//             builder:
//                 (_) => AlertDialog(
//                   title: Text("تفاصيل اشتراك ${currentPlan.name}"),
//                   content: Text(
//                     "العميل: $name\n"
//                     "السعر: ${finalPrice.toStringAsFixed(2)} ج\n"
//                     "بدأت: $nowStr\n"
//                     "تنتهي: $endStr\n"
//                     "$durationInfo\n"
//                     "$dailyLimitInfo",
//                   ),
//                   actions: [
//                     TextButton(
//                       onPressed: () => Navigator.pop(context),
//                       child: const Text("تمام"),
//                     ),
//                   ],
//                 ),
//           );
//
//           // 🔹 تحديث الرصيد ومسح الخصم لو single-use
//           if (_appliedDiscount?.singleUse == true) {
//             AdminDataService.instance.discounts.removeWhere(
//               (d) => d.id == _appliedDiscount!.id,
//             );
//             _appliedDiscount = null;
//           }
//
//           await _loadDrawerBalance();
//           ScaffoldMessenger.of(context).showSnackBar(
//             SnackBar(
//               content: Text(
//                 'تم دفع اشتراك ${currentPlan.name} (${finalPrice.toStringAsFixed(2)} ج)',
//               ),
//             ),
//           );
//         } catch (e, st) {
//           debugPrint('Failed to process quick sale: $e\n$st');
//           ScaffoldMessenger.of(context).showSnackBar(
//             const SnackBar(content: Text('فشل تسجيل الدفعة — حاول مرة أخرى')),
//           );
//         }
//       } else {
//         // لو لغى الدايالوج
//         return;
//       }
//     }
