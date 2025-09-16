import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'Db_helper.dart';
import 'models.dart';
import 'data_service.dart';

class CartDb {
  static Future<void> insertCartItem(CartItem item, String sessionId) async {
    final db = await DbHelper.instance.database;
    await db.insert('cart_items', {
      'id': generateId(),
      'sessionId': sessionId,
      'productId': item.product.id,
      'qty': item.qty,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> updateCartItemQty(String id, int qty) async {
    final db = await DbHelper.instance.database;
    await db.update(
      'cart_items',
      {'qty': qty},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> deleteCartItem(String id) async {
    final db = await DbHelper.instance.database;
    await db.delete('cart_items', where: 'id = ?', whereArgs: [id]);
  }

  static Future<List<CartItem>> getCartBySession(String sessionId) async {
    final db = await DbHelper.instance.database;
    final maps = await db.query(
      'cart_items',
      where: 'sessionId = ?',
      whereArgs: [sessionId],
    );

    return maps.map((m) {
      final product = AdminDataService.instance.products.firstWhere(
        (p) => p.id == m['productId'],
      );
      return CartItem(
        id: m['id'] as String,
        product: product,
        qty: m['qty'] as int,
      );
    }).toList();
  }
}
