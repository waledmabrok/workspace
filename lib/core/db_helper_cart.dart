/*
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'Db_helper.dart';
import 'models.dart';
import 'data_service.dart';

class CartDb {
  static Future<void> insertCartItem(CartItem item, String sessionId) async {
    print("🟢 INSERT cart_item: "
        "sessionId=$sessionId, "
        "productId=${item.product.id}, "
        "name=${item.product.name}, "
        "price=${item.product.price}, "
        "qty=${item.qty}");

    final db = await DbHelper.instance.database;
    await db.insert(
        'cart_items',
        {
          'id': generateId(),
          'sessionId': sessionId.toString(),
          'productId': item.product.id.toString(),
          'productName': item.product.name, // 🟢 جديد
          'productPrice': item.product.price,
          'qty': item.qty,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
    print(
        "🟢 INSERT cart_item: sessionId=$sessionId (${sessionId.runtimeType}), "
        "productId=${item.product.id}, name=${item.product.name}, price=${item.product.price}, qty=${item.qty}");

    final all = await db.query("cart_items");
    print("📦 بعد الإضافة cart_items:");
    for (var r in all) {
      print(r);
    }
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

// CartDb.insertOrUpdateCartItem
  static Future<void> insertOrUpdateCartItem(
      CartItem item, String sessionId) async {
    final db = await DbHelper.instance.database;
    final existing = await db.query(
      'cart_items',
      where: 'sessionId = ? AND productId = ?',
      whereArgs: [sessionId.toString(), item.product.id.toString()],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final row = existing.first;
      final currentQty = int.tryParse(row['qty'].toString()) ?? 0;
      final newQty = currentQty + item.qty;
      await db.update(
        'cart_items',
        {'qty': newQty},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    } else {
      await db.insert('cart_items', {
        'id': generateId(),
        'sessionId': sessionId.toString(),
        'productId': item.product.id.toString(),
        'productName': item.product.name,
        'productPrice': item.product.price,
        'qty': item.qty,
      });
    }
  }

  static Future<void> deleteCartItem(String id) async {
    final db = await DbHelper.instance.database;
    print("🗑️ محاولة مسح العنصر: id=$id");
    await db.delete('cart_items', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> updateStock(String productId, int change) async {
    final db = await DbHelper.instance.database;
    await db.rawUpdate('''
    UPDATE products 
    SET stock = stock + ? 
    WHERE id = ?
  ''', [change, productId]);
  }

  static Future<List<CartItem>> getCartBySession(String sessionId,
      {Session? session}) async {
    final db = await DbHelper.instance.database;

    // طباعة PRAGMA لتأكيد نوع العمود ووجوده
    final cols = await db.rawQuery("PRAGMA table_info(cart_items)");
    print("DEBUG PRAGMA cart_items columns:");
    for (var c in cols) print("  - ${c['name']} : ${c['type']}");

    // استعلام شامل يطبع كل الصفوف مع typeof(sessionId)
    final allRows = await db
        .rawQuery("SELECT *, typeof(sessionId) as sessionType FROM cart_items");
    print("DEBUG all cart_items rows: total=${allRows.length}");
    for (var r in allRows) {
      print("  ROW -> sessionId=[${r['sessionId']}] "
          "typeof=${r['sessionType']} "
          "productId=${r['productId']} qty=${r['qty']} id=${r['id']}");
    }

    // أول محاولة بحث عادي (string)
    final maps = await db.query(
      'cart_items',
      where: 'sessionId = ?',
      whereArgs: [sessionId.toString()],
    );
    print(
        "DEBUG: queried cart_items for sessionId=${sessionId.toString()}, rows=${maps.length}");

    // لو مافي نتائج، جرّب match بالتمثيل الرقمي كـ fallback
    if (maps.isEmpty) {
      final maybeInt = int.tryParse(sessionId);
      if (maybeInt != null) {
        // جرب البحث بالمقدار الرقمي كـ parameter ثاني
        final maps2 = await db.rawQuery(
            'SELECT *, typeof(sessionId) as sessionType FROM cart_items WHERE sessionId = ? OR sessionId = ?',
            [sessionId.toString(), maybeInt]);
        print("DEBUG fallback numeric match rows=${maps2.length}");
        if (maps2.isNotEmpty) {
          // استخدم maps2 لبناء العناصر
          final List<CartItem> cartItems = [];
          for (var m in maps2) {
            final qty = int.tryParse(m['qty'].toString()) ?? 0;
            final product = Product(
              id: m['productId'].toString(),
              name: m['productName']?.toString() ?? 'منتج غير موجود',
              price:
                  double.tryParse(m['productPrice']?.toString() ?? '0') ?? 0.0,
              stock: 0,
            );
            cartItems.add(
                CartItem(id: m['id'].toString(), product: product, qty: qty));
          }
          return cartItems;
        }
      }
    }

    // البناء الاعتيادي
    final List<CartItem> cartItems = [];
    for (var m in maps) {
      final qty = int.tryParse(m['qty'].toString()) ?? 0;
      final product = Product(
        id: m['productId'].toString(),
        name: m['productName']?.toString() ?? 'منتج غير موجود',
        price: double.tryParse(m['productPrice']?.toString() ?? '0') ?? 0.0,
        stock: 0,
      );
      cartItems
          .add(CartItem(id: m['id'].toString(), product: product, qty: qty));
    }

    return cartItems;
  }

// إضافة الباقة كمنتج افتراضي فقط لو الباقة موجودة
// إضافة الباقة كمنتج افتراضي فقط لو الباقة موجودة
*/
/*  if (session != null && session.subscription != null) {
      final plan = session.subscription!;
      cartMap[-1] = CartItem(
        id: 'package-${session.id}',
        product: Product(
          id: 'package-${plan.name}',
          name: plan.name,
          price: plan.price,
          stock: 1,
        ),
        qty: 1,
      );
    }
*/ /*

}
*/
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'Db_helper.dart';
import 'models.dart';
import 'data_service.dart';

class CartDb {
  static Future<void> insertCartItem(CartItem item, String sessionId) async {
    final db = await DbHelper.instance.database;
    await db.insert(
        'cart_items',
        {
          'id': generateId(),
          'sessionId': sessionId,
          'productId': item.product.id,
          'productName': item.product.name, // 👈 أضفناها
          'productPrice': item.product.price,
          'qty': item.qty,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
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

  static Future<void> insertOrUpdateCartItem(
      CartItem item, String sessionId) async {
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
        {
          'qty': newQty,
          // تحديث الاسم والسعر Snapshot كمان (لو عايز تحتفظ بأحدث نسخة)
          'productName': item.product.name,
          'productPrice': item.product.price,
        },
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    } else {
      // المنتج غير موجود → نضيفه جديد
      await db.insert('cart_items', {
        'id': generateId(),
        'sessionId': sessionId,
        'productId': item.product.id,
        'productName': item.product.name, // 👈
        'productPrice': item.product.price,
        'qty': item.qty,
      });
    }
  }

  static Future<void> deleteCartItem(String id) async {
    final db = await DbHelper.instance.database;
    await db.delete('cart_items', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> clearCartBySession(String sessionId) async {
    final db = await DbHelper.instance.database;
    await db.delete(
      'cart_items',
      where: 'sessionId = ?',
      whereArgs: [sessionId],
    );
  }

  static Future<List<CartItem>> getCartCopyBySession(String sessionId,
      {Session? session}) async {
    final cart = await getCartBySession(sessionId, session: session);

    // نرجّع نسخة جديدة (Deep Copy)
    final copy = cart
        .map((item) => CartItem(
              id: item.id,
              product: Product(
                id: item.product.id,
                name: item.product.name,
                price: item.product.price,
                stock: item.product.stock,
              ),
              qty: item.qty,
            ))
        .toList();

    return copy;
  }

/*  static Future<List<CartItem>> getCartBySession(String sessionId,
      {Session? session}) async {
    final db = await DbHelper.instance.database;

    final rows = await db.rawQuery('''
    SELECT ci.id, ci.sessionId, ci.productId, ci.qty,
           p.name as productName,
           p.price as productPrice,
           p.stock as productStock
    FROM cart_items ci
    LEFT JOIN products p ON ci.productId = p.id
    WHERE ci.sessionId = ?
  ''', [sessionId]);

    final Map<String, CartItem> cartMap = {};

    for (var m in rows) {
      final productId = m['productId'].toString();
      final qty = m['qty'] as int;

      final product = Product(
        id: productId,
        name: m['productName']?.toString() ?? "❌ غير معروف",
        price: (m['productPrice'] as num?)?.toDouble() ?? 0.0,
        stock: 0, // أو لو عندك عمود stock في الجدول خده منه
      );

      if (cartMap.containsKey(productId)) {
        cartMap[productId]!.qty += qty;
      } else {
        cartMap[productId] = CartItem(
          id: m['id'].toString(),
          product: product,
          qty: qty,
        );
      }
    }

    return cartMap.values.toList();
  }*/
  static Future<List<CartItem>> getCartBySession(String sessionId,
      {Session? session}) async {
    final db = await DbHelper.instance.database;

    final rows = await db.rawQuery('''
    SELECT ci.id, ci.sessionId, ci.productId, ci.qty,
           COALESCE(p.name, ci.productName) as productName,
           COALESCE(p.price, ci.productPrice) as productPrice,
           p.stock as productStock
    FROM cart_items ci
    LEFT JOIN products p ON ci.productId = p.id
    WHERE ci.sessionId = ?
  ''', [sessionId]);

    final Map<String, CartItem> cartMap = {};

    for (var m in rows) {
      final productId = m['productId'].toString();
      final qty = int.tryParse(m['qty'].toString()) ?? 0;

      final product = Product(
        id: productId,
        name: m['productName']?.toString() ?? "❌ غير معروف",
        price: (m['productPrice'] as num?)?.toDouble() ?? 0.0,
        stock: (m['productStock'] as num?)?.toInt() ?? 0,
      );

      if (cartMap.containsKey(productId)) {
        cartMap[productId]!.qty += qty;
      } else {
        cartMap[productId] = CartItem(
          id: m['id'].toString(),
          product: product,
          qty: qty,
        );
      }
    }

    return cartMap.values.toList();
  }
}
