import 'dart:convert';
import 'package:flutter/material.dart';

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

/// ---------------- Session ----------------
// داخل models.dart — تعديل/استبدال class Session الموجود عندك

class Session {
  final String id;
  final String name;
  DateTime start;
  DateTime? end;
  double amountPaid;
  SubscriptionPlan? subscription;
  bool isActive;
  bool isPaused;
  int elapsedMinutes;
  List<CartItem> cart;
  String type; // "باقة" أو "حر"
  int paidMinutes; // عدد الدقائق المدفوعة مسبقًا
  DateTime? pauseStart;
  final String? customerId;

  // ===== جديد: سجل الأحداث (timeline) محفوظ كـ List of maps ثم يُسجل في DB JSON =====
  List<Map<String, dynamic>> events;

  // حقول استكمال الباقة (قد تكون موجودة عندك سابقًا — احتفظ بها)
  String? savedSubscriptionJson;
  bool? resumeNextDayRequested;
  DateTime? resumeDate;

  Session({
    required this.id,
    required this.name,
    required this.start,
    this.end,
    this.amountPaid = 0.0,
    this.subscription,
    this.isActive = true,
    this.isPaused = false,
    this.elapsedMinutes = 0,
    this.cart = const [],
    required this.type,
    this.pauseStart,
    this.paidMinutes = 0,
    this.customerId,
    this.events = const [], // جديد: افتراضيًا فاضية
    this.savedSubscriptionJson,
    this.resumeNextDayRequested,
    this.resumeDate,
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
      'type': type,
      'pauseStart': pauseStart?.millisecondsSinceEpoch,
      'paidMinutes': paidMinutes,
      'customerId': customerId,
      // ===== حفظ events كـ JSON =====
      'events': events.isNotEmpty ? jsonEncode(events) : null,
      'savedSubscriptionJson': savedSubscriptionJson,
      'resumeNextDayRequested': resumeNextDayRequested == true ? 1 : 0,
      'resumeDate': resumeDate?.millisecondsSinceEpoch,
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
    );
  }

  /// مساعد: اضف حدث للسجل مع حفظ تلقائي في الذاكرة (لا تحفظ في DB هنا — النقطة الأعلى تحفظ بعد استدعاء SessionDb.updateSession)
  // models.dart
  void addEvent(String action, {Map<String, dynamic>? meta}) {
    events.add({
      'ts': DateTime.now().toIso8601String(),
      'action': action,
      'meta': meta ?? {},
    });
  }

  // مكان الاستدعاء
}

/// ---------------- CartItem ----------------
class CartItem {
  final String id;
  final Product product;
  int qty;

  CartItem({required this.id, required this.product, required this.qty});

  double get total => product.price * qty;
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

  CustomerBalance({required this.customerId, required this.balance});

  factory CustomerBalance.fromMap(Map<String, dynamic> map) {
    return CustomerBalance(
      customerId: map['customerId'] as String,
      balance: (map['balance'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {'customerId': customerId, 'balance': balance};
  }
}
