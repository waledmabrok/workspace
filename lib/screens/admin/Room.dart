import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:workspace/utils/colors.dart';
import 'package:workspace/widget/buttom.dart';
import 'package:workspace/widget/form.dart';
import '../../core/Db_helper.dart';

class RoomsPage extends StatefulWidget {
  const RoomsPage({Key? key}) : super(key: key);

  @override
  State<RoomsPage> createState() => _RoomsPageState();
}

class _RoomsPageState extends State<RoomsPage> {
  final dbHelper = DbHelper.instance;
  final _uuid = Uuid();

  List<Map<String, dynamic>> rooms = [];
  bool _loading = true;

  // التسعيرة العامة
  late TextEditingController _freeMinutes;
  late TextEditingController _firstHour;
  late TextEditingController _perHourAfter;
  late TextEditingController _dailyCap;

  @override
  void initState() {
    super.initState();
    _loadPricingAndRooms();
  }

  Future<void> _loadPricingAndRooms() async {
    final db = await dbHelper.database;

    // جلب التسعيرة العامة من جدول pricing_settings
    final settingsRows = await db.query('pricing_settings_Room', limit: 1);
    final settings = settingsRows.first;
    _freeMinutes = TextEditingController(
      text: settings['firstFreeMinutesRoom'].toString(),
    );
    _firstHour = TextEditingController(
      text: settings['firstHourFeeRoom'].toString(),
    );
    _perHourAfter = TextEditingController(
      text: settings['perHourAfterFirstRoom'].toString(),
    );
    _dailyCap = TextEditingController(
      text: settings['dailyCapRoom'].toString(),
    );

    // جلب الغرف
    final roomList = await db.query('rooms');
    setState(() {
      rooms = roomList;
      _loading = false;
    });
  }

  Future<void> _saveGeneralPricing() async {
    final db = await dbHelper.database;
    await db.update(
      'pricing_settings_Room',
      {
        'firstFreeMinutesRoom': int.tryParse(_freeMinutes.text) ?? 15,
        'firstHourFeeRoom': double.tryParse(_firstHour.text) ?? 30,
        'perHourAfterFirstRoom': double.tryParse(_perHourAfter.text) ?? 20,
        'dailyCapRoom': double.tryParse(_dailyCap.text) ?? 150,
      },
      where: 'id = ?',
      whereArgs: [1],
    );

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('✅ تم تحديث التسعيرة العامة')));
  }

  Future<void> _addRoom() async {
    final nameCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('إضافة غرفة جديدة'),
            content: TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'اسم الغرفة'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final name = nameCtrl.text.trim();
                  if (name.isNotEmpty) {
                    final db = await dbHelper.database;
                    await db.insert('rooms', {
                      'id': _uuid.v4(),
                      'name': name,
                      // تطبيق التسعيرة العامة على الغرفة الجديدة
                      'firstFreeMinutesRoom':
                          int.tryParse(_freeMinutes.text) ?? 15,
                      'firstHourFeeRoom':
                          double.tryParse(_firstHour.text) ?? 30,
                      'perHourAfterFirstRoom':
                          double.tryParse(_perHourAfter.text) ?? 20,
                      'dailyCapRoom': double.tryParse(_dailyCap.text) ?? 150,
                    });
                    Navigator.pop(ctx);
                    _loadPricingAndRooms();
                  }
                },
                child: const Text('إضافة'),
              ),
            ],
          ),
    );
  }

  Future<void> _editRoom(Map<String, dynamic> room) async {
    final freeCtrl = TextEditingController(
      text: room['firstFreeMinutesRoom']?.toString() ?? '',
    );
    final firstHourCtrl = TextEditingController(
      text: room['firstHourFeeRoom']?.toString() ?? '',
    );
    final perHourCtrl = TextEditingController(
      text: room['perHourAfterFirstRoom']?.toString() ?? '',
    );
    final dailyCapCtrl = TextEditingController(
      text: room['dailyCapRoom']?.toString() ?? '',
    );

    await showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text('تعديل ${room['name']}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: freeCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'الدقائق المجانية',
                  ),
                ),
                TextField(
                  controller: firstHourCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'سعر أول ساعة'),
                ),
                TextField(
                  controller: perHourCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'سعر كل ساعة بعد الأولى',
                  ),
                ),
                TextField(
                  controller: dailyCapCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'الحد اليومي'),
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
                  final db = await dbHelper.database;
                  await db.update(
                    'rooms',
                    {
                      'firstFreeMinutesRoom': int.tryParse(freeCtrl.text) ?? 15,
                      'firstHourFeeRoom':
                          double.tryParse(firstHourCtrl.text) ?? 30,
                      'perHourAfterFirstRoom':
                          double.tryParse(perHourCtrl.text) ?? 20,
                      'dailyCapRoom': double.tryParse(dailyCapCtrl.text) ?? 150,
                    },
                    where: 'id = ?',
                    whereArgs: [room['id']],
                  );
                  Navigator.pop(ctx);
                  _loadPricingAndRooms();
                },
                child: const Text('حفظ'),
              ),
            ],
          ),
    );
  }

  Future<List<Map<String, dynamic>>> getActiveBookingsForRoom(
    String roomId,
  ) async {
    final db = await dbHelper.database;
    return db.query(
      'room_bookings',
      where: 'roomId = ? AND status = ?',
      whereArgs: [roomId, 'open'],
      orderBy: 'startTime DESC',
    );
  }

  Future<void> _deleteRoom(String roomId) async {
    final db = await dbHelper.database;
    await db.delete('rooms', where: 'id = ?', whereArgs: [roomId]);
    _loadPricingAndRooms();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      // backgroundColor: AppColorsDark.bgColor,
      appBar: AppBar(
        title: Center(child: const Text('إعدادات الغرف والتسعيرة')),
        forceMaterialTransparency: true,
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        backgroundColor: AppColorsDark.mainColor,
        onPressed: _addRoom,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'التسعيرة العامة',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            _buildCardField(_freeMinutes, 'عدد الدقائق المجانية'),
            _buildCardField(_firstHour, 'سعر أول ساعة'),
            _buildCardField(_perHourAfter, 'سعر كل ساعة بعد الأولى'),
            _buildCardField(_dailyCap, 'الحد اليومي الأعلى'),
            const SizedBox(height: 12),

            Padding(
              padding: const EdgeInsets.all(16.0),
              child: CustomButton(
                text: 'حفظ التغييرات',
                onPressed: _saveGeneralPricing,
              ),
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 12),
            const Text(
              'قائمة الغرف',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...rooms.map(
              (room) => Card(
                color: AppColorsDark.bgCardColor,
                child: Column(
                  children: [
                    ListTile(
                      title: Text(room['name']),
                      subtitle: Text(
                        'دقائق مجانية: ${room['firstFreeMinutesRoom'] ?? 'استخدام العام'} - '
                        'أول ساعة: ${room['firstHourFeeRoom'] ?? 'استخدام العام'} - '
                        'بعد الأولى: ${room['perHourAfterFirstRoom'] ?? 'استخدام العام'} - '
                        'الحد اليومي: ${room['dailyCapRoom'] ?? 'استخدام العام'}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CustomButton(
                            text: "تعديل",
                            onPressed: () => _editRoom(room),
                            infinity: false,
                          ),
                          /* ElevatedButton(
                            onPressed: () => _editRoom(room),
                            child: const Text('تعديل'),
                          ),*/
                          const SizedBox(width: 8),
                          CustomButton(
                            text: 'حذف',
                            onPressed: () => _deleteRoom(room['id']),
                            infinity: false,
                            color: Colors.red,

                            border: true,
                          ),
                          /* ElevatedButton(
                            onPressed: () => _deleteRoom(room['id']),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                            child: const Text('حذف'),
                          ),*/
                        ],
                      ),
                    ),
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: getActiveBookingsForRoom(room['id']),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData)
                          return const CircularProgressIndicator();
                        final bookings = snapshot.data!;
                        if (bookings.isEmpty)
                          return Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: const Text("لا يوجد حجوزات نشطة"),
                          );
                        return Column(
                          children:
                              bookings.map((booking) {
                                final start =
                                    DateTime.fromMillisecondsSinceEpoch(
                                      booking['startTime'],
                                    );
                                final formatter = DateFormat(
                                  'EEEE، d MMMM yyyy – الساعه  HH:mm',
                                  'ar',
                                );
                                final formattedStart = formatter.format(start);
                                return ListTile(
                                  title: Text(
                                    "${booking['customerName']} - ${booking['numPersons']} أشخاص",
                                  ),
                                  subtitle: Text("بدأ: $formattedStart"),
                                  trailing: Text("🕒 مفتوح"),
                                );
                              }).toList(),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardField(TextEditingController controller, String label) {
    return Card(
      color: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: CustomFormField(hint: label, controller: controller),
      ),
    );
  }
}
