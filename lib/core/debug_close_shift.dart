/*
// debug_close_shift.dart (محدّثة)
import 'dart:convert';
import 'package:flutter/material.dart';
import 'db_helper.dart';

Future<void> debugPopulateAndClose() async {
  final db = await DbHelper.instance.database;

  // 1) افتح شيفت جديد (id فريد)
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  final shiftId = 'shift_$nowMs';
  await DbHelper.instance.openShift(

    cashierName: 'Ali',
    openingBalance: 100.0,
  );

  // 2) اضف مبيعات (cash & card) مع ids فريدة
  final sCashId = 's_cash_$nowMs';
  final sCardId = 's_card_$nowMs';

  try {
    await db.insert('sales', {
      'id': sCashId,
      'description': 'Sale - cash',
      'amount': 50.0,
      'discount': 5.0,
      'date': nowMs,
      'paymentMethod': 'cash',
      'shiftId': shiftId,
    });
  } catch (e) {
    debugPrint('insert s_cash error: $e');
  }

  try {
    await db.insert('sales', {
      'id': sCardId,
      'description': 'Sale - card',
      'amount': 80.0,
      'discount': 0.0,
      'date': nowMs,
      'paymentMethod': 'card',
      'shiftId': shiftId,
    });
  } catch (e) {
    debugPrint('insert s_card error: $e');
  }

  // 3) اضف مصروف داخل نفس الفترة
  final expId = 'exp_$nowMs';
  try {
    await db.insert('expenses', {
      'id': expId,
      'title': 'Coffee',
      'amount': 20.0,
      'date': nowMs,
    });
  } catch (e) {
    debugPrint('insert expense error: $e');
  }

  // 4) اضف حركات درج (deposit, withdraw)
  final txDep = 'tx_deposit_$nowMs';
  final txWdr = 'tx_withdraw_$nowMs';
  try {
    await db.insert('shift_transactions', {
      'id': txDep,
      'shiftId': shiftId,
      'type': 'deposit',
      'amount': 30.0,
      'description': 'Cash deposit',
      'createdAt': nowMs,
    });
    await db.insert('shift_transactions', {
      'id': txWdr,
      'shiftId': shiftId,
      'type': 'withdraw',
      'amount': 10.0,
      'description': 'Withdraw to safe',
      'createdAt': nowMs,
    });
  } catch (e) {
    debugPrint('insert shift_transactions error: $e');
  }

  // 5) ننفّذ اغلاق الشيفت
  final report = await DbHelper.instance.closeShiftDetailed(
    shiftId,
    countedClosingBalance: null,
    cashierName: 'Ali',
  );

  // 6) اطبع التقرير ورصيد الدرج وامتحان جدول shift_reports
  debugPrint('=== SHIFT CLOSE REPORT ===');
  debugPrint(const JsonEncoder.withIndent('  ').convert(report));

  final drawerRows = await db.query('drawer', where: 'id = ?', whereArgs: [1], limit: 1);
  debugPrint('drawer balance after close: ${drawerRows.first['balance']}');

  final savedReports = await db.query('shift_reports', where: 'shiftId = ?', whereArgs: [shiftId]);
  debugPrint('shift_reports rows for this shift: ${savedReports.length}');
  if (savedReports.isNotEmpty) {
    debugPrint('stored reportJson (preview): ${savedReports.first['reportJson'].toString().substring(0, 200)}');
  }
}
*/
