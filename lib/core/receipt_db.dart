import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'db_helper.dart';
import 'models.dart';

class ReceiptDb {
  static Future<void> createTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS receipts (
        id TEXT PRIMARY KEY,
        sessionId TEXT,
        date TEXT,
        itemsJson TEXT
      )
    ''');
  }

  /// إدخال فاتورة جديدة مرتبطة بسيشن
  static Future<void> insertReceipt(
      String sessionId, List<CartItem> items) async {
    final db = await DbHelper.instance.database;

    final receipt = {
      'id': generateId(),
      'sessionId': sessionId,
      'date': DateTime.now().toIso8601String(),
      'itemsJson': jsonEncode(
        items
            .map((ci) => {
                  'id': ci.product.id,
                  'name': ci.product.name,
                  'price': ci.product.price,
                  'qty': ci.qty,
                  'total': ci.total,
                })
            .toList(),
      ),
    };

    await db.insert('receipts', receipt);
  }

  /// كل الفواتير
  static Future<List<Map<String, dynamic>>> getAllReceipts() async {
    final db = await DbHelper.instance.database;
    return await db.query('receipts', orderBy: 'date DESC');
  }

  /// كل الفواتير لسيشن محدد
  static Future<List<Map<String, dynamic>>> getReceiptsBySession(
      String sessionId) async {
    final db = await DbHelper.instance.database;
    return await db.query(
      'receipts',
      where: 'sessionId = ?',
      whereArgs: [sessionId],
      orderBy: 'date DESC',
    );
  }
}
