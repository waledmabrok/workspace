/*
import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../core/models.dart';


class SubscriptionDb {
  static Database? _db;

  static Future<Database> get instance async {
    if (_db != null) return _db!;
    final dbPath = await databaseFactoryFfi.getDatabasesPath();
    final path = join(dbPath, 'subscriptions.db');
    _db = await databaseFactoryFfi.openDatabase(path, options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE subscriptions (
            id TEXT PRIMARY KEY,
            name TEXT,
            durationType TEXT,
            durationValue INTEGER,
            price REAL,
            dailyUsageType TEXT,
            dailyUsageHours INTEGER,
            weeklyHours TEXT,
            isUnlimited INTEGER
          )
        ''');
      },
    ));
    return _db!;
  }

  static Future<void> insertPlan(SubscriptionPlan plan) async {
    final db = await instance;
    await db.insert('subscriptions', plan.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<List<SubscriptionPlan>> getPlans() async {
    final db = await instance;
    final res = await db.query('subscriptions');
    return res.map((e) => SubscriptionPlan.fromMap(e)).toList();
  }

  static Future<void> deletePlan(String id) async {
    final db = await instance;
    await db.delete('subscriptions', where: 'id = ?', whereArgs: [id]);
  }
}
*/
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'Db_helper.dart';
import 'models.dart';

class SubscriptionDb {
  static Future<void> insertPlan(SubscriptionPlan plan) async {
    final db = await DbHelper.instance.database;
    await db.insert(
      'subscriptions',
      plan.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get active subscription of a customer (null if none)
  static Future<SubscriptionPlan?> getActiveForCustomer(
    String customerId,
  ) async {
    final db = await DbHelper.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT sp.* 
      FROM customer_subscriptions cs
      JOIN subscriptions sp ON cs.subscriptionPlanId = sp.id
      WHERE cs.customerId = ? 
        AND (cs.endDate IS NULL OR cs.endDate > strftime('%s','now')*1000)
      ORDER BY cs.startDate DESC
      LIMIT 1
    ''',
      [customerId],
    );

    if (rows.isEmpty) return null;
    return SubscriptionPlan.fromMap(rows.first);
  }

  static Future<List<SubscriptionPlan>> getPlans() async {
    final db = await DbHelper.instance.database;
    final res = await db.query('subscriptions');
    return res.map((e) => SubscriptionPlan.fromMap(e)).toList();
  }

  static Future<void> updatePlan(SubscriptionPlan plan) async {
    final db = await DbHelper.instance.database;
    await db.update(
      'subscriptions',
      plan.toMap(),
      where: 'id = ?',
      whereArgs: [plan.id],
    );
  }

  static Future<void> deletePlan(String id) async {
    final db = await DbHelper.instance.database;
    await db.delete('subscriptions', where: 'id = ?', whereArgs: [id]);
  }
}
