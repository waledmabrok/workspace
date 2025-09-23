import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:workspace/utils/colors.dart';
import '../../core/FinanceDb.dart';
import '../../core/data_service.dart';
import '../../core/db_helper_cart.dart';
import '../../core/db_helper_customer_balance.dart';
import '../../core/db_helper_customers.dart';
import '../../core/db_helper_sessions.dart';
import '../../core/models.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import '../../core/product_db.dart';
import '../../widget/buttom.dart';
import '../../widget/dialog.dart';
import '../../widget/dialogSup.dart';
import 'notification.dart';

class AdminSubscribersPagee extends StatefulWidget {
  const AdminSubscribersPagee({super.key});

  @override
  AdminSubscribersPageeState createState() => AdminSubscribersPageeState();
}

class AdminSubscribersPageeState extends State<AdminSubscribersPagee> {
  @override
  bool get wantKeepAlive => true; // حافظ على الحالة
  DateTime _selectedDate = DateTime.now();
  List<Session> _sessionsSub = [];
  bool _loading = true;
  Timer? _uiTimer;
  Timer? _checkTimer;
  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Map<String, String>? formatEndDateParts(DateTime? date) {
    if (date == null) return null;

    final localDate = date.toLocal();

    // التاريخ فقط
    final datePart = DateFormat('yyyy/MM/dd', 'ar').format(localDate);

    // الوقت فقط بصيغة 12 ساعة مع AM/PM
    final timePart = DateFormat('hh:mm a', 'ar').format(localDate);

    return {'date': datePart, 'time': timePart};
  }

  @override
  void initState() {
    super.initState();
    _updateActiveSubscriptionsForNewDay();
    // مؤقّت واحد فقط مع فحص mounted
    /*_expiringTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (!mounted) return;
      checkExpiringSessionsSub(context, _sessionsSub);
    });
*/
    _loadSessionsSub().then((_) => _applyDailyLimitForAllSessionsSub());
    reloadData();
    /*  _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
*/
    /*   _checkTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      if (!_loading) _applyDailyLimitForAllSessionsSub();
    });*/
  }

  @override
  void dispose() {
    //  _expiringTimer?.cancel();
    _uiTimer?.cancel();
    _checkTimer?.cancel();
    super.dispose();
  }

  ///load from cashier=====================================
  Future<void> reloadData() async {
    await _loadSessionsSub(); // تحديث مباشر
    if (mounted) setState(() {});

    /* _expiringTimer?.cancel();
    _expiringTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!mounted || _loading) return;
      await _applyDailyLimitForAllSessionsSub();
    });*/
  }

  List<Session> _filtered = [];
  List<Session> _all = [];
  String _searchQuery = "";

  void applySearch(String query) {
    setState(() {
      _searchQuery = query;
    });
  }

  List<Session> _filteredSessionsSup = [];

  ///=============================================================
  Future<void> _ensureSnapshot(Session s) async {
    if (s.subscription != null && s.savedSubscriptionJson == null) {
      s.savedSubscriptionJson = jsonEncode(s.subscription!.toJson());
      s.savedSubscriptionEnd = _getSubscriptionEndSub(s);
      s.savedElapsedMinutes = s.elapsedMinutes;
      s.savedDailySpent = _minutesOverlapWithDateSub(s, DateTime.now());
      s.savedSubscriptionConvertedAt = DateTime.now();
      await SessionDb.updateSession(s);
      debugPrint("💾 Snapshot auto-saved for ${s.name}");
    }
  }

  Future<void> checkExpiringSessionsSub(
    BuildContext context,
    List<Session> allSessions,
  ) async {
    final now = DateTime.now();

    for (var s in allSessions) {
      if (s.subscription == null) continue;

      // حد يومي
      final plan = s.subscription!;
      if (plan.dailyUsageType == 'limited' && plan.dailyUsageHours != null) {
        final spentToday = _minutesOverlapWithDateSub(s, now);
        final allowedToday = plan.dailyUsageHours! * 60;

        if (spentToday >= allowedToday && s.dailyLimitNotified != true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                "⚠️ ${s.name} وصل حد الباقة اليومي — سيكمل على سعر الحر",
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
          s.dailyLimitNotified = true;
          await SessionDb.updateSession(s);
        }
      }

      // الاشتراك نفسه قرب ينتهي
      if (s.end != null && now.isBefore(s.end!)) {
        final remaining = s.end!.difference(now);
        if (remaining.inMinutes <= 50 && s.expiringNotified != true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("⚠️ ${s.name} اشتراكه قرب يخلص"),
              backgroundColor: Colors.yellow,
              duration: Duration(seconds: 4),
            ),
          );
          s.expiringNotified = true;
          await SessionDb.updateSession(s);
        }
      }

      // الاشتراك انتهى
      if (s.end != null && now.isAfter(s.end!) && s.expiredNotified != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("⛔ ${s.name} اشتراكه انتهى"),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
        s.expiredNotified = true;
        await SessionDb.updateSession(s);
      }
    }
  }

  Timer? _expiringTimer;

  Future<void> _updateActiveSubscriptionsForNewDay() async {
    final now = DateTime.now();

    for (final s in _sessionsSub) {
      if (s.type == "باقة" && s.isActive) {
        // لو لم يتم حفظ نسخة لليوم الجديد بعد
        if (s.savedSubscriptionJson == null ||
            (s.savedSubscriptionEnd != null &&
                s.savedSubscriptionEnd!.day != now.day)) {
          s.savedSubscriptionJson = jsonEncode(s.subscription?.toJson());
          s.savedSubscriptionEnd = s.end;

          // مهم: مسح علامة التحويل القديمة لأنها تخص يوم سابق
          //   s.savedSubscriptionConvertedAt = null;

          await SessionDb.updateSession(s);

          debugPrint('💾 Updated saved subscription for ${s.name} for new day');
        }
      }
    }

    if (mounted) setState(() {});
  }

  double? _getSubscriptionProgress(Session s) {
    final end = _getSubscriptionEndSub(s);
    if (end == null) return null;

    final total = end.difference(s.start).inMinutes;
    if (total <= 0) return null;

    final elapsed = getSessionMinutesSub(s); // هنا بيتحسب الوقف المؤقت صح
    final progress = elapsed / total;
    return progress.clamp(0.0, 1.0);
  }

  Future<void> _saveSessionWithEvent(
    Session s,
    String action, {
    Map<String, dynamic>? meta,
  }) async {
    s.addEvent(action, meta: meta);
    await SessionDb.updateSession(s);
    if (mounted) setState(() {});
  }

  Future<void> _confirmAndConvertToPaygSub(
    Session s, {
    String reason = 'manual',
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('تحويل الجلسة إلى حر'),
            content: Text(
              'هل تريد تحويل الجلسة "${s.name}" إلى سعر الحر الآن؟ السبب: $reason',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('الغاء'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('تحويل'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;

    // حفظ نسخة الاشتراك القديم لو مش محفوظة
    // حفظ نسخة الاشتراك القديم لو مش محفوظة
    if (s.savedSubscriptionJson == null && s.subscription != null) {
      s.savedSubscriptionJson = jsonEncode(s.subscription!.toJson());
      s.savedSubscriptionEnd = _getSubscriptionEndSub(s);
      await SessionDb.updateSession(s);
      debugPrint("💾 Snapshot saved before converting ${s.name} to payg");
    }

    // نفّذ التحويل
    s.subscription = null;
    s.type = 'حر';

    s.runningSince = DateTime.now();
    s.isPaused = false;

    // ===== مهم: افرغ/اعد تهيئة حقول الوقت كي لا يتحسب وقت الباقة كـ payg =====
    s.savedSubscriptionConvertedAt = DateTime.now();
    s.elapsedMinutes = 0; // ابدأ العد من الصفر للـ payg
    s.paidMinutes = 0; // لا يوجد مدفوعات مسبقة للـ payg الجديدة
    // s.pauseStart = DateTime.now();
    // لو عندك frozenMinutes استخدمها حسب رغبتك (غالباً تبقى 0 بعد التحويل)
    s.frozenMinutes = s.frozenMinutes ?? 0;

    s.addEvent('converted_to_payg', meta: {'reason': reason});
    await SessionDb.updateSession(s);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم تحويل الجلسة إلى حر.')));
      setState(() {});
    }
  }

  void _maybeNotifyDailyLimitApproachingSub(Session s) {
    final plan = s.subscription;
    if (plan == null ||
        plan.dailyUsageType != 'limited' ||
        plan.dailyUsageHours == null)
      return;

    final spentToday = _minutesOverlapWithDateSub(s, DateTime.now());
    final allowedToday = plan.dailyUsageHours! * 60;
    final remaining = allowedToday - spentToday;

    if (remaining > 0 && remaining <= 10) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تبقى $remaining دقيقة من الباقة اليوم — بعد ذلك سيكمل على سعر الحر',
            ),
          ),
        );
      }

      Timer(Duration(minutes: remaining), () async {
        final idx = _sessionsSub.indexWhere((x) => x.id == s.id);
        if (idx == -1) return;
        final stillSession = _sessionsSub[idx];
        if (!mounted) return;

        final planNow = stillSession.subscription;
        if (planNow == null ||
            planNow.dailyUsageType != 'limited' ||
            planNow.dailyUsageHours == null)
          return;

        final newSpentToday = _minutesOverlapWithDateSub(
          stillSession,
          DateTime.now(),
        );
        final newRemaining = planNow.dailyUsageHours! * 60 - newSpentToday;
        if (newRemaining <= 0) {
          // تحويل تلقائي (بدون تأكيد) لأن الوقت انتهى
          if (stillSession.savedSubscriptionJson == null &&
              stillSession.subscription != null) {
            stillSession.savedSubscriptionJson = jsonEncode(
              stillSession.subscription!.toJson(),
            );
          }
          stillSession.subscription = null;
          stillSession.type = 'حر';
          stillSession.addEvent(
            'converted_to_payg',
            meta: {'reason': 'daily_limit'},
          );
          await SessionDb.updateSession(stillSession);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'انتهى حد الباقة اليوم. الجلسة الآن تعمل على سعر الحر.',
                ),
              ),
            );
            setState(() {});
          }
        }
      });
    }
  }

  Future<void> _loadSessionsSub() async {
    setState(() => _loading = true);
    final data = await SessionDb.getSessions();

    setState(() {
      _all = data;
      _filtered = List.from(_all);
    });
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
    debugPrint("⏳ [_applyDailyLimitForAllSessions] Checking at $now ...");

    final toConvert = <Session>[];

    for (var s in _sessionsSub) {
      debugPrint(
        "Checking ${s.name}: originalId=${s.originalSubscriptionId}, savedJson=${s.savedSubscriptionJson}",
      );

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
        // فقط إذا لم يتم تحويلها مسبقًا
        if (s.originalSubscriptionId == null &&
            s.savedSubscriptionJson == null &&
            s.type != 'حر') {
          await convertSubscriptionToPayg_CreateNew(s);
        }
      }
    }

    await _loadSessionsSub();
    if (mounted) {
      setState(() {}); // تحديث الواجهة فورًا
    }
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

  String getSessionFormattedTimeSub(Session s) {
    final minutes = getSessionMinutesSub(s);
    if (minutes < 60) {
      return "$minutes دقيقة"; // أقل من ساعة
    }
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (mins == 0) {
      return "$hours ساعة"; // ساعات بس
    }
    return "$hours ساعة و $mins دقيقة";
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

  Future<void> pauseSessionSub(Session s) async {
    final now = DateTime.now();
    if (!s.isPaused) {
      final since = s.runningSince ?? s.start;
      final diff = now.difference(since).inMinutes;

      if (s.type == 'حر') {
        s.elapsedMinutesPayg += diff;
      } else {
        s.elapsedMinutes += diff;
      }

      s.isPaused = true;
      s.runningSince = null;
      await SessionDb.updateSession(s);
    }
  }

  Future<void> resumeSessionSub(Session s) async {
    if (s.isPaused) {
      s.isPaused = false;
      s.runningSince = DateTime.now();
      await SessionDb.updateSession(s);
    }
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

  String _formatMinutesSub(int minutes) {
    if (minutes <= 0) return "0د";
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0) return "${h}س ${m}د";
    return "${m}د";
  }

  double _calculateTimeChargeFromMinutesSub(int minutes) {
    final settings = AdminDataService.instance.pricingSettings;
    if (minutes <= settings.firstFreeMinutes) return 0;
    if (minutes <= 60) return settings.firstHourFee;
    final extraHours = ((minutes - 60) / 60).ceil();
    double amount =
        settings.firstHourFee + extraHours * settings.perHourAfterFirst;
    if (amount > settings.dailyCap) amount = settings.dailyCap;
    return amount;
  }

  /* Future<void> _chargePayAsYouGoOnStopSub(Session s) async {
    if (s.type != 'حر') return; // لا نحسب إذا لم تكن حالة حر

    final totalMinutes = getSessionMinutesSub(s);
    final diff = totalMinutes - s.paidMinutes;
    final minutesToCharge = diff > 0 ? diff.toInt() : 0;
    if (minutesToCharge <= 0) return;

    final amount = _calculateTimeChargeFromMinutesSub(minutesToCharge);
    final sale = Sale(
      id: generateId(),
      description: 'دفع وقت - جلسة ${s.name}',
      amount: amount,
    );
    await AdminDataService.instance.addSale(
      sale,
      paymentMethod: 'cash',
      updateDrawer: true,
    );
    s.paidMinutes += minutesToCharge;
    s.addEvent('charged', meta: {'minutes': minutesToCharge, 'amount': amount});
    await SessionDb.updateSession(s);
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'دُفعت ${amount.toStringAsFixed(2)} ج لوقت ${_formatMinutesSub(minutesToCharge)}',
          ),
        ),
      );
  }*/
  Future<double> _chargePayAsYouGoOnStopSub(Session s) async {
    if (s.type != 'حر') return 0; // لا نحسب إذا لم تكن حالة حر

    final totalMinutes = getSessionMinutesSub(s);
    final diff = totalMinutes - s.paidMinutes;
    final minutesToCharge = diff > 0 ? diff.toInt() : 0;
    if (minutesToCharge <= 0) return 0;

    final amount = _calculateTimeChargeFromMinutesSub(minutesToCharge);

    final sale = Sale(
      id: generateId(),
      description: 'دفع وقت - جلسة ${s.name}',
      amount: amount,
    );
    await AdminDataService.instance.addSale(
      sale,
      paymentMethod: 'cash',
      updateDrawer: true,
    );

    s.paidMinutes += minutesToCharge;
    s.addEvent('charged', meta: {'minutes': minutesToCharge, 'amount': amount});
    await SessionDb.updateSession(s);

    return amount;
  }

  Future<void> _restoreSavedSubscription(Session s) async {
    if (s.savedSubscriptionJson == null) return;

    try {
      // 1) إغلاق أي جلسات Pay-as-you-go مرتبطة
      final all = await SessionDb.getSessions();
      final relatedPaygs =
          all
              .where((x) => x.originalSubscriptionId == s.id && x.type == 'حر')
              .toList();
      /*for (final p in relatedPaygs) {
        // أولاً احسب المبلغ المستحق
        final amount = await _chargePayAsYouGoOnStopSub(p);
        // دالة لحساب المبلغ المستحق فقط
        Future<double> getPaygAmount(Session s) async {
          final minutes = getSessionMinutesSub(s) - s.paidMinutes;
          if (minutes <= 0) return 0;
          return _calculateTimeChargeFromMinutesSub(minutes);
        }

        for (final p in relatedPaygs) {
          final amount = await getPaygAmount(p); // ترجع double
          if (amount > 0) {
            final paid = await showDialog<bool>(
              context: context,
              builder:
                  (_) => ReceiptDialog(
                    session: p,
                    fixedAmount: amount,
                    description: 'دفع وقت حر قبل استعادة الباقة',
                  ),
            );
            if (paid != true) {
              p.addEvent('restore_failed_due_to_unpaid');
              continue;
            }
          }
        }

        p.isActive = false;
        p.isPaused = true;
        p.addEvent('closed_on_restore_of_parent');
        await SessionDb.updateSession(p);
      }*/
      for (final p in relatedPaygs) {
        final amount = await _chargePayAsYouGoOnStopSub(p); // الحساب
        if (amount > 0) {
          final paid = await showDialog<bool>(
            context: context,
            builder:
                (_) => ReceiptDialog(
                  session: p,
                  fixedAmount: amount,
                  description: 'دفع وقت حر قبل استعادة الباقة',
                ),
          );
          if (paid != true) {
            p.addEvent('restore_failed_due_to_unpaid');
            await SessionDb.updateSession(p);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('لم يتم الدفع، الباقة لم تُستأنف'),
                ),
              );
            }
            return; // توقف الاستعادة لو ما دفعش
          }
        }

        // ⚠️ حتى لو amount = 0، لازم نقفل الجلسة الحر
        p.isActive = false;
        p.isPaused = true;
        p.addEvent('closed_on_restore_of_parent');
        await SessionDb.updateSession(p);
      }

      // 2) استعادة الاشتراك الأصلي
      final map = jsonDecode(s.savedSubscriptionJson!);
      final restoredPlan = SubscriptionPlan.fromJson(
        Map<String, dynamic>.from(map),
      );

      s.subscription = restoredPlan;
      s.type = "باقة";

      if (s.savedSubscriptionEnd != null) s.end = s.savedSubscriptionEnd;
      s.elapsedMinutes = s.savedElapsedMinutes ?? 0;

      // ✅ مسح كل snapshot/flags القديمة
      s.savedSubscriptionJson = null;
      s.savedSubscriptionEnd = null;
      s.savedElapsedMinutes = null;
      s.savedDailySpent = null;
      s.savedSubscriptionConvertedAt = null;
      s.resumeNextDayRequested = false;
      s.resumeDate = null;

      s.isActive = true;
      s.isPaused = false;
      s.runningSince = DateTime.now();

      s.addEvent('restored_subscription');
      await SessionDb.updateSession(s);

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم استئناف الباقة بنجاح')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('حدث خطأ أثناء الاستعادة')),
        );
      }
    }
  }

  Future<void> resumeSubscription(Session s) async {
    if (s.savedSubscriptionJson != null) {
      await _restoreSavedSubscription(s);
      return;
    }

    // لو مفيش snapshot، نرجع للجلسة العادية
    await resumeSessionSub(s);
  }

  Future<void> convertSubscriptionToPayg_CreateNew(Session sub) async {
    final now = DateTime.now();
    // 🛑 تحقق إذا كانت الجلسة تم تحويلها مسبقًا
    if (sub.originalSubscriptionId != null ||
        sub.savedSubscriptionJson != null) {
      debugPrint("🚫 Session ${sub.name} already converted to PAYG");
      return;
    }
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

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم إنشاء جلسة حر جديدة من الباقة: ${sub.name}'),
        ),
      );
    }
  }

  Widget _buildEventTile(Map<String, dynamic> ev) {
    final ts = ev['ts'] ?? '';
    final action = ev['action'] ?? '';
    final meta = ev['meta'] ?? {};
    String label = action;
    switch (action) {
      case 'started':
        label = 'بدأت الجلسة';
        break;
      case 'resumed':
        label = 'استئناف';
        break;
      case 'paused':
        label = 'إيقاف مؤقت';
        break;
      case 'converted_to_payg':
        label = 'تحويل لحر';
        break;
      case 'charged':
        label = 'تحصيل وقت';
        break;
      case 'paid_now':
        label = 'دفع الآن';
        break;
      case 'restored_subscription':
        label = 'استعادة باقة';
        break;
      case 'started_payg':
        label = 'بدأت الجلسة (حر)';
        break;
      case 'paused_payg':
        label = 'إيقاف مؤقت (حر)';
        break;
      case 'resumed_payg':
        label = 'استئناف (حر)';
        break;
      default:
        label = action;
    }
    return ListTile(
      dense: true,
      title: Text(label),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(ts.toString()),
          if (meta != null && meta.isNotEmpty)
            Text(meta.toString(), style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  int getSubscriptionMinutes(Session s) {
    final now = DateTime.now();

    if (s.isPaused) {
      // واقف مؤقت → احسب لحد pauseStart
      return s.pauseStart != null
          ? s.pauseStart!.difference(s.start).inMinutes
          : now.difference(s.start).inMinutes;
    } else {
      // شغال → احسب لحد دلوقتي
      return now.difference(s.start).inMinutes;
    }
  }

  Future<void> _renewSubscription(Session s) async {
    final plan =
        s.subscription ??
        (s.savedSubscriptionJson != null
            ? SubscriptionPlan.fromJson(jsonDecode(s.savedSubscriptionJson!))
            : null);

    if (plan == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('لا توجد باقة للتجديد')));
      return;
    }

    // نحسب المبلغ المطلوب للتجديد
    double amount = plan.price ?? 0.0;

    // عرض ReceiptDialog
    final paid = await showDialog<bool>(
      context: context,
      builder:
          (_) => ReceiptDialog(
            session: s,
            fixedAmount: amount,
            description: 'تجديد باقة: ${plan.name}',
          ),
    );

    if (paid != true) {
      // المستخدم لم يدفع → لا نبدأ الباقة
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إلغاء التجديد لعدم الدفع')),
      );
      return;
    }

    // ✅ بعد الدفع → بدء نفس الباقة
    s.type = "باقة";
    s.start = DateTime.now();
    s.elapsedMinutes = 0;
    s.isPaused = false;
    s.runningSince = DateTime.now();
    s.pauseStart = null;

    // تحديد نهاية الاشتراك بناءً على الخطة نفسها
    if (plan.durationType == "hour") {
      s.end = DateTime.now().add(Duration(hours: plan.durationValue ?? 1));
    } else if (plan.durationType == "day") {
      s.end = DateTime.now().add(Duration(days: plan.durationValue ?? 1));
    } else if (plan.durationType == "month") {
      s.end = DateTime(
        DateTime.now().year,
        DateTime.now().month + (plan.durationValue ?? 1),
        DateTime.now().day,
        DateTime.now().hour,
        DateTime.now().minute,
      );
    } else {
      s.end = DateTime.now().add(const Duration(hours: 1));
    }

    s.isActive = true;
    await SessionDb.updateSession(s);
    setState(() {});

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم تجديد الباقة وبدأت الجلسة')),
    );
  }

  @override
  Widget build(BuildContext context) {
    /* final filteredSessions =
        _sessions.where((s) {
          final d = s.start;
          return d.year == _selectedDate.year &&
              d.month == _selectedDate.month &&
              d.day == _selectedDate.day;
        }).toList();

    */
    ////===========================
    final filteredSessions =
        _sessionsSub.where((s) {
          final wasSubscriber =
              s.subscription != null || s.savedSubscriptionJson != null;

          if (s.end == null) return wasSubscriber;

          final dayStart = DateTime(
            _selectedDate.year,
            _selectedDate.month,
            _selectedDate.day,
          );
          final dayEnd = dayStart.add(const Duration(days: 1));

          final overlaps = s.start.isBefore(dayEnd) && s.end!.isAfter(dayStart);

          // فلترة بالبحث
          final matchesSearch = s.name.toLowerCase().contains(
            _searchQuery.toLowerCase(),
          );

          return wasSubscriber && overlaps && matchesSearch;
        }).toList();

    ////==================================================================

    /*  final filteredSessions =
        _sessions.where((s) {
          final isSubscriber = s.subscription != null; // مشترك فقط

          // لو الجلسة لسه شغالة، خليها تظهر في اليوم الحالي
          if (s.end == null) {
            return isSubscriber;
          }

          // لو الجلسة انتهت، نشوف هل تاريخها يغطي اليوم المختار
          final dayStart = DateTime(
            _selectedDate.year,
            _selectedDate.month,
            _selectedDate.day,
          );
          final dayEnd = dayStart.add(const Duration(days: 1));

          final sessionStart = s.start;
          final sessionEnd = s.end!;

          final overlaps =
              sessionStart.isBefore(dayEnd) && sessionEnd.isAfter(dayStart);

          return isSubscriber && overlaps;
        }).toList();

*/
    // الآن نعرض كل الجلسات (حتى اللي تحولت لحر)، لكن نميّزهم بصرياً.
    final list =
        _sessionsSub.toList()..sort((a, b) => a.name.compareTo(b.name));

    return Scaffold(
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Text(
                          "عرض ليوم: ",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          child: Text(
                            "${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}",
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white.withOpacity(
                              0,
                            ), // خلفية شفافة
                            foregroundColor: Colors.white, // لون النص والأيقونة
                            shadowColor: Colors.transparent, // إزالة الظل
                            side: BorderSide(
                              color: AppColorsDark.mainColor,
                              width: 1.5,
                            ), // البوردر
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                8,
                              ), // تقويس الحواف
                            ),
                          ),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _selectedDate,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              setState(() {
                                _selectedDate = DateTime(
                                  picked.year,
                                  picked.month,
                                  picked.day,
                                );
                              });
                            }
                          },
                        ),

                        const SizedBox(width: 12),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white.withOpacity(
                              0,
                            ), // خلفية شفافة
                            foregroundColor: Colors.white, // لون النص والأيقونة
                            shadowColor: Colors.transparent, // إزالة الظل
                            side: BorderSide(
                              color: AppColorsDark.mainColor,
                              width: 1.5,
                            ), // البوردر
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                8,
                              ), // تقويس الحواف
                            ),
                          ),
                          onPressed:
                              () => setState(
                                () => _selectedDate = DateTime.now(),
                              ),
                          child: const Text("اليوم"),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child:
                        list.isEmpty
                            ? const Center(child: Text('لا توجد جلسات'))
                            : ListView.builder(
                              itemCount: filteredSessions.length,
                              itemBuilder: (ctx, i) {
                                final s = filteredSessions[i];

                                final plan =
                                    s.subscription ??
                                    (s.savedSubscriptionJson != null
                                        ? SubscriptionPlan.fromJson(
                                          jsonDecode(s.savedSubscriptionJson!),
                                        )
                                        : null);

                                // عدد الدقائق المسموح بها اليوم
                                final allowedToday =
                                    (plan != null &&
                                            plan.dailyUsageType == 'limited' &&
                                            plan.dailyUsageHours != null)
                                        ? plan.dailyUsageHours! * 60
                                        : -1; // -1 يعني لا حد يومي

                                // عدد الدقائق المستهلكة اليوم

                                // هل وصل الحد اليومي؟

                                // يمكن تفعيل زر الإيقاف فقط لو الجلسة نشطة والحد اليومي لم ينتهِ

                                final isSub = plan != null;
                                final endParts = formatEndDateParts(
                                  _getSubscriptionEndSub(s),
                                );
                                final spentToday = _minutesOverlapWithDateSub(
                                  s,
                                  _selectedDate,
                                );
                                final isLimitReached =
                                    isSub &&
                                    allowedToday > 0 &&
                                    spentToday >= allowedToday;

                                final totalSoFar =
                                    s.type == "باقة"
                                        ? getSubscriptionMinutes(s)
                                        : getSessionMinutesSub(s);
                                final canPause = s.isActive && !isLimitReached;
                                // DEBUG
                                /*debugPrint(
  'DBG SESSION ${s.name} -> start=${s.start}, elapsedMinutesField=${s.elapsedMinutes}, '
  'totalSoFar=$totalSoFar, pauseStart=${s.pauseStart}, isPaused=${s.isPaused}, '
  'isActive=${s.isActive}, plan=$plan',
);*/

                                final remaining =
                                    allowedToday > 0
                                        ? (allowedToday - spentToday)
                                        : -1;

                                final minutesToCharge =
                                    ((totalSoFar - s.paidMinutes).clamp(
                                      0,
                                      totalSoFar > 0 ? totalSoFar : 0,
                                    )).toInt();
                                final isSubActive =
                                    s.type == "باقة" && s.isActive;
                                final canPauseButton =
                                    isSubActive &&
                                    canPause; // canPause حسب منطقك

                                // badge
                                final badge =
                                    isSub
                                        ? InkWell(
                                          onTap: () {
                                            print('تم الضغط على الباقة');
                                          },
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          child: Container(
                                            width: 85, // يملأ كل العرض المتاح
                                            height: 37,

                                            decoration: BoxDecoration(
                                              color: Colors.green.withOpacity(
                                                0.1,
                                              ), // لون الخلفية
                                              borderRadius:
                                                  BorderRadius.circular(
                                                    8,
                                                  ), // تقوس الحواف
                                              border: Border.all(
                                                color:
                                                    Colors.green, // لون البوردر
                                                width: 1, // سمك البوردر
                                              ),
                                            ),
                                            child: const Center(
                                              child: Text(
                                                'باقة',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          ),
                                        )
                                        : Chip(
                                          label: Text('حر'),
                                          backgroundColor: Colors.black,
                                        );

                                String stopButtonText = 'إيقاف';
                                if (s.isActive && !s.isPaused) {
                                  if (isSub &&
                                      allowedToday > 0 &&
                                      remaining > 0)
                                    stopButtonText = 'إيقاف (هيكمل كباقة)';
                                  else if (isSub)
                                    stopButtonText = 'إيقاف (هيبدأ حر)';
                                  else
                                    stopButtonText = 'إيقاف';
                                }

                                return Card(
                                  color: AppColorsDark.bgCardColor,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: BorderSide(
                                      color: AppColorsDark.mainColor
                                          .withOpacity(0.4),
                                      width: 1.5,
                                    ),
                                  ),
                                  /* color:
                                      (isSub &&
                                              s.end != null &&
                                              s.end!.isBefore(DateTime.now()))
                                          ? Colors.grey
                                          : null,*/
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Text(
                                                        s.name,
                                                        style: const TextStyle(
                                                          fontSize: 18,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 10),
                                                      badge,
                                                      const SizedBox(width: 10),
                                                      if (s.savedSubscriptionJson !=
                                                          null)
                                                        const Icon(
                                                          Icons.bookmark,
                                                          size: 22,
                                                          color:
                                                              Colors
                                                                  .transparent,
                                                        ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 6),
                                                  if (allowedToday > 0)
                                                    Text(
                                                      allowedToday > 0
                                                          ? 'حد الاستخدام اليومي: ${_formatMinutesSub(allowedToday)}'
                                                          : 'حد الاستخدام اليومي: غير محدود',
                                                    ),
                                                  /* مدفوع: ${_formatMinutesSub(s.paidMinutes)}*/
                                                  Text(
                                                    'مضى وقت: ${getSessionFormattedTimeSub(s)}   ',
                                                  ),
                                                  if (isSub)
                                                    /* Text(
                                                      'تنتهي الباقة: ${_getSubscriptionEndSub(s)?.toLocal().toString().split('.').first ?? 'غير محددة'}',
                                                    ),*/
                                                    Row(
                                                      children: [
                                                        Text(
                                                          'تنتهي الباقة في يوم: ${endParts?['date'] ?? 'غير محدد'}',
                                                        ),
                                                        const SizedBox(
                                                          width: 8,
                                                        ),
                                                        Text(
                                                          'وعند الساعة: ${endParts?['time'] ?? 'غير محدد'}',
                                                        ),
                                                      ],
                                                    ),
                                                ],
                                              ),
                                            ),
                                            Row(
                                              children: [
                                                // 👇 لو الاشتراك انتهى
                                                if (s.end != null &&
                                                    DateTime.now().isAfter(
                                                      s.end!,
                                                    )) ...[
                                                  CustomButton(
                                                    color: Colors.orange,
                                                    text: "تجديد الباقة",
                                                    onPressed: () async {
                                                      // هنا تعمل منطق تجديد الباقة (مثلاً ترجع الاشتراك القديم أو تفتح شاشة اختيار خطة جديدة)
                                                      await _renewSubscription(
                                                        s,
                                                      );
                                                      if (mounted)
                                                        setState(() {});
                                                    },
                                                    infinity: false,
                                                  ),
                                                ] else ...[
                                                  // زر استئناف باقة (لو محفوظة + في يوم جديد)
                                                  if (s.savedSubscriptionJson !=
                                                      null) ...[
                                                    if (s.savedSubscriptionConvertedAt !=
                                                        null)
                                                      if (!_isSameDay(
                                                        s.savedSubscriptionConvertedAt!,
                                                        DateTime.now(),
                                                      ))
                                                        CustomButton(
                                                          infinity: false,
                                                          color: Colors.green,
                                                          text: 'كمل باقتك',
                                                          onPressed:
                                                              () =>
                                                                  _restoreSavedSubscription(
                                                                    s,
                                                                  ),
                                                        ),
                                                  ],

                                                  const SizedBox(width: 10),
                                                  CustomButton(
                                                    infinity: false,
                                                    border:
                                                        s.isPaused
                                                            ? false
                                                            : true,
                                                    color: Colors.transparent,
                                                    text:
                                                        s.isPaused
                                                            ? 'استكمال الوقت'
                                                            : 'إيقاف مؤقت',
                                                    onPressed:
                                                        canPauseButton
                                                            ? () async {
                                                              final now =
                                                                  DateTime.now();

                                                              if (!s.isPaused) {
                                                                // Pause الباقة
                                                                final from =
                                                                    s.runningSince ??
                                                                    s.start;
                                                                final consumed =
                                                                    now
                                                                        .difference(
                                                                          from,
                                                                        )
                                                                        .inMinutes;
                                                                if (consumed >
                                                                    0)
                                                                  s.elapsedMinutes +=
                                                                      consumed;

                                                                s.isPaused =
                                                                    true;
                                                                s.pauseStart =
                                                                    now;
                                                                s.runningSince =
                                                                    null;

                                                                await _saveSessionWithEvent(
                                                                  s,
                                                                  'paused',
                                                                  meta: {
                                                                    'consumedAdded':
                                                                        consumed,
                                                                  },
                                                                );
                                                              } else {
                                                                // Resume الباقة
                                                                int frozen = 0;
                                                                if (s.pauseStart !=
                                                                    null) {
                                                                  frozen =
                                                                      now
                                                                          .difference(
                                                                            s.pauseStart!,
                                                                          )
                                                                          .inMinutes;
                                                                  if (s.end !=
                                                                      null)
                                                                    s.end = s.end!.add(
                                                                      Duration(
                                                                        minutes:
                                                                            frozen,
                                                                      ),
                                                                    );
                                                                }

                                                                s.isPaused =
                                                                    false;
                                                                s.pauseStart =
                                                                    null;
                                                                s.runningSince =
                                                                    now;

                                                                await _saveSessionWithEvent(
                                                                  s,
                                                                  'resumed',
                                                                  meta: {
                                                                    'frozenMinutesAdded':
                                                                        frozen,
                                                                  },
                                                                );
                                                              }

                                                              await SessionDb.updateSession(
                                                                s,
                                                              );
                                                              if (mounted)
                                                                setState(() {});
                                                            }
                                                            : null,
                                                  ),
                                                  SizedBox(width: 6),
                                                  s.isActive
                                                      ? CustomButton(
                                                        infinity: false,
                                                        text: " اضف منتجات",
                                                        onPressed: () async {
                                                          final selectedSession =
                                                              s;

                                                          await showModalBottomSheet(
                                                            context: context,
                                                            isScrollControlled:
                                                                true,
                                                            builder:
                                                                (
                                                                  _,
                                                                ) => _buildAddProductsAndPay(
                                                                  selectedSession,
                                                                ),
                                                          );

                                                          setState(() {
                                                            _filteredSessionsSup =
                                                                _sessionsSub;
                                                          });
                                                        },
                                                      )
                                                      : const SizedBox.shrink(),

                                                  // زر البدء/ايقاف الموحد يتصرف بحسب نوع الجلسة
                                                  /* ElevatedButton(
                                                    onPressed:
                                                        canPauseButton
                                                            ? () async {
                                                              final now =
                                                                  DateTime.now();

                                                              if (!s.isPaused) {
                                                                // Pause الباقة
                                                                final from =
                                                                    s.runningSince ??
                                                                    s.start;
                                                                final consumed =
                                                                    now
                                                                        .difference(
                                                                          from,
                                                                        )
                                                                        .inMinutes;
                                                                if (consumed >
                                                                    0)
                                                                  s.elapsedMinutes +=
                                                                      consumed;

                                                                s.isPaused =
                                                                    true;
                                                                s.pauseStart =
                                                                    now;
                                                                s.runningSince =
                                                                    null;

                                                                await _saveSessionWithEvent(
                                                                  s,
                                                                  'paused',
                                                                  meta: {
                                                                    'consumedAdded':
                                                                        consumed,
                                                                  },
                                                                );
                                                              } else {
                                                                // Resume الباقة
                                                                int frozen = 0;
                                                                if (s.pauseStart !=
                                                                    null) {
                                                                  frozen =
                                                                      now
                                                                          .difference(
                                                                            s.pauseStart!,
                                                                          )
                                                                          .inMinutes;
                                                                  if (s.end !=
                                                                      null)
                                                                    s.end = s.end!.add(
                                                                      Duration(
                                                                        minutes:
                                                                            frozen,
                                                                      ),
                                                                    );
                                                                }

                                                                s.isPaused =
                                                                    false;
                                                                s.pauseStart =
                                                                    null;
                                                                s.runningSince =
                                                                    now;

                                                                await _saveSessionWithEvent(
                                                                  s,
                                                                  'resumed',
                                                                  meta: {
                                                                    'frozenMinutesAdded':
                                                                        frozen,
                                                                  },
                                                                );
                                                              }

                                                              await SessionDb.updateSession(
                                                                s,
                                                              );
                                                              if (mounted)
                                                                setState(() {});
                                                            }
                                                            : null,
                                                    child: Text(
                                                      s.isPaused
                                                          ? 'استمر'
                                                          : 'إيقاف مؤقت',
                                                    ),
                                                  ),*/

                                                  /*     const SizedBox(width: 6),

                                                  ElevatedButton(
                                                    onPressed: () {
                                                      final result = showDialog(
                                                        context: context,
                                                        builder: (
                                                          BuildContext context,
                                                        ) {
                                                          return ReceiptDialog(
                                                            session: s,
                                                          );
                                                        },
                                                      );

                                                      if (result == true) {
                                                        setState(() {
                                                          // 🔄 هنا تعمل تحديث للصفحة (مثلاً إعادة تحميل الدرج أو تحديث الليستة)
                                                        });
                                                      }
                                                    },

                                                    */
                                                  /* _showReceiptDialog(s),*/
                                                  /*
                                                    child: const Text("تفاصيل"),
                                                  ),*/
                                                ],
                                              ],
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        // بدل الشرط الحالي
                                        if (_getSubscriptionProgress(s) !=
                                                null &&
                                            s.end != null &&
                                            s.end!.isAfter(DateTime.now())) ...[
                                          const SizedBox(height: 6),
                                          /*      */
                                          /* LinearProgressIndicator(
                                            value: _getSubscriptionProgress(s),
                                            backgroundColor: Colors.grey[300],
                                            color: Colors.blueAccent,
                                            borderRadius:
                                                const BorderRadius.all(
                                                  Radius.circular(12),
                                                ),
                                            valueColor: AlwaysStoppedAnimation<
                                              Color
                                            >(
                                              _getSubscriptionProgress(s)! < 0.5
                                                  ? Colors.green
                                                  : (_getSubscriptionProgress(
                                                            s,
                                                          )! <
                                                          0.8
                                                      ? Colors.orange
                                                      : Colors.red),
                                            ),
                                            minHeight: 8,
                                          ),*/
                                          /*
                                          Text(
                                            "${((_getSubscriptionProgress(s)! * 100).toStringAsFixed(0))}%",
                                            style: const TextStyle(
                                              fontSize: 15,
                                              color: Colors.white,
                                            ),
                                          ),
                                          // Timeline section
                                          ExpansionTile(
                                            title: const Text(
                                              'Timeline & تفاصيل الجلسة',
                                            ),
                                            children: [
                                              Padding(
                                                padding: const EdgeInsets.all(
                                                  8.0,
                                                ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'بداية الجلسة: ${s.start.toLocal()}',
                                                    ),
                                                    if (s.pauseStart != null)
                                                      Text(
                                                        'آخر إيقاف مؤقت: ${s.pauseStart!.toLocal()}',
                                                      ),
                                                    Text(
                                                      'Elapsed (دقيقة): ${getSessionMinutesSub(s)}',
                                                    ),
                                                    const SizedBox(height: 8),
                                                    const Text(
                                                      'سجل الأحداث:',
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                    if (s.events.isEmpty)
                                                      const Padding(
                                                        padding: EdgeInsets.all(
                                                          8.0,
                                                        ),
                                                        child: Text(
                                                          'لا توجد أحداث بعد',
                                                        ),
                                                      ),
                                                    ...s.events.reversed
                                                        .map(
                                                          (ev) =>
                                                              _buildEventTile(
                                                                ev,
                                                              ),
                                                        )
                                                        .toList(),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),*/
                                        ] else ...[
                                          // هنا يظهر مكانهم كلمة expired
                                          const Padding(
                                            padding: EdgeInsets.all(8.0),
                                            child: Text(
                                              '⛔ انتهت الباقة ',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.red,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                  ),
                ],
              ),
    );
  }

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

  Map<String, TextEditingController> qtyControllers = {};
  Customer? _currentCustomer;
  Widget _buildAddProductsAndPay(Session s) {
    Future<void> _showReceiptDialog(Session s, double productsTotal) async {
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
              double finalTotal = productsTotal - discountValue;

              return AlertDialog(
                title: Text(
                  'إيصال الدفع - ${s.name} (الرصيد: ${customerBalance.toStringAsFixed(2)} ج)',
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      ...s.cart.map(
                        (item) => Text(
                          '${item.product.name} x${item.qty} = ${item.total} ج',
                        ),
                      ),

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

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '💵 أخذ العميل باقي ${diff.toStringAsFixed(2)} ج كاش من الدرج',
                            ),
                          ),
                        );
                      }

                      // تحديث دقائق الدفع
                      //    s.paidMinutes += minutesToCharge;
                      s.amountPaid += paidAmount;

                      // ---- قفل الجلسة وتحديث DB ----
                      /* setState(() {
                        s.isActive = false;
                        s.isPaused = false;
                      });
                      await SessionDb.updateSession(s);
*/
                      // حفظ المبيعة كما هي
                      final sale = Sale(
                        id: generateId(),
                        description:
                            'جلسة ${s.name} |   منتجات: ${s.cart.fold(0.0, (sum, item) => sum + item.total)}',
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
                      /* s.paidMinutes += minutesToCharge;*/
                      s.amountPaid += paidAmount;

                      // ---- تحديث رصيد العميل بشكل صحيح ----
                      // 1) نحدد customerId الهدف: نفضل s.customerId ثم _currentCustomer
                      String? targetCustomerId =
                          s.customerId ?? _currentCustomer?.id;

                      // 2) لو لسه فاضي حاول نبحث عن العميل بالاسم، وإن لم يوجد - ننشئ واحد جديد
                      if (targetCustomerId == null ||
                          targetCustomerId.isEmpty) {
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
                        final oldBalance = AdminDataService
                            .instance
                            .customerBalances
                            .firstWhere(
                              (b) => b.customerId == targetCustomerId,
                              orElse:
                                  () => CustomerBalance(
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
                            .indexWhere(
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

                      /*   // ---- قفل الجلسة وتحديث DB ----
                      setState(() {
                        s.isActive = false;
                        s.isPaused = false;
                      });
                      await SessionDb.updateSession(s);
*/
                      // ---- حفظ المبيعة ----
                      final sale = Sale(
                        id: generateId(),
                        description:
                            'جلسة ${s.name} | منتجات: ${s.cart.fold(0.0, (sum, item) => sum + item.total)}'
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

    void _completeAndPayForProducts(Session s) async {
      final productsTotal = s.cart.fold(0.0, (sum, item) => sum + item.total);

      if (productsTotal == 0) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("لا يوجد منتجات للإتمام")));
        return;
      }

      await _showReceiptDialog(
        s,
        productsTotal,
        // مفيش دقائق شحن هنا
      );
    }

    Product? selectedProduct;
    TextEditingController qtyCtrl = TextEditingController(text: '1');

    return StatefulBuilder(
      builder: (context, setSheetState) {
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
                items:
                    AdminDataService.instance.products.map((p) {
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
                    child: TextField(
                      controller: qtyCtrl,
                      style: const TextStyle(color: Colors.white),
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'عدد',
                        labelStyle: const TextStyle(color: Colors.white70),
                        filled: true,
                        fillColor: Colors.grey[800],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CustomButton(
                    text: "اضف",
                    onPressed: () async {
                      if (selectedProduct == null) return;

                      final qty = int.tryParse(qtyCtrl.text) ?? 1;
                      if (qty <= 0) return;

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
                  /* ElevatedButton(
                    onPressed: () async {
                      final qty = int.tryParse(qtyCtrl.text) ?? 1;
                      if (selectedProduct != null) {
                        final item = CartItem(
                          id: generateId(),
                          product: selectedProduct!,
                          qty: qty,
                        );

                        await CartDb.insertCartItem(item, s.id);

                        final updatedCart = await CartDb.getCartBySession(s.id);
                        setSheetState(() => s.cart = updatedCart);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'اضف',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),*/
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
                          await CartDb.deleteCartItem(item.id);

                          // إعادة الكمية للمخزون
                          item.product.stock += item.qty;
                          final idx = AdminDataService.instance.products
                              .indexWhere((p) => p.id == item.product.id);
                          if (idx != -1)
                            AdminDataService.instance.products[idx].stock =
                                item.product.stock;

                          s.cart.remove(item);
                          setSheetState(() {});
                        },
                      ),
                    ],
                  ),
                );
              }).toList(),
              const SizedBox(height: 12),
              CustomButton(
                text: "إتمام ودفع",
                onPressed: () async {
                  Navigator.pop(context);
                  // 1️⃣ افتح نافذة الدفع أولًا
                  _completeAndPayForProducts(s);

                  // 2️⃣ خصم المخزون من المنتجات
                  for (var item in s.cart) {
                    await sellProduct(item.product, item.qty);

                    // 3️⃣ امسح الـ controller
                    qtyControllers[item.id]?.dispose();
                    qtyControllers.remove(item.id);
                  }

                  // 4️⃣ مسح الكارت من الذاكرة وDB
                  for (var item in s.cart) {
                    await CartDb.deleteCartItem(item.id);
                  }
                  s.cart.clear();

                  // 5️⃣ حدث الـ UI
                  setSheetState(() {});
                },
                infinity: false,
                color: Colors.green,
              ),
            ],
          ),
        );
      },
    );
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
}

/* Future<void> _showReceiptDialog(Session s) async {
    // ==== E) safer calculations in _showReceiptDialog (snippet)
    final totalMinutes = getSessionMinutes(s);
    final spentToday = _minutesOverlapWithDate(s, _selectedDate);
    int allowedToday = -1;
    if (s.subscription != null &&
        s.subscription!.dailyUsageType == 'limited' &&
        s.subscription!.dailyUsageHours != null) {
      allowedToday = s.subscription!.dailyUsageHours! * 60;
    }

    final minutesDiff = totalMinutes - s.paidMinutes;
    final minutesToCharge = minutesDiff > 0 ? minutesDiff.toInt() : 0;

    // continue with coveredByPlan / extraIfPayNow using safe min/max as above
    final extraNow =
        (allowedToday > 0)
            ? (spentToday - allowedToday).clamp(0, double.infinity).toInt()
            : 0;
    int coveredByPlan = 0;
    int extraIfPayNow = minutesToCharge;
    if (allowedToday > 0) {
      final priorSpentToday =
          (spentToday - minutesToCharge).clamp(0, spentToday).toInt();
      final remainingAllowanceBefore = (allowedToday - priorSpentToday).clamp(
        0,
        allowedToday,
      );
      coveredByPlan =
          (minutesToCharge <= remainingAllowanceBefore)
              ? minutesToCharge
              : remainingAllowanceBefore;
      extraIfPayNow = minutesToCharge - coveredByPlan;
    }
    final extraChargeEstimate = _calculateTimeChargeFromMinutes(extraIfPayNow);
    final productsTotal = s.cart.fold(0.0, (sum, item) => sum + item.total);
    final requiredNow = extraChargeEstimate + productsTotal;
    final remaining = allowedToday > 0 ? (allowedToday - spentToday) : -1;

    await showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('تفاصيل الدفع - ${s.name}'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("الحالة: ${s.subscription != null ? 'باقة' : 'حر'}"),
                  Text("تاريخ البداية: ${s.start.toLocal().toString()}"),
                  if (s.pauseStart != null)
                    Text(
                      "آخر إيقاف مؤقت عند: ${s.pauseStart!.toLocal().toString()}",
                    ),
                  Text("مضى كلي: ${_formatMinutes(totalMinutes)}"),
                  Text(' مدفوع: ${_formatMinutes(s.paidMinutes)}'),
                  if (s.subscription != null)
                    Text(
                      'المتبقي من الباقة: ${_getSubscriptionEnd(s) != null ? _formatMinutes(_getSubscriptionEnd(s)!.difference(DateTime.now()).inMinutes) : "غير محدود"}',
                    ),
                  if (s.subscription != null && _getSubscriptionEnd(s) != null)
                    Text(
                      'انتهاء الاشتراك: ${_getSubscriptionEnd(s)!.toLocal().toString().split(".").first}',
                    ),
                  if (allowedToday > 0)
                    Text('المتبقي من اليوم: ${_formatMinutes(remaining)}'),

                  if (allowedToday > 0)
                    Text(
                      "اليوم: ${_formatMinutes(spentToday)} / ${_formatMinutes(allowedToday)}",
                    ),
                  if (extraNow > 0)
                    Text("⛔ دقائق زائدة الآن: ${_formatMinutes(extraNow)}"),
                  const SizedBox(height: 10),
                  Text("المنتجات:"),
                  ...s.cart.map(
                    (item) => Text(
                      "${item.product.name} x${item.qty} = ${item.total} ج",
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text("المطلوب الآن: ${requiredNow.toStringAsFixed(2)} ج"),
                ],
              ),
            ),
            actions: [
              ElevatedButton(
                onPressed: () async {
                  s.paidMinutes += minutesToCharge;
                  s.addEvent(
                    'paid_now',
                    meta: {
                      'amount': requiredNow,
                      'minutesPaid': minutesToCharge,
                    },
                  );
                  await SessionDb.updateSession(s);
                  if (mounted)
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          "✅ تم الدفع ${requiredNow.toStringAsFixed(2)} ج",
                        ),
                      ),
                    );
                  setState(() {});
                  Navigator.pop(context);
                },
                child: const Text("ادفع الآن"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("إغلاق"),
              ),
            ],
          ),
    );
  }
  /* Future<void> _showReceiptDialog(
      Session s,
      double timeCharge,
      double productsTotal,
      int minutesToCharge,
      ) async {
    double discountValue = 0.0;
    String? appliedCode;
    final codeCtrl = TextEditingController();

    String paymentMethod = "cash"; // افتراضي: كاش
    final TextEditingController paidCtrl = TextEditingController();

    // 🔹 حساب المنطق بتاع الباقة
    final totalMinutes = getSessionMinutes(s);
    final spentToday = _minutesOverlapWithDate(s, _selectedDate);

    int allowedToday = -1;
    if (s.subscription != null &&
        s.subscription!.dailyUsageType == 'limited' &&
        s.subscription!.dailyUsageHours != null) {
      allowedToday = s.subscription!.dailyUsageHours! * 60;
    }

    final minutesDiff = totalMinutes - s.paidMinutes;
    final minutesToChargeSafe = minutesDiff > 0 ? minutesDiff.toInt() : 0;

    final extraNow =
    (allowedToday > 0)
        ? (spentToday - allowedToday).clamp(0, double.infinity).toInt()
        : 0;
    int coveredByPlan = 0;
    int extraIfPayNow = minutesToChargeSafe;
    if (allowedToday > 0) {
      final priorSpentToday =
      (spentToday - minutesToChargeSafe).clamp(0, spentToday).toInt();
      final remainingAllowanceBefore = (allowedToday - priorSpentToday).clamp(
        0,
        allowedToday,
      );
      coveredByPlan =
      (minutesToChargeSafe <= remainingAllowanceBefore)
          ? minutesToChargeSafe
          : remainingAllowanceBefore;
      extraIfPayNow = minutesToChargeSafe - coveredByPlan;
    }

    final extraChargeEstimate = _calculateTimeChargeFromMinutes(extraIfPayNow);

    // 🔹 إجمالي المطلوب (زيادة فقط + منتجات - خصم)
    double finalTotal =
        extraChargeEstimate + productsTotal - discountValue;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('إيصال الدفع - ${s.name}'),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("الحالة: ${s.subscription != null ? 'باقة' : 'حر'}"),
                    Text("إجمالي الوقت: ${_formatMinutes(totalMinutes)}"),
                    Text("مدفوع سابقًا: ${_formatMinutes(s.paidMinutes)}"),

                    if (allowedToday > 0)
                      Text(
                        "اليوم: ${_formatMinutes(spentToday)} / ${_formatMinutes(allowedToday)}",
                      ),
                    if (coveredByPlan > 0)
                      Text("✅ متغطي بالباقة: ${_formatMinutes(coveredByPlan)}"),
                    if (extraIfPayNow > 0)
                      Text("⛔ زيادة مدفوعة: ${_formatMinutes(extraIfPayNow)}"),

                    const SizedBox(height: 10),
                    Text("وقت زائد (فلوس): ${extraChargeEstimate.toStringAsFixed(2)} ج"),
                    const SizedBox(height: 8),
                    Text("منتجات: ${productsTotal.toStringAsFixed(2)} ج"),
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        const Text("طريقة الدفع: "),
                        const SizedBox(width: 8),
                        DropdownButton<String>(
                          value: paymentMethod,
                          items: const [
                            DropdownMenuItem(value: "cash", child: Text("كاش")),
                            DropdownMenuItem(value: "wallet", child: Text("محفظة")),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() => paymentMethod = val);
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    Text(
                      'المطلوب: ${finalTotal.toStringAsFixed(2)} ج',
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

                    Builder(
                      builder: (_) {
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
                ElevatedButton(
                  onPressed: () async {
                    final paidAmount = double.tryParse(paidCtrl.text) ?? 0.0;
                    final diff = paidAmount - finalTotal;
                    if (paidAmount < finalTotal) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('⚠️ المبلغ المدفوع أقل من المطلوب.'),
                        ),
                      );
                      return;
                    }

                    // ✅ سجل دقائق الدفع (الزيادة فقط)
                    s.paidMinutes += minutesToCharge;
                    s.amountPaid += paidAmount;

                    setState(() {
                      s.isActive = false;
                      s.isPaused = false;
                    });
                    await SessionDb.updateSession(s);

                    final sale = Sale(
                      id: generateId(),
                      description:
                      'جلسة ${s.name} | ${extraIfPayNow} دقيقة زيادة + منتجات: ${productsTotal}',
                      amount: paidAmount,
                    );

                    await AdminDataService.instance.addSale(
                      sale,
                      paymentMethod: paymentMethod,
                      customer: _currentCustomer,
                      updateDrawer: paymentMethod == "cash",
                    );

                    Navigator.pop(context);

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '✅ دفع ${paidAmount.toStringAsFixed(2)} ج',
                        ),
                      ),
                    );
                  },
                  child: const Text("تأكيد الدفع"),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("إلغاء"),
                ),
              ],
            );
          },
        );
      },
    );
  }*/
*/

// ======== استبدل هذه الدالة بالكامل =========
/* int _minutesOverlapWithDate(Session s, DateTime date) {
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    // بداية الجلسة الفعلية
    final actualStart = s.start;

    // إذا بدت الجلسة بعد نهاية اليوم فليس هناك تداخل
    if (actualStart.isAfter(dayEnd)) return 0;

    // حساب المجموع الكلي للدقائق التي مضت منذ بداية الجلسة (دفاعي)
    final totalMinutes = getSessionMinutes(s);

    // بناء نهاية الجلسة التقديرية من بداية الجلسة + دقائق مضت
    var sessEndCandidate = actualStart.add(Duration(minutes: totalMinutes));

    // لا تسمح أن تكون النهاية أبعد من "الآن" (لا نحسب وقت من المستقبل)
    final now = DateTime.now();
    if (sessEndCandidate.isAfter(now)) sessEndCandidate = now;

    // إذا الجلسة منتهية في الحقل use s.end بدل الحساب
    if (s.end != null) {
      sessEndCandidate = s.end!;
      if (sessEndCandidate.isAfter(now)) sessEndCandidate = now;
    }

    // قيد البداية والنهاية داخل حدود اليوم
    final sessStart = actualStart.isBefore(dayStart) ? dayStart : actualStart;
    final sessEnd =
        sessEndCandidate.isAfter(dayEnd) ? dayEnd : sessEndCandidate;

    if (sessEnd.isBefore(dayStart) || sessStart.isAfter(dayEnd)) return 0;

    final overlap = sessEnd.difference(sessStart).inMinutes;
    return overlap < 0 ? 0 : overlap;
  }*/
//////////////////////////
/*Future<void> _applyDailyLimitForAllSessions() async {
    final now = DateTime.now();
    final toUpdate = <Session>[];
    for (var s in List<Session>.from(_sessions)) {
      final plan = s.subscription;
      if (plan == null ||
          plan.dailyUsageType != 'limited' ||
          plan.dailyUsageHours == null)
        continue;

      final spentToday = _minutesOverlapWithDate(s, now);
      final allowedToday = plan.dailyUsageHours! * 60;

      if (spentToday >= allowedToday) {
        if (s.savedSubscriptionJson == null && s.subscription != null)
          s.savedSubscriptionJson = jsonEncode(s.subscription!.toJson());
        s.subscription = null;
        s.type = 'حر';
        s.addEvent('converted_to_payg', meta: {'reason': 'daily_limit'});
        toUpdate.add(s);
      }
    }

    if (toUpdate.isNotEmpty) {
      for (var s in toUpdate) await SessionDb.updateSession(s);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${toUpdate.length} جلسة تحولت إلى حر لبلوغها الحد اليومي',
            ),
          ),
        );
        setState(() {});
      }
    }
  }*/
//
/*  Future<void> _chargePayAsYouGoOnStop(Session s) async {
    // ==== D) fixed minutesToCharge example (use in _chargePayAsYouGoOnStop)
    final totalMinutes = getSessionMinutes(s);
    final diff = totalMinutes - s.paidMinutes;
    final minutesToCharge = diff > 0 ? diff.toInt() : 0;
    if (minutesToCharge <= 0) return;

    final amount = _calculateTimeChargeFromMinutes(minutesToCharge);
    final sale = Sale(
      id: generateId(),
      description: 'دفع وقت - جلسة ${s.name}',
      amount: amount,
    );
    await AdminDataService.instance.addSale(
      sale,
      paymentMethod: 'cash',
      updateDrawer: true,
    );
    s.paidMinutes += minutesToCharge;
    s.addEvent('charged', meta: {'minutes': minutesToCharge, 'amount': amount});
    await SessionDb.updateSession(s);
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'دُفعت ${amount.toStringAsFixed(2)} ج لوقت ${_formatMinutes(minutesToCharge)}',
          ),
        ),
      );
  }*/

/*Future<void> _restoreSavedSubscription(Session s) async {
    if (s.savedSubscriptionJson == null) return;
    try {
      final map = jsonDecode(s.savedSubscriptionJson!);
      final restored = SubscriptionPlan.fromJson(
        Map<String, dynamic>.from(map),
      );
      s.subscription = restored;
      s.savedSubscriptionJson = null;
      s.resumeNextDayRequested = false;
      s.resumeDate = null;
      if (!s.isActive) {
        s.isActive = true;
        s.pauseStart = DateTime.now();
      }
      s.addEvent('restored_subscription');
      await SessionDb.updateSession(s);
      setState(() {});
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم استئناف باقتك')));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('خطأ في استعادة الباقة')));
    }
  }*/

/*DateTime? _getSubscriptionEnd(Session s) {
    final plan = s.subscription;
    if (plan == null || plan.isUnlimited) return null;
    final start = s.start;
    switch (plan.durationType) {
      case "hour":
        return start.add(Duration(hours: plan.durationValue ?? 0));
      case "day":
        return start.add(Duration(days: plan.durationValue ?? 0));
      case "week":
        return start.add(Duration(days: 7 * (plan.durationValue ?? 0)));
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
  }*/

/*

  @override
  void initState() {
    super.initState();
    // خزّن المؤقت عشان نقدر نوقفه في dispose لاحقاً
    _expiringTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      // لو الـ State متفكك خلاص ما تعملش حاجة
      if (!mounted) return;
      checkExpiringSessions(context, _sessions);
    });

    Timer.periodic(const Duration(minutes: 5), (_) {
      checkExpiringSessions(context, _sessions);
    });
    _loadSessions().then((_) => _applyDailyLimitForAllSessions());
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _checkTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_loading) _applyDailyLimitForAllSessions();
    });
  }

  @override
  void dispose() {
    _expiringTimer?.cancel();
    _uiTimer?.cancel();
    _checkTimer?.cancel();
    super.dispose();
  }
*/

/*  int _minutesOverlapWithDate(Session s, DateTime date) {
    // 👇 إذا الجلسة دلوقتي حر فنرجع 0 — لا نحسب وقت بعد التحويل كباقي باقة
    if (s.type == 'حر') return 0;

    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    // بداية الجلسة الفعلية
    final actualStart = s.start;

    // إذا بدت الجلسة بعد نهاية اليوم فليس هناك تداخل
    if (actualStart.isAfter(dayEnd)) return 0;

    // حساب المجموع الكلي للدقائق التي مضت منذ بداية الجلسة (دفاعي)
    final totalMinutes = getSessionMinutes(s);

    // بناء نهاية الجلسة التقديرية من بداية الجلسة + دقائق مضت
    var sessEndCandidate = actualStart.add(Duration(minutes: totalMinutes));

    // لا تسمح أن تكون النهاية أبعد من "الآن" (لا نحسب وقت من المستقبل)
    final now = DateTime.now();
    if (sessEndCandidate.isAfter(now)) sessEndCandidate = now;

    // إذا الجلسة منتهية في الحقل use s.end بدل الحساب
    if (s.end != null) {
      sessEndCandidate = s.end!;
      if (sessEndCandidate.isAfter(now)) sessEndCandidate = now;
    }

    // قيد البداية والنهاية داخل حدود اليوم
    final sessStart = actualStart.isBefore(dayStart) ? dayStart : actualStart;
    final sessEnd =
        sessEndCandidate.isAfter(dayEnd) ? dayEnd : sessEndCandidate;

    if (sessEnd.isBefore(dayStart) || sessStart.isAfter(dayEnd)) return 0;

    final overlap = sessEnd.difference(sessStart).inMinutes;
    return overlap < 0 ? 0 : overlap;
  }*/

/*  int getSessionMinutes(Session s) {
    // قاعدة مبدئية من القيمة المخزنة (الزمن المجمّع سابقاً)
    int base = s.elapsedMinutes;
    if (base < 0) base = 0;

    // لو الجلسة غير نشطة أو موقوفة نرجع القيمة المخزنة فقط
    if (!s.isActive || s.isPaused) {
      debugPrint(
        'DBG getSessionMinutes => ${s.name}: base=$base isActive=${s.isActive} isPaused=${s.isPaused} pauseStart=${s.pauseStart}',
      );
      return base;
    }

    // الجلسة حالياً نشطة -> نحسب الوقت الجاري منذ آخر resume (أو منذ start)
    final since =
        s.pauseStart ?? s.start; // pauseStart هنا يمثل آخر resume/start
    final running = DateTime.now().difference(since).inMinutes;
    final runningNonNegative = running < 0 ? 0 : running;

    final total = base + runningNonNegative;
    return total < 0 ? 0 : total;
  }*/

/*Future<void> _confirmAndConvertToPayg(
    Session s, {
    String reason = 'manual',
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('تحويل الجلسة إلى حر'),
            content: Text(
              'هل تريد تحويل الجلسة "${s.name}" إلى سعر الحر الآن؟ السبب: $reason',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('الغاء'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('تحويل'),
              ),
            ],
          ),
    );

    if (confirmed != true) return;

    */ /* if (s.subscription != null && s.savedSubscriptionJson == null) {
      s.savedSubscriptionJson = jsonEncode(s.subscription!.toJson());
    }*/ /*
    if (s.savedSubscriptionJson == null && s.subscription != null) {
      s.savedSubscriptionJson = jsonEncode(s.subscription!.toJson());
      s.savedSubscriptionEnd = _getSubscriptionEnd(s);
    }
    s.subscription = null;
    s.type = 'حر';
    s.addEvent('converted_to_payg', meta: {'reason': reason});
    await SessionDb.updateSession(s);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم تحويل الجلسة إلى حر.')));
      setState(() {});
    }
  }*/

/*
Future<void> _toggleSession(Session s) async {
  final now = DateTime.now();

  // =========================
  // حالة وجود باقة (subscriber)
  // =========================
  if (s.subscription != null) {
    if (!s.isActive) {
      // بدء الجلسة (من متوقف)
      s.isActive = true;
      s.isPaused = false;
      s.pauseStart = now; // يمثل آخر resume
      await _saveSessionWithEvent(s, 'started');
      _maybeNotifyDailyLimitApproaching(s);
    } else if (s.isPaused) {
      // استئناف الباقة -> نمدد نهاية الباقة بمدة التجميد
      if (s.pauseStart != null && s.end != null) {
        final frozen = now.difference(s.pauseStart!).inMinutes;
        if (frozen > 0) {
          s.end = s.end!.add(Duration(minutes: frozen));
        }
      }
      s.isPaused = false;
      s.pauseStart = now; // يمثل آخر resume
      await _saveSessionWithEvent(s, 'resumed');
      _maybeNotifyDailyLimitApproaching(s);
    } else {
      // إيقاف باقة الآن (نجمدها) - لا نلمس elapsedMinutes
      s.isPaused = true;
      s.pauseStart = now; // يمثل بداية الإيقاف (pause start)
      await _saveSessionWithEvent(s, 'paused');

      // نفحص المتبقي اليومي
      final plan = s.subscription;
      final spentToday = _minutesOverlapWithDate(s, DateTime.now());
      final allowedToday =
      (plan != null &&
          plan.dailyUsageType == 'limited' &&
          plan.dailyUsageHours != null)
          ? plan.dailyUsageHours! * 60
          : -1;

      if (plan != null && allowedToday > 0 && spentToday <= allowedToday) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'تم الإيقاف — تبقى ضمن الباقة (${_formatMinutes(allowedToday - spentToday)})',
              ),
            ),
          );
        }
      } else {
        // لا باقة متبقية -> تحويل إلى حر (نطلب تأكيد)
        await _confirmAndConvertToPayg(s, reason: 'exhausted_on_pause');
        // بعد التحويل نححتسب ونحصّل إن لزم
        await _chargePayAsYouGoOnStop(s);
      }
    }
  } else {
    // =========================
    // حالة الجلسة حر (payg)
    // =========================
    if (!s.isActive) {
      // بدء جلسة حر
      s.isActive = true;
      s.isPaused = false;
      s.pauseStart = now; // يمثل آخر resume
      await _saveSessionWithEvent(s, 'started_payg');
    } else if (s.isPaused) {
      // استئناف حر -> نعيّن آخر resume
      s.isPaused = false;
      s.pauseStart = now;
      await _saveSessionWithEvent(s, 'resumed_payg');
    } else {
      // إيقاف حر -> نجمع الدقائق منذ آخر resume (أو منذ start)
      final since = s.pauseStart ?? s.start;
      final added = now.difference(since).inMinutes;
      if (added > 0) {
        s.elapsedMinutes += added;
      }
      s.isPaused = true;
      s.pauseStart = now; // يمثل بداية الإيقاف
      await _saveSessionWithEvent(
        s,
        'paused_payg',
        meta: {'addedMinutes': added},
      );
      // عند إيقاف payg نحسب ونجمع
      await _chargePayAsYouGoOnStop(s);
    }
  }

  await SessionDb.updateSession(s);
  if (mounted) setState(() {});
}*/
