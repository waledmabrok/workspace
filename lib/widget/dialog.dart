import 'package:flutter/material.dart';

import '../core/FinanceDb.dart';
import '../core/data_service.dart';
import '../core/db_helper_customer_balance.dart';
import '../core/db_helper_customers.dart';
import '../core/db_helper_sessions.dart';
import '../core/models.dart';

class ReceiptDialog extends StatefulWidget {
  final Session session;
  final double? fixedAmount; // 🟢 المبلغ الثابت (اختياري)
  final String? description;
  const ReceiptDialog({
    super.key,
    required this.session,
    this.fixedAmount,
    this.description,
  });

  @override
  State<ReceiptDialog> createState() => _ReceiptDialogState();
}

class _ReceiptDialogState extends State<ReceiptDialog> {
  late TextEditingController paidCtrl;
  String paymentMethod = "cash";
  Customer? _currentCustomer;
  double _drawerBalance = 0.0;
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

  @override
  void initState() {
    super.initState();
    paidCtrl = TextEditingController();
  }

  @override
  void dispose() {
    paidCtrl.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    final s = widget.session;

    final totalMinutes = getSessionMinutes(s);
    final minutesToCharge = (totalMinutes - s.paidMinutes).clamp(
      0,
      totalMinutes,
    );
    final timeCharge = _calculateTimeChargeFromMinutes(minutesToCharge);
    final productsTotal = s.cart.fold(0.0, (sum, item) => sum + item.total);
    final finalTotal = widget.fixedAmount ?? timeCharge + productsTotal;

    double discountValue = 0.0;
    String? appliedCode;
    final codeCtrl = TextEditingController();

    String paymentMethod = "cash"; // 🟢 افتراضي: كاش
    final TextEditingController paidCtrl = TextEditingController();
    return StatefulBuilder(
      builder: (context, setDialogState) {
        double finalTotal =
            widget.fixedAmount ?? timeCharge + productsTotal - discountValue;
        return AlertDialog(
          title: Text('إيصال الدفع - ${s.name}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.description ??
                      'وقت الجلسة: ${timeCharge.toStringAsFixed(2)} ج',
                ),
                const SizedBox(height: 8),
                ...s.cart.map(
                  (item) => Text(
                    '${item.product.name} x${item.qty} = ${item.total} ج',
                  ),
                ),
                const SizedBox(height: 12),

                // طريقة الدفع

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
                    final paidAmount = double.tryParse(paidCtrl.text) ?? 0.0;
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

                Navigator.pop(context, true);

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
                String? targetCustomerId = s.customerId ?? _currentCustomer?.id;

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
                        AdminDataService.instance.customers.add(newCustomer);
                      } catch (_) {}
                      targetCustomerId = newCustomer.id;
                    }
                  }
                }

                if (targetCustomerId != null && targetCustomerId.isNotEmpty) {
                  // احصل الرصيد القديم من الذاكرة (أو استخدم 0)
                  final oldBalance = AdminDataService.instance.customerBalances
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
                    AdminDataService.instance.customerBalances[idx] = updated;
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

                Navigator.pop(context, true); // بيرجع إشارة إن حصل دفع

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
  }
}
