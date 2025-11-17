import 'Db_helper.dart';
import 'models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:convert';

class FinanceDb {
  // ------------------- Expenses -------------------
  static Future<void> insertExpense(Expense e, {String? shiftId}) async {
    final db = await DbHelper.instance.database;

    // تخزين المصروف في جدول expenses
    await db.insert(
        'expenses',
        {
          'id': e.id,
          'title': e.title,
          'amount': e.amount,
          'date': e.date.millisecondsSinceEpoch,
          'shiftId': shiftId,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);

    // إضافة حركة في shift_transactions إذا تم تمرير shiftId
    if (shiftId != null) {
      await DbHelper.instance.addTransaction(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        shiftId: shiftId,
        type: 'expense',
        amount: e.amount,
        description: e.title,
      );
    }

    // ✅ خصم المبلغ من الدرج
    await updateDrawerBalanceBy(-e.amount);
  }

  static Future<List<Expense>> getExpenses({String? shiftId}) async {
    final db = await DbHelper.instance.database;
    final maps = await db.query(
      'expenses',
      where: shiftId != null ? 'shiftId = ?' : null,
      whereArgs: shiftId != null ? [shiftId] : null,
    );
    return maps
        .map(
          (m) => Expense(
            id: m['id'] as String,
            title: m['title'] as String,
            amount: (m['amount'] as num).toDouble(),
            date: DateTime.fromMillisecondsSinceEpoch(m['date'] as int),
          ),
        )
        .toList();
  }

  // ------------------- Sales -------------------
  static Future<void> insertSale(
    Sale s, {
    String? paymentMethod,
    String? customerId,
    String? customerName,
    double? discount,
  }) async {
    final db = await DbHelper.instance.database;
    await db.insert(
      'sales',
      {
        'id': s.id,
        'description': s.description,
        'amount': s.amount,
        'discount': discount ?? 0.0,
        'date': s.date.millisecondsSinceEpoch,
        'paymentMethod': paymentMethod,
        'customerId': customerId,
        'customerName': customerName,
        'shiftId': s.shiftId,
        'itemsJson': jsonEncode(
          s.items.map((i) => i.toJson()).toList(),
        ),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /*static Future<List<Sale>> getSales({String? shiftId}) async {
    final db = await DbHelper.instance.database;
    final maps = await db.query(
      'sales',
      where: shiftId != null ? 'shiftId = ?' : null,
      whereArgs: shiftId != null ? [shiftId] : null,
    );
    return maps
        .map(
          (m) => Sale(
            id: m['id'] as String,
            description: m['description'] as String,
            amount: (m['amount'] as num).toDouble(),
            date: DateTime.fromMillisecondsSinceEpoch(m['date'] as int),
          ),
        )
        .toList();
  }
*/
  static Future<List<Sale>> getSales({String? shiftId}) async {
    final db = await DbHelper.instance.database;
    final maps = await db.query(
      'sales',
      where: shiftId != null ? 'shiftId = ?' : null,
      whereArgs: shiftId != null ? [shiftId] : null,
    );

    return maps.map((m) {
      List<CartItem> items = [];
      try {
        final decoded = jsonDecode(m['itemsJson']?.toString() ?? '[]') as List;
        items = decoded.map((j) => CartItem.fromJson(j)).toList();
      } catch (e) {
        items = [];
      }

      return Sale(
        id: m['id'] as String,
        description: m['description'] as String,
        amount: (m['amount'] as num).toDouble(),
        discount: (m['discount'] as num?)?.toDouble() ?? 0.0,
        date: DateTime.fromMillisecondsSinceEpoch(m['date'] as int),
        paymentMethod: m['paymentMethod'] as String? ?? 'cash',
        customerId: m['customerId'] as String?,
        customerName: m['customerName'] as String?,
        shiftId: m['shiftId']?.toString(),
        items: items, // ✅ استرجاع المنتجات
      );
    }).toList();
  }

  // ------------------- Drawer -------------------
  static Future<double> getDrawerBalance() async {
    final db = await DbHelper.instance.database;
    final rows = await db.query(
      'drawer',
      where: 'id = ?',
      whereArgs: [1],
      limit: 1,
    );
    if (rows.isEmpty) {
      await db.insert('drawer', {'id': 1, 'balance': 0.0});
      return 0.0;
    }
    return (rows.first['balance'] as num).toDouble();
  }

  static Future<void> updateDrawerBalanceBy(double delta) async {
    final current = await getDrawerBalance();
    await setDrawerBalance(current + delta);
  }

  static Future<void> setDrawerBalance(double newBalance) async {
    final db = await DbHelper.instance.database;
    final exists =
        (await db.query('drawer', where: 'id = ?', whereArgs: [1])).isNotEmpty;
    if (exists) {
      await db.update(
        'drawer',
        {'balance': newBalance},
        where: 'id = ?',
        whereArgs: [1],
      );
    } else {
      await db.insert('drawer', {'id': 1, 'balance': newBalance});
    }
  }

  // ------------------- Customer Balances -------------------
  static Future<double> getCustomerBalance(String customerId) async {
    final db = await DbHelper.instance.database;
    final rows = await db.query(
      'customer_balances',
      where: 'customerId = ?',
      whereArgs: [customerId],
      limit: 1,
    );
    if (rows.isEmpty) return 0.0;
    return (rows.first['balance'] as num).toDouble();
  }

  static Future<void> setCustomerBalance(
    String customerId,
    double newBalance,
  ) async {
    final db = await DbHelper.instance.database;
    await db.insert(
        'customer_balances',
        {
          'customerId': customerId,
          'balance': newBalance,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> adjustCustomerBalance(
    String customerId,
    double delta,
  ) async {
    final current = await getCustomerBalance(customerId);
    await setCustomerBalance(customerId, current + delta);
  }

  // ------------------- Shifts -------------------
  static Future<int> openShift(
    String cashierName, {
    double openingBalance = 0.0,
  }) async {
    return await DbHelper.instance.openShift(
      cashierName,
      openingBalance: openingBalance,
    );
  }

  static Future<Map<String, dynamic>> closeShiftDetailed(
    String shiftId, {
    double? countedClosingBalance,
    String? cashierName,
  }) async {
    return await DbHelper.instance.closeShiftDetailed(
      shiftId,
      countedClosingBalance: countedClosingBalance,
      cashierName: cashierName,
    );
  }

  static Future<Map<String, dynamic>?> getCurrentShift() async {
    return await DbHelper.instance.getCurrentShift();
  }

  static Future<Map<String, dynamic>?> getCurrentShiftForCashier(
    String cashierName,
  ) async {
    return await DbHelper.instance.getCurrentShiftForCashier(cashierName);
  }

  static Future<List<Map<String, dynamic>>> getAllShifts() async {
    return await DbHelper.instance.getAllShifts();
  }

  static Future<Map<String, dynamic>> getShiftSummary(int shiftId) async {
    return await DbHelper.instance.getShiftSummary(shiftId);
  }

  // ------------------- Utilities -------------------
  static String genId() => DateTime.now().millisecondsSinceEpoch.toString();

  static Future<void> addShiftExpense(double amount, String title) async {
    final currentShift = await getCurrentShift();
    if (currentShift == null) throw Exception('لا يوجد شيفت مفتوح');

    final shiftId = currentShift['id'].toString();

    await insertExpense(
      Expense(id: genId(), title: title, amount: amount, date: DateTime.now()),
      shiftId: shiftId,
    );
  }

  static Future<void> insertOrUpdateSale(
    Sale s, {
    String? paymentMethod,
    String? customerId,
    String? customerName,
    double? discount,
  }) async {
    final db = await DbHelper.instance.database;

    // 🔍 هل يوجد Sale بنفس id؟
    final existing = await db.query(
      'sales',
      where: 'id = ?',
      whereArgs: [s.id],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      // ✅ لو موجود → اجمع المنتجات
      final old = Sale.fromMap(existing.first);

      // دمج العناصر (لو فيه منتجات مكررة، نزود الكمية بدل ما نكررها)
      final mergedItems = <CartItem>[];
      final mapById = <String, CartItem>{};

      for (var item in [...old.items, ...s.items]) {
        if (mapById.containsKey(item.product.id)) {
          mapById[item.product.id]!.qty += item.qty;
        } else {
          mapById[item.product.id] = item.copy();
        }
      }
      mergedItems.addAll(mapById.values);

      // تحديث السطر
      await db.update(
        'sales',
        {
          'description': s.description,
          'amount': s.amount + old.amount, // نجمع المبلغ مع القديم
          'discount': discount ?? old.discount,
          'date': s.date.millisecondsSinceEpoch,
          'paymentMethod': paymentMethod ?? old.paymentMethod,
          'customerId': customerId ?? old.customerId,
          'customerName': customerName ?? old.customerName,
          'shiftId': s.shiftId ?? old.shiftId,
          'itemsJson': jsonEncode(mergedItems.map((i) => i.toJson()).toList()),
        },
        where: 'id = ?',
        whereArgs: [s.id],
      );
    } else {
      // 🆕 لو مش موجود → أدخله جديد
      await db.insert(
        'sales',
        {
          'id': s.id,
          'description': s.description,
          'amount': s.amount,
          'discount': discount ?? 0.0,
          'date': s.date.millisecondsSinceEpoch,
          'paymentMethod': paymentMethod,
          'customerId': customerId,
          'customerName': customerName,
          'shiftId': s.shiftId,
          'itemsJson': jsonEncode(
            s.items.map((i) => i.toJson()).toList(),
          ),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }
}
