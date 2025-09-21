// db_helper_cashiers.dart
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'Db_helper.dart';

class CashierDb {
  static Future<void> createTable(Database db) async {
    await db.execute('''
    CREATE TABLE IF NOT EXISTS shifts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      cashierId TEXT,
      cashierName TEXT,
      openedAt TEXT,
      closedAt TEXT,
      openingBalance REAL,
      closingBalance REAL,
      totalSales REAL,
      totalExpenses REAL
    )
  ''');
  }

  static Future<void> insertCashier(
    String id,
    String name,
    String password,
  ) async {
    final db = await DbHelper.instance.database;
    await db.insert("cashiers", {"id": id, "name": name, "password": password});
  }

  static Future<Map<String, dynamic>?> login(
    String name,
    String password,
  ) async {
    final db = await DbHelper.instance.database;
    final res = await db.query(
      "cashiers",
      where: "name = ? AND password = ?",
      whereArgs: [name, password],
    );
    if (res.isNotEmpty) return res.first;
    return null;
  }

  static Future<List<Map<String, dynamic>>> getAll() async {
    final db = await DbHelper.instance.database;
    return db.query("cashiers");
  }
}
