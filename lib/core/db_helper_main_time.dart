import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'Db_helper.dart';
import 'data_service.dart'; // فيه PricingSettings

class PricingDb {
  static Future<void> saveSettings(PricingSettings s) async {
    final db = await DbHelper.instance.database;

    await db.insert('pricing_settings', {
      'id': 1, // دايمًا الصف الوحيد
      'firstFreeMinutes': s.firstFreeMinutes,
      'firstHourFee': s.firstHourFee,
      'perHourAfterFirst': s.perHourAfterFirst,
      'dailyCap': s.dailyCap,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<PricingSettings> loadSettings() async {
    final db = await DbHelper.instance.database;
    final maps = await db.query(
      'pricing_settings',
      where: 'id = ?',
      whereArgs: [1],
      limit: 1,
    );

    if (maps.isNotEmpty) {
      final m = maps.first;
      return PricingSettings(
        firstFreeMinutes:
            m['firstFreeMinutes'] is int
                ? m['firstFreeMinutes'] as int
                : int.tryParse(m['firstFreeMinutes'].toString()) ?? 0,
        firstHourFee:
            m['firstHourFee'] is num
                ? (m['firstHourFee'] as num).toDouble()
                : double.tryParse(m['firstHourFee'].toString()) ?? 0.0,
        perHourAfterFirst:
            m['perHourAfterFirst'] is num
                ? (m['perHourAfterFirst'] as num).toDouble()
                : double.tryParse(m['perHourAfterFirst'].toString()) ?? 0.0,
        dailyCap:
            m['dailyCap'] is num
                ? (m['dailyCap'] as num).toDouble()
                : double.tryParse(m['dailyCap'].toString()) ?? 0.0,
      );
    }

    // fallback (لو الجدول فاضي لأي سبب)
    return PricingSettings(
      firstFreeMinutes: 2,
      firstHourFee: 15,
      perHourAfterFirst: 10,
      dailyCap: 90,
    );
  }
}
