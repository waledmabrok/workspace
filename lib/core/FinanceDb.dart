// import 'Db_helper.dart';
// import 'models.dart';
// import 'package:sqflite_common_ffi/sqflite_ffi.dart';
// import 'dart:convert';
//
// class FinanceDb {
//   // ---------- مصاريف ومبيعات (بقي كما كان مع ضمان تحويل النوع double) ----------
//   static Future<void> insertExpense(Expense e) async {
//     final db = await DbHelper.instance.database;
//     await db.insert('expenses', {
//       'id': e.id,
//       'title': e.title,
//       'amount': e.amount,
//       'date': e.date.millisecondsSinceEpoch,
//     }, conflictAlgorithm: ConflictAlgorithm.replace);
//   }
//
//   static Future<void> insertSale(
//       Sale s, {
//         String? paymentMethod,
//         String? customerId,
//         String? customerName,
//         double? discount,
//       }) async {
//     final db = await DbHelper.instance.database;
//     await db.insert('sales', {
//       'id': s.id,
//       'description': s.description,
//       'amount': s.amount,
//       'discount': discount ?? 0.0,
//       'date': s.date.millisecondsSinceEpoch,
//       'paymentMethod': paymentMethod,
//       'customerId': customerId,
//       'customerName': customerName,
//     }, conflictAlgorithm: ConflictAlgorithm.replace);
//   }
//
//   static Future<List<Expense>> getExpenses() async {
//     final db = await DbHelper.instance.database;
//     final maps = await db.query('expenses');
//     return maps
//         .map(
//           (m) => Expense(
//         id: m['id'] as String,
//         title: m['title'] as String,
//         amount: (m['amount'] as num).toDouble(),
//         date: DateTime.fromMillisecondsSinceEpoch(m['date'] as int),
//       ),
//     )
//         .toList();
//   }
//
//   static Future<List<Sale>> getSales() async {
//     final db = await DbHelper.instance.database;
//     final maps = await db.query('sales');
//     return maps
//         .map(
//           (m) => Sale(
//         id: m['id'] as String,
//         description: m['description'] as String,
//         amount: (m['amount'] as num).toDouble(),
//         date: DateTime.fromMillisecondsSinceEpoch(m['date'] as int),
//       ),
//     )
//         .toList();
//   }
//
//   // ---------- درج الكاشير ----------
//   // احصل الرصيد (لو ما فيش سجل → أنشئ واحد بصفر)
//   static Future<double> getDrawerBalance() async {
//     final db = await DbHelper.instance.database;
//     final rows = await db.query('drawer', where: 'id = ?', whereArgs: [1], limit: 1);
//     if (rows.isEmpty) {
//       await db.insert('drawer', {'id': 1, 'balance': 0.0});
//       return 0.0;
//     }
//     final bal = rows.first['balance'];
//     return (bal as num).toDouble();
//   }
//
//   // ضف/اطرح مبلغ من درج الكاش (delta موجب = اضافة، سالب = سحب)
//   static Future<void> updateDrawerBalanceBy(double delta) async {
//     final db = await DbHelper.instance.database;
//     final current = await getDrawerBalance();
//     final updated = current + delta;
//     await db.update('drawer', {'balance': updated}, where: 'id = ?', whereArgs: [1]);
//   }
//
//   // عيّن رصيد الدرج بقيمة محددة
//   static Future<void> setDrawerBalance(double newBalance) async {
//     final db = await DbHelper.instance.database;
//     final exists = (await db.query('drawer', where: 'id = ?', whereArgs: [1])).isNotEmpty;
//     if (exists) {
//       await db.update('drawer', {'balance': newBalance}, where: 'id = ?', whereArgs: [1]);
//     } else {
//       await db.insert('drawer', {'id': 1, 'balance': newBalance});
//     }
//   }
//
//   // ---------- أرصدة العملاء (موجب = رصيد للعميل، سالب = دين عليه) ----------
//   static Future<double> getCustomerBalance(String name) async {
//     final db = await DbHelper.instance.database;
//     final rows = await db.query('customer_balances', where: 'name = ?', whereArgs: [name], limit: 1);
//     if (rows.isEmpty) return 0.0;
//     final bal = rows.first['balance'];
//     return (bal as num).toDouble();
//   }
//
//   static Future<void> setCustomerBalance(String name, double newBalance) async {
//     final db = await DbHelper.instance.database;
//     await db.insert('customer_balances', {'name': name, 'balance': newBalance},
//         conflictAlgorithm: ConflictAlgorithm.replace);
//   }
//
//   static Future<void> adjustCustomerBalance(String name, double delta) async {
//     final current = await getCustomerBalance(name);
//     final updated = current + delta;
//     await setCustomerBalance(name, updated);
//   }
//
//   // ---------- قفل الشيفت ----------
//   // signers: List<String> بأسماء الثلاث أشخاص
//   static Future<void> closeShift({
//     required String id,
//     required List<String> signers,
//     required double drawerBalanceAtClose,
//     required double totalSales,
//     DateTime? closedAt,
//   }) async {
//     final db = await DbHelper.instance.database;
//     final now = (closedAt ?? DateTime.now()).millisecondsSinceEpoch;
//     final signersJson = jsonEncode(signers);
//     await db.insert('shifts', {
//       'id': id,
//       'closed_at': now,
//       'signers': signersJson,
//       'drawer_balance': drawerBalanceAtClose,
//       'total_sales': totalSales,
//     }, conflictAlgorithm: ConflictAlgorithm.replace);
//   }
//
//   // اختياري: استعلام shifts
//   static Future<List<Map<String, dynamic>>> getShifts() async {
//     final db = await DbHelper.instance.database;
//     return await db.query('shifts', orderBy: 'closed_at DESC');
//   }
// }

// lib/core/FinanceDb.dart

import 'Db_helper.dart'; // أو 'db_helper.dart' حسب اسم الملف عندك - خليه متطابق مع اسم الملف
import 'models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:convert';

class FinanceDb {
  // ---------- مصاريف ----------
  static Future<void> insertExpense(Expense e) async {
    final db = await DbHelper.instance.database;
    await db.insert('expenses', {
      'id': e.id,
      'title': e.title,
      'amount': e.amount,
      'date': e.date.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---------- مبيعات ----------
  /// Insert sale with optional paymentMethod, customerId, customerName, discount
  static Future<void> insertSale(
    Sale s, {
    String? paymentMethod,
    String? customerId,
    String? customerName,
    double? discount,
  }) async {
    final db = await DbHelper.instance.database;
    await db.insert('sales', {
      'id': s.id,
      'description': s.description,
      'amount': s.amount,
      'discount': discount ?? 0.0,
      'date': s.date.millisecondsSinceEpoch,
      'paymentMethod': paymentMethod,
      'customerId': customerId,
      'customerName': customerName,
      'shiftId': s.shiftId,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<List<Expense>> getExpenses() async {
    final db = await DbHelper.instance.database;
    final maps = await db.query('expenses');
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

  static Future<List<Sale>> getSales() async {
    final db = await DbHelper.instance.database;
    final maps = await db.query('sales');
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

  // ---------- درج الكاشير ----------
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
    final bal = rows.first['balance'];
    return (bal as num).toDouble();
  }

  static Future<void> updateDrawerBalanceBy(double delta) async {
    final db = await DbHelper.instance.database;
    final current = await getDrawerBalance();
    final updated = current + delta;
    await db.update(
      'drawer',
      {'balance': updated},
      where: 'id = ?',
      whereArgs: [1],
    );
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

  // ---------- أرصدة العملاء ----------
  // NOTE: use customerId (not name) because your table column is customerId
  static Future<double> getCustomerBalance(String customerId) async {
    final db = await DbHelper.instance.database;
    final rows = await db.query(
      'customer_balances',
      where: 'customerId = ?',
      whereArgs: [customerId],
      limit: 1,
    );
    if (rows.isEmpty) return 0.0;
    final bal = rows.first['balance'];
    return (bal as num).toDouble();
  }

  static Future<void> setCustomerBalance(
    String customerId,
    double newBalance,
  ) async {
    final db = await DbHelper.instance.database;
    await db.insert('customer_balances', {
      'customerId': customerId,
      'balance': newBalance,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> adjustCustomerBalance(
    String customerId,
    double delta,
  ) async {
    final current = await getCustomerBalance(customerId);
    final updated = current + delta;
    await setCustomerBalance(customerId, updated);
  }

  // ---------- قفل الشيفت ----------
  static Future<void> closeShift({
    required String id,
    required List<String> signers,
    required double drawerBalanceAtClose,
    required double totalSales,
    DateTime? closedAt,
  }) async {
    final db = await DbHelper.instance.database;
    final now = (closedAt ?? DateTime.now()).millisecondsSinceEpoch;
    final signersJson = jsonEncode(signers);
    await db.insert('shifts', {
      'id': id,
      'closed_at': now,
      'signers': signersJson,
      'drawer_balance': drawerBalanceAtClose,
      'total_sales': totalSales,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<List<Map<String, dynamic>>> getShiftsByDate(
    DateTime date,
  ) async {
    final db = await openDatabase('finance.db');

    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));

    final shifts = await db.query(
      'shifts',
      where: 'openedAt >= ? AND openedAt < ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
    );

    List<Map<String, dynamic>> result = [];

    for (var shift in shifts) {
      // هنا نحسب المبيعات والمصروفات من جدول المبيعات والمصروفات
      final shiftId = shift['id'];

      final totalSalesResult = await db.rawQuery(
        'SELECT SUM(amount) as total FROM sales WHERE shiftId = ?',
        [shiftId],
      );
      final totalExpensesResult = await db.rawQuery(
        'SELECT SUM(amount) as total FROM expenses WHERE shiftId = ?',
        [shiftId],
      );

      final totalSales = totalSalesResult.first['total'] ?? 0.0;
      final totalExpenses = totalExpensesResult.first['total'] ?? 0.0;

      result.add({
        'cashierName': shift['cashierName'],
        'openedAt': shift['openedAt'],
        'closedAt': shift['closedAt'],
        'openingBalance': shift['openingBalance'],
        'closingBalance': shift['closingBalance'],
        'totalSales': totalSales,
        'totalExpenses': totalExpenses,
      });
    }

    return result;
  }

  static Future<List<Map<String, dynamic>>> getShifts() async {
    final db = await DbHelper.instance.database;
    final rows = await db.query('shifts');

    List<Map<String, dynamic>> updatedRows = [];

    for (var row in rows) {
      final shiftId = row['id'] as String;

      final salesResult = await db.rawQuery(
        "SELECT SUM(amount) as total FROM sales WHERE shiftId = ?",
        [shiftId],
      );

      final expensesResult = await db.rawQuery(
        "SELECT SUM(amount) as total FROM expenses WHERE shiftId = ?",
        [shiftId],
      );

      final totalSales =
          (salesResult.first['total'] as num?)?.toDouble() ?? 0.0;
      final totalExpenses =
          (expensesResult.first['total'] as num?)?.toDouble() ?? 0.0;

      updatedRows.add({
        ...row,
        'totalSales': totalSales,
        'totalExpenses': totalExpenses,
      });
    }

    return updatedRows;
  }
}
