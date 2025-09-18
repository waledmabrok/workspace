import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/data_service.dart';
import '../../core/db_helper_cart.dart';
import '../../core/db_helper_sessions.dart';
import '../../core/models.dart';
import 'dart:convert';

import '../../widget/dialog.dart';
import 'notification.dart';

class AdminSubscribersPagee extends StatefulWidget {
  const AdminSubscribersPagee({super.key});

  @override
  State<AdminSubscribersPagee> createState() => _AdminSubscribersPageState();
}

class _AdminSubscribersPageState extends State<AdminSubscribersPagee> {
  DateTime _selectedDate = DateTime.now();
  List<Session> _sessions = [];
  bool _loading = true;
  Timer? _uiTimer;
  Timer? _checkTimer;
  Future<void> checkExpiringSessions(
    BuildContext context,
    List<Session> allSessions,
  ) async {
    final now = DateTime.now();
    final expiring = <Session>[];
    final expired = <Session>[];

    for (var s in allSessions) {
      if (s.subscription == null) continue;
      if (s.end == null) continue;

      final remaining = s.end!.difference(now);

      if (remaining.inMinutes <= 0) {
        expired.add(s);
      } else if (remaining.inMinutes <= 60) {
        expiring.add(s);
      }
    }

    if (expiring.isNotEmpty || expired.isNotEmpty) {
      List<String> notifications = [];

      if (expiring.isNotEmpty) {
        notifications.add("⚠️ فيه ${expiring.length} اشتراك قرب يخلص");
      }

      if (expired.isNotEmpty) {
        notifications.add("⛔ فيه ${expired.length} اشتراك انتهى خلاص");
      }
      // إشعار بسيط داخل الأب
      if (expiring.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("⚠️ فيه ${expiring.length} اشتراك قرب يخلص"),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
      }

      if (expired.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("⛔ فيه ${expired.length} اشتراك انتهى خلاص"),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
      }

      // 🔔 أو تقدر تستخدم flutter_local_notifications عشان يظهر إشعار ع النظام
    }
  }

  @override
  void initState() {
    super.initState();
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
    _uiTimer?.cancel();
    _checkTimer?.cancel();
    super.dispose();
  }

  double? _getSubscriptionProgress(Session s) {
    final end = _getSubscriptionEnd(s);
    if (end == null) return null;

    final total = end.difference(s.start).inMinutes;
    if (total <= 0) return null;

    final elapsed = getSessionMinutes(s); // هنا بيتحسب الوقف المؤقت صح
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

  Future<void> _confirmAndConvertToPayg(
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

    if (s.subscription != null && s.savedSubscriptionJson == null) {
      s.savedSubscriptionJson = jsonEncode(s.subscription!.toJson());
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
  }

  void _maybeNotifyDailyLimitApproaching(Session s) {
    final plan = s.subscription;
    if (plan == null ||
        plan.dailyUsageType != 'limited' ||
        plan.dailyUsageHours == null)
      return;

    final spentToday = _minutesOverlapWithDate(s, DateTime.now());
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
        final idx = _sessions.indexWhere((x) => x.id == s.id);
        if (idx == -1) return;
        final stillSession = _sessions[idx];
        if (!mounted) return;

        final planNow = stillSession.subscription;
        if (planNow == null ||
            planNow.dailyUsageType != 'limited' ||
            planNow.dailyUsageHours == null)
          return;

        final newSpentToday = _minutesOverlapWithDate(
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

  Future<void> _loadSessions() async {
    setState(() => _loading = true);
    final data = await SessionDb.getSessions();
    for (var s in data) {
      try {
        s.cart = await CartDb.getCartBySession(s.id);
      } catch (_) {}
    }
    setState(() {
      _sessions = data;
      _loading = false;
    });
  }

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
  Future<void> _applyDailyLimitForAllSessions() async {
    final now = DateTime.now();
    debugPrint("⏳ [_applyDailyLimitForAllSessions] Checking at $now ...");

    final toUpdate = <Session>[];
    for (var s in List<Session>.from(_sessions)) {
      debugPrint(
        "➡️ Session ${s.name} (${s.id}) - type=${s.type}, sub=${s.subscription?.name}",
      );

      final plan = s.subscription;
      if (plan == null) {
        debugPrint("   ❌ no subscription, skip");
        continue;
      }
      if (plan.dailyUsageType != 'limited' || plan.dailyUsageHours == null) {
        debugPrint("   ℹ️ unlimited or no daily limit, skip");
        continue;
      }

      final spentToday = _minutesOverlapWithDate(s, now);
      final allowedToday = plan.dailyUsageHours! * 60;
      debugPrint(
        "   🕒 spentToday=$spentToday min / allowed=$allowedToday min",
      );

      if (spentToday >= allowedToday) {
        debugPrint("   🚨 limit reached! converting to حر");
        if (s.savedSubscriptionJson == null) {
          s.savedSubscriptionJson = jsonEncode(s.subscription!.toJson());
        }
        s.subscription = null;
        s.type = 'حر';
        s.addEvent('converted_to_payg', meta: {'reason': 'daily_limit'});
        toUpdate.add(s);
      }
    }

    if (toUpdate.isNotEmpty) {
      for (var s in toUpdate) {
        debugPrint("💾 updating DB for session ${s.name}");
        await SessionDb.updateSession(s);
      }
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
  }

  // ======== استبدل هذه الدالة بالكامل =========
  int _minutesOverlapWithDate(Session s, DateTime date) {
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
  }

  int getSessionMinutes(Session s) {
    // قاعدة مبدئية من القيمة المخزنة (الزمن المجمّع سابقاً)
    int base = s.elapsedMinutes;
    if (base < 0) base = 0;

    // إذا الجلسة موقوفة (محسوبة مسبقاً) نرجع القيمة المخزنة فقط
    if (!s.isActive || s.isPaused) {
      return base;
    }

    // الجلسة حالياً نشطة -> نحسب الوقت الجاري منذ آخر resume (أو منذ start)
    final since = s.pauseStart ?? s.start;
    final running = DateTime.now().difference(since).inMinutes;
    final runningNonNegative = running < 0 ? 0 : running;

    final total = base + runningNonNegative;
    return total < 0 ? 0 : total;
  }

  DateTime? _getSubscriptionEnd(Session s) {
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
  }

  String _formatMinutes(int minutes) {
    if (minutes <= 0) return "0د";
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0) return "${h}س ${m}د";
    return "${m}د";
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

  Future<void> _toggleSession(Session s) async {
    // اذا الجلسة باقة
    if (s.subscription != null) {
      if (!s.isActive) {
        s.isActive = true;
        s.isPaused = false;
        s.pauseStart = DateTime.now();
        await _saveSessionWithEvent(s, 'started');
        _maybeNotifyDailyLimitApproaching(s);
      } else if (s.isPaused) {
        s.isPaused = false;
        s.pauseStart = DateTime.now();
        await _saveSessionWithEvent(s, 'resumed');
        _maybeNotifyDailyLimitApproaching(s);
      } else {
        // إيقاف باقة الآن
        final since = s.pauseStart ?? s.start;
        final added = DateTime.now().difference(since).inMinutes;
        s.elapsedMinutes += added;
        s.isPaused = true;
        s.pauseStart = null;
        await _saveSessionWithEvent(s, 'paused', meta: {'addedMinutes': added});

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
          // يبقى ضمن الباقة
          if (mounted)
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'تم الإيقاف — تبقى ضمن الباقة (${_formatMinutes(allowedToday - spentToday)})',
                ),
              ),
            );
        } else {
          // لا باقة متبقية -> تحويل إلى حر (نطلب تأكيد)
          await _confirmAndConvertToPayg(s, reason: 'exhausted_on_pause');
          // بعد التحويل نححتسب ونحصّل إن لزم
          await _chargePayAsYouGoOnStop(s);
        }
      }
    } else {
      // اذا الجلسة حر (payg)
      if (!s.isActive) {
        s.isActive = true;
        s.isPaused = false;
        s.pauseStart = DateTime.now();
        await _saveSessionWithEvent(s, 'started_payg');
      } else if (s.isPaused) {
        s.isPaused = false;
        s.pauseStart = DateTime.now();
        await _saveSessionWithEvent(s, 'resumed_payg');
      } else {
        final since = s.pauseStart ?? s.start;
        final added = DateTime.now().difference(since).inMinutes;
        s.elapsedMinutes += added;
        s.isPaused = true;
        s.pauseStart = null;
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
  }

  Future<void> _chargePayAsYouGoOnStop(Session s) async {
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
  }

  Future<void> _restoreSavedSubscription(Session s) async {
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

  Future<void> _pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = DateTime(picked.year, picked.month, picked.day);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    /*  final filteredSessions =
        _sessions.where((s) {
          final d = s.start;
          return d.year == _selectedDate.year &&
              d.month == _selectedDate.month &&
              d.day == _selectedDate.day;
        }).toList();*/
    final filteredSessions =
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

    // الآن نعرض كل الجلسات (حتى اللي تحولت لحر)، لكن نميّزهم بصرياً.
    final list = _sessions.toList()..sort((a, b) => a.name.compareTo(b.name));

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
                        const Text("عرض ليوم: "),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.calendar_today),
                          label: Text(
                            "${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}",
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
                          onPressed:
                              () => setState(
                                () => _selectedDate = DateTime.now(),
                              ),
                          child: const Text("اليوم"),
                        ),
                        Spacer(),
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: _loadSessions,
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
                                final plan = s.subscription;
                                final isSub = plan != null;
                                final spentToday = _minutesOverlapWithDate(
                                  s,
                                  _selectedDate,
                                );
                                final totalSoFar = getSessionMinutes(s);
                                // -------- DEBUG: الصق هذا السطر هنا ----------
                                /*      debugPrint(
                                  'DBG SESSION ${s.name} -> start=${s.start}, elapsedMinutesField=${s.elapsedMinutes}, totalSoFar=$totalSoFar, pauseStart=${s.pauseStart}, isPaused=${s.isPaused}, isActive=${s.isActive}',
                                );
                              */ // --------------------------------------------
                                final allowedToday =
                                    (isSub &&
                                            plan!.dailyUsageType == 'limited' &&
                                            plan.dailyUsageHours != null)
                                        ? plan.dailyUsageHours! * 60
                                        : -1;
                                final remaining =
                                    allowedToday > 0
                                        ? (allowedToday - spentToday)
                                        : -1;
                                final minutesToCharge =
                                    (totalSoFar - s.paidMinutes)
                                        .clamp(0, totalSoFar)
                                        .toInt();

                                // badge
                                final badge =
                                    isSub
                                        ? Chip(
                                          label: Text('باقة'),
                                          backgroundColor:
                                              Colors.green.shade300,
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
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(8.0),
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
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      badge,
                                                      const SizedBox(width: 6),
                                                      if (s.savedSubscriptionJson !=
                                                          null)
                                                        const Icon(
                                                          Icons.bookmark,
                                                          size: 18,
                                                          color:
                                                              Colors.blueAccent,
                                                        ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 6),
                                                  if (allowedToday > 0)
                                                    Text(
                                                      'متبقي اليوم: ${_formatMinutes(remaining)}',
                                                    ),
                                                  Text(
                                                    'مضى كلي: ${_formatMinutes(totalSoFar)}    مدفوع: ${_formatMinutes(s.paidMinutes)}',
                                                  ),
                                                  if (isSub)
                                                    Text(
                                                      'تنتهي الباقة: ${_getSubscriptionEnd(s)?.toLocal().toString().split('.').first ?? 'غير محددة'}',
                                                    ),
                                                ],
                                              ),
                                            ),
                                            Row(
                                              children: [
                                                // زر استئناف باقة (لو محفوظة + في يوم جديد)
                                                if (s.savedSubscriptionJson !=
                                                    null) ...[
                                                  if (DateTime.now().year !=
                                                          s.start.year ||
                                                      DateTime.now().month !=
                                                          s.start.month ||
                                                      DateTime.now().day !=
                                                          s.start.day)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                            right: 6.0,
                                                          ),
                                                      child: ElevatedButton(
                                                        onPressed:
                                                            () =>
                                                                _restoreSavedSubscription(
                                                                  s,
                                                                ),
                                                        child: const Text(
                                                          'استئناف باقتك',
                                                        ),
                                                      ),
                                                    ),
                                                ],

                                                const SizedBox(width: 6),

                                                // زر البدء/ايقاف الموحد يتصرف بحسب نوع الجلسة
                                                ElevatedButton(
                                                  onPressed: () async {
                                                    if (!s.isPaused &&
                                                        s.isActive) {
                                                      // إيقاف مؤقت
                                                      final since =
                                                          s.pauseStart ??
                                                          s.start;
                                                      final added =
                                                          DateTime.now()
                                                              .difference(since)
                                                              .inMinutes;
                                                      s.elapsedMinutes += added;
                                                      s.isPaused = true;
                                                      s.pauseStart = null;
                                                      await _saveSessionWithEvent(
                                                        s,
                                                        'paused',
                                                        meta: {
                                                          'addedMinutes': added,
                                                        },
                                                      );
                                                    } else if (s.isPaused) {
                                                      // استئناف
                                                      s.isPaused = false;
                                                      s.pauseStart =
                                                          DateTime.now();
                                                      await _saveSessionWithEvent(
                                                        s,
                                                        'resumed',
                                                      );
                                                    }
                                                    await SessionDb.updateSession(
                                                      s,
                                                    );
                                                    setState(() {});
                                                  },
                                                  child: Text(
                                                    s.isPaused
                                                        ? 'استئناف'
                                                        : 'إيقاف مؤقت',
                                                  ),
                                                ),

                                                const SizedBox(width: 6),

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

                                                  /* _showReceiptDialog(s),*/
                                                  child: const Text("تفاصيل"),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        if (_getSubscriptionProgress(s) !=
                                            null) ...[
                                          const SizedBox(height: 6),
                                          LinearProgressIndicator(
                                            value: _getSubscriptionProgress(s),
                                            backgroundColor: Colors.grey[300],
                                            color: Colors.blueAccent,
                                            borderRadius: BorderRadius.all(
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
                                          ),
                                          Text(
                                            "${((_getSubscriptionProgress(s)! * 100).toStringAsFixed(0))}%",
                                            style: const TextStyle(
                                              fontSize: 15,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
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
                                                    'Elapsed (دقيقة): ${getSessionMinutes(s)}',
                                                  ),
                                                  const SizedBox(height: 8),
                                                  const Text(
                                                    'سجل الأحداث:',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                  if ((s.events).isEmpty)
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
                                                            _buildEventTile(ev),
                                                      )
                                                      .toList(),
                                                ],
                                              ),
                                            ),
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
              ),
    );
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
