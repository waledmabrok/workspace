import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:workspace/utils/colors.dart';
import 'package:workspace/widget/buttom.dart';
import '../../core/Db_helper.dart';
import '../../core/FinanceDb.dart';
import '../../core/data_service.dart';
import '../../core/db_helper_cart.dart';
import '../../core/db_helper_customer_balance.dart';
import '../../core/db_helper_customers.dart';
import '../../core/models.dart';
import '../../core/product_db.dart';
import '../../widget/dialog.dart';

class CashierRoomsPage extends StatefulWidget {
  const CashierRoomsPage({Key? key}) : super(key: key);

  @override
  State<CashierRoomsPage> createState() => _CashierRoomsPageState();
}

class _CashierRoomsPageState extends State<CashierRoomsPage> {
  final dbHelper = DbHelper.instance;
  final _uuid = Uuid();

  List<Map<String, dynamic>> rooms = [];
  List<Map<String, dynamic>> bookings = [];

  @override
  void initState() {
    super.initState();
    loadRooms();
    loadBookings();
  }

  Future<void> loadRooms() async {
    final db = await dbHelper.database;
    final list = await db.query('rooms');
    setState(() => rooms = list);
  }

  final Map<String, dynamic> defaultRoom = {
    'id': 'default-room',
    'name': 'غرفة عامة',
  };

  Future<void> loadBookings() async {
    final db = await dbHelper.database;
    final list = await db.query(
      'room_bookings',
      where: 'status = ?',
      whereArgs: ['open'],
    );
    setState(() => bookings = list);
  }

  double calculateRoomPrice({
    required int durationMinutes,
    required int firstFreeMinutes,
    required double firstHourFee,
    required double perHourAfterFirst,
    required double dailyCap,
    required int numPersons,
  }) {
    int chargeableMinutes = durationMinutes - firstFreeMinutes;
    if (chargeableMinutes <= 0) return 0.0;

    double price = firstHourFee;
    int remainingMinutes = chargeableMinutes - 60;
    if (remainingMinutes > 0) {
      int extraHours = (remainingMinutes / 60).ceil();
      price += extraHours * perHourAfterFirst;
    }

    /* price *= numPersons;*/

    if (price > dailyCap) price = dailyCap;
    return price;
  }

  Future<void> bookRoom(Map<String, dynamic> room) async {
    final nameCtrl = TextEditingController();
    final personsCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text("حجز ${room['name']}"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: "اسم العميل"),
                ),
                TextField(
                  controller: personsCtrl,
                  decoration: const InputDecoration(labelText: "عدد الأشخاص"),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("إلغاء"),
              ),
              ElevatedButton(
                onPressed: () async {
                  final customerName = nameCtrl.text.trim();
                  final numPersons = int.tryParse(personsCtrl.text.trim()) ?? 1;
                  if (customerName.isNotEmpty && numPersons > 0) {
                    final db = await dbHelper.database;
                    await db.insert('room_bookings', {
                      'id': _uuid.v4(),
                      'roomId': room['id'],
                      'customerName': customerName,
                      'numPersons': numPersons,
                      'startTime': DateTime.now().millisecondsSinceEpoch,
                      'endTime': null,
                      'price': 0.0,
                      'status': 'open',
                    });
                    Navigator.pop(ctx);
                    loadBookings();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("تم الحجز بنجاح")),
                    );
                  }
                },
                child: const Text("حجز"),
              ),
            ],
          ),
    );
  }

  Future<void> showBookingPaymentDialog(Map<String, dynamic> booking) async {
    final db = await dbHelper.database;
    final startTime = DateTime.fromMillisecondsSinceEpoch(booking['startTime']);
    final now = DateTime.now();
    final durationMinutes = now.difference(startTime).inMinutes;

    // جلب بيانات الغرفة
    final roomList = await db.query(
      'rooms',
      where: 'id = ?',
      whereArgs: [booking['roomId']],
      limit: 1,
    );
    final roomData = roomList.first;

    // حساب السعر النهائي
    final totalPrice = calculateRoomPrice(
      durationMinutes: durationMinutes,
      firstFreeMinutes: (roomData['firstFreeMinutesRoom'] as int?) ?? 15,
      firstHourFee: (roomData['firstHourFeeRoom'] as num?)?.toDouble() ?? 30.0,
      perHourAfterFirst:
          (roomData['perHourAfterFirstRoom'] as num?)?.toDouble() ?? 20.0,
      dailyCap: (roomData['dailyCapRoom'] as num?)?.toDouble() ?? 150.0,
      numPersons: (booking['numPersons'] as int?) ?? 1,
    );
    final updatedCart = await CartDb.getCartBySession(booking['id']);
    // إنشاء Session مؤقت لاستخدامه في ReceiptDialog
    final session = Session(
      id: booking['id'],
      name: booking['customerName'],
      start: startTime,
      end: now,
      type: 'باقة', // أو 'حر' حسب نوع الحجز
      cart: updatedCart, // لو عندك منتجات للحجز ضيفها هنا
      customerId: booking['customerId'],
      amountPaid: booking['price']?.toDouble() ?? 0.0,
    );

    // فتح ReceiptDialog
    final paid = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => ReceiptDialog(
            session: session,
            description: 'دفع حجز الغرفة',
            fixedAmount: totalPrice,
          ),
    );

    if (paid == true) {
      // تحديث الحجز والدرج في DB بعد الدفع
      await db.update(
        'room_bookings',
        {
          'endTime': now.millisecondsSinceEpoch,
          'status': 'closed',
          'price': totalPrice,
        },
        where: 'id = ?',
        whereArgs: [booking['id']],
      );

      final drawerRows = await db.query(
        'drawer',
        where: 'id = ?',
        whereArgs: [1],
        limit: 1,
      );
      final currentBalance = (drawerRows.first['balance'] as num).toDouble();
      await db.update(
        'drawer',
        {'balance': currentBalance + totalPrice},
        where: 'id = ?',
        whereArgs: [1],
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم دفع الحجز: ${totalPrice.toStringAsFixed(2)} ج'),
        ),
      );

      loadBookings(); // لتحديث القائمة
    }
  }

  Future<void> addProductToBooking(Map<String, dynamic> booking) async {
    final db = await dbHelper.database;
    final products = await db.query('products');

    await showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text('إضافة منتجات لـ ${booking['customerName']}'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children:
                    products.map((prod) {
                      final qtyCtrl = TextEditingController(text: '0');
                      return Row(
                        children: [
                          Expanded(child: Text(prod['name']?.toString() ?? '')),

                          SizedBox(
                            width: 50,
                            child: TextField(
                              controller: qtyCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(hintText: '0'),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              final qty = int.tryParse(qtyCtrl.text) ?? 0;
                              if (qty > 0) {
                                final total =
                                    qty * (prod['price'] as num).toDouble();
                                await db.insert('room_cart', {
                                  'id': const Uuid().v4(),
                                  'bookingId': booking['id'],
                                  'productId': prod['id'],
                                  'productName': prod['name'],
                                  'qty': qty,
                                  'total': total,
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('تمت إضافة ${prod['name']}'),
                                  ),
                                );
                              }
                            },
                            child: const Text('إضافة'),
                          ),
                        ],
                      );
                    }).toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('تم'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "الغرف المتاحة",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              /*   IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () async {
                  await loadRooms();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("تم تحديث قائمة الغرف")),
                  );
                },
              ),*/
            ],
          ),
          const SizedBox(height: 10),

          ...rooms.map(
            (room) => Card(
              color: AppColorsDark.bgCardColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color: AppColorsDark.mainColor.withOpacity(0.4),
                  width: 1.5,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: ListTile(
                  title: Text(
                    room['name'],
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  // subtitle: Text("السعر الأساسي: ${room['basePrice']} ج"),
                  trailing: SizedBox(
                    width: 140,
                    height: 35,
                    child: CustomButton(
                      infinity: false,
                      text: "حجز",
                      onPressed: () => bookRoom(room),
                    ),
                  ),
                  /* ElevatedButton(
                    onPressed: () => bookRoom(room),
                    child: const Text("حجز"),
                  ),*/
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            "الحجوزات المفتوحة",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          ...bookings.map((booking) {
            final startTime = DateTime.fromMillisecondsSinceEpoch(
              booking['startTime'],
            );

            return Card(
              color: AppColorsDark.bgCardColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color: Colors.green.withOpacity(0.4),
                  width: 1.5,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Container(
                  margin: const EdgeInsets.symmetric(
                    vertical: 6,
                    horizontal: 8,
                  ),
                  padding: const EdgeInsets.all(12),
                  /* decoration: BoxDecoration(
                    color: AppColorsDark.bgCardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.green.withOpacity(0.4),
                      width: 1.5,
                    ),
                  ),*/
                  child: Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // الاسم + عدد الأشخاص
                          Text(
                            "الاسم: ${booking['customerName']}   |   عدد الأشخاص: ${booking['numPersons']}",
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 6),

                          // وقت البداية
                          Text(
                            "بدأ في يوم ${DateFormat.yMMMMEEEEd('ar').format(startTime)} "
                            "وفي ساعة ${DateFormat('hh:mm a', 'ar').format(startTime)}",
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.white70,
                            ),
                          ),
                          const SizedBox(height: 12),

                          // الأزرار
                        ],
                      ),
                      Spacer(),
                      Row(
                        children: [
                          SizedBox(
                            height: 40,
                            width: 135,
                            child: CustomButton(
                              border: true,
                              text: "اغلاق",
                              onPressed:
                                  () => showBookingPaymentDialog(booking),
                              infinity: false,
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            height: 40,
                            width: 135,
                            child: CustomButton(
                              infinity: false,
                              text: "إضافة منتج",
                              onPressed: () async {
                                final session = Session(
                                  id: booking['id'],
                                  name: booking['customerName'],
                                  cart: await CartDb.getCartBySession(
                                    booking['id'],
                                  ),
                                  customerId: booking['customerId'],
                                  amountPaid:
                                      booking['price']?.toDouble() ?? 0.0,
                                  start: DateTime.now(),
                                  type: '',
                                );

                                await showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  builder:
                                      (_) => _buildAddProductsAndPay(session),
                                );

                                final updatedCart =
                                    await CartDb.getCartBySession(
                                      booking['id'],
                                    );
                                session.cart = updatedCart;
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
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

  Map<String, TextEditingController> qtyControllers = {};
  Customer? _currentCustomer;
  Widget _buildAddProductsAndPay(Session s) {
    Future<void> _showReceiptDialog(Session s, double productsTotal) async {
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
              double finalTotal = productsTotal - discountValue;

              return AlertDialog(
                title: Text(
                  'إيصال الدفع - ${s.name} (الرصيد: ${customerBalance.toStringAsFixed(2)} ج)',
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      ...s.cart.map(
                        (item) => Text(
                          '${item.product.name} x${item.qty} = ${item.total} ج',
                        ),
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
                        // بعد إضافة الـ Sale وإنهاء كل الحسابات
                        await CartDb.deleteCartItem(
                          s.id,
                        ); // 🟢 يمسح كل العناصر من قاعدة البيانات
                        s.cart.clear(); // 🟢 تحديث الـ session محليًا
                        setState(() {}); // لو عايز الـ UI يتحدث فورًا
                        Navigator.pop(context); // إغلاق الـ dialog

                        // تحديث الـ session محليًا
                      }

                      // تحديث دقائق الدفع
                      //    s.paidMinutes += minutesToCharge;
                      s.amountPaid += paidAmount;

                      // ---- قفل الجلسة وتحديث DB ----
                      /* setState(() {
                        s.isActive = false;
                        s.isPaused = false;
                      });
                      await SessionDb.updateSession(s);
*/
                      // حفظ المبيعة كما هي
                      final sale = Sale(
                        id: generateId(),
                        description:
                            'جلسة ${s.name} |   منتجات: ${s.cart.fold(0.0, (sum, item) => sum + item.total)}',
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
                      /* s.paidMinutes += minutesToCharge;*/
                      s.amountPaid += paidAmount;

                      // ---- تحديث رصيد العميل بشكل صحيح ----
                      // 1) نحدد customerId الهدف: نفضل s.customerId ثم _currentCustomer
                      String? targetCustomerId =
                          s.customerId ?? _currentCustomer?.id;

                      // 2) لو لسه فاضي حاول نبحث عن العميل بالاسم، وإن لم يوجد - ننشئ واحد جديد
                      if (targetCustomerId == null ||
                          targetCustomerId.isEmpty) {
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
                            .indexWhere(
                              (b) => b.customerId == targetCustomerId,
                            );
                        if (idx >= 0) {
                          AdminDataService.instance.customerBalances[idx] =
                              updated;
                        } else {
                          AdminDataService.instance.customerBalances.add(
                            updated,
                          );
                        }
                      } else {
                        // لم نتمكن من إيجاد/إنشاء عميل --> تسجّل ملاحظۀ debug
                        debugPrint(
                          'No customer id for session ${s.id}; balance not updated.',
                        );
                      }

                      /*   // ---- قفل الجلسة وتحديث DB ----
                      setState(() {
                        s.isActive = false;
                        s.isPaused = false;
                      });
                      await SessionDb.updateSession(s);
*/
                      // ---- حفظ المبيعة ----
                      final sale = Sale(
                        id: generateId(),
                        description:
                            'جلسة ${s.name} | منتجات: ${s.cart.fold(0.0, (sum, item) => sum + item.total)}'
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

    void _completeAndPayForProducts(Session s) async {
      final productsTotal = s.cart.fold(0.0, (sum, item) => sum + item.total);

      if (productsTotal == 0) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("لا يوجد منتجات للإتمام")));
        return;
      }

      await _showReceiptDialog(
        s,
        productsTotal,
        // مفيش دقائق شحن هنا
      );
    }

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
                  fillColor: AppColorsDark.bgCardColor,
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
                          '${p.name} (${p.price} ج - ${p.stock} متاح)',
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
                  CustomButton(
                    text: "اضف",
                    onPressed: () async {
                      if (selectedProduct == null) return;

                      final qty = int.tryParse(qtyCtrl.text) ?? 1;
                      if (qty <= 0) return;

                      // تحقق من المخزون
                      if (selectedProduct!.stock < qty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '⚠️ المخزون غير كافي (${selectedProduct!.stock} فقط)',
                            ),
                          ),
                        );
                        return;
                      }

                      // خصم المخزون مؤقتًا
                      /*    selectedProduct!.stock -= qty;
                      final index = AdminDataService.instance.products
                          .indexWhere((p) => p.id == selectedProduct!.id);
                      if (index != -1)
                        AdminDataService.instance.products[index].stock =
                            selectedProduct!.stock;*/

                      // إضافة للكارت
                      final item = CartItem(
                        id: generateId(),
                        product: selectedProduct!,
                        qty: qty,
                      );
                      await CartDb.insertCartItem(item, s.id);

                      final updatedCart = await CartDb.getCartBySession(s.id);
                      setSheetState(() => s.cart = updatedCart);
                    },
                    infinity: false,
                  ),
                  /* ElevatedButton(
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
                  ),*/
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
                            final newQty = int.tryParse(val) ?? item.qty;

                            // تحقق من المخزون عند تعديل الكمية
                            final availableStock =
                                item.product.stock + item.qty;
                            if (newQty > availableStock) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '⚠️ المخزون غير كافي (${availableStock} فقط)',
                                  ),
                                ),
                              );
                              setSheetState(() {});
                              return;
                            }

                            // تعديل المخزون
                            item.product.stock += (item.qty - newQty);
                            final idx = AdminDataService.instance.products
                                .indexWhere((p) => p.id == item.product.id);
                            if (idx != -1)
                              AdminDataService.instance.products[idx].stock =
                                  item.product.stock;

                            item.qty = newQty;
                            await CartDb.updateCartItemQty(item.id, newQty);
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

                          // إعادة الكمية للمخزون
                          item.product.stock += item.qty;
                          final idx = AdminDataService.instance.products
                              .indexWhere((p) => p.id == item.product.id);
                          if (idx != -1)
                            AdminDataService.instance.products[idx].stock =
                                item.product.stock;

                          s.cart.remove(item);
                          setSheetState(() {});
                        },
                      ),
                    ],
                  ),
                );
              }).toList(),
              const SizedBox(height: 12),

              CustomButton(
                text: "إتمام ودفع",
                onPressed: () async {
                  Navigator.pop(context);
                  // 1️⃣ افتح نافذة الدفع أولًا
                  _completeAndPayForProducts(s);

                  // 2️⃣ خصم المخزون من المنتجات
                  for (var item in s.cart) {
                    await sellProduct(item.product, item.qty);

                    // 3️⃣ امسح الـ controller
                    qtyControllers[item.id]?.dispose();
                    qtyControllers.remove(item.id);
                  }

                  // 4️⃣ مسح الكارت من الذاكرة وDB
                  for (var item in s.cart) {
                    await CartDb.deleteCartItem(item.id);
                  }
                  s.cart.clear();

                  // 5️⃣ حدث الـ UI
                  setSheetState(() {});
                },
                infinity: false,
                color: Colors.green,
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> sellProduct(Product product, int qty) async {
    if (qty <= 0) return;

    // 1️⃣ خصم من الـ DB
    final newStock = max(0, product.stock - qty);
    product.stock = newStock;
    await ProductDb.insertProduct(product); // تحديث المخزون في DB

    // 2️⃣ خصم من AdminDataService
    final index = AdminDataService.instance.products.indexWhere(
      (p) => p.id == product.id,
    );
    if (index != -1) {
      AdminDataService.instance.products[index].stock = newStock;
    }

    setState(() {}); // تحديث الـ UI
  }
}
