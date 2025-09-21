import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';

import 'db_helper_shifts.dart';

class DbHelper {
  DbHelper._();
  static final DbHelper instance = DbHelper._();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;

    sqfliteFfiInit();
    final databaseFactory = databaseFactoryFfi;

    final dbPath = await databaseFactory.getDatabasesPath();
    final path = join(dbPath, 'workspace6.db');

    _database = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 6,
        onCreate: _onCreate,

        onOpen: (db) async {
          await _ensureSalesColumns(db);
          await _ensureFinanceTables(db);
          await _ensureSubscriptionsColumns(db);
          await _ensureSessionsColumns(db);
          await _ensureShiftsColumns(db);
          await _ensureShiftTables(db);
          await migrateSalesTable(db);
        },
      ),
    );

    return _database!;
  }

  Future<void> migrateSalesTable(Database db) async {
    final cols = await db.rawQuery('PRAGMA table_info(sales)');
    final colNames = cols.map((c) => c['name'] as String).toList();

    if (!colNames.contains('shiftId')) {
      await db.execute('ALTER TABLE sales ADD COLUMN shiftId TEXT;');
    }
  }

  // ---------------- onCreate ----------------
  Future<void> _onCreate(Database db, int version) async {
    // إعداد جدول الاشتراكات
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
        isUnlimited INTEGER,
        endDate INTEGER
      )
    ''');

    // إعداد جدول الجلسات
    await db.execute('''
      CREATE TABLE sessions(
        id TEXT PRIMARY KEY,
        name TEXT,
        start INTEGER,
        end INTEGER,
        amountPaid REAL,
        subscriptionId TEXT,
        isActive INTEGER,
        isPaused INTEGER,
        elapsedMinutes INTEGER,
          frozenMinutes INTEGER DEFAULT 0, 
        type TEXT,
        paidMinutes INTEGER DEFAULT 0,
        pauseStart INTEGER,
        customerId TEXT,
       events TEXT,
  savedSubscriptionJson TEXT,
  resumeNextDayRequested INTEGER DEFAULT 0,
  resumeDate INTEGER
      )
    ''');

    // جدول علاقة العميل بالاشتراك
    await db.execute('''
      CREATE TABLE customer_subscriptions (
        id TEXT PRIMARY KEY,
        customerId TEXT,
        subscriptionPlanId TEXT,
        startDate INTEGER,
        endDate INTEGER,
        FOREIGN KEY(customerId) REFERENCES customers(id),
        FOREIGN KEY(subscriptionPlanId) REFERENCES subscriptions(id)
      )
    ''');

    // المنتجات
    await db.execute('''
      CREATE TABLE products (
        id TEXT PRIMARY KEY,
        name TEXT,
        price REAL,
        stock INTEGER
      )
    ''');

    // سلة المنتجات
    await db.execute('''
      CREATE TABLE cart_items(
        id TEXT PRIMARY KEY,
        sessionId TEXT,
        productId TEXT,
        qty INTEGER
      )
    ''');

    // الغرفه
    await db.execute('''
      CREATE TABLE  rooms (
  id TEXT PRIMARY KEY,
  name TEXT,
  basePrice REAL -- السعر الأساسي للغرفة للساعة أو للعدد الأساسي من الأشخاص
);

    ''');
    // الغرفه
    await db.execute('''
   CREATE TABLE room_bookings (
  id TEXT PRIMARY KEY,
  roomId TEXT,
  customerName TEXT,
  numPersons INTEGER,
  startTime INTEGER,
  endTime INTEGER, -- هيفضل NULL لحد ما يقفل الكاشير الحجز
  price REAL,
  status TEXT DEFAULT 'open', -- open / closed
  FOREIGN KEY(roomId) REFERENCES rooms(id)
);


    ''');

    // المصروفات
    await db.execute('''
      CREATE TABLE expenses(
        id TEXT PRIMARY KEY,
        title TEXT,
        amount REAL,
        date INTEGER
      )
    ''');

    // المبيعات
    await db.execute('''
      CREATE TABLE sales(
      
        id TEXT PRIMARY KEY,
        description TEXT,
        amount REAL,
        discount REAL,
        date INTEGER,
        paymentMethod TEXT,
        customerId TEXT,
        customerName TEXT,
         shiftId TEXT
      )
    ''');

    // الخصومات
    await db.execute('''
      CREATE TABLE discounts (
        id TEXT PRIMARY KEY,
        code TEXT,
        percent REAL,
        expiry INTEGER,
        singleUse INTEGER,
        used INTEGER
      )
    ''');

    // العملاء
    await db.execute('''
      CREATE TABLE customers (
        id TEXT PRIMARY KEY,
        name TEXT,
        phone TEXT,
        notes TEXT
      )
    ''');

    // أرصدة العملاء
    await db.execute('''
      CREATE TABLE customer_balances (
        customerId TEXT PRIMARY KEY,
        balance REAL,
        FOREIGN KEY(customerId) REFERENCES customers(id)
      )
    ''');

    // الدرج النقدي
    await db.execute('''
      CREATE TABLE drawer (
        id INTEGER PRIMARY KEY,
        balance REAL
      )
    ''');
    await db.insert('drawer', {'id': 1, 'balance': 0.0});

    // الشيفتات
    await db.execute('''
      CREATE TABLE shifts (
        id TEXT PRIMARY KEY,
        closed_at INTEGER,
        signers TEXT,
        drawer_balance REAL,
        total_sales REAL
      )
    '''); // الشيفتات
    await db.execute('''
      CREATE TABLE shift_transactions (
  id TEXT PRIMARY KEY,
  shiftId TEXT,
  type TEXT, -- sale / expense
  amount REAL,
  description TEXT,
  createdAt INTEGER,
  FOREIGN KEY (shiftId) REFERENCES shifts(id)
) ''');

    // إعداد جدول التسعير
    await db.execute('''
      CREATE TABLE pricing_settings (
        id INTEGER PRIMARY KEY,
        firstFreeMinutes INTEGER,
        firstHourFee REAL,
        perHourAfterFirst REAL,
        dailyCap REAL
      )
    ''');
    await db.insert("pricing_settings", {
      'id': 1,
      'firstFreeMinutes': 15,
      'firstHourFee': 30,
      'perHourAfterFirst': 20,
      'dailyCap': 150,
    });
  }

  // ---------------- أدوات مساعدة ----------------
  Future<void> _ensureSalesColumns(Database db) async {
    try {
      final cols = await db.rawQuery('PRAGMA table_info(sales)');
      final colNames = cols.map((c) => c['name'] as String).toList();

      if (!colNames.contains('discount')) {
        await db.execute(
          'ALTER TABLE sales ADD COLUMN discount REAL DEFAULT 0.0',
        );
      }
      if (!colNames.contains('shiftId')) {
        await db.execute('ALTER TABLE sales ADD COLUMN shiftId TEXT');
      }
      if (!colNames.contains('paymentMethod')) {
        await db.execute('ALTER TABLE sales ADD COLUMN paymentMethod TEXT');
      }
      if (!colNames.contains('customerId')) {
        await db.execute('ALTER TABLE sales ADD COLUMN customerId TEXT');
      }
      if (!colNames.contains('customerName')) {
        await db.execute('ALTER TABLE sales ADD COLUMN customerName TEXT');
      }
    } catch (_) {}
  }

  Future<void> _ensureSessionsColumns(Database db) async {
    try {
      final cols = await db.rawQuery('PRAGMA table_info(sessions)');
      final colNames = cols.map((c) => c['name'] as String).toList();

      if (!colNames.contains('events')) {
        await db.execute('ALTER TABLE sessions ADD COLUMN events TEXT');
      }
      if (!colNames.contains('savedSubscriptionJson')) {
        await db.execute(
          'ALTER TABLE sessions ADD COLUMN savedSubscriptionJson TEXT',
        );
      }
      if (!colNames.contains('resumeNextDayRequested')) {
        await db.execute(
          'ALTER TABLE sessions ADD COLUMN resumeNextDayRequested INTEGER DEFAULT 0',
        );
      }
      if (!colNames.contains('resumeDate')) {
        await db.execute('ALTER TABLE sessions ADD COLUMN resumeDate INTEGER');
      }
      if (!colNames.contains('savedSubscriptionEnd')) {
        await db.execute(
          'ALTER TABLE sessions ADD COLUMN savedSubscriptionEnd TEXT',
        );
      }
      if (!colNames.contains('savedSubscriptionConvertedAt')) {
        await db.execute(
          'ALTER TABLE sessions ADD COLUMN savedSubscriptionConvertedAt INTEGER',
        );
      }
      // جديد: ensure runningSince exists (INTEGER msSinceEpoch)
      if (!colNames.contains('runningSince')) {
        await db.execute(
          'ALTER TABLE sessions ADD COLUMN runningSince INTEGER',
        );
        debugPrint('[_ensureSessionsColumns] Added runningSince column');
      }

      // ===== جديد: ensure frozenMinutes exists =====
      if (!colNames.contains('frozenMinutes')) {
        await db.execute(
          'ALTER TABLE sessions ADD COLUMN frozenMinutes INTEGER DEFAULT 0',
        );
        debugPrint('[_ensureSessionsColumns] Added frozenMinutes column');
      }
      if (!colNames.contains('elapsedMinutesPayg')) {
        await db.execute(
          'ALTER TABLE sessions ADD COLUMN elapsedMinutesPayg INTEGER DEFAULT 0;',
        );
        debugPrint('[_ensureSessionsColumns] Added elapsedMinutesPayg column');
      }
      if (!colNames.contains('originalSubscriptionId')) {
        await db.execute(
          'ALTER TABLE sessions ADD COLUMN originalSubscriptionId TEXT',
        );
        debugPrint(
          '[_ensureSessionsColumns] Added originalSubscriptionId column',
        );
      }
    } catch (e) {
      debugPrint('[_ensureSessionsColumns] migration error: $e');
    }
  }

  Future<void> _ensureFinanceTables(Database db) async {
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS customer_balances (
          customerId TEXT PRIMARY KEY,
          balance REAL,
          FOREIGN KEY(customerId) REFERENCES customers(id)
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS drawer (
          id INTEGER PRIMARY KEY,
          balance REAL
        )
      ''');

      final rows = await db.query(
        'drawer',
        where: 'id = ?',
        whereArgs: [1],
        limit: 1,
      );
      if (rows.isEmpty) {
        await db.insert('drawer', {'id': 1, 'balance': 0.0});
      }

      await db.execute('''
        CREATE TABLE IF NOT EXISTS shifts (
          id TEXT PRIMARY KEY,
          closed_at INTEGER,
          signers TEXT,
          drawer_balance REAL,
          total_sales REAL
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS customer_subscriptions (
          id TEXT PRIMARY KEY,
          customerId TEXT,
          subscriptionPlanId TEXT,
          startDate INTEGER,
          endDate INTEGER,
          FOREIGN KEY(customerId) REFERENCES customers(id),
          FOREIGN KEY(subscriptionPlanId) REFERENCES subscriptions(id)
        )
      ''');
    } catch (_) {}
  }

  Future<void> _ensureShiftsColumns(Database db) async {
    try {
      final cols = await db.rawQuery('PRAGMA table_info(shifts)');
      final colNames = cols.map((c) => c['name'] as String).toList();

      if (!colNames.contains('cashierName')) {
        await db.execute('ALTER TABLE shifts ADD COLUMN cashierName TEXT');
      }
      if (!colNames.contains('openedAt')) {
        await db.execute('ALTER TABLE shifts ADD COLUMN openedAt TEXT');
      }
      if (!colNames.contains('closedAt')) {
        await db.execute('ALTER TABLE shifts ADD COLUMN closedAt TEXT');
      }
      if (!colNames.contains('openingBalance')) {
        await db.execute('ALTER TABLE shifts ADD COLUMN openingBalance REAL');
      }
      if (!colNames.contains('closingBalance')) {
        await db.execute('ALTER TABLE shifts ADD COLUMN closingBalance REAL');
      }
      if (!colNames.contains('totalSales')) {
        await db.execute('ALTER TABLE shifts ADD COLUMN totalSales REAL');
      }
      if (!colNames.contains('totalExpenses')) {
        await db.execute('ALTER TABLE shifts ADD COLUMN totalExpenses REAL');
      }
    } catch (e) {
      debugPrint('[_ensureShiftsColumns] migration error: $e');
    }
  }

  // ---------------- تحديث جدول subscriptions ----------------
  Future<void> _ensureSubscriptionsColumns(Database db) async {
    try {
      final cols = await db.rawQuery('PRAGMA table_info(subscriptions)');
      final colNames = cols.map((c) => c['name'] as String).toList();

      if (!colNames.contains('dailyUsageType')) {
        await db.execute(
          'ALTER TABLE subscriptions ADD COLUMN dailyUsageType TEXT',
        );
      }
      if (!colNames.contains('dailyUsageHours')) {
        await db.execute(
          'ALTER TABLE subscriptions ADD COLUMN dailyUsageHours INTEGER',
        );
      }
      if (!colNames.contains('weeklyHours')) {
        await db.execute(
          'ALTER TABLE subscriptions ADD COLUMN weeklyHours TEXT',
        );
      }
      if (!colNames.contains('isUnlimited')) {
        await db.execute(
          'ALTER TABLE subscriptions ADD COLUMN isUnlimited INTEGER DEFAULT 0',
        );
      }
      if (!colNames.contains('endDate')) {
        await db.execute(
          'ALTER TABLE subscriptions ADD COLUMN endDate INTEGER',
        );
      }
    } catch (_) {}
  }

  ///===========================sfift
  Future<void> _ensureShiftTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS shifts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      cashierId TEXT,
      cashierName TEXT,
      openedAt TEXT,
      closedAt TEXT,
      openingBalance REAL,
      closingBalance REAL,
      totalSales REAL,
      totalExpenses REAL
    )
  ''');
  }

  // ---------------- إدارة الشيفت ----------------
  Future<void> openShift({
    required String id,
    required String cashierName,
    required double openingBalance,
  }) async {
    final db = await database;
    await db.insert("shifts", {
      "id": id,
      "cashierName": cashierName,
      "openedAt": DateTime.now().toIso8601String(),
      "openingBalance": openingBalance,
      "closingBalance": null,
      "totalSales": 0.0,
      "totalExpenses": 0.0,
    });
  }

  Future<void> closeShift(
    String shiftId,
    double closingBalance,
    String cashierName,
  ) async {
    final db = await database;

    final sales = await db.rawQuery(
      "SELECT SUM(amount) as total FROM shift_transactions WHERE shiftId = ? AND type = 'sale'",
      [shiftId],
    );
    final expenses = await db.rawQuery(
      "SELECT SUM(amount) as total FROM shift_transactions WHERE shiftId = ? AND type = 'expense'",
      [shiftId],
    );

    final totalSales = (sales.first["total"] as num?)?.toDouble() ?? 0.0;
    final totalExpenses = (expenses.first["total"] as num?)?.toDouble() ?? 0.0;

    await db.update(
      "shifts",
      {
        "closedAt": DateTime.now().toIso8601String(),
        "closingBalance": closingBalance,
        "cashierName": cashierName,
        "totalSales": totalSales,
        "totalExpenses": totalExpenses,
      },
      where: "id = ?",
      whereArgs: [shiftId],
    );
  }

  // ---------------- الحركات ----------------
  Future<void> addTransaction({
    required String id,
    required String shiftId,
    required String type, // sale / expense / deposit / withdraw
    required double amount,
    required String description,
  }) async {
    final db = await database;
    await db.insert("shift_transactions", {
      "id": id,
      "shiftId": shiftId,
      "type": type,
      "amount": amount,
      "description": description,
      "createdAt": DateTime.now().toIso8601String(),
    });
  }

  // ---------------- الاستعلامات ----------------
  Future<List<Map<String, dynamic>>> getShifts() async {
    final db = await database;
    return db.query("shifts", orderBy: "openedAt DESC");
  }

  Future<List<Map<String, dynamic>>> getTransactions(String shiftId) async {
    final db = await database;
    return db.query(
      "shift_transactions",
      where: "shiftId = ?",
      whereArgs: [shiftId],
      orderBy: "createdAt DESC",
    );
  }

  Future<Map<String, double>> getShiftSummary(String shiftId) async {
    final db = await database;

    final sales = await db.rawQuery(
      "SELECT SUM(amount) as total FROM shift_transactions WHERE shiftId = ? AND type = 'sale'",
      [shiftId],
    );
    final expenses = await db.rawQuery(
      "SELECT SUM(amount) as total FROM shift_transactions WHERE shiftId = ? AND type = 'expense'",
      [shiftId],
    );

    return {
      "sales": (sales.first["total"] as num?)?.toDouble() ?? 0.0,
      "expenses": (expenses.first["total"] as num?)?.toDouble() ?? 0.0,
      "profit":
          ((sales.first["total"] as num?)?.toDouble() ?? 0.0) -
          ((expenses.first["total"] as num?)?.toDouble() ?? 0.0),
    };
  }
}
