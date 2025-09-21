import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../core/Db_helper.dart';
import '../../core/models.dart';
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

  Future<void> loadBookings() async {
    final db = await dbHelper.database;
    final list = await db.query(
      'room_bookings',
      where: 'status = ?',
      whereArgs: ['open'],
    );
    setState(() => bookings = list);
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
                      'price': 0.0, // يحسب عند الإغلاق
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

    // أول 5 دقائق مجانية
    final chargeableMinutes = durationMinutes > 5 ? durationMinutes - 5 : 0;
    final chargeableHours =
        chargeableMinutes == 0
            ? 0
            : (chargeableMinutes / 60).clamp(0, double.infinity);
    final billHours =
        (chargeableHours > 0 && chargeableHours < 1) ? 1 : chargeableHours;

    // سعر الغرفة
    final roomList = await db.query(
      'rooms',
      where: 'id = ?',
      whereArgs: [booking['roomId']],
      limit: 1,
    );
    final basePrice = (roomList.first['basePrice'] as num).toDouble();
    final numPersons = booking['numPersons'] as int;
    final totalPrice = basePrice * numPersons * billHours;

    final paidCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder: (context, setState) {
              final paidAmount = double.tryParse(paidCtrl.text) ?? 0.0;
              final diff = paidAmount - totalPrice;
              final diffText =
                  diff == 0
                      ? '✅ دفع كامل'
                      : diff > 0
                      ? '💰 الباقي للعميل: ${diff.toStringAsFixed(2)} ج'
                      : '💸 على العميل: ${diff.abs().toStringAsFixed(2)} ج';

              return AlertDialog(
                title: Text('دفع حجز ${booking['customerName']}'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('مدة الحجز: $durationMinutes دقيقة'),
                    Text('المبلغ المطلوب: ${totalPrice.toStringAsFixed(2)} ج'),
                    TextField(
                      controller: paidCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "المبلغ المدفوع",
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      diffText,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('إلغاء'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      if (paidAmount < totalPrice) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('⚠️ المبلغ المدفوع أقل من المطلوب'),
                          ),
                        );
                        return; // الدايلوج يبقى ظاهر
                      }

                      // دفع كامل → تحديث الحجز والدرج
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
                      final currentBalance =
                          (drawerRows.first['balance'] as num).toDouble();
                      await db.update(
                        'drawer',
                        {'balance': currentBalance + totalPrice},
                        where: 'id = ?',
                        whereArgs: [1],
                      );

                      Navigator.pop(ctx, true);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            "تم دفع الحجز: ${totalPrice.toStringAsFixed(2)} ج",
                          ),
                        ),
                      );
                    },
                    child: const Text("دفع كامل"),
                  ),
                ],
              );
            },
          ),
    );

    // بعد الدايلوج → تحديث القائمة بدون أي إغلاق تلقائي
    loadBookings();
  }

  Future<void> addProductToBooking(Map<String, dynamic> booking) async {
    final db = await dbHelper.database;
    final products = await db.query('products');

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
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
        );
      },
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
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () async {
                  await loadRooms(); // يعيد تحميل الغرف
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("تم تحديث قائمة الغرف")),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...rooms.map(
            (room) => Card(
              child: ListTile(
                title: Text(room['name']),
                subtitle: Text("السعر الأساسي: ${room['basePrice']} ج"),
                trailing: ElevatedButton(
                  onPressed: () => bookRoom(room),
                  child: const Text("حجز"),
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
          ...bookings.map(
            (booking) => Card(
              child: ListTile(
                title: Text(
                  "${booking['customerName']} - ${booking['numPersons']} أشخاص",
                ),
                subtitle: Text(
                  "بدأ: ${DateTime.fromMillisecondsSinceEpoch(booking['startTime'])}",
                ),
                trailing: SizedBox(
                  width: 250,
                  child: Row(
                    children: [
                      ElevatedButton(
                        onPressed: () async {
                          final product =
                              await showDialog<Map<String, dynamic>>(
                                context: context,
                                builder:
                                    (_) => AddProductDialog(
                                      bookingId: booking['id'],
                                      id: const Uuid().v4(),
                                    ), // دايلوج صغير لاختيار المنتج والكمية
                              );
                          if (product == true) {
                            // هنا تحدث قائمة المنتجات المعروضة
                            loadBookings(); // أو loadCartItems(booking['id']);
                          }
                        },
                        child: const Text("إضافة منتج"),
                      ),
                      SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => showBookingPaymentDialog(booking),
                        child: const Text("إغلاق"),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class RoomPaymentDialog extends StatefulWidget {
  final String customerName;
  final int numPersons;
  final double basePrice;
  final DateTime startTime;

  const RoomPaymentDialog({
    super.key,
    required this.customerName,
    required this.numPersons,
    required this.basePrice,
    required this.startTime,
  });

  @override
  State<RoomPaymentDialog> createState() => _RoomPaymentDialogState();
}

class _RoomPaymentDialogState extends State<RoomPaymentDialog> {
  final paidCtrl = TextEditingController();
  double getTotal() {
    final now = DateTime.now();
    final durationMinutes = now.difference(widget.startTime).inMinutes;

    const freeMinutes = 15; // أي مدة أقل من 15 دقيقة مجانية
    if (durationMinutes <= freeMinutes) return 0.0;

    final hours = ((durationMinutes - freeMinutes) / 60).ceil();
    return widget.basePrice * widget.numPersons * hours;
  }

  @override
  Widget build(BuildContext context) {
    final total = getTotal();

    return AlertDialog(
      title: Text('دفع ${widget.customerName}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('عدد الأشخاص: ${widget.numPersons}'),
          Text('بدأ الحجز: ${widget.startTime}'),
          const SizedBox(height: 10),
          Text('المطلوب: ${total.toStringAsFixed(2)} ج'),
          TextField(
            controller: paidCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'المبلغ المدفوع'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          Builder(
            builder: (_) {
              final paid = double.tryParse(paidCtrl.text) ?? 0.0;
              final diff = paid - total;
              if (diff == 0) return const Text('✅ دفع كامل');
              if (diff > 0)
                return Text('💰 الباقي للعميل: ${diff.toStringAsFixed(2)} ج');
              return Text('💸 على العميل: ${diff.abs().toStringAsFixed(2)} ج');
            },
          ),
        ],
      ),
      actions: [
        ElevatedButton(
          onPressed: () {
            final paid = double.tryParse(paidCtrl.text) ?? 0.0;
            if (paid < total) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('⚠️ المبلغ المدفوع أقل من المطلوب'),
                ),
              );
              return;
            }
            Navigator.pop(context, true); // دفع كامل
          },
          child: const Text('تأكيد الدفع'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('إلغاء'),
        ),
      ],
    );
  }
}

class AddProductDialog extends StatefulWidget {
  final String bookingId;
  final String id; // لو محتاج

  const AddProductDialog({
    super.key,
    required this.bookingId,
    required this.id,
  });

  @override
  State<AddProductDialog> createState() => _AddProductDialogState();
}

class _AddProductDialogState extends State<AddProductDialog> {
  final dbHelper = DbHelper.instance;
  List<Map<String, dynamic>> products = [];

  @override
  void initState() {
    super.initState();
    loadProducts();
  }

  Future<void> loadProducts() async {
    final db = await dbHelper.database;
    final list = await db.query('products');
    setState(() => products = list);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('اختر المنتجات'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: products.length,
          itemBuilder: (ctx, i) {
            final prod = products[i];
            final qtyCtrl = TextEditingController(text: '0');
            return Row(
              children: [
                Expanded(child: Text(prod['name'].toString())),
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
                      final total = qty * (prod['price'] as num).toDouble();
                      final db = await dbHelper.database;
                      await db.insert('cart_items', {
                        'id': widget.id,
                        'sessionId': widget.bookingId, // بدل bookingId
                        // 'productId': widget.productId,
                        'qty': qty,
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('تمت إضافة ${prod['name']}')),
                      );
                    }
                  },
                  child: const Text('إضافة'),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('تم'),
        ),
      ],
    );
  }
}
