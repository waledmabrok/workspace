import 'dart:convert';
import 'package:sqflite/sqflite.dart';
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
    final path = join(dbPath, 'workspace25.db');

    _database = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 11,
        onCreate: _onCreate,

        onOpen: (db) async {
          await _ensureSalesColumns(db);
          await _ensureFinanceTables(db);
          await _ensureSubscriptionsColumns(db);
          await _ensureSessionsColumns(db);
          await _ensureShiftsColumns(db);
          await _ensureShiftTables(db);
          await _ensureRoomsColumns(db);
          await _ensurePricingSettingsRoom(db);
          await migrateSalesTable(db);
          await _ensureNotificationsTable(db);
          await _ensureCashiersTable(db);
          await migrateCashiers(db);
          await ensureCashierIdColumn(db);
          await _ensureExpensesColumns(db);
        },
      ),
    );

    return _database!;
  }

  Future<void> ensureCashierIdColumn(Database db) async {
    final cols = await db.rawQuery('PRAGMA table_info(shifts)');
    final colNames = cols.map((c) => c['name'] as String).toList();
    if (!colNames.contains('cashierId')) {
      await db.execute('ALTER TABLE shifts ADD COLUMN cashierId TEXT');
    }
  }

  Future<void> migrateCashiers(Database db) async {
    final cols = await db.rawQuery('PRAGMA table_info(cashiers)');
    final colNames = cols.map((c) => c['name'] as String).toList();

    if (!colNames.contains('username')) {
      await db.execute('''
      CREATE TABLE cashiers_new (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        username TEXT UNIQUE,
        password TEXT NOT NULL
      )
    ''');

      // نسخ البيانات القديمة
      final oldRows = await db.query('cashiers');
      for (final row in oldRows) {
        await db.insert('cashiers_new', {
          'id': row['id'],
          'name': row['name'],
          'password': row['password'],
          'username': row['name'], // استخدام الاسم كـ username افتراضي
        });
      }

      // حذف الجدول القديم
      await db.execute('DROP TABLE cashiers');
      // إعادة التسمية
      await db.execute('ALTER TABLE cashiers_new RENAME TO cashiers');
    }
  }

  Future<void> _ensurePricingSettingsRoom(Database db) async {
    // إنشاء الجدول إذا مش موجود
    await db.execute('''
    CREATE TABLE IF NOT EXISTS pricing_settings_Room (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      firstFreeMinutesRoom INTEGER DEFAULT 15,
      firstHourFeeRoom REAL DEFAULT 30,
      perHourAfterFirstRoom REAL DEFAULT 20,
      dailyCapRoom REAL DEFAULT 150
    )
  ''');

    // التأكد من وجود صف واحد على الأقل
    final rows = await db.query('pricing_settings_Room', limit: 1);
    if (rows.isEmpty) {
      await db.insert('pricing_settings_Room', {
        'firstFreeMinutesRoom': 15,
        'firstHourFeeRoom': 30,
        'perHourAfterFirstRoom': 20,
        'dailyCapRoom': 150,
      });
    }
  }

  Future<double> getClosingBalance() async {
    final db = await database;
    final rows = await db.query(
      'drawer',
      where: 'id = ?',
      whereArgs: [1],
      limit: 1,
    );
    return (rows.first['balance'] as num?)?.toDouble() ?? 0.0;
  }

  // ✅ تجيب آخر شيفت مفتوح
  Future<Map<String, dynamic>?> getCurrentShift() async {
    final db = await instance.database;
    final res = await db.query(
      'shifts',
      where: 'closed_at IS NULL',
      orderBy: 'id DESC',
      limit: 1,
    );
    return res.isNotEmpty ? res.first : null;
  }

  Future<Map<String, dynamic>?> getCurrentShiftForCashier(
    String cashierName,
  ) async {
    final db = await database;
    final rows = await db.query(
      'shifts',
      where: 'closed_at IS NULL AND cashierName = ?',
      whereArgs: [cashierName],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final shift = rows.first;
    final summary = await getShiftSummary(shift['id'] as int);

    return {
      "id":shift['id'] as String,
      "cashierName": shift['cashierName'],
      "opened_at": shift['opened_at'],
      "openingBalance": shift['openingBalance'],
      "closingBalance": shift['closingBalance'],
      "sales": summary['sales'],
      "expenses": summary['expenses'],
      "profit": summary['profit'],
    };
  }

  Future<void> _ensureCashiersTable(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS cashiers (
  id TEXT PRIMARY KEY,
  username TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  password TEXT NOT NULL
)
''');
  }

  Future<void> _ensureNotificationsTable(Database db) async {
    try {
      await db.execute('''
      CREATE TABLE IF NOT EXISTS notifications (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sessionId TEXT,
        type TEXT,          -- expiring / expired / dailyLimit
        message TEXT,
        isRead INTEGER DEFAULT 0,
        isDeleted INTEGER DEFAULT 0,
        createdAt INTEGER DEFAULT (strftime('%s','now') * 1000),
        UNIQUE(sessionId, type) ON CONFLICT IGNORE
      )
    ''');

      // لو الجدول قديم ومفيهوش العمود نزوده
      final cols = await db.rawQuery('PRAGMA table_info(notifications)');
      final colNames = cols.map((c) => c['name'] as String).toList();
      if (!colNames.contains('isDeleted')) {
        await db.execute(
          'ALTER TABLE notifications ADD COLUMN isDeleted INTEGER DEFAULT 0',
        );
      }
    } catch (e) {
      debugPrint('[_ensureNotificationsTable] error: $e');
    }
  }

  Future<void> _ensureRoomsColumns(Database db) async {
    final cols = await db.rawQuery('PRAGMA table_info(rooms)');
    final colNames = cols.map((c) => c['name'] as String).toList();

    if (!colNames.contains('firstFreeMinutesRoom')) {
      await db.execute(
        'ALTER TABLE rooms ADD COLUMN firstFreeMinutesRoom INTEGER DEFAULT 15',
      );
    }
    if (!colNames.contains('firstHourFeeRoom')) {
      await db.execute(
        'ALTER TABLE rooms ADD COLUMN firstHourFeeRoom REAL DEFAULT 30.0',
      );
    }
    if (!colNames.contains('perHourAfterFirstRoom')) {
      await db.execute(
        'ALTER TABLE rooms ADD COLUMN perHourAfterFirstRoom REAL DEFAULT 20.0',
      );
    }
    if (!colNames.contains('dailyCapRoom')) {
      await db.execute(
        'ALTER TABLE rooms ADD COLUMN dailyCapRoom REAL DEFAULT 150.0',
      );
    }
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

    //notification
    await db.execute('''
   CREATE TABLE IF NOT EXISTS notifications (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  sessionId TEXT,
  type TEXT,          -- expiring / expired / dailyLimit
  message TEXT,
  isRead INTEGER DEFAULT 0,
  createdAt TEXT,
  UNIQUE(sessionId, type) ON CONFLICT IGNORE
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
  basePrice REAL, -- السعر الأساسي للغرفة للساعة أو للعدد الأساسي من الأشخاص
  firstFreeMinutesRoom INTEGER,
firstHourFeeRoom REAL,
perHourAfterFirstRoom REAL,
dailyCapRoom REAL

);

    ''');
    await db.execute('''
  CREATE TABLE IF NOT EXISTS pricing_settings_Room (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  firstFreeMinutesRoom INTEGER DEFAULT 15,
  firstHourFeeRoom REAL DEFAULT 30,
  perHourAfterFirstRoom REAL DEFAULT 20,
  dailyCapRoom REAL DEFAULT 150
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
    // جدول الكاشيرز الجديد
    await db.execute('''
    CREATE TABLE IF NOT EXISTS cashiers (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      password TEXT NOT NULL
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
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    opened_at TEXT,
    closed_at TEXT,
    cashier_name TEXT,
    drawer_balance REAL,
    total_sales REAL
  )
''');

// الشيفتات
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
    // داخل _onCreate(...) بعد تعريف جداول shifts
    await db.execute('''
  CREATE TABLE IF NOT EXISTS shift_reports (
    id TEXT PRIMARY KEY,
    shiftId TEXT,
    reportJson TEXT,
    createdAt INTEGER
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
  Future<void> _ensureExpensesColumns(Database db) async {
    final cols = await db.rawQuery('PRAGMA table_info(expenses)');
    final colNames = cols.map((c) => c['name'] as String).toList();
    if (!colNames.contains('shiftId')) {
      await db.execute('ALTER TABLE expenses ADD COLUMN shiftId TEXT');
    }
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
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  cashierId TEXT,
  cashierName TEXT,
  opened_at TEXT,
  closed_at TEXT,
  openingBalance REAL,
  closingBalance REAL,
  totalSales REAL,
  totalExpenses REAL
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
      if (!colNames.contains('opened_at')) {
        await db.execute('ALTER TABLE shifts ADD COLUMN opened_at TEXT');
      }
      if (!colNames.contains('closed_at')) {
        await db.execute('ALTER TABLE shifts ADD COLUMN closed_at TEXT');
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
      id TEXT PRIMARY KEY,
      cashierId TEXT,
      cashierName TEXT,
      opened_at TEXT,
      closed_at TEXT,
      openingBalance REAL,
      closingBalance REAL,
      totalSales REAL,
      totalExpenses REAL
    )
  ''');
  }

  // ---------------- إدارة الشيفت ----------------

  Future<int> openShift(String cashierName, {double openingBalance = 0.0}) async {
    final db = await instance.database;
    return await db.insert('shifts', {
      'opened_at': DateTime.now().toIso8601String(),
      'cashierName': cashierName,
      'openingBalance': openingBalance,
      'closingBalance': 0.0,
      'totalSales': 0.0,
      'totalExpenses': 0.0,
    });
  }


  Future<void> closeShift(int shiftId, double closingBalance, String cashierName) async {
    final db = await instance.database;

    await db.update(
      'shifts',
      {
        'closed_at': DateTime.now().toIso8601String(),
        'cashier_name': cashierName,
        'drawer_balance': closingBalance,
      },
      where: 'id = ?',
      whereArgs: [shiftId],
    );

    // جلب الشيفت بعد التحديث
    final updatedShift = await db.query(
      'shifts',
      where: 'id = ?',
      whereArgs: [shiftId],
      limit: 1,
    );

    if (updatedShift.isNotEmpty) {
      print('✅ بيانات الشيفت بعد التقفيل:');
      print(updatedShift.first);
    } else {
      print('⚠️ لم يتم العثور على الشيفت بعد التحديث.');
    }
  }




  Future<List<Map<String, dynamic>>> getAllShifts() async {
    final db = await instance.database;
    return await db.query('shifts', orderBy: 'id DESC');
  }


  /*Future<void> closeShift(
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
  }*/

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
    final db = await DbHelper.instance.database;
    return db.rawQuery('''
    SELECT
      id,
      cashier_name AS cashierName,
      opened_at AS openedAt,
      closed_at AS closedAt,
      drawer_balance AS openingBalance,
      total_sales AS closingBalance
    FROM shifts
    ORDER BY opened_at DESC
  ''');
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

  Future<Map<String, dynamic>> getShiftSummary(int shiftId) async {
    final db = await instance.database;

    // المبيعات
    final sales = Sqflite.firstIntValue(await db.rawQuery(
      "SELECT SUM(COALESCE(amount,0) - COALESCE(discount,0)) "
          "FROM sales WHERE shiftId = ?",
      [shiftId],
    )) ?? 0;

    // المصروفات
    // لو هتربط بالشيفت، لازم تضيف shiftId في جدول expenses أولًا
    final expenses = Sqflite.firstIntValue(await db.rawQuery(
      "SELECT SUM(COALESCE(amount,0)) FROM expenses WHERE shiftId = ?",
      [shiftId],
    )) ?? 0;

    // الرصيد الافتتاحي
    final result = await db.query(
      "shifts",
      columns: ["openingBalance"],
      where: "id = ?",
      whereArgs: [shiftId],
      limit: 1,
    );

    final openingBalance = result.isNotEmpty
        ? (result.first["openingBalance"] as num?)?.toDouble() ?? 0.0
        : 0.0;

    return {
      "sales": sales.toDouble(),
      "expenses": expenses.toDouble(),
      "openingBalance": openingBalance,
      "profit": (sales - expenses).toDouble(),
      "currentBalance": (openingBalance + sales - expenses).toDouble(),
    };
  }

  //////////////////////////////////////
  // helper id generator (لو مش عندك)
  String _genId() => DateTime.now().millisecondsSinceEpoch.toString();

  /// حفظ تقرير شيفت
  Future<void> saveShiftReport(
    String id,
    String shiftId,
    Map<String, dynamic> report,
    DatabaseExecutor txn,
  ) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await txn.insert('shift_reports', {
      'id': id,
      'shiftId': shiftId,
      'reportJson': jsonEncode(report),
      'createdAt': nowMs,
    });
  }

  /// تقفيل شيفت مفصل وحفظ تقرير
  Future<Map<String, dynamic>> closeShiftDetailed(
    String shiftId, {
    double? countedClosingBalance,
    String? cashierName,
  }) async {
    final db = await database;

    return await db.transaction((txn) async {
      // 1) جلب الشيفت
      final shiftRows = await txn.query(
        'shifts',
        where: 'id = ?',
        whereArgs: [shiftId],
        limit: 1,
      );
      if (shiftRows.isEmpty) {
        throw Exception('Shift not found: $shiftId');
      }
      final shift = shiftRows.first;

      // parse openedAt (could be TEXT ISO or INTEGER ms)
      DateTime opened_at;
      final openedRaw = shift['opened_at'];
      if (openedRaw == null) {
        opened_at = DateTime.now();
      } else if (openedRaw is int) {
        opened_at = DateTime.fromMillisecondsSinceEpoch(openedRaw);
      } else {
        final maybeInt = int.tryParse(openedRaw.toString());
        if (maybeInt != null) {
          opened_at = DateTime.fromMillisecondsSinceEpoch(maybeInt);
        } else {
          try {
            opened_at = DateTime.parse(openedRaw.toString());
          } catch (_) {
            opened_at = DateTime.now();
          }
        }
      }

      final closed_at = DateTime.now();
      final openedMs = opened_at.millisecondsSinceEpoch;
      final closedMs = closed_at.millisecondsSinceEpoch;

      // 2) المبيعات بحسب طريقة الدفع (نحسب صافي = amount - discount)
      final salesByMethod = await txn.rawQuery(
        '''
      SELECT
        COALESCE(paymentMethod, 'cash') AS paymentMethod,
        SUM(COALESCE(amount,0) - COALESCE(discount,0)) AS total,
        COUNT(*) as count
      FROM sales
      WHERE shiftId = ?
      GROUP BY paymentMethod
    ''',
        [shiftId],
      );

      double totalSales = 0.0;
      Map<String, double> salesByPaymentMethod = {};

      if (salesByMethod.isEmpty) {
        // fallback: استخدم نطاق التاريخ
        final fallback = await txn.rawQuery(
          '''
        SELECT
          COALESCE(paymentMethod, 'cash') AS paymentMethod,
          SUM(COALESCE(amount,0) - COALESCE(discount,0)) AS total,
          COUNT(*) as count
        FROM sales
        WHERE date BETWEEN ? AND ?
        GROUP BY paymentMethod
      ''',
          [openedMs, closedMs],
        );

        for (final r in fallback) {
          final pm = r['paymentMethod']?.toString() ?? 'cash';
          final t = (r['total'] as num?)?.toDouble() ?? 0.0;
          salesByPaymentMethod[pm] = t;
          totalSales += t;
        }

        // optional: bind those sales to shiftId
        try {
          await txn.rawUpdate(
            '''
          UPDATE sales
          SET shiftId = ?
          WHERE (shiftId IS NULL OR shiftId = '') AND date BETWEEN ? AND ?
        ''',
            [shiftId, openedMs, closedMs],
          );
        } catch (_) {}
      } else {
        for (final r in salesByMethod) {
          final pm = r['paymentMethod']?.toString() ?? 'cash';
          final t = (r['total'] as num?)?.toDouble() ?? 0.0;
          salesByPaymentMethod[pm] = t;
          totalSales += t;
        }

        // أيضاً: قد تكون مبيعات ضمن النطاق بدون shiftId — نربطها (اختياري)
        try {
          await txn.rawUpdate(
            '''
          UPDATE sales
          SET shiftId = ?
          WHERE (shiftId IS NULL OR shiftId = '') AND date BETWEEN ? AND ?
        ''',
            [shiftId, openedMs, closedMs],
          );
        } catch (_) {}
      }

      // 3) مصروفات: من expenses داخل النطاق + من shift_transactions
      final expensesFromExpensesTable = await txn.rawQuery(
        '''
      SELECT SUM(COALESCE(amount,0)) as total
      FROM expenses
      WHERE date BETWEEN ? AND ?
    ''',
        [openedMs, closedMs],
      );
      final expenses1 =
          (expensesFromExpensesTable.first['total'] as num?)?.toDouble() ?? 0.0;

      final expensesFromShiftTx = await txn.rawQuery(
        '''
      SELECT SUM(COALESCE(amount,0)) as total
      FROM shift_transactions
      WHERE shiftId = ? AND type = 'expense'
    ''',
        [shiftId],
      );
      final expenses2 =
          (expensesFromShiftTx.first['total'] as num?)?.toDouble() ?? 0.0;

      final totalExpenses = expenses1 + expenses2;

      // 4) ملخص shift_transactions
      final txSummaryRows = await txn.rawQuery(
        '''
      SELECT type, SUM(COALESCE(amount,0)) as total
      FROM shift_transactions
      WHERE shiftId = ?
      GROUP BY type
    ''',
        [shiftId],
      );

      double deposits = 0.0;
      double withdrawals = 0.0;
      double txSales = 0.0;
      for (final r in txSummaryRows) {
        final type = r['type']?.toString() ?? '';
        final total = (r['total'] as num?)?.toDouble() ?? 0.0;
        if (type == 'deposit')
          deposits += total;
        else if (type == 'withdraw')
          withdrawals += total;
        else if (type == 'sale')
          txSales += total;
      }

      // 5) opening balance
      final openingBalance =
          (shift['openingBalance'] as num?)?.toDouble() ?? 0.0;

      // 6) حساب المتوقع: opening + نقديات + deposits - withdrawals - expenses
      final cashSales = salesByPaymentMethod['cash'] ?? 0.0;
      final expectedClosingBalance =
          openingBalance + cashSales + deposits - withdrawals - totalExpenses;

      // 7) final closing
      final finalClosingBalance =
          countedClosingBalance ?? expectedClosingBalance;

      // 8) حدّث drawer (id=1)
      try {
        await txn.rawUpdate('UPDATE drawer SET balance = ? WHERE id = 1', [
          finalClosingBalance,
        ]);
      } catch (_) {
        try {
          await txn.insert('drawer', {'id': 1, 'balance': finalClosingBalance});
        } catch (_) {}
      }

      // 9) حدّث جدول الشيفت
      final updateMap = {
        'closed_at': closed_at.toIso8601String(),
        'closingBalance': finalClosingBalance,
        'cashierName': cashierName ?? shift['cashierName'],
        'totalSales': totalSales,
        'totalExpenses': totalExpenses,
      };
      await txn.update(
        'shifts',
        updateMap,
        where: 'id = ?',
        whereArgs: [shiftId],
      );

      // 10) جهّز التقرير
      final report = {
        'shiftId': shiftId,
        'opened_at': opened_at.toIso8601String(),
        'closed_at': closed_at.toIso8601String(),
        'openingBalance': openingBalance,
        'countedClosingBalance': countedClosingBalance,
        'computedClosingBalance': expectedClosingBalance,
        'finalClosingBalance': finalClosingBalance,
        'totalSales': totalSales,
        'salesByPaymentMethod': salesByPaymentMethod,
        'totalExpenses': totalExpenses,
        'expensesFromExpensesTable': expenses1,
        'expensesFromShiftTransactions': expenses2,
        'deposits': deposits,
        'withdrawals': withdrawals,
        'txSales': txSales,
        'savedAt': DateTime.now().toIso8601String(),
      };

      // 11) حفظ التقرير في shift_reports
      final reportId = _genId();
      await saveShiftReport(reportId, shiftId, report, txn);

      return report;
    });
  }// في DbHelper


  Future<Map<String, dynamic>?> getLastClosedShift() async {
    final db = await database;
    final result = await db.query(
      'shifts',
      where: 'closed_at IS NOT NULL',
      orderBy: 'id DESC',
      limit: 1,
    );
    if (result.isEmpty) return null;
    return result.first;
  }


}
