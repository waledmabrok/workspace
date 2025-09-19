/*
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';

class DbHelper {
  DbHelper._();
  static final DbHelper instance = DbHelper._();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;

    // تهيئة FFI للويندوز/لينكس
    sqfliteFfiInit();
    final databaseFactory = databaseFactoryFfi;

    final dbPath = await databaseFactory.getDatabasesPath();
    final path = join(dbPath, 'workspace.db');

    _database = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 9,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );

    return _database!;
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // الترقية للنسخ القديمة <8 (كودك القديم كان يتعامل مع <8)
    if (oldVersion < 9) {
      // ... (احتفظ بما لديك سابقًا) ...
      // جلب قائمة الأعمدة في جدول sessions
      final columns = await db.rawQuery('PRAGMA table_info(sessions)');
      final columnNames = columns.map((c) => c['name'] as String).toList();

      if (!columnNames.contains('type')) {
        await db.execute(
          'ALTER TABLE sessions ADD COLUMN type TEXT DEFAULT "حر"',
        );
      }

      if (!columnNames.contains('pauseStart')) {
        await db.execute('ALTER TABLE sessions ADD COLUMN pauseStart INTEGER');
      }
      if (!columnNames.contains('paidMinutes')) {
        await db.execute(
          'ALTER TABLE sessions ADD COLUMN paidMinutes INTEGER DEFAULT 0',
        );
      }

      // أي تغييرات أخرى للجداول لو محتاج

      // أي تغييرات أخرى للجداول
      await db.execute('''
      CREATE TABLE IF NOT EXISTS expenses(
        id TEXT PRIMARY KEY,
        title TEXT,
        amount REAL,
        date INTEGER
      )
    ''');
      await db.execute('''
      CREATE TABLE IF NOT EXISTS sales(
        id TEXT PRIMARY KEY,
        description TEXT,
        amount REAL,
        date INTEGER
      )
    ''');
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    // جدول إعدادات التسعير (صف واحد فقط)
    await db.execute('''
      CREATE TABLE pricing_settings (
        id INTEGER PRIMARY KEY,
        firstFreeMinutes INTEGER,
        firstHourFee REAL,
        perHourAfterFirst REAL,
        dailyCap REAL
      )
    ''');

    // أول إدخال افتراضي
    await db.insert("pricing_settings", {
      'id': 1,
      'firstFreeMinutes': 15,
      'firstHourFee': 30,
      'perHourAfterFirst': 20,
      'dailyCap': 150,
    });

    // جدول الجلسات
    // جدول الجلسات
    await db.execute('''
  CREATE TABLE sessions(
    id TEXT PRIMARY KEY,
    name TEXT,
    start INTEGER, -- نخزن كـ timestamp
    end INTEGER,
    amountPaid REAL,
    subscriptionId TEXT,
    isActive INTEGER,
    isPaused INTEGER,
    elapsedMinutes INTEGER,
      type TEXT, -- 🟢 العمود الجديد
      paidMinutes INTEGER DEFAULT 0,

       pauseStart INTEGER
  )
''');

    // جدول الاشتراكات
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

    // جدول المنتجات
    await db.execute('''
      CREATE TABLE products (
        id TEXT PRIMARY KEY,
        name TEXT,
        price REAL,
        stock INTEGER
      )
    ''');
    await db.execute('''
    CREATE TABLE cart_items(
      id TEXT PRIMARY KEY,
      sessionId TEXT,
      productId TEXT,
      qty INTEGER
    )
  ''');
    await db.execute('''
CREATE TABLE expenses(
  id TEXT PRIMARY KEY,
  title TEXT,
  amount REAL,
  date INTEGER
)
''');

    await db.execute('''
CREATE TABLE sales(
  id TEXT PRIMARY KEY,
  description TEXT,
  amount REAL,
  discount REAL, -- 🟢
  date INTEGER
)

''');
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
  }
}
*/
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';

class DbHelper {
  DbHelper._();
  static final DbHelper instance = DbHelper._();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;

    sqfliteFfiInit();
    final databaseFactory = databaseFactoryFfi;

    final dbPath = await databaseFactory.getDatabasesPath();
    final path = join(dbPath, 'workspace4.db');

    _database = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: _onCreate,

        onOpen: (db) async {
          await _ensureSalesColumns(db);
          await _ensureFinanceTables(db);
          await _ensureSubscriptionsColumns(db);
          await _ensureSessionsColumns(db);
        },
      ),
    );

    return _database!;
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
        customerName TEXT
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
    ''');

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
}
