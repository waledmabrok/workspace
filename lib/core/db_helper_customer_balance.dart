import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'db_helper.dart';
import 'models.dart';

class CustomerBalanceDb {
  static Future<void> upsert(CustomerBalance b) async {
    final db = await DbHelper.instance.database;
    await _ensureUpdatedAtColumn(db);
    await db.insert(
      "customer_balances",
      b.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> _ensureUpdatedAtColumn(Database db) async {
    // جرب إضافة العمود إذا مش موجود
    try {
      await db.execute(
        'ALTER TABLE customer_balances ADD COLUMN updatedAt TEXT',
      );
    } catch (_) {
      // لو العمود موجود هيرمي خطأ، نتجاهله
    }
  }

  static Future<List<CustomerBalance>> getAll() async {
    final db = await DbHelper.instance.database;
    final maps = await db.query("customer_balances");
    return maps.map((e) => CustomerBalance.fromMap(e)).toList();
  }

  static Future<void> delete(String customerId) async {
    final db = await DbHelper.instance.database;
    await db.delete(
      "customer_balances",
      where: "customerId = ?",
      whereArgs: [customerId],
    );
  }

  /// ✅ تعديل الرصيد (موجب = يزود، سالب = يخصم)
  static Future<void> adjust(String customerId, double delta) async {
    final db = await DbHelper.instance.database;
    await _ensureUpdatedAtColumn(db);
    // هات الرصيد الحالي
    final current = await getBalance(customerId);
    final newBalance = current + delta;

    // Upsert
    await db.insert('customer_balances', {
      'customerId': customerId,
      'balance': newBalance,
      'updatedAt': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<double> getBalance(String customerId) async {
    final db = await DbHelper.instance.database;
    final res = await db.query(
      'customer_balances',
      where: 'customerId = ?',
      whereArgs: [customerId],
    );
    if (res.isNotEmpty) {
      return (res.first['balance'] as num).toDouble();
    }
    return 0.0;
  }
}
