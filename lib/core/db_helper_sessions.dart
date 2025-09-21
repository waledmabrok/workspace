/*
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:path/path.dart';
import 'models.dart';
import 'data_service.dart';

class SessionDb {
  static Database? _db;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  static Future<Database> _initDb() async {
    final path = join(await getDatabasesPath(), 'workspace.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
        CREATE TABLE sessions(
          id TEXT PRIMARY KEY,
          name TEXT,
          start TEXT,
          end TEXT,
          amountPaid REAL,
          subscriptionId TEXT,
          isActive INTEGER,
          isPaused INTEGER,
          elapsedMinutes INTEGER
        )
      ''');
      },
    );
  }


  static Future<void> insertSession(Session s) async {
    final db = await database;
    await db.insert('sessions', s.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> updateSession(Session s) async {
    final db = await database;
    await db.update('sessions', s.toMap(), where: 'id = ?', whereArgs: [s.id]);
  }

  static Future<void> deleteSession(String id) async {
    final db = await database;
    await db.delete('sessions', where: 'id = ?', whereArgs: [id]);
  }

  static Future<List<Session>> getSessions() async {
    final db = await database;
    final maps = await db.query('sessions', orderBy: 'start DESC');

    // ربط الاشتراك لو موجود
    return List.generate(maps.length, (i) {
      final subId = maps[i]['subscriptionId'];
      final plan = AdminDataService.instance.subscriptions.firstWhere(
            (s) => s.id == subId,
          orElse: () => SubscriptionPlan(
            id: '',
            name: '',
            durationType: 'hour',
            price: 0.0,
          )

      );
      return Session.fromMap(maps[i], plan: plan);
    });
  }
}
*/
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'Db_helper.dart';

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
    await db.update('sessions', s.toMap(), where: 'id = ?', whereArgs: [s.id]);
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
