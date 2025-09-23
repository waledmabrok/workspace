import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'Db_helper.dart';
import 'models.dart';

class NotificationsDb {
  static Future<int> insertNotification(NotificationItem item) async {
    final db = await DbHelper.instance.database;
    return await db.insert(
      'notifications',
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore, // يمنع التكرار
    );
  }

  static Future<List<NotificationItem>> getAll() async {
    final db = await DbHelper.instance.database;
    final maps = await db.query('notifications', orderBy: 'createdAt DESC');
    return maps.map((m) => NotificationItem.fromMap(m)).toList();
  }

  static Future<bool> exists(String sessionId, String type) async {
    final db = await DbHelper.instance.database;

    final res = await db.query(
      'notifications',
      where: 'sessionId = ? AND type = ?',
      whereArgs: [sessionId, type],
      limit: 1,
    );
    return res.isNotEmpty;
  }

  static Future<void> markAsRead(int id) async {
    final db = await DbHelper.instance.database;
    await db.update(
      'notifications',
      {'isRead': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> markAllAsRead() async {
    final db = await DbHelper.instance.database;
    await db.update('notifications', {'isRead': 1});
  }

  static Future<void> delete(int id) async {
    final db = await DbHelper.instance.database;
    await db.update(
      'notifications',
      {'isRead': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> clearAll() async {
    final db = await DbHelper.instance.database;
    await db.delete('notifications');
  }
}
