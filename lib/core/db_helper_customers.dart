import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'db_helper.dart';
import 'models.dart';

class CustomerDb {
  static Future<void> insert(Customer c) async {
    final db = await DbHelper.instance.database;
    await db.insert("customers", c.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<List<Customer>> getAll() async {
    final db = await DbHelper.instance.database;
    final maps = await db.query("customers");
    return maps.map((e) => Customer.fromMap(e)).toList();
  }

  static Future<void> update(Customer c) async {
    final db = await DbHelper.instance.database;
    await db.update("customers", c.toMap(),
        where: "id = ?", whereArgs: [c.id]);
  }

  static Future<void> delete(String id) async {
    final db = await DbHelper.instance.database;
    await db.delete("customers", where: "id = ?", whereArgs: [id]);
  }
}
