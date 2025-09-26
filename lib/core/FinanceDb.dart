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

import 'Db_helper.dart';
import 'models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:convert';

class FinanceDb {
  // ------------------- Expenses -------------------
  static Future<void> insertExpense(Expense e, {String? shiftId}) async {
    final db = await DbHelper.instance.database;

    // تخزين المصروف في جدول expenses
    await db.insert('expenses', {
      'id': e.id,
      'title': e.title,
      'amount': e.amount,
      'date': e.date.millisecondsSinceEpoch,
      'shiftId': shiftId,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

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

  static Future<List<Sale>> getSales({String? shiftId}) async {
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
}
