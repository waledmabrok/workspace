import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'Db_helper.dart';
import 'dart:convert';

import 'models.dart';
import 'data_service.dart';

class SessionDb {
  static Future<void> insertSession(Session s) async {
    final db = await DbHelper.instance.database;
    await db.insert(
      'sessions',
      s.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> updateSession(Session s) async {
    final db = await DbHelper.instance.database;

    // طباعة قبل التحديث
    print("🔹 تحديث الجلسة: ${s.name}, id=${s.id}");
    print("   بيانات الجلسة قبل التحديث: ${s.toMap()}");

    // تحديث الحقول بدون تغيير الـ id
    final mapToUpdate = {
      'name': s.name,
      'start': s.start.millisecondsSinceEpoch, // بدل DateTime
      'end': s.end?.millisecondsSinceEpoch,
      'amountPaid': s.amountPaid,
      'subscriptionId': s.subscription?.id,
      'isActive': s.isActive ? 1 : 0,
      'isPaused': s.isPaused ? 1 : 0,
      'elapsedMinutes': s.elapsedMinutes,
      'frozenMinutes': s.frozenMinutes,
      'elapsedMinutesPayg': s.elapsedMinutesPayg,
      'type': s.type,
      'pauseStart': s.pauseStart?.millisecondsSinceEpoch,
      'paidMinutes': s.paidMinutes,
      'customerId': s.customerId,
      'events': s.events != null ? jsonEncode(s.events) : null,
      'savedSubscriptionJson': s.savedSubscriptionJson,
      'resumeNextDayRequested': (s.resumeNextDayRequested ?? false) ? 1 : 0,
      'resumeDate': s.resumeDate?.millisecondsSinceEpoch,
      'savedSubscriptionEnd': s.savedSubscriptionEnd?.millisecondsSinceEpoch,
      'savedSubscriptionConvertedAt':
          s.savedSubscriptionConvertedAt?.millisecondsSinceEpoch,
      'runningSince': s.runningSince?.millisecondsSinceEpoch,
      'originalSubscriptionId': s.originalSubscriptionId,
    };

    final count = await db.update(
      'sessions',
      mapToUpdate,
      where: 'id = ?',
      whereArgs: [s.id],
    );

    // طباعة بعد التحديث
    print("✅ عدد الصفوف المحدثة: $count");
    print("   بيانات الجلسة بعد التحديث: ${s.toMap()}");
  }

  static Future<void> deleteSession(String id) async {
    final db = await DbHelper.instance.database;
    await db.delete('sessions', where: 'id = ?', whereArgs: [id]);
  }

  static Future<Session?> getSessionById(String id) async {
    final db = await DbHelper.instance.database;
    final maps = await db.query(
      'sessions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (maps.isEmpty) return null;

    final map = maps.first;

    // حاول تجيب الخطة لو موجودة
    SubscriptionPlan? plan;
    final subId = map['subscriptionId'];
    if (subId != null && subId.toString().isNotEmpty) {
      try {
        plan = AdminDataService.instance.subscriptions.firstWhere(
          (s) => s.id == subId,
        );
      } catch (_) {
        plan = null;
      }
    }

    return Session.fromMap(map, plan: plan);
  }

  static Future<List<Session>> getSessions() async {
    final db = await DbHelper.instance.database;
    final maps = await db.query('sessions', orderBy: 'start DESC');

    return List.generate(maps.length, (i) {
      final subId = maps[i]['subscriptionId'];

      SubscriptionPlan? plan;
      if (subId != null && subId.toString().isNotEmpty) {
        try {
          plan = AdminDataService.instance.subscriptions.firstWhere(
            (s) => s.id == subId,
          );
        } catch (_) {
          plan = null; // لو الخطة مش لاقيها
        }
      }

      return Session.fromMap(maps[i], plan: plan);
    });
  }
}
