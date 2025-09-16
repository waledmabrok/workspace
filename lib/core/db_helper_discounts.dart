import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'Db_helper.dart';
import 'models.dart';

class DiscountDb {
  static Future<void> insert(Discount d) async {
    final db = await DbHelper.instance.database;
    await db.insert('discounts', {
      'id': d.id,
      'code': d.code,
      'percent': d.percent,
      'expiry': d.expiry?.millisecondsSinceEpoch,
      'singleUse': d.singleUse ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<List<Discount>> getAll() async {
    final db = await DbHelper.instance.database;
    final data = await db.query('discounts');
    return data.map((e) {
      return Discount(
        id: e['id'] as String,
        code: e['code'] as String,
        percent: (e['percent'] as num).toDouble(),
        expiry:
            e['expiry'] != null
                ? DateTime.fromMillisecondsSinceEpoch(e['expiry'] as int)
                : null,
        singleUse: (e['singleUse'] as int) == 1,
      );
    }).toList();
  }

  static Future<void> update(Discount d) async {
    final db = await DbHelper.instance.database;
    await db.update(
      'discounts',
      {
        'code': d.code,
        'percent': d.percent,
        'expiry': d.expiry?.millisecondsSinceEpoch,
        'singleUse': d.singleUse ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [d.id],
    );
  }

  static Future<void> delete(String id) async {
    final db = await DbHelper.instance.database;
    await db.delete('discounts', where: 'id = ?', whereArgs: [id]);
  }
}
