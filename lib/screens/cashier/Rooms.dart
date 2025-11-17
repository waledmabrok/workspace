import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:workspace/utils/colors.dart';
import 'package:workspace/widget/buttom.dart';
import 'package:workspace/widget/form.dart';
import '../../core/Db_helper.dart';
import '../../core/FinanceDb.dart';
import '../../core/data_service.dart';
import '../../core/db_helper_cart.dart';
import '../../core/db_helper_customer_balance.dart';
import '../../core/db_helper_customers.dart';
import '../../core/models.dart';
import '../../core/product_db.dart';
import '../../widget/DialogForRooms.dart';
import '../../widget/dialog.dart';

class CashierRoomsPage extends StatefulWidget {
  const CashierRoomsPage({Key? key}) : super(key: key);

  @override
  State<CashierRoomsPage> createState() => _CashierRoomsPageState();
}

class _CashierRoomsPageState extends State<CashierRoomsPage> {
  final dbHelper = DbHelper.instance;
  final _uuid = Uuid();
  final AdminDataService ds = AdminDataService.instance;

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
      builder: (ctx) => AlertDialog(
        title: Text("حجز ${room['name']}"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomFormField(hint: "اسم العميل", controller: nameCtrl),
            /*TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: "اسم العميل"),
                ),*/
            const SizedBox(height: 12),
            CustomFormField(hint: "عدد الأشخاص", controller: personsCtrl),
            /*  TextField(
                  controller: personsCtrl,
                  decoration: const InputDecoration(labelText: "عدد الأشخاص"),
                  keyboardType: TextInputType.number,
                ),*/
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

  Future<void> printCartItems(String sessionId) async {
    final cartItems = await CartDb.getCartBySession(sessionId);
    for (var item in cartItems) {
      print('اسم المنتج: ${item.product.name}');
      print('الكمية: ${item.qty}');
      print('السعر الفردي: ${item.product.price}');
      print('المجموع: ${item.total}');
    }
  }

  Future<void> showBookingPaymentDialog(Map<String, dynamic> booking) async {
    final db = await dbHelper.database;
    final startTime = DateTime.fromMillisecondsSinceEpoch(booking['startTime']);
    final now = DateTime.now();
    final durationMinutes = getActiveDuration(booking).inMinutes;

    // جلب بيانات الغرفة
    final roomList = await db.query(
      'rooms',
      where: 'id = ?',
      whereArgs: [booking['roomId']],
      limit: 1,
    );
    final roomData = roomList.first;

    // جلب الكارت
    final updatedCart = await CartDb.getCartBySession(booking['id']);
    final productsTotal = updatedCart.fold<double>(
      0.0,
      (sum, item) => sum + (item.product.price * item.qty),
    );

    // حساب سعر الغرفة
    final roomPrice = calculateRoomPrice(
      durationMinutes: durationMinutes,
      firstFreeMinutes: (roomData['firstFreeMinutesRoom'] as int?) ?? 15,
      firstHourFee: (roomData['firstHourFeeRoom'] as num?)?.toDouble() ?? 30.0,
      perHourAfterFirst:
          (roomData['perHourAfterFirstRoom'] as num?)?.toDouble() ?? 20.0,
      dailyCap: (roomData['dailyCapRoom'] as num?)?.toDouble() ?? 150.0,
      numPersons: (booking['numPersons'] as int?) ?? 1,
    );

    final finalTotal = roomPrice + productsTotal;

    final paidCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final paidAmount = double.tryParse(paidCtrl.text) ?? 0.0;
            final diff = paidAmount - finalTotal;

            return AlertDialog(
              title: Text("إيصال الدفع - ${booking['customerName']}"),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("وقت الغرفة: ${roomPrice.toStringAsFixed(2)} ج"),
                    const SizedBox(height: 8),
                    ...updatedCart.map(
                      (item) => Text(
                        "${item.product.name} x${item.qty} = ${item.total} ج",
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'المطلوب: ${finalTotal.toStringAsFixed(2)} ج',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: paidCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "المبلغ المدفوع",
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      diff == 0
                          ? "✅ دفع كامل"
                          : diff > 0
                              ? "💰 الباقي للعميل: ${diff.toStringAsFixed(2)} ج"
                              : "💸 على العميل: ${(diff.abs()).toStringAsFixed(2)} ج",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              actions: [
                ElevatedButton(
                  child: const Text("تأكيد الدفع بالكامل"),
                  onPressed: () async {
                    if (paidAmount < finalTotal) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text("⚠️ المبلغ المدفوع أقل من المطلوب")),
                      );
                      return;
                    }

                    // تحديث الحجز كمدفوع
                    await db.update(
                      'room_bookings',
                      {
                        'endTime': now.millisecondsSinceEpoch,
                        'status': 'closed',
                        'price': roomPrice,
                      },
                      where: 'id = ?',
                      whereArgs: [booking['id']],
                    );

                    // تحديث رصيد الدرج
                    final drawerRows = await db.query('drawer',
                        where: 'id = ?', whereArgs: [1], limit: 1);
                    final currentBalance =
                        (drawerRows.first['balance'] as num).toDouble();
                    await db.update(
                        'drawer', {'balance': currentBalance + finalTotal},
                        where: 'id = ?', whereArgs: [1]);

                    // إدخال بيع
                    final roomItem = CartItem(
                      id: generateId(),
                      product: Product(
                        id: 'room_${booking['roomId']}',
                        name: roomData['name'].toString(),
                        price: roomPrice,
                        stock: 1,
                      ),
                      qty: 1,
                    );
                    final allItems = [roomItem, ...updatedCart];
                    final sale = Sale(
                      id: generateId(),
                      description: 'حجز ${roomData['name']}',
                      amount: finalTotal,
                      date: DateTime.now(),
                      items: allItems,
                      customerId: booking['customerId'],
                      paymentMethod: "cash",
                    );
                    await AdminDataService.instance.addSale(sale,
                        paymentMethod: "cash", updateDrawer: true);
                    await FinanceDb.insertSale(sale);

                    Navigator.pop(ctx, true);
                    loadBookings();
                  },
                ),
                ElevatedButton(
                  child: const Text("على الحساب"),
                  onPressed: () async {
                    final roomItem = CartItem(
                      id: generateId(),
                      product: Product(
                        id: 'room_${booking['roomId']}',
                        name: roomData['name'].toString(),
                        price: roomPrice,
                        stock: 1,
                      ),
                      qty: 1,
                    );
                    final allItems = [roomItem, ...updatedCart];
                    final requiredAmount = finalTotal;
                    final paidAmount = double.tryParse(paidCtrl.text) ?? 0.0;

                    // فرق المبلغ: إذا دفع أكثر يبقى له، إذا أقل يبقى عليه
                    final diff = paidAmount - requiredAmount;

                    // تحديد العميل
                    String? targetCustomerId =
                        booking['customerId'] ?? _currentCustomer?.id;
                    if (targetCustomerId == null || targetCustomerId.isEmpty) {
                      final found =
                          await CustomerDb.getByName(booking['customerName']);
                      if (found != null) {
                        targetCustomerId = found.id;
                      } else if ((booking['customerName'] ?? '')
                          .trim()
                          .isNotEmpty) {
                        final newCustomer = Customer(
                          id: generateId(),
                          name: booking['customerName'],
                          phone: null,
                          notes: null,
                        );
                        await CustomerDb.insert(newCustomer);
                        AdminDataService.instance.customers.add(newCustomer);
                        targetCustomerId = newCustomer.id;
                      }
                    }

                    if (targetCustomerId != null &&
                        targetCustomerId.isNotEmpty) {
                      // احصل الرصيد القديم من الذاكرة أو 0
                      final oldBalance =
                          AdminDataService.instance.customerBalances.firstWhere(
                        (b) => b.customerId == targetCustomerId,
                        orElse: () => CustomerBalance(
                            customerId: targetCustomerId!, balance: 0.0),
                      );

                      // تعديل الرصيد: إذا diff > 0 يبقى له، إذا diff < 0 يبقى عليه
                      final newBalance = oldBalance.balance + diff;
                      final updated = CustomerBalance(
                        customerId: targetCustomerId,
                        balance: newBalance,
                      );

                      await CustomerBalanceDb.upsert(updated);

                      final idx = AdminDataService.instance.customerBalances
                          .indexWhere((b) => b.customerId == targetCustomerId);
                      if (idx >= 0) {
                        AdminDataService.instance.customerBalances[idx] =
                            updated;
                      } else {
                        AdminDataService.instance.customerBalances.add(updated);
                      }
                    } else {
                      debugPrint(
                          'No customer id for session ${booking['id']}; balance not updated.');
                    }

                    // إنشاء Sale على الحساب
                    final sale = Sale(
                      id: generateId(),
                      description: 'حجز ${roomData['name']} (على الحساب)',
                      amount: paidAmount,
                      date: DateTime.now(),
                      items: allItems,
                      customerId: targetCustomerId,
                      paymentMethod: "cash",
                    );

                    if (paidAmount > 0) {
                      await AdminDataService.instance.addSale(
                        Sale(
                          date: DateTime.now(),
                          items: allItems,
                          customerId: targetCustomerId,
                          id: generateId(),
                          description: 'حجز ${roomData['name']} (على الحساب)',
                          amount: paidAmount,
                        ),
                        paymentMethod: 'cash',
                        updateDrawer: true,
                      );
                    }

                    await FinanceDb.insertSale(sale);

                    // تحديث الحجز كمنتهي
                    await db.update(
                      'room_bookings',
                      {
                        'endTime': now.millisecondsSinceEpoch,
                        'status': 'closed',
                        'price': roomPrice,
                      },
                      where: 'id = ?',
                      whereArgs: [booking['id']],
                    );

                    Navigator.pop(ctx, true);
                    loadBookings();
                  },
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("إلغاء"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> addProductToBooking(Map<String, dynamic> booking) async {
    final db = await dbHelper.database;
    final products = await db.query('products');

    // إنشاء Controllers لكل منتج
    final qtyControllers = <int, TextEditingController>{};
    for (var prod in products) {
      qtyControllers[prod['id'] as int] = TextEditingController(text: '0');
    }

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('إضافة منتجات لـ ${booking['customerName']}'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: products.map((prod) {
              final prodId = prod['id'] as int;
              final qtyCtrl = qtyControllers[prodId]!;

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
                      if (qty <= 0) return;

                      final bookingId = booking['id'] is int
                          ? booking['id']
                          : int.parse(booking['id'].toString());
                      final productId = prod['id'] is int
                          ? prod['id']
                          : int.parse(prod['id'].toString());

                      final existing = await db.query(
                        'room_cart',
                        where: 'bookingId = ? AND productId = ?',
                        whereArgs: [bookingId, productId],
                        limit: 1,
                      );

                      if (existing.isNotEmpty) {
                        final row = existing.first;
                        final currentQty = row['qty'] is int
                            ? row['qty'] as int
                            : int.parse(row['qty'].toString());
                        final newQty = currentQty + qty;
                        final newTotal =
                            newQty * (prod['price'] as num).toDouble();

                        await db.update(
                          'room_cart',
                          {'qty': newQty, 'total': newTotal},
                          where: 'id = ?',
                          whereArgs: [row['id']],
                        );
                      } else {
                        final total = qty * (prod['price'] as num).toDouble();
                        await db.insert('room_cart', {
                          'id': const Uuid().v4(),
                          'bookingId': bookingId,
                          'productId': productId,
                          'productName': prod['name'],
                          'qty': qty,
                          'total': total,
                        });
                      }

                      qtyCtrl.text = '0';
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('تمت إضافة ${prod['name']}'),
                        ),
                      );
                      final cartItems = await db.query(
                        'room_cart',
                        where: 'bookingId = ?',
                        whereArgs: [bookingId],
                      );
                      print('=== محتوى السلة بعد الإضافة ===');
                      for (var item in cartItems) {
                        print(
                          'منتج: ${item['productName']}, كمية: ${item['qty']}, المجموع: ${item['total']}',
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

  Duration getActiveDuration(Map<String, dynamic> booking) {
    final startTime = DateTime.fromMillisecondsSinceEpoch(booking['startTime']);
    final now = DateTime.now();

    final totalPaused = (booking['totalPausedDuration'] as int?) ?? 0;
    final pauseTime = booking['pauseTime'] as int?;

    if (booking['isPaused'] == 1 && pauseTime != null) {
      // متوقف دلوقتي → استبعد الوقت من آخر إيقاف لحد دلوقتي
      final pausedSoFar = now.millisecondsSinceEpoch - pauseTime;
      return Duration(
        milliseconds: now.millisecondsSinceEpoch -
            startTime.millisecondsSinceEpoch -
            (totalPaused + pausedSoFar),
      );
    } else {
      // شغال دلوقتي
      return Duration(
        milliseconds: now.millisecondsSinceEpoch -
            startTime.millisecondsSinceEpoch -
            totalPaused,
      );
    }
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
            final startTime =
                DateTime.fromMillisecondsSinceEpoch(booking['startTime']);
            final now = DateTime.now();

            final totalPaused = (booking['totalPausedDuration'] as int?) ?? 0;
            final pauseTime = booking['pauseTime'] as int?;
            int activeMinutes;

            if (booking['isPaused'] == 1 && pauseTime != null) {
              // الجلسة متوقفة حاليًا → استبعد الوقت من آخر إيقاف
              activeMinutes = DateTime.fromMillisecondsSinceEpoch(pauseTime)
                      .difference(startTime)
                      .inMinutes -
                  Duration(milliseconds: totalPaused).inMinutes;
            } else {
              // الجلسة شغالة
              activeMinutes = now.difference(startTime).inMinutes -
                  Duration(milliseconds: totalPaused).inMinutes;
            }

            // final startTime = DateTime.fromMillisecondsSinceEpoch(
            //   booking['startTime'],
            // );
            // final now = DateTime.now();
            // final activeDuration = now.difference(startTime);
            final activeDuration = getActiveDuration(booking);
            String formatDuration(Duration d) {
              final hours = d.inHours;
              final minutes = d.inMinutes.remainder(60);
              if (hours > 0) {
                return "$hours ساعة و $minutes دقيقة";
              } else {
                return "$minutes دقيقة";
              }
            }

            return Card(
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
                          Text(
                            "نشط منذ: ${formatDuration(activeDuration)}",
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.white70,
                              fontWeight: FontWeight.w500,
                            ),
                          ),

                          // الأزرار
                        ],
                      ),
                      Spacer(),
                      Row(
                        children: [
                          SizedBox(
                            height: 40,
                            width: 170,
                            child: CustomButton(
                              infinity: false,
                              text: "اضف منتجات",
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
                                  builder: (_) =>
                                      _buildAddProductsAndPay(session),
                                );

                                final updatedCart =
                                    await CartDb.getCartBySession(
                                  booking['id'],
                                );
                                session.cart = updatedCart;
                              },
                            ),
                          ),
                          SizedBox(
                            width: 8,
                          ),
                          SizedBox(
                            height: 40,
                            width: 170,
                            child: CustomButton(
                              color: Colors.transparent,
                              borderColor: AppColorsDark.mainColor,
                              border: booking['isPaused'] == 1 ? false : true,
                              text: booking['isPaused'] == 1
                                  ? "استكمال الوقت"
                                  : "إيقاف مؤقت",
                              onPressed: () async {
                                final db = await dbHelper.database;
                                final now =
                                    DateTime.now().millisecondsSinceEpoch;

                                if (booking['isPaused'] == 1) {
                                  // ▶️ استئناف
                                  final pausedAt = booking['pauseTime'] as int?;
                                  if (pausedAt != null) {
                                    final pausedDuration = now - pausedAt;
                                    final newTotalPaused =
                                        ((booking['totalPausedDuration']
                                                    as int?) ??
                                                0) +
                                            pausedDuration;

                                    await db.update(
                                      'room_bookings',
                                      {
                                        'isPaused': 0,
                                        'pauseTime': null,
                                        'totalPausedDuration': newTotalPaused,
                                      },
                                      where: 'id = ?',
                                      whereArgs: [booking['id']],
                                    );
                                  }
                                } else {
                                  // ⏸️ إيقاف
                                  await db.update(
                                    'room_bookings',
                                    {
                                      'isPaused': 1,
                                      'pauseTime': now,
                                    },
                                    where: 'id = ?',
                                    whereArgs: [booking['id']],
                                  );
                                }

                                loadBookings(); // تحديث الواجهة
                              },
                              infinity: false,
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            height: 40,
                            width: 170,
                            child: CustomButton(
                              borderColor: Colors.red,
                              border: true,
                              text: "دفع",
                              onPressed: () =>
                                  showBookingPaymentDialog(booking),
                              infinity: false,
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
    Product? selectedProduct;
    final qtyCtrl = TextEditingController(text: '1');
    late StateSetter sheetSetState;
    Future<void> _showReceiptDialog(Session s, double productsTotal) async {
      if (!context.mounted) return;
      final paidCtrl = TextEditingController();
      double discountValue = 0.0;

      await showDialog(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              sheetSetState = setDialogState;
              Future.microtask(() async {
                final updatedCart = await CartDb.getCartBySession(s.id);
                if (!context.mounted) return;
                sheetSetState(() => s.cart = List.from(updatedCart));
              });

              final finalTotal = productsTotal - discountValue;
              return AlertDialog(
                title: Text('إيصال الدفع - ${s.name}'),
                content: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ...s.cart.map((item) {
                        final qtyController = TextEditingController(
                          text: item.qty.toString(),
                        );

                        return StatefulBuilder(
                          builder: (context, setItemState) {
                            bool isDeleting = false; // لكل item

                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 4.0,
                                horizontal: 0,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.product.name,
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 60,
                                    child: TextField(
                                      controller: qtyController,
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                      keyboardType: TextInputType.number,
                                      onChanged: (val) async {
                                        final newQty =
                                            int.tryParse(val) ?? item.qty;
                                        if (newQty <= 0 ||
                                            newQty >
                                                item.product.stock + item.qty)
                                          return;

                                        item.product.stock +=
                                            (item.qty - newQty);
                                        item.qty = newQty;

                                        await CartDb.updateCartItemQty(
                                          item.id,
                                          newQty,
                                        );

                                        if (!context.mounted) return;
                                        sheetSetState(
                                          () =>
                                              selectedProduct = val as Product?,
                                        ); // ✅ ده بتاع الـ bottom sheet كله
                                      },
                                    ),
                                  ),
                                  IconButton(
                                    icon: isDeleting
                                        ? const Icon(
                                            Icons.hourglass_top,
                                            color: Colors.grey,
                                          ) // ⏳ شكلي
                                        : const Icon(
                                            Icons.delete,
                                            color: Colors.redAccent,
                                          ),
                                    onPressed: isDeleting
                                        ? null // ⛔ ممنوع الضغط لو العملية شغالة
                                        : () async {
                                            setItemState(
                                              () => isDeleting = true,
                                            ); // تحديث حالة الزرار بس

                                            try {
                                              if (item.qty > 1) {
                                                item.qty -= 1;
                                                item.product.stock += 1;

                                                await CartDb.updateCartItemQty(
                                                  item.id,
                                                  item.qty,
                                                );
                                              } else {
                                                await CartDb.deleteCartItem(
                                                  item.id,
                                                );

                                                item.product.stock += 1;
                                                s.cart.remove(item);
                                              }

                                              await ProductDb.insertProduct(
                                                item.product,
                                              );

                                              final idx = AdminDataService
                                                  .instance.products
                                                  .indexWhere(
                                                (p) => p.id == item.product.id,
                                              );
                                              if (idx != -1) {
                                                AdminDataService
                                                    .instance
                                                    .products[idx]
                                                    .stock = item.product.stock;
                                              }
                                              final updatedCart =
                                                  await CartDb.getCartBySession(
                                                s.id,
                                              );
                                              if (!context.mounted) return;
                                              sheetSetState(
                                                () => s.cart = List.from(
                                                  updatedCart,
                                                ),
                                              ); // ✅ إعادة رسم كل الـ bottom sheet
                                            } finally {
                                              setItemState(
                                                () => isDeleting = false,
                                              ); // تفعيل الزرار تاني
                                            }
                                          },
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      }).toList(),
                      const SizedBox(height: 12),
                      Text(
                        'المطلوب: ${finalTotal.toStringAsFixed(2)} ج',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      TextField(
                        controller: paidCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: "المبلغ المدفوع",
                        ),
                        onChanged: (_) {
                          if (context.mounted) setDialogState(() {});
                        },
                      ),
                    ],
                  ),
                ),
                actions: [
                  ElevatedButton(
                    onPressed: () async {
                      // تحويل الـ Session إلى شكل Map لتتناسب مع showBookingPaymentDialog
                      final bookingMap = {
                        'id': s.id,
                        'customerName': s.name,
                        'numPersons': s.cart.length, // أو أي قيمة مناسبة
                        'startTime': s.start.millisecondsSinceEpoch,
                        'price': s.amountPaid,
                        'customerId': s.customerId,
                        'roomId': '', // إذا كان عندك ID الغرفة هنا
                      };

                      await showBookingPaymentDialog(bookingMap);
                    },
                    child: const Text('تأكيد الدفع'),
                  ),
                  TextButton(
                    onPressed: () {
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: const Text('إلغاء'),
                  ),
                ],
              );
            },
          );
        },
      );
    }

    return StatefulBuilder(
      builder: (context, setSheetState) {
        CartDb.getCartBySession(s.id).then((updatedCart) {
          if (!mounted) return;
          setSheetState(() {
            s.cart = updatedCart;
          });
        });

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                ),
                items: AdminDataService.instance.products.map((p) {
                  return DropdownMenuItem(
                    value: p,
                    child: Text(
                      '${p.name} (${p.price} ج - ${p.stock} متاح)',
                      style: const TextStyle(color: Colors.white),
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  if (!context.mounted) return;
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
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CustomButton(
                    text: "اضف",
                    onPressed: () async {
                      if (selectedProduct == null) return;
                      final qty = int.tryParse(qtyCtrl.text) ?? 1;
                      if (qty <= 0 || selectedProduct!.stock < qty) return;

                      // خصم المخزون مباشرة
                      selectedProduct!.stock -= qty;
                      await ProductDb.insertProduct(
                        selectedProduct!,
                      ); // تحديث المخزون في DB

                      // تحديث AdminDataService
                      final index = AdminDataService.instance.products
                          .indexWhere((p) => p.id == selectedProduct!.id);
                      if (index != -1) {
                        AdminDataService.instance.products[index].stock =
                            selectedProduct!.stock;
                      }

                      final item = CartItem(
                        id: generateId(),
                        product: selectedProduct!,
                        qty: qty,
                      );

                      // استخدام insertOrUpdate لجمع الكمية
                      await CartDb.insertOrUpdateCartItem(item, s.id);

                      // جلب السلة بعد الإضافة واستبدال القائمة بالكامل
                      final updatedCart = await CartDb.getCartBySession(s.id);
                      if (!context.mounted) return;
                      setSheetState(() => s.cart = List.from(updatedCart));

                      // طباعة محتوى السلة بعد الإضافة
                      debugPrint('=== محتوى السلة بعد الإضافة ===');
                      for (var i in s.cart) {
                        debugPrint('${i.product.name} x${i.qty} = ${i.total}');
                      }
                    },
                    infinity: false,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...s.cart.map((item) {
                bool isDeleting = false;
                final qtyController = TextEditingController(
                  text: item.qty.toString(),
                );
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 4.0,
                    horizontal: 0,
                  ), // يمكنك تعديل القيم حسب الحاجة
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
                            if (newQty <= 0 ||
                                newQty > item.product.stock + item.qty) return;
                            item.product.stock += (item.qty - newQty);
                            item.qty = newQty;
                            await CartDb.updateCartItemQty(item.id, newQty);
                            if (!context.mounted) return;
                            setSheetState(() {});
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.redAccent),
                        onPressed: () async {
                          if (isDeleting)
                            return; // ⛔ تجاهل الضغط لو في عملية شغالة
                          isDeleting = true;

                          try {
                            if (item.qty > 1) {
                              // 🟢 قلل 1 من الكمية
                              item.qty -= 1;
                              item.product.stock += 1;

                              // تحديث DB
                              await CartDb.updateCartItemQty(item.id, item.qty);
                            } else {
                              // 🟠 لو آخر واحدة → امسح العنصر
                              await CartDb.deleteCartItem(item.id);

                              item.product.stock += 1;
                              s.cart.remove(item);
                            }
                            await ProductDb.insertProduct(item.product);
                            // تحديث AdminDataService
                            final idx = AdminDataService.instance.products
                                .indexWhere((p) => p.id == item.product.id);
                            if (idx != -1) {
                              AdminDataService.instance.products[idx].stock =
                                  item.product.stock;
                            }

                            setSheetState(() {});
                          } finally {
                            isDeleting = false; // ✅ فك القفل بعد انتهاء العملية
                          }
                        },
                      ),
                    ],
                  ),
                );
              }).toList(),
              const SizedBox(height: 12),
              CustomButton(
                text: "تم اضافه السله",
                onPressed: () async {
                  Navigator.pop(context);
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
