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
  static Future<void> insertOrUpdateCartItem(CartItem item, String sessionId) async {
    final db = await DbHelper.instance.database;

    // البحث عن المنتج لنفس الجلسة
    final existing = await db.query(
      'cart_items',
      where: 'sessionId = ? AND productId = ?',
      whereArgs: [sessionId, item.product.id],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      // المنتج موجود → نجمع الكمية
      final row = existing.first;
      final currentQty = row['qty'] as int;
      final newQty = currentQty + item.qty;

      await db.update(
        'cart_items',
        {'qty': newQty},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    } else {
      // المنتج غير موجود → نضيفه جديد
      await db.insert('cart_items', {
        'id': generateId(),
        'sessionId': sessionId,
        'productId': item.product.id,
        'qty': item.qty,
      });
    }
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

    final Map<int, CartItem> cartMap = {};

    for (var m in maps) {
      final productId = m['productId'] is int
          ? m['productId'] as int
          : int.parse(m['productId'].toString());

      final qty = m['qty'] is int
          ? m['qty'] as int
          : int.parse(m['qty'].toString());

      final product = AdminDataService.instance.products.firstWhere(
            (p) => p.id == productId.toString(), // حوّل ID من int لـ String
        orElse: () => Product(
          id: productId.toString(),
          name: 'منتج غير موجود',
          price: 0.0,
          stock: 0,
        ),
      );

      if (cartMap.containsKey(productId)) {
        cartMap[productId]!.qty += qty;
      } else {
        cartMap[productId] = CartItem(
          id: m['id'] as String,
          product: product,
          qty: qty,
        );
      }
    }

    return cartMap.values.toList();
  }

}
