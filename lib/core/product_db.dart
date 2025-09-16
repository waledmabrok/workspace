import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'Db_helper.dart';

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
