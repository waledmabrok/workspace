import 'dart:convert';
import 'package:flutter/material.dart';

import 'Db_helper.dart';

String generateId() => DateTime.now().millisecondsSinceEpoch.toString();

/// ---------------- SubscriptionPlan ----------------

class SubscriptionPlan {
  String id;
  String name;
  String durationType;
  int? durationValue;
  double price;
  String dailyUsageType;
  int? dailyUsageHours;
  Map<String, int>? weeklyHours;
  bool isUnlimited;
  DateTime? endDate; // ✅ جديد

  SubscriptionPlan({
    required this.id,
    required this.name,
    required this.durationType,
    this.durationValue,
    required this.price,
    this.dailyUsageType = "full",
    this.dailyUsageHours,
    this.weeklyHours,
    this.isUnlimited = false,
    this.endDate, // ✅ جديد
  });

  /// ✅ للتخزين في SQLite
  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'durationType': durationType,
    'durationValue': durationValue,
    'price': price,
    'dailyUsageType': dailyUsageType,
    'dailyUsageHours': dailyUsageHours,
    'weeklyHours': weeklyHours != null ? jsonEncode(weeklyHours) : null,
    'isUnlimited': isUnlimited ? 1 : 0,
    'endDate': endDate?.millisecondsSinceEpoch, // ✅ جديد
  };

  factory SubscriptionPlan.fromMap(Map<String, dynamic> map) =>
      SubscriptionPlan(
        id: map['id'],
        name: map['name'],
        durationType: map['durationType'],
        durationValue: map['durationValue'],
        price: (map['price'] as num).toDouble(),
        dailyUsageType: map['dailyUsageType'] ?? "full",
        dailyUsageHours: map['dailyUsageHours'],
        weeklyHours:
            map['weeklyHours'] != null
                ? Map<String, int>.from(jsonDecode(map['weeklyHours']))
                : null,
        isUnlimited: map['isUnlimited'] == 1,
        endDate:
            map['endDate'] != null
                ? DateTime.fromMillisecondsSinceEpoch(map['endDate'])
                : null, // ✅ جديد
      );

  /// ✅ للتخزين في SharedPreferences (jsonEncode/jsonDecode)
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'durationType': durationType,
    'durationValue': durationValue,
    'price': price,
    'dailyUsageType': dailyUsageType,
    'dailyUsageHours': dailyUsageHours,
    'weeklyHours': weeklyHours,
    'isUnlimited': isUnlimited,
    'endDate': endDate?.toIso8601String(), // ✅ جديد
  };

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) =>
      SubscriptionPlan(
        id: json['id'],
        name: json['name'],
        durationType: json['durationType'],
        durationValue: json['durationValue'],
        price: (json['price'] as num).toDouble(),
        dailyUsageType: json['dailyUsageType'] ?? "full",
        dailyUsageHours: json['dailyUsageHours'],
        weeklyHours:
            json['weeklyHours'] != null
                ? Map<String, int>.from(json['weeklyHours'])
                : null,
        isUnlimited: json['isUnlimited'] ?? false,
        endDate:
            json['endDate'] != null
                ? DateTime.parse(json['endDate'])
                : null, // ✅ جديد
      );
}

/// ---------------- Product ----------------
class Product {
  final String id;
  final String name;
  final double price;
  int stock;

  Product({
    required this.id,
    required this.name,
    required this.price,
    required this.stock,
  });

  /// ✅ للتخزين في SharedPreferences
  Map<String, dynamic> toJson() => {
    "id": id,
    "name": name,
    "price": price,
    "stock": stock,
  };

  factory Product.fromJson(Map<String, dynamic> json) => Product(
    id: json["id"],
    name: json["name"],
    price: (json["price"] as num).toDouble(),
    stock: json["stock"],
  );

  /// ✅ للتخزين في SQLite
  Map<String, dynamic> toMap() => {
    "id": id,
    "name": name,
    "price": price,
    "stock": stock,
  };

  factory Product.fromMap(Map<String, dynamic> map) => Product(
    id: map["id"],
    name: map["name"],
    price: (map["price"] as num).toDouble(),
    stock: map["stock"],
  );
}

///=========================Shif=============
///
class Shift {
  final String id;
  final String cashierName;
  final DateTime openedAt;
  final DateTime? closedAt;
  final double openingBalance;
  final double closingBalance;
  final double totalSales;
  final double totalExpenses;

  Shift({
    required this.id,
    required this.cashierName,
    required this.openedAt,
    this.closedAt,
    this.openingBalance = 0.0,
    this.closingBalance = 0.0,
    this.totalSales = 0.0,
    this.totalExpenses = 0.0,
  });

  Map<String, dynamic> toMap() => {
    "id": id,
    "cashierName": cashierName,
    "openedAt": openedAt.toIso8601String(),
    "closedAt": closedAt?.toIso8601String(),
    "openingBalance": openingBalance,
    "closingBalance": closingBalance,
    "totalSales": totalSales,
    "totalExpenses": totalExpenses,
  };

  factory Shift.fromMap(Map<String, dynamic> map) => Shift(
    id: map["id"],
    cashierName: map["cashierName"],
    openedAt: DateTime.parse(map["openedAt"]),
    closedAt: map["closedAt"] != null ? DateTime.parse(map["closedAt"]) : null,
    openingBalance: map["openingBalance"] ?? 0.0,
    closingBalance: map["closingBalance"] ?? 0.0,
    totalSales: map["totalSales"] ?? 0.0,
    totalExpenses: map["totalExpenses"] ?? 0.0,
  );
}

/// ---------------- Expense ----------------
class Expense {
  final String id;
  String title;
  double amount;
  DateTime date;
  Expense({
    required this.id,
    required this.title,
    required this.amount,
    DateTime? date,
  }) : date = date ?? DateTime.now();
}

/// ---------------- Sale ----------------
class Sale {
  final String id;
  String description;
  double amount;
  double discount;
  DateTime date;
  String? shiftId;
  // حقول إضافية للتوافق مع DB وأغراض التقارير
  String paymentMethod; // 'cash' | 'wallet' | 'balance' | ...
  String? customerId;
  String? customerName;

  Sale({
    required this.id,
    required this.description,
    required this.amount,
    this.discount = 0.0,
    DateTime? date,
    this.paymentMethod = 'cash',
    this.customerId,
    this.customerName,
    this.shiftId,
  }) : date = date ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'description': description,
      'amount': amount,
      'discount': discount,
      'date': date.millisecondsSinceEpoch,
      'paymentMethod': paymentMethod,
      'customerId': customerId,
      'customerName': customerName,
      'shiftId': shiftId,
    };
  }

  factory Sale.fromMap(Map<String, dynamic> map) {
    return Sale(
      id: map['id'] as String,
      description: map['description'] as String? ?? '',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      discount: (map['discount'] as num?)?.toDouble() ?? 0.0,
      date:
          map['date'] != null
              ? DateTime.fromMillisecondsSinceEpoch(map['date'] as int)
              : DateTime.now(),
      paymentMethod: map['paymentMethod'] as String? ?? 'cash',
      customerId: map['customerId'] as String?,
      customerName: map['customerName'] as String?,
      shiftId: map['shiftId'] as String?,
    );
  }
}

/// ---------------- Discount ----------------
class Discount {
  final String id;
  final String code;
  final double percent;
  final DateTime? expiry;
  final bool singleUse;
  final bool used; // 🟢 جديد

  Discount({
    required this.id,
    required this.code,
    required this.percent,
    this.expiry,
    this.singleUse = false,
    this.used = false, // الافتراضي انه لسه متستخدمش
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'code': code,
      'percent': percent,
      'expiry': expiry?.toIso8601String(),
      'singleUse': singleUse ? 1 : 0,
      'used': used ? 1 : 0, // 🟢 جديد
    };
  }

  factory Discount.fromMap(Map<String, dynamic> map) {
    return Discount(
      id: map['id'],
      code: map['code'],
      percent: map['percent'],
      expiry: map['expiry'] != null ? DateTime.tryParse(map['expiry']) : null,
      singleUse: map['singleUse'] == 1,
      used: map['used'] == 1, // 🟢 جديد
    );
  }
}

class RoomPricing {
  final String roomId;
  final String roomName;
  final double basePrice;
  final int firstFreeMinutes;
  final double firstHourFee;
  final double perHourAfterFirst;
  final double dailyCap;

  RoomPricing({
    required this.roomId,
    required this.roomName,
    required this.basePrice,
    required this.firstFreeMinutes,
    required this.firstHourFee,
    required this.perHourAfterFirst,
    required this.dailyCap,
  });
}

extension DbHelperRooms on DbHelper {
  Future<List<RoomPricing>> getRoomPricings() async {
    final db = await database;
    final rows = await db.query('rooms');

    return rows.map((row) {
      return RoomPricing(
        roomId: row['id'] as String,
        roomName: row['name'] as String,
        basePrice: (row['basePrice'] as num).toDouble(),
        firstFreeMinutes: (row['firstFreeMinutesRoom'] as num).toInt(),
        firstHourFee: (row['firstHourFeeRoom'] as num).toDouble(),
        perHourAfterFirst: (row['perHourAfterFirstRoom'] as num).toDouble(),
        dailyCap: (row['dailyCapRoom'] as num).toDouble(),
      );
    }).toList();
  }
}

///-----------------------notification===========
class NotificationItem {
  final int? id;
  final String sessionId;
  final String type; // "expiring", "expired", "dailyLimit"
  final String message;
  bool isRead;
  final DateTime createdAt;

  NotificationItem({
    this.id,
    required this.sessionId,
    required this.type,
    required this.message,
    this.isRead = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sessionId': sessionId,
      'type': type,
      'message': message,
      'isRead': isRead ? 1 : 0,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory NotificationItem.fromMap(Map<String, dynamic> map) {
    return NotificationItem(
      id: map['id'],
      sessionId: map['sessionId'],
      type: map['type'],
      message: map['message'],
      isRead: map['isRead'] == 1,
      createdAt: DateTime.parse(map['createdAt']),
    );
  }
}

/// ---------------- Session ----------------
// داخل models.dart — تعديل/استبدال class Session الموجود عندك

class Session {
  final String id;
  final String name;
  int? savedDailySpent; // الدقايق المستهلكة اليوم
  int? savedElapsedMinutes; // اجمالي الدقايق المستهلكة

  DateTime start;
  DateTime? end;
  double amountPaid;
  SubscriptionPlan? subscription;
  bool isActive;
  bool isPaused;
  int elapsedMinutes;
  // للحر
  int frozenMinutes;
  // للباقة
  int elapsedMinutesPayg;
  List<CartItem> cart;
  String type; // "باقة" أو "حر"
  int paidMinutes;
  DateTime? pauseStart;
  final String? customerId;
  DateTime? runningSince;
  String? originalSubscriptionId;
  List<Map<String, dynamic>> events;
  String? savedSubscriptionJson;
  bool? resumeNextDayRequested;
  DateTime? resumeDate;
  DateTime? savedSubscriptionEnd;
  DateTime? savedSubscriptionConvertedAt;
  DateTime? lastDailySpentCheckpoint;
  bool dailyLimitNotified = false;
  bool expiringNotified = false;
  bool expiredNotified = false;
  bool shownInBadge = false;
  bool shownExpired = false; // لانهاء الاشتراك
  bool shownExpiring = false; // لقرب الانتهاء
  bool shownDailyLimit = false; // للحد اليومي
  bool isMergedOrClosed = false;
  Session({
    required this.id,
    this.originalSubscriptionId,
    required this.name,
    required this.start,
    this.end,
    this.amountPaid = 0.0,
    this.subscription,
    this.isActive = true,
    this.isPaused = false,
    this.elapsedMinutes = 0,
    this.frozenMinutes = 0, // جديد
    this.elapsedMinutesPayg = 0,
    this.cart = const [],
    required this.type,
    this.pauseStart,
    this.paidMinutes = 0,
    this.customerId,
    this.events = const [],
    this.savedSubscriptionJson,
    this.resumeNextDayRequested,
    this.resumeDate,
    this.savedSubscriptionEnd,
    this.savedSubscriptionConvertedAt,
    this.runningSince,
    this.savedDailySpent,
    this.savedElapsedMinutes,
    this.lastDailySpentCheckpoint,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'start': start.millisecondsSinceEpoch,
      'end': end?.millisecondsSinceEpoch,
      'amountPaid': amountPaid,
      'subscriptionId': subscription?.id,
      'isActive': isActive ? 1 : 0,
      'isPaused': isPaused ? 1 : 0,
      'elapsedMinutes': elapsedMinutes,
      'frozenMinutes': frozenMinutes, // جديد
      'elapsedMinutesPayg': elapsedMinutesPayg,
      'type': type,
      'pauseStart': pauseStart?.millisecondsSinceEpoch,
      'paidMinutes': paidMinutes,
      'customerId': customerId,
      'events': events.isNotEmpty ? jsonEncode(events) : null,
      'savedSubscriptionJson': savedSubscriptionJson,
      'resumeNextDayRequested': resumeNextDayRequested == true ? 1 : 0,
      'resumeDate': resumeDate?.millisecondsSinceEpoch,
      'savedSubscriptionEnd': savedSubscriptionEnd?.toIso8601String(),
      'savedSubscriptionConvertedAt':
          savedSubscriptionConvertedAt?.millisecondsSinceEpoch,
      'runningSince': runningSince?.millisecondsSinceEpoch,
      'originalSubscriptionId': originalSubscriptionId,
    };
  }

  factory Session.fromMap(Map<String, dynamic> map, {SubscriptionPlan? plan}) {
    List<Map<String, dynamic>> parsedEvents = [];
    try {
      if (map['events'] != null) {
        final raw = map['events'] as String;
        final dec = jsonDecode(raw);
        if (dec is List) {
          parsedEvents = List<Map<String, dynamic>>.from(dec);
        }
      }
    } catch (_) {
      parsedEvents = [];
    }

    return Session(
      id: map['id'] as String,
      name: map['name'] as String,
      start: DateTime.fromMillisecondsSinceEpoch(map['start'] as int),
      end:
          map['end'] != null
              ? DateTime.fromMillisecondsSinceEpoch(map['end'] as int)
              : null,
      amountPaid: (map['amountPaid'] as num?)?.toDouble() ?? 0.0,
      subscription: plan,
      isActive: (map['isActive'] as int?) == 1,
      isPaused: (map['isPaused'] as int?) == 1,
      elapsedMinutes: map['elapsedMinutes'] as int? ?? 0,
      frozenMinutes: map['frozenMinutes'] as int? ?? 0, // جديد
      elapsedMinutesPayg: map['elapsedMinutesPayg'] as int? ?? 0, // جديد
      cart: [],
      type: map['type'] as String? ?? (plan != null ? "باقة" : "حر"),
      pauseStart:
          map['pauseStart'] != null
              ? DateTime.fromMillisecondsSinceEpoch(map['pauseStart'] as int)
              : null,
      paidMinutes: map['paidMinutes'] as int? ?? 0,
      customerId: map['customerId'] as String?,
      events: parsedEvents,
      savedSubscriptionJson: map['savedSubscriptionJson'] as String?,
      resumeNextDayRequested: (map['resumeNextDayRequested'] as int?) == 1,
      resumeDate:
          map['resumeDate'] != null
              ? DateTime.fromMillisecondsSinceEpoch(map['resumeDate'] as int)
              : null,
      savedSubscriptionEnd:
          map['savedSubscriptionEnd'] != null
              ? DateTime.parse(map['savedSubscriptionEnd'] as String)
              : null,
      savedSubscriptionConvertedAt:
          map['savedSubscriptionConvertedAt'] != null
              ? DateTime.fromMillisecondsSinceEpoch(
                map['savedSubscriptionConvertedAt'] as int,
              )
              : null,
      runningSince:
          map['runningSince'] != null
              ? DateTime.fromMillisecondsSinceEpoch(map['runningSince'] as int)
              : null,
      originalSubscriptionId: map['originalSubscriptionId'] as String?,
      savedDailySpent: map['savedDailySpent'] as int?,
      savedElapsedMinutes: map['savedElapsedMinutes'] as int?,
    );
  }

  void addEvent(String action, {Map<String, dynamic>? meta}) {
    events.add({
      'ts': DateTime.now().toIso8601String(),
      'action': action,
      'meta': meta ?? {},
    });
  }
}

/// ---------------- CartItem ----------------
class CartItem {
  final String id;
  final Product product;
  int qty;

  CartItem({required this.id, required this.product, required this.qty});

  double get total => product.price * qty; // السعر محسوب تلقائياً
}


///========================Customer====================
class Customer {
  final String id;
  String name;
  String? phone;
  String? notes;

  Customer({required this.id, required this.name, this.phone, this.notes});

  factory Customer.fromMap(Map<String, dynamic> map) {
    return Customer(
      id: map['id'] as String,
      name: map['name'] ?? '',
      phone: map['phone'],
      notes: map['notes'],
    );
  }

  Map<String, dynamic> toMap() {
    return {'id': id, 'name': name, 'phone': phone, 'notes': notes};
  }
}

class CustomerBalance {
  final String customerId;
  double balance;
  DateTime updatedAt; // ✅ حقل جديد لتاريخ آخر تعديل

  CustomerBalance({
    required this.customerId,
    required this.balance,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  factory CustomerBalance.fromMap(Map<String, dynamic> map) {
    return CustomerBalance(
      customerId: map['customerId'] as String,
      balance: (map['balance'] as num).toDouble(),
      updatedAt:
          map['updatedAt'] != null
              ? DateTime.parse(map['updatedAt'] as String)
              : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'customerId': customerId,
      'balance': balance,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}
