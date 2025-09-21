import 'package:flutter/material.dart';
import '../../core/Db_helper.dart';
import 'package:uuid/uuid.dart';

class RoomsPage extends StatefulWidget {
  final bool isAdmin; // true للأدمن, false للكاشير
  const RoomsPage({Key? key, this.isAdmin = true}) : super(key: key);

  @override
  State<RoomsPage> createState() => _RoomsPageState();
}

class _RoomsPageState extends State<RoomsPage> {
  List<Map<String, dynamic>> rooms = [];
  final dbHelper = DbHelper.instance;
  final _uuid = Uuid();

  @override
  void initState() {
    super.initState();
    loadRooms();
  }

  Future<void> loadRooms() async {
    final db = await dbHelper.database;
    final list = await db.query('rooms');
    setState(() => rooms = list);
  }

  // ---------- إضافة غرفة ----------
  Future<void> addRoomDialog() async {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text("إضافة غرفة جديدة"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: "اسم الغرفة"),
                ),
                TextField(
                  controller: priceCtrl,
                  decoration: const InputDecoration(labelText: "السعر الأساسي"),
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
                  final name = nameCtrl.text.trim();
                  final price = double.tryParse(priceCtrl.text.trim()) ?? 0.0;
                  if (name.isNotEmpty && price > 0) {
                    final db = await dbHelper.database;
                    await db.insert('rooms', {
                      'id': _uuid.v4(),
                      'name': name,
                      'basePrice': price,
                    });
                    await loadRooms();
                    Navigator.pop(ctx);
                  }
                },
                child: const Text("إضافة"),
              ),
            ],
          ),
    );
  }

  Future<List<Map<String, dynamic>>> getBookingsForRoom(String roomId) async {
    final db = await dbHelper.database;
    return db.query(
      'room_bookings',
      where: 'roomId = ?',
      whereArgs: [roomId],
      orderBy: 'startTime DESC',
    );
  }

  // ---------- حجز غرفة للكاشير ----------
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
                    final price = (room['basePrice'] as double) * numPersons;
                    final db = await dbHelper.database;
                    await db.insert('room_bookings', {
                      'id': _uuid.v4(),
                      'roomId': room['id'],
                      'customerName': customerName,
                      'numPersons': numPersons,
                      'startTime': DateTime.now().millisecondsSinceEpoch,
                      'endTime': null,
                      'price': price,
                      'status': 'open',
                    });
                    Navigator.pop(ctx);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("غرف الحجز"),
        forceMaterialTransparency: true,
      ),
      floatingActionButton:
          widget.isAdmin
              ? FloatingActionButton(
                child: const Icon(Icons.add),
                onPressed: addRoomDialog,
              )
              : null,
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: rooms.length,
        itemBuilder: (context, index) {
          final room = rooms[index];
          return Card(
            child: ExpansionTile(
              title: Text(room['name']),
              subtitle: Text("السعر الأساسي: ${room['basePrice']} ج"),
              children: [
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: getBookingsForRoom(room['id']),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData)
                      return const CircularProgressIndicator();
                    final bookings = snapshot.data!;
                    if (bookings.isEmpty)
                      return const Text("لا يوجد حجوزات حالياً");
                    return Column(
                      children:
                          bookings.map((booking) {
                            final start = DateTime.fromMillisecondsSinceEpoch(
                              booking['startTime'],
                            );
                            final status =
                                booking['status'] == 'closed'
                                    ? "✅ مغلق"
                                    : "🕒 مفتوح";
                            return ListTile(
                              title: Text(
                                "${booking['customerName']} - ${booking['numPersons']} أشخاص",
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("بدأ: $start"),
                                  Text(
                                    "المبلغ المدفوع: ${booking['price'].toStringAsFixed(2)} ج",
                                  ),
                                ],
                              ),
                              trailing: Text(status),
                            );
                          }).toList(),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
