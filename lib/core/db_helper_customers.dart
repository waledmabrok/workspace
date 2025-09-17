// lib/core/db_helper_customers.dart

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'db_helper.dart';
import 'models.dart';

/// Helper for customers table.
///
/// Requirements:
/// - Customer model must implement `toMap()` and `fromMap(Map)`.
/// - A `generateId()` function should exist in your project (used when creating new customers).
class CustomerDb {
  /// Insert (or replace) a customer.
  static Future<void> insert(Customer c) async {
    final db = await DbHelper.instance.database;
    await db.insert(
      "customers",
      c.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Upsert synonym
  static Future<void> upsert(Customer c) async => insert(c);

  /// Get all customers
  static Future<List<Customer>> getAll() async {
    final db = await DbHelper.instance.database;
    final maps = await db.query("customers", orderBy: 'name COLLATE NOCASE');
    return maps.map((e) => Customer.fromMap(e)).toList();
  }

  /// Get customer by id, or null if not found
  static Future<Customer?> getById(String id) async {
    final db = await DbHelper.instance.database;
    final maps = await db.query(
      'customers',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Customer.fromMap(maps.first);
  }

  /// Get customer by exact name (case-sensitive). Returns null if not found.
  /// If you want case-insensitive search, use getByNameInsensitive.
  // static Future<Customer?> getByName(String name) async {
  //   final db = await DbHelper.instance.database;
  //   final maps = await db.query(
  //     'customers',
  //     where: 'name = ?',
  //     whereArgs: [name],
  //     limit: 1,
  //   );
  //   if (maps.isEmpty) return null;
  //   return Customer.fromMap(maps.first);
  // }
  static Future<Customer?> getByName(String name) async {
    final db = await DbHelper.instance.database;
    final rows = await db.query(
      'customers',
      where: 'name = ?',
      whereArgs: [name],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Customer.fromMap(rows.first);
  }

  /// Case-insensitive search by name (first match).
  static Future<Customer?> getByNameInsensitive(String name) async {
    final db = await DbHelper.instance.database;
    // Use COLLATE NOCASE for case-insensitive match
    final maps = await db.query(
      'customers',
      where: 'name COLLATE NOCASE = ?',
      whereArgs: [name],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Customer.fromMap(maps.first);
  }

  /// Search by phone (exact)
  static Future<Customer?> getByPhone(String phone) async {
    final db = await DbHelper.instance.database;
    final maps = await db.query(
      'customers',
      where: 'phone = ?',
      whereArgs: [phone],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Customer.fromMap(maps.first);
  }

  /// Find customer by name or phone; if not found create a new customer and return it.
  ///
  /// Usage:
  ///   final c = await CustomerDb.addOrGetByNamePhone(name: 'Ali', phone: '0123');
  static Future<Customer> addOrGetByNamePhone({
    required String name,
    String? phone,
  }) async {
    final db = await DbHelper.instance.database;

    // Build query: try to match by phone first (more specific), then by name.
    if (phone != null && phone.isNotEmpty) {
      final byPhone = await getByPhone(phone);
      if (byPhone != null) return byPhone;
    }

    if (name.isNotEmpty) {
      final byName = await getByNameInsensitive(name);
      if (byName != null) return byName;
    }

    // Not found → create new
    final newCustomer = Customer(
      id: generateId(),
      name: name,
      phone: phone,
      notes: null,
    );

    await insert(newCustomer);
    return newCustomer;
  }

  /// Update an existing customer (by id). If id not found nothing happens.
  static Future<void> update(Customer c) async {
    final db = await DbHelper.instance.database;
    await db.update("customers", c.toMap(), where: "id = ?", whereArgs: [c.id]);
  }

  /// Delete customer by id.
  static Future<void> delete(String id) async {
    final db = await DbHelper.instance.database;
    await db.delete("customers", where: "id = ?", whereArgs: [id]);
  }

  /// Simple search: returns customers whose name contains [query] (case-insensitive).
  static Future<List<Customer>> searchByName(String query) async {
    final db = await DbHelper.instance.database;
    if (query.trim().isEmpty) return getAll();
    final maps = await db.rawQuery(
      "SELECT * FROM customers WHERE name LIKE ? COLLATE NOCASE ORDER BY name",
      ['%$query%'],
    );
    return maps.map((e) => Customer.fromMap(e)).toList();
  }
}
