import 'dart:math';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'Db_helper.dart';

import 'data_service.dart';
import 'models.dart';

class ProductDb {
  static Future<void> insertProduct(Product product) async {
    final db = await DbHelper.instance.database;
    await db.insert(
      'products',
      product.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> sellProduct(Product p, int qty) async {
    if (qty <= 0) return;

    // 1️⃣ تحديث قاعدة البيانات
    final newStock = max(0, p.stock - qty);
    p.stock = newStock;
    await ProductDb.insertProduct(p); // replace old stock

    // 2️⃣ تحديث AdminDataService
    final index = AdminDataService.instance.products.indexWhere(
      (prod) => prod.id == p.id,
    );
    if (index != -1) {
      AdminDataService.instance.products[index].stock = newStock;
    }

    // تحديث الـ UI
  }

  static Future<List<Product>> getProducts() async {
    final db = await DbHelper.instance.database;
    final res = await db.query('products');
    return res.map((e) => Product.fromMap(e)).toList();
  }

  static Future<void> deleteProduct(String id) async {
    final db = await DbHelper.instance.database;
    await db.delete('products', where: 'id = ?', whereArgs: [id]);
  }
}
