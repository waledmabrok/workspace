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

  static Future<List<SubscriptionPlan>> getPlans() async {
    final db = await DbHelper.instance.database;
    final res = await db.query('subscriptions');
    return res.map((e) => SubscriptionPlan.fromMap(e)).toList();
  }

  static Future<void> deletePlan(String id) async {
    final db = await DbHelper.instance.database;
    await db.delete('subscriptions', where: 'id = ?', whereArgs: [id]);
  }
}
