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

  // بدل delete خليه soft delete
  static Future<void> deleteBySessionAndType(
    String sessionId,
    String type,
  ) async {
    final db = await DbHelper.instance.database;
    await db.update(
      'notifications',
      {'isDeleted': 1},
      where: 'sessionId = ? AND type = ?',
      whereArgs: [sessionId, type],
    );
  }

  // لما تجيب الإشعارات
  static Future<List<NotificationItem>> getAll() async {
    final db = await DbHelper.instance.database;
    final maps = await db.query(
      'notifications',
      where: 'isDeleted = 0', // هات بس اللي مش متشالين
      orderBy: 'createdAt DESC',
    );
    return maps.map((m) => NotificationItem.fromMap(m)).toList();
  }

  static Future<List<NotificationItem>> getUnread() async {
    final db = await DbHelper.instance.database;
    final maps = await db.query(
      'notifications',
      where: 'isRead = 0 AND isDeleted = 0',
      orderBy: 'createdAt DESC',
    );
    return maps.map((m) => NotificationItem.fromMap(m)).toList();
  }

  static Future<int> getUnreadCount() async {
    final db = await DbHelper.instance.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM notifications WHERE isRead = 0 AND isDeleted = 0',
    );
    final cntRaw = result.first['cnt'];
    return (cntRaw is int) ? cntRaw : int.tryParse(cntRaw.toString()) ?? 0;
  }

  static Future<bool> exists(String sessionId, String type) async {
    final db = await DbHelper.instance.database;
    final res = await db.query(
      'notifications',
      where: 'sessionId = ? AND type = ?',
      whereArgs: [sessionId, type],
      limit: 1,
    );
    return res.isNotEmpty; // يشمل حتى المحذوف
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

  static Future<void> markAsReadBySession(String sessionId) async {
    final db = await DbHelper.instance.database;
    await db.update(
      'notifications',
      {'isRead': 1},
      where: 'sessionId = ?',
      whereArgs: [sessionId],
    );
  }

  static Future<void> markAsReadBySessionAndType(
    String sessionId,
    String type,
  ) async {
    final db = await DbHelper.instance.database;
    await db.update(
      'notifications',
      {'isRead': 1},
      where: 'sessionId = ? AND type = ?',
      whereArgs: [sessionId, type],
    );
  }

  static Future<void> markAllAsRead() async {
    final db = await DbHelper.instance.database;
    await db.update('notifications', {'isRead': 1}, where: 'isDeleted = 0');
  }

  static Future<void> softDeleteBySessionAndType(
    String sessionId,
    String type,
  ) async {
    final db = await DbHelper.instance.database;
    await db.update(
      'notifications',
      {'isDeleted': 1},
      where: 'sessionId = ? AND type = ?',
      whereArgs: [sessionId, type],
    );
  }

  static Future<void> delete(int id) async {
    final db = await DbHelper.instance.database;
    await db.update(
      'notifications',
      {'isDeleted': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> clearAll() async {
    final db = await DbHelper.instance.database;
    await db.delete('notifications');
  }
}
