import 'dart:convert';
import 'dart:math';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:flutter/material.dart';
import 'package:workspace/screens/cashier/user_Subscripe.dart';
import 'package:workspace/utils/colors.dart';
import '../../core/Db_helper.dart';
import '../../core/FinanceDb.dart';
import '../../core/NotificationsDb.dart';
import '../../core/db_helper_cart.dart';
import '../../core/db_helper_customers.dart';
import '../../core/models.dart';
import '../../core/data_service.dart';
import '../../core/db_helper_sessions.dart';
import 'dart:async';

import '../../core/product_db.dart';
import '../../widget/buttom.dart';
import '../../widget/dropDown.dart';
import '../../widget/form.dart';
import '../admin/CustomerSubscribe.dart';
import 'SearchBalanceCustomer.dart';
import 'notification.dart';
import 'Rooms.dart';
import '../../core/db_helper_customer_balance.dart';

class CashierScreen extends StatefulWidget {
  const CashierScreen({super.key});

  @override
  State<CashierScreen> createState() => _CashierScreenState();
}

class _CashierScreenState extends State<CashierScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _qtyCtrl = TextEditingController(text: '1');
  final TextEditingController _searchCtrl = TextEditingController();
  final GlobalKey<AdminSubscribersPageeState> _subsKey = GlobalKey();

  int? _currentShiftId;
  // داخل class _CashierScreenState
  String get _currentCustomerName {
    // إذا فيه جلسة مختارة، استخدم اسمها، وإلا خذ الاسم من حقل الإدخال
    final fromSelected = _selectedSession?.name;
    if (fromSelected != null && fromSelected.isNotEmpty) return fromSelected;
    return _nameCtrl.text.trim();
  }

  List<Session> _sessions = [];
  List<Session> _filteredSessions = [];
  Timer? _autoStopTimer;
  Product? _selectedProduct;
  SubscriptionPlan? _selectedPlan;
  Session? _selectedSession;
  Timer? _timer;
  int _unseenExpiringCount = 0;

  Timer? _badgeTimer;
  // 🟢 الخصم
  Discount? _appliedDiscount;
  final TextEditingController _discountCodeCtrl = TextEditingController();

  ///=================================Subscrib=================
  bool _loading = true;
  List<Session> _sessionsSub = [];
  Future<void> _loadSessionsSub() async {
    setState(() => _loading = true);
    final data = await SessionDb.getSessions();
    for (var s in data) {
      try {
        s.cart = await CartDb.getCartBySession(s.id);
      } catch (_) {}
    }
    setState(() {
      _sessionsSub = data;
      _loading = false;
    });
  }

  Future<void> _applyDailyLimitForAllSessionsSub() async {
    final now = DateTime.now();

    final toConvert = <Session>[];

    for (var s in _sessionsSub) {
      if (!s.isActive) continue;
      if (s.type == 'حر') continue;
      if (s.subscription == null) continue;
      if (s.end != null && now.isAfter(s.end!)) {
        s.isActive = false;
        await SessionDb.updateSession(s);
        continue;
      }

      final plan = s.subscription!;
      if (plan.dailyUsageType != 'limited' || plan.dailyUsageHours == null)
        continue;

      final spentToday = _getMinutesConsumedTodaySub(s, now);
      final allowedToday = plan.dailyUsageHours! * 60;

      debugPrint(
        "➡️ Session ${s.name}: spentToday=$spentToday / allowed=$allowedToday",
      );

      if (spentToday >= allowedToday) {
        toConvert.add(s);
      }
    }

    // تحويل الجلسات التي وصلت الحد اليومي
    for (final s in toConvert) {
      await convertSubscriptionToPayg_CreateNew(s);
    }

    await _loadSessionsSub();
  }

  int _minutesOverlapWithDateSub(Session s, DateTime date) {
    // إذا الجلسة دلوقتي حر فنرجع 0 — لا نحسب وقت بعد التحويل كباقي باقة
    if (s.type == 'حر') return 0;

    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final now = DateTime.now();

    // دالة مساعدة: كم دقّة استهلكت الجلسة من بداية الـ session حتى وقت محدد
    int consumedUntil(DateTime t) {
      // نمنع حساب زمن من المستقبل
      final upto = t.isBefore(now) ? t : now;
      // نعطي نسخة مؤقتة من الsession لنستخدم دوالنا بصورة صحيحة
      // أسهل طريقه: نحتسب استهلاك حتى upto بنفس منطق getSessionMinutes لكن محددًا بـ upto
      final effectiveEnd = _getSubscriptionEndSub(s) ?? upto;
      final end = effectiveEnd.isBefore(upto) ? effectiveEnd : upto;
      final totalSinceStart = end.difference(s.start).inMinutes;
      int frozen = s.frozenMinutes;
      // إذا كان هناك إيقاف جارٍ وبدأ قبل `upto`، نحسب جزء التجميد حتى upto
      if (s.isPaused && s.pauseStart != null && s.pauseStart!.isBefore(upto)) {
        final curFrozen = upto.difference(s.pauseStart!).inMinutes;
        if (curFrozen > 0) frozen += curFrozen;
      }
      final consumed = totalSinceStart - frozen;
      return consumed < 0 ? 0 : consumed;
    }

    // استهلاك حتى نهاية اليوم (أو الآن إذا قبل نهاية اليوم)
    final upto = dayEnd.isBefore(now) ? dayEnd : now;
    final consumedToEnd = consumedUntil(upto);
    final consumedToStart = consumedUntil(dayStart);

    final overlap = consumedToEnd - consumedToStart;
    return overlap < 0 ? 0 : overlap;
  }

  int getSessionMinutesSub(Session s) {
    final now = DateTime.now();
    if (s.type == 'حر') {
      int base = s.elapsedMinutesPayg;
      if (!s.isActive) return base;
      if (s.isPaused) return base;
      final since = s.runningSince ?? s.start;
      return base + now.difference(since).inMinutes;
    } else {
      int base = s.elapsedMinutes;
      if (!s.isActive) return base;
      if (s.isPaused) return base;
      final since = s.runningSince ?? s.start;
      return base + now.difference(since).inMinutes;
    }
  }

  int _getMinutesConsumedTodaySub(Session s, DateTime now) {
    if (s.type == 'حر') return 0;

    final dayStart = DateTime(now.year, now.month, now.day);

    DateTime lastCheckpoint;
    if (s.lastDailySpentCheckpoint == null ||
        s.lastDailySpentCheckpoint!.isBefore(dayStart)) {
      lastCheckpoint = s.runningSince ?? s.start;
      if (lastCheckpoint.isBefore(dayStart)) lastCheckpoint = dayStart;
      s.savedDailySpent = 0; // إعادة ضبط الحد اليومي
    } else {
      lastCheckpoint = s.lastDailySpentCheckpoint!;
    }

    int spentMinutes = now.difference(lastCheckpoint).inMinutes;
    if (s.savedDailySpent != null) spentMinutes += s.savedDailySpent!;

    s.savedDailySpent = spentMinutes;
    s.lastDailySpentCheckpoint = now;

    return spentMinutes;
  }

  DateTime? _getSubscriptionEndSub(Session s) {
    final plan = s.subscription;
    if (plan == null || plan.isUnlimited)
      return s.end; // لو محفوظ end، أظهرها، وإلا null

    // احسب النهاية الأساسية من بداية الاشتراك
    final start = s.start;
    DateTime end;
    switch (plan.durationType) {
      case "hour":
        end = start.add(Duration(hours: plan.durationValue ?? 0));
        break;
      case "day":
        end = start.add(Duration(days: plan.durationValue ?? 0));
        break;
      case "week":
        end = start.add(Duration(days: 7 * (plan.durationValue ?? 0)));
        break;
      case "month":
        end = DateTime(
          start.year,
          start.month + (plan.durationValue ?? 0),
          start.day,
          start.hour,
          start.minute,
        );
        break;
      default:
        return s.end;
    }

    // ضف التجميد المتراكم
    if (s.frozenMinutes > 0) {
      end = end.add(Duration(minutes: s.frozenMinutes));
    }

    // اذا الجلسة موقوفة حاليا - اضف زمن التجميد الحالى (حتى يظهر الوقت متوقف أثناء العرض)
    if (s.isPaused && s.pauseStart != null) {
      final now = DateTime.now();
      final currentFrozen = now.difference(s.pauseStart!).inMinutes;
      if (currentFrozen > 0) end = end.add(Duration(minutes: currentFrozen));
    }

    // إذا كان بحقل s.end قيمة محفوظة (مثلاً اذا خزنتها عند الإنشاء) فاستخدمها بدل ذلك
    if (s.end != null) {
      // end في السجل يمكن أن يكون أدرجتَه سابقاً — لكن حافظ على إضافة frozen لنفس السلوك
      var stored = s.end!;
      // ضمان أن stored يساوي أو أكبر من الحساب (أو اختر سياسة أخرى)
      if (stored.isBefore(end)) stored = end;
      return stored;
    }

    return end;
  }

  Future<void> convertSubscriptionToPayg_CreateNew(Session sub) async {
    final now = DateTime.now();
    final spentToday = _minutesOverlapWithDateSub(sub, now);
    final totalMinutes = getSessionMinutesSub(sub);

    sub.savedDailySpent = spentToday;
    sub.savedElapsedMinutes = totalMinutes;

    // حفظ snapshot لو مش محفوظ
    if (sub.savedSubscriptionJson == null && sub.subscription != null) {
      sub.savedSubscriptionJson = jsonEncode(sub.subscription!.toJson());
      sub.savedSubscriptionEnd = _getSubscriptionEndSub(sub);
      sub.savedSubscriptionConvertedAt = now;
      sub.addEvent('snapshot_saved_before_conversion');
      await SessionDb.updateSession(sub);
      debugPrint("💾 Snapshot saved for ${sub.name} at $now");
    }

    // أفضل: اجعل الجلسة الأصلية "مؤرشفة" (stop) - لا تمسحها
    sub.isActive = false;
    sub.isPaused = true;
    // لو عايز تبيّن أنها محولة، ممكن تضيف event أو flag
    sub.addEvent('subscription_archived_before_payg');
    await SessionDb.updateSession(sub);

    // أنشئ جلسة حر جديدة منفصلة (مرتبطة بالأصل)
    final payg = Session(
      id: generateId(),
      name: '${sub.name} (حر)',
      start: now,
      end: null,
      amountPaid: 0.0,
      subscription: null,
      isActive: true,
      isPaused: false,
      elapsedMinutes:
          0, // لن نستخدم هذا للحساب — استخدم elapsedMinutesPayg أو runningSince
      elapsedMinutesPayg: 0,
      frozenMinutes: 0,
      cart: [], // أو انسخ الكارت لو تريد
      type: 'حر',
      pauseStart: null,
      paidMinutes: 0,
      customerId: sub.customerId,
      events: [
        {
          'ts': now.toIso8601String(),
          'action': 'created_from_subscription',
          'meta': {'from': sub.id},
        },
      ],
      runningSince: now,
      originalSubscriptionId: sub.id,
    );

    await SessionDb.insertSession(payg);

    // حدث الواجهة: أعادة تحميل الجلسات
    await _loadSessionsSub();
    await _subsKey.currentState?.reloadData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم إنشاء جلسة حر جديدة من الباقة')),
      );
    }
  }

  ///
  DateTime? getSubscriptionEnd(Session s) {
    final plan = s.subscription;
    if (plan == null || plan.isUnlimited) return null;

    final start = s.start;

    switch (plan.durationType) {
      case "hour":
        return start.add(Duration(hours: plan.durationValue ?? 0));
      case "day":
        return start.add(Duration(days: plan.durationValue ?? 0));
      case "week":
        return start.add(Duration(days: (plan.durationValue ?? 0) * 7));
      case "month":
        return DateTime(
          start.year,
          start.month + (plan.durationValue ?? 0),
          start.day,
          start.hour,
          start.minute,
        );
      default:
        return null;
    }
  }

  void applySearch(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredSessions = _sessionsSub;
      } else {
        _filteredSessions = _sessionsSub
            .where(
              (s) => s.name.toLowerCase().contains(query.toLowerCase()),
            )
            .toList();
      }
    });
  }

  Timer? _drawerBalanc;
  Customer? _currentCustomer;
  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _tabController = TabController(length: 3, vsync: this); // عدّد التابات
    _loadCurrentShift();
    _currentCustomer = AdminDataService.instance.customers.firstWhereOrNull(
      (c) => c.name == _currentCustomerName,
    );
    if (mounted) {
      setState(() {});
      _drawerBalanc = Timer.periodic(Duration(seconds: 3), (_) {
        _loadDrawerBalance();
      }); // نحافظ على تحديث الرصيد دوريًا
    }
    _searchCtrl.addListener(() {
      applySearch(_searchCtrl.text);
    });
    _startAutoStopChecker();
    _updateUnseenExpiringCount();
    _loadSessions();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    _badgeTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _loadBadge();
    });
    _loadBadge();
    _checkExpiring(); // أول مرة
    _expiringTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _checkExpiring(); // كل دقيقة يعمل فحص + يحدث الرقم
    });
  }

  @override
  void dispose() {
    _badgeTimer?.cancel();
    _expiringTimer?.cancel();
    _timer?.cancel();
    _autoStopTimer?.cancel();
    _discountCodeCtrl.dispose();

    super.dispose();
  }

  //==================Notification=======================
  Timer? _expiringTimer;
  List<Session> expiring = [];
  List<Session> expired = [];
  List<Session> dailyLimitReached = []; // ← هنا تعريفه كمتغير عضو

  Future<void> _checkExpiring() async {
    final now = DateTime.now();
    final e = <Session>[];
    final x = <Session>[];
    final daily = <Session>[];

    for (var s in _sessions) {
      if (s.subscription == null) continue;

      // منتهية
      if (s.end != null && now.isAfter(s.end!)) {
        await _notifyExpired(s);
        x.add(s);
        await _loadBadge(); // تحديث الرقم فورًا
      }
      // هتنتهي خلال أقل من ساعة
      else if (s.end != null && s.end!.difference(now).inMinutes <= 10) {
        await _notifyExpiring(s);
        e.add(s);
        await _loadBadge();
      }

      // تعدي الحد اليومي
      if (s.subscription!.dailyUsageType == 'limited' &&
          s.subscription!.dailyUsageHours != null) {
        final spentToday = _minutesOverlapWithDateSub(s, now);
        final allowedToday = s.subscription!.dailyUsageHours! * 60;
        if (spentToday >= allowedToday) {
          await _notifyDailyLimit(s);
          daily.add(s);
          await _loadBadge();
        }
      }
    }

    setState(() {
      expiring = e;
      expired = x;
      dailyLimitReached = daily;
    });
  }

  Future<void> _notifyExpired(Session s) async {
    final exists = await NotificationsDb.exists(s.id, 'expired');
    if (!exists) {
      await NotificationsDb.insertNotification(
        NotificationItem(
          sessionId: s.id,
          type: 'expired',
          message: 'انتهى الاشتراك ${s.name}',
        ),
      );
      s.expiredNotified = true; // تحديث الفلاج
    }
  }

  Future<void> _notifyExpiring(Session s) async {
    final exists = await NotificationsDb.exists(s.id, 'expiring');
    if (!exists) {
      await NotificationsDb.insertNotification(
        NotificationItem(
          sessionId: s.id,
          type: 'expiring',
          message: 'الاشتراك ${s.name} هينتهي قريب',
        ),
      );
      s.expiringNotified = true; // تحديث الفلاج
    }
  }

  Future<void> _notifyDailyLimit(Session s) async {
    final exists = await NotificationsDb.exists(s.id, 'dailyLimit');
    if (!exists) {
      await NotificationsDb.insertNotification(
        NotificationItem(
          sessionId: s.id,
          type: 'dailyLimit',
          message: 'العميل ${s.name} استهلك الحد اليومي',
        ),
      );
      s.dailyLimitNotified = true; // تحديث الفلاج
    }
  }

  ///============================================================================
  int _badgeCount = 0;
  Future<void> _loadBadge() async {
    final count = await NotificationsDb.getUnreadCount();
    if (mounted) {
      setState(() {
        _badgeCount = count;
      });
    }
  }

  Future<void> _loadSessions() async {
    final data = await SessionDb.getSessions();

    for (var s in data) {
      try {
        s.cart = await CartDb.getCartBySession(s.id);
      } catch (_) {}
    }

    // دمج أو إزالة التكرارات هنا قبل setState
    final uniqueSessions = <String, Session>{};
    for (var s in data) {
      final key = s.originalSubscriptionId ?? s.id; // إذا PayG مرتبط بالأصل
      if (!uniqueSessions.containsKey(key)) {
        uniqueSessions[key] = s;
      } else {
        // هنا ممكن تظهر دايلوج للمستخدم
        debugPrint("⚠️ Duplicate session found: ${s.name}");
        // إذا عايز تمنع ظهور الجلسة خالص، تجاهلها:
        // continue;
      }
    }

    setState(() {
      _sessions = uniqueSessions.values.toList();
      _filteredSessions = _sessions;
    });
  }

/*
  int getSessionMinutes(Session s) {
    // invariant:
    // - s.elapsedMinutes = مجموع دقائق الفترات المنتهية سابقاً
    // - s.pauseStart != null فقط عندما تكون الجلسة "تشغّل" (running)
    if (s.isPaused) {
      return s.elapsedMinutes;
    } else {
      final since = s.pauseStart ?? s.start;
      return s.elapsedMinutes + DateTime.now().difference(since).inMinutes;
    }
  }*/
  int getSessionMinutes(Session s) {
    if (!s.isActive) {
      // الجلسة انتهت → نحسب الوقت الكلي من start لـ end + أي elapsed سابق
      final endTime = s.end ?? DateTime.now();
      return s.elapsedMinutes + endTime.difference(s.start).inMinutes;
    }

    if (s.isPaused) {
      // الجلسة متوقفة مؤقتًا
      return s.elapsedMinutes;
    } else {
      // الجلسة نشطة → elapsed + الوقت منذ آخر resume
      final since = s.pauseStart ?? s.start;
      return s.elapsedMinutes + DateTime.now().difference(since).inMinutes;
    }
  }

  double _calculateTimeChargeFromMinutes(int minutes) {
    final settings = AdminDataService.instance.pricingSettings;
    if (minutes <= settings.firstFreeMinutes) return 0;
    if (minutes <= 60) return settings.firstHourFee;

    final extraHours = ((minutes - 60) / 60).ceil();
    double amount =
        settings.firstHourFee + extraHours * settings.perHourAfterFirst;
    if (amount > settings.dailyCap) amount = settings.dailyCap;

    return amount;
  }

  final TextEditingController _phoneCtrl = TextEditingController();

  // مساعد: احصل على عميل موجود أو أنشئ واحد جديد
  Future<Customer> _getOrCreateCustomer(String name, String? phone) async {
    final all = await CustomerDb.getAll();
    Customer? found;
    for (final c in all) {
      if (c.name == name ||
          (phone != null && phone.isNotEmpty && c.phone == phone)) {
        found = c;
        break;
      }
    }

    if (found != null) return found;

    final newCustomer = Customer(
      id: generateId(),
      name: name,
      phone: phone,
      notes: null,
    );

    await CustomerDb.insert(newCustomer);
    // لو عندك AdminDataService.instance.customers ممكن تضيفه هناك علطول:
    try {
      AdminDataService.instance.customers.add(newCustomer);
    } catch (_) {}
    return newCustomer;
  }

  void _startSession() async {
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('رجاءً ضع اسم العميل')));
      return;
    }

    // تأكد/انشئ العميل
    Customer? customer;
    try {
      customer = await _getOrCreateCustomer(name, phone.isEmpty ? null : phone);
      _currentCustomer = customer;
    } catch (e, st) {
      debugPrint('Failed to get/create customer: $e\n$st');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'فشل حفظ بيانات العميل، سيتم متابعة الجلسة بدون ربط عميل.',
          ),
        ),
      );
      customer = null;
      _currentCustomer = null;
    }

    final now = DateTime.now();
    DateTime? end;
    SubscriptionPlan? currentPlan = _selectedPlan;

    if (currentPlan != null && !currentPlan.isUnlimited) {
      switch (currentPlan.durationType) {
        case "hour":
          end = now.add(Duration(hours: currentPlan.durationValue ?? 0));
          break;
        case "day":
          end = now.add(Duration(days: currentPlan.durationValue ?? 0));
          break;
        case "week":
          end = now.add(Duration(days: 7 * (currentPlan.durationValue ?? 0)));
          break;
        case "month":
          end = DateTime(
            now.year,
            now.month + (currentPlan.durationValue ?? 0),
            now.day,
            now.hour,
            now.minute,
          );
          break;
      }
    }

    final session = Session(
      id: generateId(),
      name: name,
      start: now,
      end: end,
      subscription: currentPlan,
      isActive: true,
      isPaused: false,
      elapsedMinutes: 0,
      cart: [],
      amountPaid: 0.0,
      type: currentPlan != null ? "باقة" : "حر",
      savedDailySpent: 0,
      lastDailySpentCheckpoint: now,
    );

    // الدفع للباقة إذا موجودة
    if (currentPlan != null && customer != null) {
      final basePrice = currentPlan.price;
      final discountPercent = _appliedDiscount?.percent ?? 0.0;
      final finalPrice = basePrice - (basePrice * discountPercent / 100);

      final paid = await showSubscriptionPaymentDialog(
        context,
        s: session,
        customer: customer,
        currentPlan: currentPlan,
        basePrice: basePrice,
        discountPercent: discountPercent,
      );

      if (paid != true) return; // إذا ألغي المستخدم الدفع

      session.amountPaid = finalPrice;

      /*   final sale = Sale(
        id: generateId(),
        description: 'اشتراك ${currentPlan.name} للعميل ${name}' +
            (_appliedDiscount != null
                ? " (خصم ${_appliedDiscount!.percent}%)"
                : ""),
        amount: finalPrice,
      );

      try {
        await AdminDataService.instance.addSale(
          sale,
          paymentMethod: 'cash',
          customer: customer,
          updateDrawer: true,
        );

        // إزالة خصم single-use بعد استخدامه
        if (_appliedDiscount?.singleUse == true) {
          AdminDataService.instance.discounts.removeWhere(
            (d) => d.id == _appliedDiscount!.id,
          );
          _appliedDiscount = null;
        }

        await _loadDrawerBalance();
      } catch (e, st) {
        debugPrint('Failed to process quick sale: $e\n$st');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فشل تسجيل الدفعة — حاول مرة أخرى')),
        );
        return; // توقف إذا فشل الدفع
      }
*/
    }

    // حفظ الجلسة في DB
    await SessionDb.insertSession(session);
    await _subsKey.currentState?.reloadData();
    // تحديث AdminSubscribersPagee مباشرة بدون reload كامل

    // تحديث الواجهة الحالية
    setState(() {
      _sessions.insert(0, session);
      _filteredSessions = _searchCtrl.text.isEmpty
          ? _sessions
          : _sessions
              .where(
                (s) => s.name.toLowerCase().contains(
                      _searchCtrl.text.toLowerCase(),
                    ),
              )
              .toList();

      _nameCtrl.clear();
      _phoneCtrl.clear();
      _selectedPlan = null;
      _appliedDiscount = null;
      _discountCodeCtrl.clear();
    });
    /* final current = List<Session>.from(SessionsNotifier.sessions.value);
    current.insert(0, session);
    SessionsNotifier.sessions.value = current;

    // تنظيف الحقول
    _nameCtrl.clear();
    _phoneCtrl.clear();
    _selectedPlan = null;
    _appliedDiscount = null;
    _discountCodeCtrl.clear();*/
  }

  Future<bool?> showSubscriptionPaymentDialog(
    BuildContext context, {
    required Customer customer,
    required SubscriptionPlan currentPlan,
    required double basePrice,
    double discountPercent = 0.0,
    required Session s,
  }) async {
    final paidCtrl = TextEditingController();
    final discountValue = basePrice * (discountPercent / 100);
    final finalPrice = basePrice - discountValue;

    return await showDialog<bool>(
      context: context,
      barrierDismissible: false, // لازم يختار زرار
      builder: (
        ctx,
      ) {
        return StatefulBuilder(
          builder: (
            ctx,
            setDialogState,
          ) {
            final paidAmount = double.tryParse(paidCtrl.text) ?? 0.0;
            final diff = paidAmount - finalPrice;
            String paymentMethod = "cash";
            String diffText;
            if (diff == 0) {
              diffText = '✅ دفع كامل';
            } else if (diff > 0) {
              diffText = '💰 الباقي للعميل: ${diff.toStringAsFixed(2)} ج';
            } else {
              diffText = '💸 على العميل: ${(diff.abs()).toStringAsFixed(2)} ج';
            }

            return AlertDialog(
              title: Text("إيصال دفع - ${currentPlan.name}"),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("الباقة: ${currentPlan.name}"),
                    Text("السعر الأساسي: ${basePrice.toStringAsFixed(2)} ج"),
                    if (discountPercent > 0)
                      Text(
                        "خصم: $discountPercent% (-${discountValue.toStringAsFixed(2)} ج)",
                      ),
                    const Divider(),
                    Text(
                      "المطلوب: ${finalPrice.toStringAsFixed(2)} ج",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: paidCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "المبلغ المدفوع",
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      diffText,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              actions: [
                // داخل actions: []
                ElevatedButton(
                  onPressed: () async {
                    final paidAmount = double.tryParse(paidCtrl.text) ?? 0.0;
                    final diff = paidAmount - finalPrice;
                    if (paidAmount < finalPrice) {
                      // رسالة تحذير: المبلغ أقل من المطلوب
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('⚠️ المبلغ المدفوع أقل من المطلوب.'),
                        ),
                      );
                      return; // لا يتم تنفيذ أي شيء
                    }
                    if (diff > 0) {
                      // خصم الفائض من الدرج
                      await AdminDataService.instance.addSale(
                        Sale(
                          id: generateId(),
                          description: 'سداد الباقي كاش للعميل',
                          amount: diff,
                        ),
                        paymentMethod: 'cash',
                        updateDrawer: true,
                        drawerDelta: -diff, // خصم من الدرج بدل الإضافة
                      );
                    }

                    // final sale = Sale(
                    //   id: generateId(),
                    //   description:
                    //       'جلسة ${s.name} |   منتجات: ${s.cart.fold(0.0, (sum, item) => sum + item.total)}',
                    //   amount: paidAmount,
                    // );
                    //
                    // await AdminDataService.instance.addSale(
                    //   sale,
                    //   paymentMethod: paymentMethod,
                    //   customer: _currentCustomer,
                    //   updateDrawer: paymentMethod == "cash",
                    // );
                    //
                    try {
                      await _loadDrawerBalance();
                    } catch (e, st) {
                      debugPrint('Failed to update drawer: $e\n$st');
                    }
                    // 🗑️ مسح الكارت من DB و Session
                    // 2️⃣ بعد الدفع → مسح الكارت من DB

                    // 5️⃣ اقفل الشيت بعد ما اتأكدنا انه اتمسح

                    // 5️⃣ حدث الsetـ UI
                    Navigator.pop(ctx, true);
                    // إشعار للمستخدم بأن الباقي أخذ كاش
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '💵 الباقي ${diff > 0 ? diff.toStringAsFixed(2) : 0} ج أخذ كاش',
                        ),
                      ),
                    );
                  },
                  child: const Text('تأكيد الدفع بالكامل'),
                ),

                ElevatedButton(
                  onPressed: () async {
                    // required / paid / diff
                    final requiredAmount = finalPrice;
                    final paidAmount = double.tryParse(paidCtrl.text) ?? 0.0;
                    final diff = paidAmount - requiredAmount;
                    if (diff > 0) {
                      // إضافة الفائض للدرج
                      await AdminDataService.instance.addSale(
                        Sale(
                          id: generateId(),
                          description: 'فائض دفع العميل على الحساب',
                          amount: paidAmount,
                        ),
                        paymentMethod: 'cash',
                        updateDrawer: true,
                      );
                      await _loadDrawerBalance();
                    } /* else if (diff < 0) {
                      // خصم الفرق من الدرج
                      await AdminDataService.instance.addSale(
                        Sale(
                          id: generateId(),
                          description: 'العميل دفع أقل من المطلوب على الحساب',
                          amount: diff.abs(),
                        ),
                        paymentMethod: 'cash',
                        updateDrawer: true,
                        drawerDelta: -diff.abs(), // خصم من الدرج
                      );
                    }*/

                    // ---- تحديث رصيد العميل بشكل صحيح ----
                    // 1) نحدد customerId الهدف: نفضل s.customerId ثم _currentCustomer
                    String? targetCustomerId =
                        s.customerId ?? _currentCustomer?.id;

                    // 2) لو لسه فاضي حاول نبحث عن العميل بالاسم، وإن لم يوجد - ننشئ واحد جديد
                    if (targetCustomerId == null || targetCustomerId.isEmpty) {
                      // حاول إيجاد العميل في DB بحسب الاسم
                      final found = await CustomerDb.getByName(s.name);
                      if (found != null) {
                        targetCustomerId = found.id;
                      } else {
                        // لو اسم موجود في الحقل ونفّذنا إنشاء: ننشئ عميل جديد ونتخزن
                        if (s.name.trim().isNotEmpty) {
                          final newCustomer = Customer(
                            id: generateId(),
                            name: s.name,
                            phone: "011",
                            notes: null,
                          );
                          await CustomerDb.insert(newCustomer);
                          // حدث الذاكرة المحلية إن وُجد (AdminDataService)
                          try {
                            AdminDataService.instance.customers.add(
                              newCustomer,
                            );
                          } catch (_) {}
                          targetCustomerId = newCustomer.id;
                        }
                      }
                    }

                    if (targetCustomerId != null &&
                        targetCustomerId.isNotEmpty) {
                      // احصل الرصيد القديم من الذاكرة (أو استخدم 0)
                      final oldBalance =
                          AdminDataService.instance.customerBalances.firstWhere(
                        (b) => b.customerId == targetCustomerId,
                        orElse: () => CustomerBalance(
                          customerId: targetCustomerId!,
                          balance: 0.0,
                        ),
                      );

                      final newBalance = oldBalance.balance + diff;
                      final updated = CustomerBalance(
                        customerId: targetCustomerId,
                        balance: newBalance,
                      );

                      // اكتب للـ DB
                      await CustomerBalanceDb.upsert(updated);

                      // حدّث الذاكرة (AdminDataService)
                      final idx =
                          AdminDataService.instance.customerBalances.indexWhere(
                        (b) => b.customerId == targetCustomerId,
                      );
                      if (idx >= 0) {
                        AdminDataService.instance.customerBalances[idx] =
                            updated;
                      } else {
                        AdminDataService.instance.customerBalances.add(
                          updated,
                        );
                      }
                    } else {
                      // لم نتمكن من إيجاد/إنشاء عميل --> تسجّل ملاحظۀ debug
                      debugPrint(
                        'No customer id for session ${s.id}; balance not updated.',
                      );
                    }

                    // ---- حفظ المبيعة ----
                    final sale = Sale(
                      id: generateId(),
                      description:
                          "اشتراك ${currentPlan.name} للعميل ${customer.name}"
                          "${discountPercent > 0 ? " (خصم $discountPercent%)" : ""}",
                      amount: finalPrice,
                    );

                    if (paidAmount > 0) {
                      await AdminDataService.instance.addSale(
                        Sale(
                          id: generateId(),
                          description:
                              "اشتراك ${currentPlan.name} للعميل ${customer.name} علي الحساب",
                          amount: paidAmount,
                        ),
                        paymentMethod: 'cash',
                        customer: _currentCustomer,
                        updateDrawer: true,
                      );
                    }

                    try {
                      await _loadDrawerBalance();
                    } catch (e, st) {
                      debugPrint('Failed to update drawer: $e\n$st');
                    }
                    // 🗑️ مسح الكارت من DB و Session

                    // 5️⃣ حدث الـ UI
                    Navigator.pop(ctx, true);

                    // إشعار للمستخدم (باقي/له/عليه)
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          diff == 0
                              ? '✅ دفع كامل: ${paidAmount.toStringAsFixed(2)} ج'
                              : diff > 0
                                  ? '✅ دفع ${paidAmount.toStringAsFixed(2)} ج — باقي له ${diff.toStringAsFixed(2)} ج عندك'
                                  : '✅ دفع ${paidAmount.toStringAsFixed(2)} ج — باقي عليك ${(diff.abs()).toStringAsFixed(2)} ج',
                        ),
                      ),
                    );
                  },
                  child: const Text('علي الحساب'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('إلغاء'),
                ),
              ],
              /* ElevatedButton(
                  onPressed: () async {
                    if (paidAmount < finalPrice) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('⚠️ المبلغ المدفوع أقل من المطلوب'),
                        ),
                      );
                      return;
                    }

                    final sale = Sale(
                      id: generateId(),
                      description:
                          "اشتراك ${currentPlan.name} للعميل ${customer.name}"
                          "${discountPercent > 0 ? " (خصم $discountPercent%)" : ""}",
                      amount: finalPrice,
                    );

                    Navigator.pop(ctx, true); // ✅ هترجع true
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '✅ تم دفع اشتراك ${currentPlan.name} (${finalPrice.toStringAsFixed(2)} ج)',
                        ),
                      ),
                    );
                  },
                  child: const Text("تأكيد الدفع"),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false), // ✅ هترجع false
                  child: const Text("إلغاء"),
                ),
              ],*/
            );
          },
        );
      },
    );
  }

  Future<void> _togglePauseSessionFor(Session s) async {
    if (!s.isActive) return;

    setState(() {
      if (s.isPaused) {
        // استئناف: نبدأ العد من الآن
        s.isPaused = false;
        s.pauseStart = DateTime.now();
      } else {
        // إيقاف مؤقت: نجمع الدقائق منذ آخر resume (أو start) ونوقف
        final since = s.pauseStart ?? s.start;
        s.elapsedMinutes += DateTime.now().difference(since).inMinutes;
        s.isPaused = true;
        s.pauseStart = null; // نفضّل تعيينه null عند الإيقاف
      }
    });

    try {
      await SessionDb.updateSession(s);
    } catch (e, st) {
      debugPrint('Failed to update session pause toggle: $e\n$st');
    }
  }

  void _stopSession(Session s) async {
    setState(() {
      s.isActive = false;
    });

    await SessionDb.updateSession(s);

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text("انتهى الاشتراك للعميل ${s.name}")));
  }

  void _startAutoStopChecker() {
    _autoStopTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      for (var s in _sessions) {
        if (s.isActive && s.subscription != null && s.end != null) {
          final now = DateTime.now();
          if (now.isAfter(s.end!)) {
            _stopSession(s);
          } else if (s.end!.difference(now).inMinutes == 10) {
            _showExpiryWarning(s);
          }
        }
      }
    });
  }

  void _showExpiryWarning(Session s) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("⚠️ الاشتراك للعميل ${s.name} هينتهي بعد 10 دقائق"),
        backgroundColor: Colors.orange,
      ),
    );
  }

  /// دقائق الجلسة داخل نفس اليوم (من بداية اليوم حتى الآن أو end إذا أسبق)
  int getSessionMinutesToday(Session s) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));

    final sessionStart = s.start.isBefore(todayStart) ? todayStart : s.start;
    // لو الجلسة لها end داخل اليوم خده، وإلا خُد الآن
    final sessionEnd = (s.end != null && s.end!.isBefore(now)) ? s.end! : now;

    if (sessionEnd.isBefore(todayStart)) return 0;
    if (sessionStart.isAfter(todayEnd)) return 0;

    return sessionEnd.difference(sessionStart).inMinutes;
  }

  int allowedMinutesTodayForPlan(SubscriptionPlan? plan) {
    if (plan == null) return -1;
    if (plan.dailyUsageType != 'limited' || plan.dailyUsageHours == null)
      return -1;
    return plan.dailyUsageHours! * 60; // تحويل ساعات إلى دقائق
  }

  //Cart==================================
  void _completeAndPayForSession(Session s) async {
    final totalMinutes = getSessionMinutes(s);

    // دقائق جديدة لم تُدفع بعد
    final minutesToCharge = (totalMinutes - s.paidMinutes).clamp(
      0,
      totalMinutes,
    );

    // رسوم الوقت فقط على الدقائق الجديدة
    final timeCharge = _calculateTimeChargeFromMinutes(minutesToCharge);

    final productsTotal = s.cart.fold(0.0, (sum, item) => sum + item.total);

    await _showReceiptDialog(s, timeCharge, productsTotal, minutesToCharge);
  }

  Widget _buildAddProductsAndPay(Session s, {bool onlyAdd = false}) {
    Product? selectedProduct;
    bool isDeleting = false;
    TextEditingController qtyCtrl = TextEditingController(text: '0');

    return StatefulBuilder(
      builder: (context, setSheetState) {
        CartDb.getCartBySession(s.id).then((updatedCart) {
          setSheetState(() {
            s.cart = updatedCart;
          });
        });
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Dropdown لاختيار المنتج
              DropdownButtonFormField<Product>(
                value: selectedProduct,
                hint: const Text(
                  'اختر منتج/مشروب',
                  style: TextStyle(color: Colors.white70),
                ),
                dropdownColor: Colors.grey[850],
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColorsDark.bgCardColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                ),
                items: AdminDataService.instance.products.map((p) {
                  return DropdownMenuItem(
                    value: p,
                    child: Text(
                      '${p.name} (${p.price} ج - ${p.stock} متاح)',
                      style: const TextStyle(color: Colors.white),
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  setSheetState(() => selectedProduct = val);
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: CustomFormField(hint: "عدد", controller: qtyCtrl),
                  ),
                  const SizedBox(width: 8),
                  CustomButton(
                    text: "اضف",
                    onPressed: () async {
                      if (selectedProduct == null) return;

                      final qty = int.tryParse(qtyCtrl.text) ?? 0;
                      if (qty <= 0) return;
                      // خصم المخزون مباشرة

                      // تحقق من المخزون
                      if (selectedProduct!.stock < qty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '⚠️ المخزون غير كافي (${selectedProduct!.stock} فقط)',
                            ),
                          ),
                        );
                        return;
                      }
                      selectedProduct!.stock -= qty;
                      await ProductDb.insertProduct(
                        selectedProduct!,
                      ); // تحديث المخزون في DB

                      // تحديث AdminDataService
                      final index = AdminDataService.instance.products
                          .indexWhere((p) => p.id == selectedProduct!.id);
                      if (index != -1) {
                        AdminDataService.instance.products[index].stock =
                            selectedProduct!.stock;
                      }
                      // خصم المخزون مؤقتًا
                      /*    selectedProduct!.stock -= qty;
                      final index = AdminDataService.instance.products
                          .indexWhere((p) => p.id == selectedProduct!.id);
                      if (index != -1)
                        AdminDataService.instance.products[index].stock =
                            selectedProduct!.stock;*/

                      // إضافة للكارت
                      final item = CartItem(
                        id: generateId(),
                        product: selectedProduct!,
                        qty: qty,
                      );
                      await CartDb.insertCartItem(item, s.id);

                      final updatedCart = await CartDb.getCartBySession(s.id);
                      setSheetState(() => s.cart = updatedCart);
                    },
                    infinity: false,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // قائمة العناصر المضافة
              ...s.cart.map((item) {
                final qtyController = TextEditingController(
                  text: item.qty.toString(),
                );
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.product.name,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      SizedBox(
                        width: 60,
                        child: TextField(
                          controller: qtyController,
                          style: const TextStyle(color: Colors.white),
                          keyboardType: TextInputType.number,
                          onChanged: (val) async {
                            final newQty = int.tryParse(val) ?? item.qty;

                            // تحقق من المخزون عند تعديل الكمية
                            final availableStock =
                                item.product.stock + item.qty;
                            if (newQty > availableStock) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '⚠️ المخزون غير كافي (${availableStock} فقط)',
                                  ),
                                ),
                              );
                              setSheetState(() {});
                              return;
                            }

                            // تعديل المخزون
                            item.product.stock += (item.qty - newQty);

                            final idx = AdminDataService.instance.products
                                .indexWhere((p) => p.id == item.product.id);
                            if (idx != -1)
                              AdminDataService.instance.products[idx].stock =
                                  item.product.stock;

                            item.qty = newQty;
                            await CartDb.updateCartItemQty(item.id, newQty);
                            setSheetState(() {});
                          },
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.grey[800],
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.redAccent),
                        onPressed: () async {
                          if (isDeleting)
                            return; // ⛔ تجاهل الضغط لو في عملية شغالة
                          isDeleting = true;

                          try {
                            if (item.qty > 1) {
                              // 🟢 قلل 1 من الكمية
                              item.qty -= 1;
                              item.product.stock += 1;

                              // تحديث DB
                              await CartDb.updateCartItemQty(item.id, item.qty);
                            } else {
                              // 🟠 لو آخر واحدة → امسح العنصر
                              await CartDb.deleteCartItem(item.id);

                              item.product.stock += 1;
                              s.cart.remove(item);
                            }
                            await ProductDb.insertProduct(item.product);
                            // تحديث AdminDataService
                            final idx = AdminDataService.instance.products
                                .indexWhere((p) => p.id == item.product.id);
                            if (idx != -1) {
                              AdminDataService.instance.products[idx].stock =
                                  item.product.stock;
                            }

                            setSheetState(() {});
                          } finally {
                            isDeleting = false; // ✅ فك القفل بعد انتهاء العملية
                          }
                        },
                      ),

                      /*  IconButton(
                        icon: const Icon(Icons.delete, color: Colors.redAccent),
                        onPressed: () async {
                          if (item.qty > 1) {
                            // 🟢 قلل 1 من الكمية
                            item.qty -= 1;
                            item.product.stock += 1;

                            // تحديث DB
                            await CartDb.updateCartItemQty(item.id, item.qty);
                          } else {
                            // 🟠 لو آخر واحدة → امسح العنصر
                            await CartDb.deleteCartItem(item.id);

                            item.product.stock += 1;
                            s.cart.remove(item);
                          }

                          // تحديث AdminDataService
                          final idx = AdminDataService.instance.products
                              .indexWhere((p) => p.id == item.product.id);
                          if (idx != -1) {
                            AdminDataService.instance.products[idx].stock =
                                item.product.stock;
                          }

                          setSheetState(() {});
                        },
                      ),
                    */
                    ],
                  ),
                );
              }).toList(),
              const SizedBox(height: 12),
              CustomButton(
                text: "تم اضافه الي السله",
                onPressed: () async {
                  Navigator.pop(context);
                },
                infinity: false,
                color: Colors.green,
              ),
              ...(!onlyAdd
                  ? [
                      CustomButton(
                        text: "إتمام ودفع",
                        onPressed: () async {
                          Navigator.pop(context);

                          _completeAndPayForSession(s);
                        },
                        infinity: false,
                        color: Colors.green,
                      ),
                    ]
                  : []),
            ],
          ),
        );
      },
    );
  }

  Future<void> tryAddToCart(
    Session s,
    Product product,
    int qty,
    StateSetter setSheetState,
  ) async {
    if (qty <= 0) return;

    // تحقق من المخزون
    if (product.stock < qty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('⚠️ المخزون غير كافي (${product.stock} فقط)')),
      );
      return;
    }

    // خصم المخزون مؤقتًا
    /*   product.stock -= qty;
    final index = AdminDataService.instance.products.indexWhere(
      (p) => p.id == product.id,
    );
    if (index != -1)
      AdminDataService.instance.products[index].stock = product.stock;
*/
    // أضف للـ Cart
    final item = CartItem(id: generateId(), product: product, qty: qty);

    await CartDb.insertCartItem(item, s.id);
    final updatedCart = await CartDb.getCartBySession(s.id);
    setSheetState(() => s.cart = updatedCart);
  }

  Future<void> _showReceiptDialog(
    Session s,
    double timeCharge,
    double productsTotal,
    int minutesToCharge,
  ) async {
    double discountValue = 0.0;
    String? appliedCode;
    final codeCtrl = TextEditingController();

    String paymentMethod = "cash"; // 🟢 افتراضي: كاش
    final TextEditingController paidCtrl = TextEditingController();
    final customerId = s.customerId;
    double customerBalance = 0.0;

    if (customerId != null && customerId.isNotEmpty) {
      customerBalance = await CustomerBalanceDb.getBalance(customerId);
    }

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            String? customerId = s.customerId ?? _currentCustomer?.id;
            double finalTotal = timeCharge + productsTotal - discountValue;
            /*  (الرصيد: ${AdminDataService.instance.customerBalances.firstWhere((b) => b.customerId == s.customerId, orElse: () => CustomerBalance(customerId: s.customerId ?? '', balance: 0.0)).balance.toStringAsFixed(2)} ج)*/
            return AlertDialog(
              title: Text('إيصال الدفع - ${s.name} '),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('وقت الجلسة: ${timeCharge.toStringAsFixed(2)} ج'),
                    const SizedBox(height: 8),
                    const SizedBox(height: 8),
                    Text('🛒 المنتجات:'),
                    ...s.cart.map((item) => Text(
                        '${item.product.name} x${item.qty} = ${item.total.toStringAsFixed(2)} ج')),
                    const Divider(),
                    Text('⏱️ الوقت: ${timeCharge.toStringAsFixed(2)} ج'),
                    const Divider(),

                    const SizedBox(height: 12),

                    // المبلغ المطلوب
                    Text(
                      'المطلوب: ${finalTotal.toStringAsFixed(2)} ج',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),

                    const SizedBox(height: 8),

                    // إدخال المبلغ المدفوع
                    TextField(
                      controller: paidCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "المبلغ المدفوع",
                      ),
                      onChanged: (val) {
                        setDialogState(
                          () {},
                        ); // كل مرة يتغير فيها المبلغ، يحدث الـ dialog
                      },
                    ),
                    const SizedBox(height: 8),
                    // عرض الباقي أو الفائض
                    Builder(
                      builder: (_) {
                        // تحديث الرصيد الفعلي من AdminDataService
                        double updatedBalance = 0.0;
                        if (s.customerId != null) {
                          final b = AdminDataService.instance.customerBalances
                              .firstWhere(
                            (b) => b.customerId == s.customerId,
                            orElse: () => CustomerBalance(
                                customerId: s.customerId!, balance: 0),
                          );
                          updatedBalance = b.balance;
                        }
                        final paidAmount =
                            double.tryParse(paidCtrl.text) ?? 0.0;
                        final diff = paidAmount - finalTotal;
                        String diffText;
                        if (diff == 0) {
                          diffText = '✅ دفع كامل';
                        } else if (diff > 0) {
                          diffText =
                              '💰 الباقي للعميل: ${diff.toStringAsFixed(2)} ج';
                        } else {
                          diffText =
                              '💸 على العميل: ${(diff.abs()).toStringAsFixed(2)} ج';
                        }
                        return Text(
                          diffText,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        );
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                // داخل actions: []
                ElevatedButton(
                  onPressed: () async {
                    final paidAmount = double.tryParse(paidCtrl.text) ?? 0.0;
                    final diff = paidAmount - finalTotal;
                    if (paidAmount < finalTotal) {
                      // رسالة تحذير: المبلغ أقل من المطلوب
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('⚠️ المبلغ المدفوع أقل من المطلوب.'),
                        ),
                      );
                      return; // لا يتم تنفيذ أي شيء
                    }
                    if (diff > 0) {
                      // خصم الفائض من الدرج
                      await AdminDataService.instance.addSale(
                        Sale(
                          id: generateId(),
                          description: 'سداد الباقي كاش للعميل',
                          amount: diff,
                        ),
                        paymentMethod: 'cash',
                        updateDrawer: true,
                        drawerDelta: -diff, // خصم من الدرج بدل الإضافة
                      );
// بعد تحديث الرصيد في DB والذاكرة
                      // بعد ما تحدث الرصيد في DB
                      // لو id فاضي، حاول تجيب العميل بالاسم
                      if (customerId == null || customerId!.isEmpty) {
                        final found = await CustomerDb.getByName(s.name);
                        if (found != null) {
                          customerId = found.id;
                        }
                      }

// لو لسه فاضي، ممكن تنشئ عميل جديد
                      if (customerId == null) {
                        final newCustomer = Customer(
                          id: generateId(),
                          name: s.name,
                        );
                        await CustomerDb.insert(newCustomer);
                        customerId = newCustomer.id;
                      }

// دلوقتي نقدر نجيب رصيد العميل
                      final double newBalance =
                          await CustomerBalanceDb.getBalance(customerId!);

// عرض رصيد العميل
                      await showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text("رصيد العميل الحالي"),
                          content: Text(
                            newBalance > 0
                                ? "💰 له: ${newBalance.toStringAsFixed(2)} ج"
                                : newBalance < 0
                                    ? "💸 عليه: ${newBalance.abs().toStringAsFixed(2)} ج"
                                    : "✅ الرصيد صفر",
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text("حسناً"),
                            ),
                          ],
                        ),
                      );

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '💵 أخذ العميل باقي ${diff.toStringAsFixed(2)} ج كاش من الدرج',
                          ),
                        ),
                      );
                    }

                    // تحديث دقائق الدفع
                    s.paidMinutes += minutesToCharge;
                    s.amountPaid += paidAmount;

                    // ---- قفل الجلسة وتحديث DB ----
                    setState(() {
                      s.isActive = false;
                      s.isPaused = false;
                      _sessions.removeWhere((sess) => sess.id == s.id);
                      //   _filteredSessions.removeWhere((sess) => sess.id == s.id);
                    });
                    s.end = DateTime.now();
                    await SessionDb.updateSession(s);

                    // حفظ المبيعة كما هي
                    final sale = Sale(
                      id: generateId(),
                      description:
                          'جلسة ${s.name} | وقت: ${minutesToCharge} دقيقة = ${timeCharge.toStringAsFixed(2)} ج + منتجات = ${productsTotal.toStringAsFixed(2)} ج',
                      amount: paidAmount,
                      items: List<CartItem>.from(s.cart), // ✅ إضافة المنتجات
                    );

                    await AdminDataService.instance.addSale(
                      sale,
                      paymentMethod: paymentMethod,
                      customer: _currentCustomer,
                      updateDrawer: paymentMethod == "cash",
                    );

                    try {
                      await _loadDrawerBalance();
                    } catch (e, st) {
                      debugPrint('Failed to update drawer: $e\n$st');
                    }

                    Navigator.pop(context);

                    // إشعار للمستخدم بأن الباقي أخذ كاش
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '💵 الباقي ${diff > 0 ? diff.toStringAsFixed(2) : 0} ج أخذ كاش',
                        ),
                      ),
                    );
                  },
                  child: const Text('تأكيد الدفع بالكامل'),
                ),

                ElevatedButton(
                  onPressed: () async {
                    // required / paid / diff
                    final requiredAmount = finalTotal;
                    final paidAmount = double.tryParse(paidCtrl.text) ?? 0.0;
                    final diff = paidAmount - requiredAmount;

                    // تحديث دقائق الدفع داخل الجلسة
                    s.paidMinutes += minutesToCharge;
                    s.amountPaid += paidAmount;

                    // ---- تحديث رصيد العميل بشكل صحيح ----
                    // 1) نحدد customerId الهدف: نفضل s.customerId ثم _currentCustomer
                    String? targetCustomerId =
                        s.customerId ?? _currentCustomer?.id;

                    // 2) لو لسه فاضي حاول نبحث عن العميل بالاسم، وإن لم يوجد - ننشئ واحد جديد
                    if (targetCustomerId == null || targetCustomerId.isEmpty) {
                      // حاول إيجاد العميل في DB بحسب الاسم
                      final found = await CustomerDb.getByName(s.name);
                      if (found != null) {
                        targetCustomerId = found.id;
                      } else {
                        // لو اسم موجود في الحقل ونفّذنا إنشاء: ننشئ عميل جديد ونتخزن
                        if (s.name.trim().isNotEmpty) {
                          final newCustomer = Customer(
                            id: generateId(),
                            name: s.name,
                            phone: null,
                            notes: null,
                          );
                          await CustomerDb.insert(newCustomer);
                          // حدث الذاكرة المحلية إن وُجد (AdminDataService)
                          try {
                            AdminDataService.instance.customers.add(
                              newCustomer,
                            );
                          } catch (_) {}
                          targetCustomerId = newCustomer.id;
                        }
                      }
                    }

                    if (targetCustomerId != null &&
                        targetCustomerId.isNotEmpty) {
                      // احصل الرصيد القديم من الذاكرة (أو استخدم 0)
                      final oldBalance =
                          AdminDataService.instance.customerBalances.firstWhere(
                        (b) => b.customerId == targetCustomerId,
                        orElse: () => CustomerBalance(
                          customerId: targetCustomerId!,
                          balance: 0.0,
                        ),
                      );

                      final newBalance = oldBalance.balance + diff;
                      final updated = CustomerBalance(
                        customerId: targetCustomerId,
                        balance: newBalance,
                      );

                      // اكتب للـ DB
                      await CustomerBalanceDb.upsert(updated);

                      // حدّث الذاكرة (AdminDataService)
                      final idx = AdminDataService.instance.customerBalances
                          .indexWhere((b) => b.customerId == targetCustomerId);
                      if (idx >= 0) {
                        AdminDataService.instance.customerBalances[idx] =
                            updated;
                      } else {
                        AdminDataService.instance.customerBalances.add(updated);
                      }
                    } else {
                      // لم نتمكن من إيجاد/إنشاء عميل --> تسجّل ملاحظۀ debug
                      debugPrint(
                        'No customer id for session ${s.id}; balance not updated.',
                      );
                    }

                    // ---- قفل الجلسة وتحديث DB ----
                    setState(() {
                      s.isActive = false;
                      s.isPaused = false;
                      _sessions.removeWhere((sess) => sess.id == s.id);
                      //   _filteredSessions.removeWhere((sess) => sess.id == s.id);
                    });
                    s.end = DateTime.now();
                    await SessionDb.updateSession(s);

                    // ---- حفظ المبيعة ----
                    final sale = Sale(
                      id: generateId(),
                      description:
                          'جلسة ${s.name} | وقت: ${minutesToCharge} دقيقة = ${timeCharge.toStringAsFixed(2)} ج + منتجات = ${productsTotal.toStringAsFixed(2)} ج',
                      amount: paidAmount,
                      items: List<CartItem>.from(s.cart),
                      customerId: targetCustomerId, // 🟢 اربط الفاتورة بالعميل
                      date: DateTime.now(),
                      // ✅ إضافة المنتجات
                    );

                    await AdminDataService.instance.addSale(
                      sale,
                      paymentMethod: paymentMethod,
                      customer: _currentCustomer,
                      updateDrawer: paymentMethod == "cash",
                    );

                    try {
                      await _loadDrawerBalance();
                    } catch (e, st) {
                      debugPrint('Failed to update drawer: $e\n$st');
                    }

                    Navigator.pop(context);

                    // إشعار للمستخدم (باقي/له/عليه)
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          diff == 0
                              ? '✅ دفع كامل: ${paidAmount.toStringAsFixed(2)} ج'
                              : diff > 0
                                  ? '✅ دفع ${paidAmount.toStringAsFixed(2)} ج — باقي له ${diff.toStringAsFixed(2)} ج عندك'
                                  : '✅ دفع ${paidAmount.toStringAsFixed(2)} ج — باقي عليك ${(diff.abs()).toStringAsFixed(2)} ج',
                        ),
                      ),
                    );
                  },
                  child: const Text('علي الحساب'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إلغاء'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  ///========================================================

  Future<void> _showCustomerBalance(Session s, double diff) async {
    // احصل customerId
    String? targetCustomerId = s.customerId ?? _currentCustomer?.id;

    double newBalance = 0.0;
    if (targetCustomerId != null) {
      final balanceEntry =
          AdminDataService.instance.customerBalances.firstWhere(
        (b) => b.customerId == targetCustomerId,
        orElse: () =>
            CustomerBalance(customerId: targetCustomerId, balance: 0.0),
      );
      newBalance = balanceEntry.balance;
    }

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("رصيد العميل الحالي"),
        content: Text(
          newBalance > 0
              ? "💰 له: ${newBalance.toStringAsFixed(2)} ج"
              : newBalance < 0
                  ? "💸 عليه: ${newBalance.abs().toStringAsFixed(2)} ج"
                  : "✅ الرصيد صفر",
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("حسناً"),
          ),
        ],
      ),
    );
  }

  List<Session> getExpiringSessions() {
    final now = DateTime.now();
    return _sessions.where((s) {
      if (s.subscription != null && s.end != null && s.isActive) {
        final minutesLeft = s.end!.difference(now).inMinutes;
        return minutesLeft <= 50; // قربت تنتهي خلال 10 دقائق
      }
      return false;
    }).toList();
  }

  List<Session> getExpiredSessions() {
    final now = DateTime.now();
    return _sessions.where((s) {
      return s.subscription != null && s.end != null && now.isAfter(s.end!);
    }).toList();
  }

  void _updateUnseenExpiringCount() {
    _unseenExpiringCount =
        getExpiringSessions().length + getExpiredSessions().length;
  }

  ///-------------------------------Shift close===============
  Map<String, dynamic>? _currentShift;

  double _drawerBalance = 0.0;

  Future<void> _loadDrawerBalance() async {
    try {
      final bal = await FinanceDb.getDrawerBalance();
      if (mounted) setState(() => _drawerBalance = bal);
    } catch (e, st) {
      // طبع الخطأ علشان تعرف لو في مشكلة في DB
      debugPrint('Failed to load drawer balance: $e\n$st');
      if (mounted) {
        // اختياري: تعرض snackbar للمستخدم لو حبيت
        // ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ في جلب رصيد الدرج')));
      }
    }
  }

  Future<Map<String, dynamic>?> _loadCurrentShift() async {
    final db = await DbHelper.instance.database;
    final rows = await db.query('shifts', where: 'closed_at IS NULL', limit: 1);

    if (rows.isEmpty) return null;

    final shift = rows.first;

    // null-safe id
    final shiftId = shift['id'] is int
        ? shift['id'] as int
        : int.tryParse(shift['id'].toString()) ?? 0;

    final summary = await DbHelper.instance.getShiftSummary(shiftId);

    final shiftData = {
      "id": shiftId,
      "cashierName": shift['cashier_name'] ?? '',
      "openedAt": shift['opened_at'] ?? '',
      "openingBalance": (shift['drawer_balance'] as num?)?.toDouble() ?? 0.0,
      "closingBalance": (shift['total_sales'] as num?)?.toDouble() ?? 0.0,
      "sales": summary['sales'],
      "expenses": summary['expenses'],
      "profit": summary['profit'],
    };

    setState(() {
      _currentShift = shiftData;
    });

    return shiftData;
  }

  Future<int?> getCurrentShiftId() async {
    final db = await DbHelper.instance.database;
    final res = await db.query('shifts', orderBy: 'id DESC', limit: 1);

    if (res.isNotEmpty) {
      final row = res.first;
      final idValue = row['id'];
      if (idValue == null) return null;
      return idValue is int ? idValue : int.tryParse(idValue.toString());
    }

    return null;
  }

  Future<double> getClosingBalance() async {
    final db = await DbHelper.instance.database;
    final rows = await db.query(
      'drawer',
      where: 'id = ?',
      whereArgs: [1],
      limit: 1,
    );
    return (rows.first['balance'] as num?)?.toDouble() ?? 0.0;
  }

  Future<void> _closeShift({required String cashierName}) async {
    final int? shiftId = await getCurrentShiftId();
    if (shiftId == null) {
      debugPrint("⚠️ لا يوجد شيفت مفتوح للتقفيل");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("لا يوجد شيفت مفتوح")));
      return;
    }

    final closingBalance = await getClosingBalance();

    await DbHelper.instance.closeShift(
      shiftId, // ✅ int
      closingBalance,
      cashierName,
    );

    debugPrint(
      "✅ تم تقفيل الشيفت بنجاح باسم $cashierName مع رصيد $closingBalance",
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("تم تقفيل الشيفت بواسطة $cashierName")),
    );

    setState(() {
      _currentShift = null;
      _currentShiftId = null; // ✅ reset
    });
  }

  final TextEditingController cashierNameCtrl = TextEditingController();

  double closingBalance = 0.0; // أو احسبه من DbHelper

  Future<void> _openShift({required String cashierName}) async {
    final openingBalance = await DbHelper.instance.getClosingBalance();
    final int id = await DbHelper.instance.openShift(
      'DefaultCashier', // اسم الكاشير
      openingBalance: openingBalance, // الرصيد الافتتاحي
    );

    setState(() {
      _currentShiftId = id; // ✅ بقى int
      _currentShift = {
        "id": id,
        "cashierName": cashierName,
        "openedAt": DateTime.now(),
        "drawer_balance": openingBalance,
      };
    });

    debugPrint("✅ تم فتح شيفت جديد: $id");
  }

  Map<String, dynamic>? _currentShiftData;

  Future<void> _closeCurrentShift() async {
    if (_currentShiftId != null && _currentShiftData != null) {
      await DbHelper.instance.closeShift(
        _currentShiftId!,
        closingBalance,
        _currentShiftData!["cashierName"] as String,
      );

      setState(() {
        _currentShiftId = null;
        _currentShiftData = null;
      });
    }
  }

  int get badgeCount {
    int count = 0;
    for (var s in _sessions) {
      if (s.expiredNotified && !s.shownExpired) count++;
      if (s.expiringNotified && !s.shownExpiring) count++;
      if (s.dailyLimitNotified && !s.shownDailyLimit) count++;
    }
    return count;
  }

  Future<void> sellProduct(Product product, int qty) async {
    if (qty <= 0) return;

    // 1️⃣ خصم من الـ DB
    final newStock = max(0, product.stock - qty);
    product.stock = newStock;
    await ProductDb.insertProduct(product); // تحديث المخزون في DB

    // 2️⃣ خصم من AdminDataService
    final index = AdminDataService.instance.products.indexWhere(
      (p) => p.id == product.id,
    );
    if (index != -1) {
      AdminDataService.instance.products[index].stock = newStock;
    }

    setState(() {}); // تحديث الـ UI
  }

  Future<int> getBadgeCount() async {
    final db = await DbHelper.instance.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM notifications WHERE isRead = 0',
    );

    if (result.isEmpty) return 0;

    final dynamic cntRaw = result.first['cnt'];
    if (cntRaw == null) return 0;
    if (cntRaw is int) return cntRaw;
    if (cntRaw is String) return int.tryParse(cntRaw) ?? 0;

    return int.tryParse(cntRaw.toString()) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Center(
            child: const Text(
              'الكاشير',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 28),
            ),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            // داخل AppBar.actions: ضع هذا قبل الأيقونات الأخرى أو بعدهم
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  'رصيد الدرج',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '${_drawerBalance.toStringAsFixed(2)} ج',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            /*
            IconButton(
              icon: Icon(
                _currentShift != null ? Icons.lock_clock : Icons.lock_person,
              ),
              tooltip:
              _currentShift != null
                  ? 'قفّل الشيفت الحالي'
                  : 'افتح شيفت جديد',
              onPressed: () async {
                if (_currentShift != null) {
                  // إذا فيه شيفت مفتوح، نقفله ونطبع التقرير
                  final int shiftId = _currentShift!['id'] as int;

                  // جلب الرصيد النهائي (مثلا من drawer أو حسب حسابك)
                  final double closingBalance = await DbHelper.instance.getClosingBalance();

                  // استخدام closeShiftDetailed للحصول على التقرير الكامل
                  final report = await DbHelper.instance.closeShiftDetailed(
                    shiftId.toString(),
                    countedClosingBalance: closingBalance,
                    cashierName: _currentShift!['cashierName'] as String,
                  );

                  // طباعة التقرير في الـ debug console
                  debugPrint("📄 تقرير الشيفت:\n$report");

                  // تحديث الحالة في الواجهة
                  setState(() {
                    _currentShift = null;
                    _currentShiftId = null;
                  });

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("تم تقفيل الشيفت بواسطة ${report['cashierName']}")),
                  );
                } else {
                  // فتح شيفت جديد
                  final cashierNameCtrl = TextEditingController();
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('فتح شيفت جديد'),
                      content: TextField(
                        controller: cashierNameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'اسم الكاشير',
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('إلغاء'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('فتح شيفت'),
                        ),
                      ],
                    ),
                  );

                  if (confirmed == true && cashierNameCtrl.text.isNotEmpty) {
                  //  await _openShift(cashierName: cashierameCtrl.text);
                  }
                }
              },
            )*/
            IconButton(
              icon: Icon(Icons.lock_clock),
              tooltip: 'قفّل الشيفت الحالي',
              onPressed: () async {
                if (_currentShift != null) {
                  // جلب رقم الشيفت المفتوح
                  final int shiftId = _currentShift!['id'] as int;

                  // جلب الرصيد النهائي
                  final double closingBalance =
                      await DbHelper.instance.getClosingBalance();

                  // إغلاق الشيفت
                  final report = await DbHelper.instance.closeShiftDetailed(
                    shiftId.toString(),
                    countedClosingBalance: closingBalance,
                    cashierName: _currentShift!['cashierName'] as String ??
                        "الموظف الحالي",
                  );

                  debugPrint("📄 تقرير الشيفت:\n$report");

                  setState(() {
                    _currentShift = null;
                    _currentShiftId = null;
                  });

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        "تم تقفيل الشيفت بواسطة X SPACE",
                      ),
                    ),
                  );
                } else {
                  // إذا مفيش شيفت مفتوح، لا نفعل شيء
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("لا يوجد شيفت مفتوح ليتم تقفيله"),
                    ),
                  );
                }
              },
            ),
            IconButton(
                onPressed: () => showCustomerSearchDialog(context),
                icon: Icon(Icons.monetization_on_sharp)),

            Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications),
                  tooltip: 'الإشعارات',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ExpiringSessionsPage(
                          sessionsSub: _sessions,
                          onViewed: () async {
                            // await NotificationsDb.markAllAsRead();
                            _loadBadge(); // صفر بعد المشاهدة
                          },
                        ),
                      ),
                    ).then((_) => _loadBadge());
                  },
                ),
                if (_badgeCount > 0)
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$_badgeCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              // ---------------- البحث ----------------
              CustomFormField(
                onChanged: (value) {
                  // لو فاضي → نرجع كل المشتركين
                  if (value.trim().isEmpty) {
                    _subsKey.currentState?.applySearch("");
                  } else {
                    _subsKey.currentState?.applySearch(value);
                  }
                },
                controller: _searchCtrl,
                hint: 'البحث',
                validator: (v) =>
                    (v?.trim().isEmpty ?? true) ? 'ادخل الاسم' : null,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: 12),

              // ---------------- اختيار باقة ----------------
              // Dropdown
              CustomDropdownFormField<SubscriptionPlan>(
                hint: "اختر اشتراك (اختياري)",
                value: _selectedPlan,
                items: [
                  const DropdownMenuItem<SubscriptionPlan>(
                    value: null,
                    child: Text(
                      "اختيار اشتراك",
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                  ...AdminDataService.instance.subscriptions.map((s) {
                    return DropdownMenuItem(
                      value: s,
                      child: Text(
                        "${s.name} - ${s.price} ج",
                        style: const TextStyle(color: Colors.white),
                      ),
                    );
                  }),
                ],
                onChanged: (val) => setState(() => _selectedPlan = val),
              ),

              const SizedBox(height: 12),

              // اسم العميل + زر التسجيل
              Row(
                children: [
                  Expanded(
                    child: CustomFormField(
                      controller: _nameCtrl,
                      hint: 'اسم العميل',
                      validator: (v) =>
                          (v?.trim().isEmpty ?? true) ? 'ادخل الاسم' : null,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 150,
                    height: 45,
                    child: CustomButton(
                      text: "ابدأ تسجيل",
                      onPressed: _startSession,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ---------------- Tabs ----------------
              Expanded(
                child: DefaultTabController(
                  length: 3,
                  child: Column(
                    children: [
                      Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: AppColorsDark.bgCardColor, // خلفية الـ TabBar
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.transparent,
                            width: 0,
                          ),
                        ),
                        child: Builder(
                          builder: (context) {
                            return TabBar(
                              onTap: (index) {
                                final controller = DefaultTabController.of(
                                  context,
                                );

                                if (controller.index == index) {
                                  // 👈 لو دوسنا على نفس التاب الحالي → نعمل reload
                                  if (index == 1) {
                                    // التاب اللي في النص "مشتركين حر"
                                    _loadSessions(); // أو أي دالة refresh عندك
                                  }
                                }

                                controller.animateTo(
                                  index,
                                  duration: Duration.zero,
                                  curve: Curves.linear,
                                );
                              },
                              overlayColor: MaterialStateProperty.all(
                                Colors.transparent,
                              ),
                              indicatorColor: Colors.transparent,
                              indicatorWeight: 0,
                              indicatorPadding: EdgeInsets.zero,
                              dividerColor: Colors.transparent,
                              indicator: BoxDecoration(
                                color: AppColorsDark.mainColor,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              indicatorSize: TabBarIndicatorSize.tab,
                              labelColor: Colors.white,
                              unselectedLabelColor: Colors.white70,
                              tabs: [
                                const Tab(
                                  child: Text(
                                    "مشتركين باقات",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 20,
                                    ),
                                  ),
                                ),
                                Tab(
                                  child: const Text(
                                    "مشتركين حر",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 20,
                                    ),
                                  ),
                                ),
                                const Tab(
                                  child: Text(
                                    "الغرف",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 20,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: TabBarView(
                          children: [
                            AdminSubscribersPagee(key: _subsKey),
                            _buildSubscribersList(withPlan: false),
                            CashierRoomsPage(), // المشتركين حر
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        /*  body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: _searchCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'ابحث عن مشترك',
                  labelStyle: const TextStyle(color: Colors.white70),
                  prefixIcon: const Icon(Icons.search, color: Colors.white70),
                  filled: true,
                  fillColor: Colors.grey[850],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (val) {
                  setState(() {
                    _filteredSessions =
                        val.isEmpty
                            ? _sessions
                            : _sessions
                                .where(
                                  (s) => s.name.toLowerCase().contains(
                                    val.toLowerCase(),
                                  ),
                                )
                                .toList();
                  });
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<SubscriptionPlan>(
                value: _selectedPlan,
                dropdownColor: Colors.grey[850],
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: "اختر اشتراك (اختياري)",
                  labelStyle: const TextStyle(color: Colors.white70),
                  filled: true,
                  fillColor: Colors.grey[850],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
                items:
                    AdminDataService.instance.subscriptions
                        .map(
                          (s) => DropdownMenuItem(
                            value: s,
                            child: Text("${s.name} - ${s.price} ج"),
                          ),
                        )
                        .toList(),
                onChanged: (val) => setState(() => _selectedPlan = val),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nameCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'اسم العميل',
                        hintStyle: const TextStyle(color: Colors.white70),
                        filled: true,
                        fillColor: Colors.grey[850],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _startSession,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueGrey[700],
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                    child: const Text('ابدأ تسجيل'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: _filteredSessions.length,
                  itemBuilder: (context, i) {
                    final s = _filteredSessions[i];
                    final spentMinutes = getSessionMinutes(s);
                    final endTime = getSubscriptionEnd(s);

                    String timeInfo;
                    if (s.subscription != null) {
                      timeInfo =
                          endTime != null
                              ? "من: ${s.start.toLocal()} ⇢ ينتهي: ${endTime.toLocal()} ⇢ مضى: ${spentMinutes} دقيقة"
                              : "من: ${s.start.toLocal()} ⇢ غير محدود ⇢ مضى: ${spentMinutes} دقيقة";
                    } else {
                      timeInfo =
                          "من: ${s.start.toLocal()} ⇢ مضى: ${spentMinutes} دقيقة";
                    }

                    double currentCharge = _calculateTimeChargeFromMinutes(
                      spentMinutes,
                    );

                    return Card(
                      child: ListTile(
                        title: Text(s.name),
                        subtitle: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${s.isActive ? (s.isPaused ? "متوقف مؤقت" : "نشط") : "انتهت"} - $timeInfo',
                              ),
                            ),
                            if (s.end != null &&
                                s.end!.difference(DateTime.now()).inMinutes <=
                                    10 &&
                                s.isActive)
                              const Icon(
                                Icons.notification_important,
                                color: Colors.orange,
                              ),
                          ],
                        ),

                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (s.isActive)
                              ElevatedButton(
                                onPressed: () => _togglePauseSession(i),
                                child: Text(
                                  s.isPaused ? 'استئناف' : 'ايقاف مؤقت',
                                ),
                              ),
                            const SizedBox(width: 4),
                            if (s.isActive && !s.isPaused)
                              ElevatedButton(
                                onPressed: () async {
                                  setState(() => _selectedSession = s);
                                  await showModalBottomSheet(
                                    context: context,
                                    builder: (_) => _buildAddProductsAndPay(s),
                                  );
                                },
                                child: const Text('اضف & دفع'),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),*/
      ),
    );
  }

  DateTime? _fromDate;
  DateTime? _toDate;

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: _fromDate != null && _toDate != null
          ? DateTimeRange(start: _fromDate!, end: _toDate!)
          : null,
    );

    if (picked != null) {
      setState(() {
        _fromDate = picked.start;
        _toDate = picked.end;
      });
    }
  }

  DateTime _selectedDate = DateTime.now();

  /// 🔹 دالة تبني لستة المشتركين
  Widget _buildSubscribersList({required bool withPlan}) {
    final searchText = _searchCtrl.text.toLowerCase();
    final filtered = _sessions.where((s) {
      final matchesType = withPlan ? s.type == "باقة" : s.type == "حر";
      final matchesSearch = s.name.toLowerCase().contains(searchText);
      final matchesDate =
          (_fromDate == null || !s.start.isBefore(_fromDate!)) &&
              (_toDate == null || !s.start.isAfter(_toDate!));
      return matchesType && matchesSearch && matchesDate;
    }).toList();

    return Column(
      children: [
        Row(
          children: [
            const Text(
              "عرض ليوم: ",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            CustomButton(
              text: _fromDate != null && _toDate != null
                  ? "${_fromDate!.year}-${_fromDate!.month.toString().padLeft(2, '0')}-${_fromDate!.day.toString().padLeft(2, '0')} ⇢ "
                      "${_toDate!.year}-${_toDate!.month.toString().padLeft(2, '0')}-${_toDate!.day.toString().padLeft(2, '0')}"
                  : "اختر الفترة",
              onPressed: () async {
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                  initialDateRange: _fromDate != null && _toDate != null
                      ? DateTimeRange(start: _fromDate!, end: _toDate!)
                      : null,
                );

                if (picked != null) {
                  setState(() {
                    _fromDate = picked.start;
                    _toDate = picked.end;
                  });
                }
              },
              infinity: false,
              border: true,
            ),
            const SizedBox(width: 12),
            CustomButton(
              text: "اليوم",
              onPressed: () => setState(() {
                final today = DateTime.now();
                _fromDate = DateTime(today.year, today.month, today.day);
                _toDate =
                    DateTime(today.year, today.month, today.day, 23, 59, 59);
              }),
              infinity: false,
              border: true,
            ),
            const SizedBox(width: 12),
            CustomButton(
              text: "الكل",
              onPressed: () => setState(() {
                _fromDate = null;
                _toDate = null;
                _searchCtrl.clear(); // 🟢 امسح البحث كمان
              }),
              infinity: false,
              border: true,
            ),
          ],
        ),
        SizedBox(
          height: 10,
        ),
        Expanded(
          child: ListView.builder(
            /*where((s) => s.isActive)*/
            itemCount: filtered.length,
            itemBuilder: (context, i) {
              /*   final activeSessions = filtered.where((s) => s.isActive).toList();
           */
              /*   final s = activeSessions[i];*/
              final s = filtered[i];
              final spentMinutes = getSessionMinutes(s);
              final endTime = getSubscriptionEnd(s);

              String timeInfo2 = s.subscription != null
                  ? (endTime != null
                      ? "من: ${s.start.toLocal()} ⇢ ينتهي: ${endTime.toLocal()} ⇢ مضى: ${spentMinutes} دقيقة"
                      : "من: ${s.start.toLocal()} ⇢ غير محدود ⇢ مضى: ${spentMinutes} دقيقة")
                  : "من: ${s.start.toLocal()} ⇢ مضى: ${spentMinutes} دقيقة";

              final hours = spentMinutes ~/ 60; // القسمة الصحيحة
              final minutes = spentMinutes % 60; // الباقي

              String timeInfo;
              if (hours > 0) {
                timeInfo = "$hours ساعة ${minutes} دقيقة";
              } else {
                timeInfo = "$minutes دقيقة";
              }

              return Card(
                color: AppColorsDark.bgCardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: AppColorsDark.mainColor.withOpacity(0.4),
                    width: 1.5,
                  ),
                ),
                margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        s.isActive
                            ? (s.isPaused
                                ? "متوقف مؤقت - $timeInfo"
                                : "نشط منذ - $timeInfo")
                            : "انتهت",
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          s.isActive
                              ? Expanded(
                                  child: CustomButton(
                                    text: 'اضف منتجات',
                                    onPressed: () async {
                                      setState(() => _selectedSession = s);
                                      await showModalBottomSheet(
                                        context: context,
                                        isScrollControlled: true,
                                        builder: (_) => _buildAddProductsAndPay(
                                          s,
                                          onlyAdd: true,
                                        ), // parameter جديد
                                      );
                                    },
                                  ),
                                )
                              : Container(),
                          const SizedBox(width: 12),
                          Expanded(
                            child: CustomButton(
                              color: s.isPaused
                                  ? Colors.transparent
                                  : AppColorsDark.mainColor,
                              border: s.isPaused ? false : true,
                              borderColor: s.isActive ? null : Colors.white,
                              text: s.isPaused
                                  ? 'استكمال الوقت'
                                  : s.isActive
                                      ? 'ايقاف مؤقت'
                                      : 'انتهت',
                              onPressed: s.isActive || s.isPaused
                                  ? () => _togglePauseSessionFor(s)
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          s.isActive
                              ? Expanded(
                                  child: CustomButton(
                                    border: true,
                                    borderColor: Colors.red,
                                    text: 'دفع',
                                    onPressed: () async {
                                      _completeAndPayForSession(s);
                                    },
                                    color: Colors.red,
                                  ),
                                )
                              : Container(),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /* Widget _buildSubscribersList({required bool withPlan}) {
    // فلترة مباشرة من _sessions
    */ /* final filtered =
        _sessions.where((s) {
          if (withPlan) return s.type == "باقة";
          return s.type == "حر";
        }).toList();*/ /*
    final searchText = _searchCtrl.text.toLowerCase();
    final filtered =
        _sessions.where((s) {
          final matchesType = withPlan ? s.type == "باقة" : s.type == "حر";
          final matchesSearch = s.name.toLowerCase().contains(searchText);
          return matchesType && matchesSearch;
        }).toList();

    if (filtered.isEmpty) return const Center(child: Text("لا يوجد بيانات"));

    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (context, i) {
        final s = filtered[i];
        final spentMinutes = getSessionMinutes(s);
        final endTime = getSubscriptionEnd(s);

        String timeInfo =
            s.subscription != null
                ? (endTime != null
                    ? "من: ${s.start.toLocal()} ⇢ ينتهي: ${endTime.toLocal()} ⇢ مضى: ${spentMinutes} دقيقة"
                    : "من: ${s.start.toLocal()} ⇢ غير محدود ⇢ مضى: ${spentMinutes} دقيقة")
                : "من: ${s.start.toLocal()} ⇢ مضى: ${spentMinutes} دقيقة";

        return Card(
          child: ListTile(
            title: Text(s.name),
            subtitle: Text(
              '${s.isActive ? (s.isPaused ? "متوقف مؤقت" : "نشط") : "انتهت"} - $timeInfo',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (s.isActive)
                  ElevatedButton(
                    onPressed: () => _togglePauseSessionFor(s),

                    child: Text(s.isPaused ? 'استئناف' : 'ايقاف مؤقت'),
                  ),
                const SizedBox(width: 4),
                if (s.isActive && !s.isPaused)
                  ElevatedButton(
                    onPressed: () async {
                      setState(() => _selectedSession = s);
                      await showModalBottomSheet(
                        context: context,
                        builder: (_) => _buildAddProductsAndPay(s),
                      );
                    },
                    child: const Text('اضف & دفع'),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }*/

  Widget _buildSubscribersList3({required bool withPlan}) {
    final searchText = _searchCtrl.text.toLowerCase();
    final filtered = _sessions.where((s) {
      final matchesType = withPlan ? s.type == "باقة" : s.type == "حر";
      final matchesSearch = s.name.toLowerCase().contains(searchText);
      return matchesType && matchesSearch;
    }).toList();

    if (filtered.isEmpty) return const Center(child: Text("لا يوجد بيانات"));

    String _formatHoursMinutes(int minutes) {
      final h = minutes ~/ 60;
      final m = minutes % 60;
      if (h > 0) return "${h}س ${m}د";
      return "${m}د";
    }

    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (context, i) {
        final s = filtered[i];

        final totalMinutes = getSessionMinutes(
          s,
        ); // إجمالي دقائق الجلسة حتى الآن
        final spentToday = getSessionMinutesToday(s); // دقائق اليوم فقط

        // حساب الحد اليومي (مخزن بالساعات في SubscriptionPlan)
        int allowedToday = -1; // -1 يعني غير محدود أو لا باقة
        if (s.subscription != null &&
            s.subscription!.dailyUsageType == 'limited' &&
            s.subscription!.dailyUsageHours != null) {
          allowedToday = s.subscription!.dailyUsageHours! * 60;
        }

        // دقائق زائدة بالفعل الآن (بحدود اليوم)
        final extraNow = (allowedToday > 0)
            ? (spentToday - allowedToday).clamp(0, double.infinity).toInt()
            : 0;

        // دقائق جديدة لم تُدفع بعد (قد تكون مغطاة جزئياً بالباقة)
        final minutesToCharge =
            (totalMinutes - s.paidMinutes).clamp(0, totalMinutes).toInt();

        // حساب كم من minutesToCharge سيغطيه الباقه وكم سيكون اضافي
        int coveredByPlan = 0;
        int extraIfPayNow = minutesToCharge;
        if (allowedToday > 0) {
          // قبل دقائق الجديدة كان spentToday - minutesToCharge
          final priorSpentToday =
              (spentToday - minutesToCharge).clamp(0, spentToday).toInt();
          final remainingAllowanceBefore =
              (allowedToday - priorSpentToday).clamp(0, allowedToday);
          coveredByPlan = (minutesToCharge <= remainingAllowanceBefore)
              ? minutesToCharge
              : remainingAllowanceBefore;
          extraIfPayNow = minutesToCharge - coveredByPlan;
        } else {
          coveredByPlan = 0;
          extraIfPayNow = minutesToCharge;
        }

        final extraChargeEstimate = _calculateTimeChargeFromMinutes(
          extraIfPayNow,
        );

        // منتجات الجلسة
        final productsTotal = s.cart.fold(0.0, (sum, item) => sum + item.total);

        // نص العرض
        final startStr = s.start.toLocal().toString().split('.').first;
        final endTime = getSubscriptionEnd(s);
        final endStr = endTime != null
            ? endTime.toLocal().toString().split('.').first
            : 'غير محدود';

        String timeInfo;
        if (s.subscription != null) {
          String dailyInfo = (allowedToday > 0)
              ? 'حد اليوم: ${_formatHoursMinutes(allowedToday)} • مضى اليوم: ${_formatHoursMinutes(spentToday)} • متبقي: ${_formatHoursMinutes((allowedToday - spentToday).clamp(0, allowedToday))}'
              : 'حد اليوم: غير محدود';
          timeInfo =
              'من: $startStr ⇢ ينتهي: $endStr\nمضى الكلي: ${_formatHoursMinutes(totalMinutes)} — $dailyInfo';
          if (extraNow > 0) {
            timeInfo +=
                '\n⛔ دقائق زائدة الآن: ${_formatHoursMinutes(extraNow)}';
          }
        } else {
          timeInfo =
              'من: $startStr\nمضى الكلي: ${_formatHoursMinutes(totalMinutes)}';
        }

        return Card(
          child: ListTile(
            title: Text(s.name),
            subtitle: Text(
              '${s.isActive ? (s.isPaused ? "متوقف مؤقت" : "نشط") : "انتهت"}\n$timeInfo',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (s.isActive)
                  ElevatedButton(
                    onPressed: () => _togglePauseSessionFor(s),
                    child: Text(s.isPaused ? 'استئناف' : 'ايقاف مؤقت'),
                  ),
                const SizedBox(width: 6),
                // استدعاء Dialog قبل الدفع
                if (s.isActive && !s.isPaused)
                  ElevatedButton(
                    onPressed: () async {
                      await _showReceiptDialog(
                        s,
                        productsTotal,
                        extraChargeEstimate,
                        extraIfPayNow,
                      );
                    },
                    child: const Text('ادفع الآن'),
                  ),

                /*  if (s.isActive && !s.isPaused)
                  ElevatedButton(
                    onPressed: () async {
                      // حساب المبلغ المطلوب الآن كما في الكود الحالي
                      final minutesToCharge =
                          (getSessionMinutes(s) - s.paidMinutes)
                              .clamp(0, getSessionMinutes(s))
                              .toInt();
                      final coveredByPlan =
                          (() {
                            // نفس منطق الحساب الذي استخدمته قبلًا لاستخراج coveredByPlan
                            int allowedToday = -1;
                            if (s.subscription != null &&
                                s.subscription!.dailyUsageType == 'limited' &&
                                s.subscription!.dailyUsageHours != null) {
                              allowedToday =
                                  s.subscription!.dailyUsageHours! * 60;
                            }
                            if (allowedToday > 0) {
                              final spentToday = getSessionMinutesToday(s);
                              final priorSpentToday =
                                  (spentToday - minutesToCharge)
                                      .clamp(0, spentToday)
                                      .toInt();
                              final remainingAllowanceBefore = (allowedToday -
                                      priorSpentToday)
                                  .clamp(0, allowedToday);
                              return minutesToCharge <= remainingAllowanceBefore
                                  ? minutesToCharge
                                  : remainingAllowanceBefore;
                            }
                            return 0;
                          })();

                      final extraIfPayNow = minutesToCharge - coveredByPlan;
                      final extraChargeEstimate =
                          _calculateTimeChargeFromMinutes(extraIfPayNow);
                      final productsTotal = s.cart.fold(
                        0.0,
                        (sum, item) => sum + item.total,
                      );
                      final requiredNow = extraChargeEstimate + productsTotal;

                      if (requiredNow <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('لا يوجد مستحقات للدفع الآن.'),
                          ),
                        );
                        return;
                      }

                      // حاول نلاقي العميل المسجل بالجلسة (أولوية: customerId داخل الجلسة ثم _currentCustomer ثم DB by name)
                      Customer? cust;
                      try {
                        // لو عندك customerId في Session استخدمها (مثال: s.customerId)
                        if ((s.customerId ?? '').isNotEmpty) {
                          // مثال: CustomerDb.getById موجود؟ لو لا استعمل getAll/getByName كما عندك
                          cust = await CustomerDb.getById(s.customerId!);
                        }
                      } catch (_) {}

                      // لو ما لقيناش عن طريق id جرب _currentCustomer أو البحث بالاسم
                      if (cust == null) {
                        cust = _currentCustomer;
                      }
                      if (cust == null) {
                        try {
                          final found = await CustomerDb.getByName(s.name);
                          if (found != null) cust = found;
                        } catch (_) {}
                      }

                      double balance = 0.0;
                      if (cust != null) {
                        // جرب من الذاكرة أولا
                        final cb = AdminDataService.instance.customerBalances
                            .firstWhere(
                              (b) => b.customerId == cust!.id,
                              orElse:
                                  () => CustomerBalance(
                                    customerId: cust!.id,
                                    balance: 0.0,
                                  ),
                            );
                        balance = cb.balance;
                        // لو القيمة صفر في الذاكرة، نحاول جلبها من DB كـ fallback
                        if (balance == 0.0) {
                          try {
                            balance = await AdminDataService.instance
                                .getCustomerBalance(cust.name);
                          } catch (_) {}
                        }
                      }

                      // لو فيه رصيد > 0، اعرض خيارات: استخدم الرصيد / كاش / مِكس
                      if (cust != null && balance > 0) {
                        final choice = await showDialog<String?>(
                          context: context,
                          builder:
                              (_) => AlertDialog(
                                title: const Text('طريقة الدفع'),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'رصيد العميل: ${balance.toStringAsFixed(2)} ج',
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'المطلوب الآن: ${requiredNow.toStringAsFixed(2)} ج',
                                    ),
                                    const SizedBox(height: 8),
                                    const Text('اختر كيف تريد تحصيل المبلغ:'),
                                  ],
                                ),
                                actions: [
                                  TextButton(
                                    onPressed:
                                        () => Navigator.pop(context, 'cash'),
                                    child: const Text('كاش فقط'),
                                  ),
                                  TextButton(
                                    onPressed:
                                        () => Navigator.pop(context, 'balance'),
                                    child: const Text('من رصيد العميل'),
                                  ),
                                  TextButton(
                                    onPressed:
                                        () => Navigator.pop(context, 'mixed'),
                                    child: const Text('رصيد + كاش (إن لزم)'),
                                  ),
                                ],
                              ),
                        );

                        if (choice == null) return;

                        if (choice == 'balance') {
                          // استخدم من الرصيد فقط (نفرض أنه يكفي أو نأخذ ما هو متاح كليًا)
                          final use =
                              balance >= requiredNow ? requiredNow : balance;
                          // خصم من رصيد العميل
                          await AdminDataService.instance.adjustCustomerBalance(
                            cust.name,
                            -use,
                          );
                          // حدّث الذاكرة سريعاً
                          final idx = AdminDataService.instance.customerBalances
                              .indexWhere((b) => b.customerId == cust!.id);
                          if (idx >= 0) {
                            AdminDataService
                                .instance
                                .customerBalances[idx] = CustomerBalance(
                              customerId: cust!.id,
                              balance:
                                  (AdminDataService
                                          .instance
                                          .customerBalances[idx]
                                          .balance -
                                      use),
                            );
                          } else {
                            AdminDataService.instance.customerBalances.add(
                              CustomerBalance(
                                customerId: cust!.id,
                                balance: 0.0,
                              ),
                            );
                          }

                          // سجّل مبيعة على أنها من رصيد العميل
                          final saleBalance = Sale(
                            id: generateId(),
                            description:
                                'دفعة من رصيد العميل ${cust.name} لجلسة ${s.name}',
                            amount: use,
                            paymentMethod: 'balance',
                            customerId: cust.id,
                          );
                          await AdminDataService.instance.addSale(
                            saleBalance,
                            paymentMethod: 'balance',
                            customer: cust,
                            updateDrawer: false,
                          );

                          // لو الرصيد لم يغطي المطلوب و requiredNow > use (نادر هنا لأن choice == 'balance' لكن نتحصّن)
                          final remaining = (requiredNow - use).clamp(
                            0.0,
                            double.infinity,
                          );
                          if (remaining > 0) {
                            // خُذ الباقي ككاش
                            final saleCash = Sale(
                              id: generateId(),
                              description: 'باقي دفعة كاش لجلسة ${s.name}',
                              amount: remaining,
                              paymentMethod: 'cash',
                              customerId: cust.id,
                            );
                            await AdminDataService.instance.addSale(
                              saleCash,
                              paymentMethod: 'cash',
                              customer: cust,
                              updateDrawer: true,
                            );
                          }

                          // حدّث الجلسة
                          s.paidMinutes += minutesToCharge;
                          s.amountPaid += requiredNow;
                          await SessionDb.updateSession(s);
                          await _loadDrawerBalance();
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'تم خصم ${use.toStringAsFixed(2)} ج من رصيد العميل.',
                              ),
                            ),
                          );
                          return;
                        }

                        if (choice == 'mixed') {
                          // استعمل أقصى ما يمكن من الرصيد ثم كاش للباقي
                          final useFromBalance =
                              balance >= requiredNow ? requiredNow : balance;
                          final cashNeeded = (requiredNow - useFromBalance)
                              .clamp(0.0, double.infinity);

                          if (useFromBalance > 0) {
                            await AdminDataService.instance
                                .adjustCustomerBalance(
                                  cust.name,
                                  -useFromBalance,
                                );
                            final idx = AdminDataService
                                .instance
                                .customerBalances
                                .indexWhere((b) => b.customerId == cust!.id);
                            if (idx >= 0) {
                              AdminDataService
                                  .instance
                                  .customerBalances[idx] = CustomerBalance(
                                customerId: cust!.id,
                                balance:
                                    (AdminDataService
                                            .instance
                                            .customerBalances[idx]
                                            .balance -
                                        useFromBalance),
                              );
                            } else {
                              AdminDataService.instance.customerBalances.add(
                                CustomerBalance(
                                  customerId: cust!.id,
                                  balance: 0.0,
                                ),
                              );
                            }
                            final saleBalance = Sale(
                              id: generateId(),
                              description:
                                  'دفعة من رصيد العميل ${cust.name} لجلسة ${s.name}',
                              amount: useFromBalance,
                              paymentMethod: 'balance',
                              customerId: cust.id,
                            );
                            await AdminDataService.instance.addSale(
                              saleBalance,
                              paymentMethod: 'balance',
                              customer: cust,
                              updateDrawer: false,
                            );
                          }

                          if (cashNeeded > 0) {
                            final saleCash = Sale(
                              id: generateId(),
                              description:
                                  'دفع كاش لباقي المبلغ لجلسة ${s.name}',
                              amount: cashNeeded,
                              paymentMethod: 'cash',
                              customerId: cust.id,
                            );
                            await AdminDataService.instance.addSale(
                              saleCash,
                              paymentMethod: 'cash',
                              customer: cust,
                              updateDrawer: true,
                            );
                          }

                          // حدّث الجلسة
                          s.paidMinutes += minutesToCharge;
                          s.amountPaid += requiredNow;
                          await SessionDb.updateSession(s);
                          await _loadDrawerBalance();
                          setState(() {});

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'تم الدفع: ${requiredNow.toStringAsFixed(2)} ج (منها ${useFromBalance.toStringAsFixed(2)} ج من الرصيد)',
                              ),
                            ),
                          );
                          return;
                        }

                        // choice == 'cash' falls through to normal cash handling
                      }

                      // إذا مافيش رصيد أو المستخدم اختار كاش:
                      // نفذ الدفع كاش كامل
                      // (نفس منطقك السابق)
                      final paidAmount = requiredNow;
                      s.paidMinutes += minutesToCharge;
                      s.amountPaid += paidAmount;
                      await SessionDb.updateSession(s);

                      final sale = Sale(
                        id: generateId(),
                        description:
                            'جلسة ${s.name} | دقائق مدفوعة: $minutesToCharge + منتجات: ${productsTotal.toStringAsFixed(2)}',
                        amount: paidAmount,
                        paymentMethod: 'cash',
                      );

                      await AdminDataService.instance.addSale(
                        sale,
                        paymentMethod: 'cash',
                        customer: cust,
                        updateDrawer: true,
                      );

                      try {
                        await _loadDrawerBalance();
                      } catch (e, st) {
                        debugPrint(
                          'Failed to update drawer after quick sale: $e\n$st',
                        );
                      }

                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '✅ تم الدفع ${paidAmount.toStringAsFixed(2)} ج',
                          ),
                        ),
                      );
                    },

                    child: const Text('ادفع الآن'),
                  ),*/
              ],
            ),
          ),
        );
      },
    );
  }

  /// 🔹 دالة المنتجات المباعة
  Widget _buildSalesList() {
    final sales = AdminDataService.instance.sales;

    if (sales.isEmpty) {
      return const Center(child: Text("لا يوجد منتجات مباعة"));
    }

    return ListView.builder(
      itemCount: sales.length,
      itemBuilder: (context, i) {
        final sale = sales[i];
        return Card(
          child: ListTile(
            title: Text(sale.description),
            subtitle: Text("المبلغ: ${sale.amount} ج"),
          ),
        );
      },
    );
  }
}

extension FirstWhereOrNullExtension<E> on List<E> {
  E? firstWhereOrNull(bool Function(E) test) {
    for (var element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}

/*  Future<void> _showReceiptDialog(
    Session s,
    double timeCharge,
    double productsTotal,
    int minutesToCharge,
  ) async {
    double discountValue = 0.0;
    String? appliedCode;
    final codeCtrl = TextEditingController();
    String paymentMethod = "cash";
    final TextEditingController paidCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            double finalTotal = timeCharge + productsTotal - discountValue;
            return AlertDialog(
              title: Text('إيصال الدفع - ${s.name}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('وقت الجلسة: ${timeCharge.toStringAsFixed(2)} ج'),
                    const SizedBox(height: 8),
                    ...s.cart.map(
                      (item) => Text(
                        '${item.product.name} x${item.qty} = ${item.total} ج',
                      ),
                    ),
                    const SizedBox(height: 12), // 🟢 اختيار وسيلة الدفع
                    Row(
                      children: [
                        const Text("طريقة الدفع: "),
                        const SizedBox(width: 8),
                        DropdownButton<String>(
                          value: paymentMethod,
                          items: const [
                            DropdownMenuItem(value: "cash", child: Text("كاش")),
                            DropdownMenuItem(
                              value: "wallet",
                              child: Text("محفظة"),
                            ),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() => paymentMethod = val);
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12), // 🟢
                    // المبلغ المطلوب
                    Text(
                      'المطلوب: ${finalTotal.toStringAsFixed(2)} ج',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8), // 🟢 إدخال المبلغ المدفوع
                    TextField(
                      controller: paidCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "المبلغ المدفوع",
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    // ✅ المبلغ المطلوب
                    final requiredAmount = finalTotal; // ✅ المبلغ المدفوع
                    final paidAmount =
                        double.tryParse(paidCtrl.text) ?? 0.0; // ✅ الفرق
                    final diff =
                        paidAmount - requiredAmount; // ✅ تحديث دقائق الدفع
                    s.paidMinutes += minutesToCharge;
                    s.amountPaid += paidAmount; // ✅ تحديث رصيد العميل
                    if (s.name.isNotEmpty) {
                      final oldBalance = AdminDataService
                          .instance
                          .customerBalances
                          .firstWhere(
                            (b) => b.customerId == s.name,
                            orElse:
                                () => CustomerBalance(
                                  customerId: s.name,
                                  balance: 0,
                                ),
                          );
                      final newBalance = oldBalance.balance + diff;
                      final updated = CustomerBalance(
                        customerId: s.name,
                        balance: newBalance,
                      );
                      await CustomerBalanceDb.upsert(updated);
                      final idx = AdminDataService.instance.customerBalances
                          .indexWhere((b) => b.customerId == s.name);
                      if (idx >= 0) {
                        AdminDataService.instance.customerBalances[idx] =
                            updated;
                      } else {
                        AdminDataService.instance.customerBalances.add(updated);
                      }
                    } // ✅ قفل الجلسة
                    setState(() {
                      s.isActive = false;
                      s.isPaused = false;
                    });
                    await SessionDb.updateSession(s); // ✅ حفظ كـ
                    Sale;
                    final sale = Sale(
                      id: generateId(),
                      description:
                          'جلسة ${s.name} | وقت: ${minutesToCharge} دقيقة + منتجات: ${s.cart.fold(0.0, (sum, item) => sum + item.total)}'
                          '${appliedCode != null ? " (بكود $appliedCode)" : ""}',
                      amount: paidAmount,
                    );
                    await AdminDataService.instance.addSale(
                      sale,
                      paymentMethod: paymentMethod,
                      customer: _currentCustomer,
                      updateDrawer: paymentMethod == "cash",
                    );
                    try {
                      await _loadDrawerBalance();
                    } catch (e, st) {
                      debugPrint('Failed to update drawer: $e\n$st');
                    }
                    Navigator.pop(context); // ✅ رسالة توضح الفلوس
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          diff == 0
                              ? '✅ دفع كامل: ${paidAmount.toStringAsFixed(2)} ج'
                              : diff > 0
                              ? '✅ دفع ${paidAmount.toStringAsFixed(2)} ج — باقي له ${diff.toStringAsFixed(2)} ج عندك'
                              : '✅ دفع ${paidAmount.toStringAsFixed(2)} ج — باقي عليك ${(diff.abs()).toStringAsFixed(2)} ج',
                        ),
                      ),
                    );
                  },
                  child: const Text('تأكيد الدفع'),
                ),
              ],
            );
          },
        );
      },
    );
  }*/

///subscrip paid
///if (currentPlan != null) {
//       // 🟢 افتح Dialog الدفع
//       final paid = await showDialog<bool>(
//         context: context,
//         builder:
//             (_) => ReceiptDialog(
//               session: session,
//               fixedAmount:
//                   currentPlan.price -
//                   (_appliedDiscount?.percent ?? 0.0) * currentPlan.price / 100,
//               description: 'اشتراك ${currentPlan.name}',
//             ),
//       );
//
//       if (paid == true) {
//         final basePrice = currentPlan.price;
//         final discountPercent = _appliedDiscount?.percent ?? 0.0;
//         final discountValue = basePrice * (discountPercent / 100);
//         final finalPrice = basePrice - discountValue;
//         debugPrint('basePrice: $basePrice');
//         debugPrint('discountPercent: $discountPercent');
//         debugPrint('discountValue: $discountValue');
//         debugPrint('finalPrice: $finalPrice');
//
//         session.amountPaid = finalPrice;
//
//         final sale = Sale(
//           id: generateId(),
//           description:
//               'اشتراك ${currentPlan.name} للعميل $name'
//               '${_appliedDiscount != null ? " (خصم ${_appliedDiscount!.percent}%)" : ""}',
//           amount: finalPrice,
//         );
//
//         try {
//           await AdminDataService.instance.addSale(
//             sale,
//             paymentMethod: 'cash',
//             customer: customer,
//             updateDrawer: true,
//           );
//
//           // 🔹 حساب معلومات الاشتراك للعرض
//           final nowStr = now.toLocal().toString();
//           final endStr = end?.toLocal().toString() ?? "غير محدود";
//
//           String durationInfo;
//           switch (currentPlan.durationType) {
//             case "hour":
//               durationInfo = "تنتهي بعد ${currentPlan.durationValue} ساعة";
//               break;
//             case "day":
//               durationInfo = "تنتهي بعد ${currentPlan.durationValue} يوم";
//               break;
//             case "week":
//               durationInfo = "تنتهي بعد ${currentPlan.durationValue} أسبوع";
//               break;
//             case "month":
//               durationInfo = "تنتهي بعد ${currentPlan.durationValue} شهر";
//               break;
//             default:
//               durationInfo =
//                   currentPlan.isUnlimited ? "غير محدودة" : "غير معروف";
//           }
//
//           String dailyLimitInfo = "";
//           if (currentPlan.dailyUsageType == "limited") {
//             dailyLimitInfo =
//                 "\nحد الاستخدام اليومي: ${currentPlan.dailyUsageHours} ساعة";
//           }
//
//           // 🔹 عرض Dialog بتفاصيل الاشتراك
//           await showDialog(
//             context: context,
//             builder:
//                 (_) => AlertDialog(
//                   title: Text("تفاصيل اشتراك ${currentPlan.name}"),
//                   content: Text(
//                     "العميل: $name\n"
//                     "السعر: ${finalPrice.toStringAsFixed(2)} ج\n"
//                     "بدأت: $nowStr\n"
//                     "تنتهي: $endStr\n"
//                     "$durationInfo\n"
//                     "$dailyLimitInfo",
//                   ),
//                   actions: [
//                     TextButton(
//                       onPressed: () => Navigator.pop(context),
//                       child: const Text("تمام"),
//                     ),
//                   ],
//                 ),
//           );
//
//           // 🔹 تحديث الرصيد ومسح الخصم لو single-use
//           if (_appliedDiscount?.singleUse == true) {
//             AdminDataService.instance.discounts.removeWhere(
//               (d) => d.id == _appliedDiscount!.id,
//             );
//             _appliedDiscount = null;
//           }
//
//           await _loadDrawerBalance();
//           ScaffoldMessenger.of(context).showSnackBar(
//             SnackBar(
//               content: Text(
//                 'تم دفع اشتراك ${currentPlan.name} (${finalPrice.toStringAsFixed(2)} ج)',
//               ),
//             ),
//           );
//         } catch (e, st) {
//           debugPrint('Failed to process quick sale: $e\n$st');
//           ScaffoldMessenger.of(context).showSnackBar(
//             const SnackBar(content: Text('فشل تسجيل الدفعة — حاول مرة أخرى')),
//           );
//         }
//       } else {
//         // لو لغى الدايالوج
//         return;
//       }
//     }
