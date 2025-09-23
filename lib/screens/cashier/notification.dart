import 'package:flutter/material.dart';
import '../../core/models.dart';

class ExpiringSessionsPage extends StatefulWidget {
  final List<Session> sessionsSub; // قائمة الجلسات الحالية
  final VoidCallback? onViewed;
  const ExpiringSessionsPage({
    super.key,
    required this.sessionsSub,
    this.onViewed,
  });

  @override
  State<ExpiringSessionsPage> createState() => _ExpiringSessionsPageState();
}

class _ExpiringSessionsPageState extends State<ExpiringSessionsPage> {
  List<Session> expiring = [];
  List<Session> expired = [];
  List<Session> dailyLimitReached = []; // ← هنا تعريفه كمتغير عضو

  @override
  void initState() {
    super.initState();
    _checkExpiring(); // أول حساب عند فتح الصفحة
    // بمجرد فتح الصفحة، اعتبر كل الجلسات تمت مشاهدتها
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // تحديث flags بعد انتهاء build الحالي

      widget.onViewed?.call(); // الآن آمن أن تنادي setState في parent
    });
  }

  void _checkExpiring() {
    final now = DateTime.now();
    final e = <Session>[];
    final x = <Session>[];
    final daily = <Session>[]; // مؤقت لحساب الحد اليومي

    for (var s in widget.sessionsSub) {
      if (s.subscription == null) continue;

      // انتهت الباقة
      if (s.end != null && now.isAfter(s.end!)) {
        x.add(s);
        continue;
      }

      // قرب الانتهاء
      if (s.end != null && now.isBefore(s.end!)) {
        final remaining = s.end!.difference(now);
        if (remaining.inMinutes <= 58) {
          e.add(s);
          continue;
        }
      }

      // الحد اليومي
      if (s.subscription!.dailyUsageType == 'limited' &&
          s.subscription!.dailyUsageHours != null) {
        final spentToday = _minutesOverlapWithDateSub(s, now);
        final allowedToday = s.subscription!.dailyUsageHours! * 60;
        if (spentToday >= allowedToday) {
          daily.add(s);
        }
      }
    }

    setState(() {
      expiring = e;
      expired = x;
      dailyLimitReached = daily; // ← تحديث المتغير العضو
    });
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

  String _formatRemainingTime(Session s) {
    final now = DateTime.now();
    if (s.end == null) return "-";
    final remaining = s.end!.difference(now);
    if (remaining.inMinutes <= 0) return "انتهت";
    final h = remaining.inHours;
    final m = remaining.inMinutes % 60;
    if (h > 0) return "$h ساعة و $m دقيقة";
    return "$m دقيقة";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("الاشتراكات القريبة من الانتهاء"),
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all),
            tooltip: "اعتبار الكل مقروء",
            onPressed: () {
              setState(() {
                for (var s in widget.sessionsSub) {
                  s.shownExpiring = true;
                  s.shownExpired = true;
                  s.shownDailyLimit = true;
                }
              });
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            if (dailyLimitReached.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "⚠️ الحد اليومي وصل",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  ...dailyLimitReached.map(
                    (s) => ListTile(
                      leading:
                          (s.dailyLimitNotified && !s.shownDailyLimit)
                              ? const Icon(Icons.fiber_new, color: Colors.red)
                              : const Icon(
                                Icons.check_circle,
                                color: Colors.grey,
                              ),

                      title: Text(s.name),
                      subtitle: Text("وصل حد استخدام اليومي للباقة"),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),

            if (expiring.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "⚠️ الاشتراكات التي ستنتهي قريباً",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  ...expiring.map(
                    (s) => ListTile(
                      leading:
                          (s.expiringNotified && !s.shownExpiring)
                              ? const Icon(
                                Icons.fiber_new,
                                color: Colors.orange,
                              )
                              : const Icon(
                                Icons.hourglass_bottom,
                                color: Colors.grey,
                              ),
                      title: Text(s.name),
                      subtitle: Text(
                        "ينتهي في: ${s.end!.toLocal()} - باقي: ${_formatRemainingTime(s)}",
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            if (expired.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "⛔ الاشتراكات المنتهية",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  ...expired.map(
                    (s) => ListTile(
                      leading:
                          (s.expiredNotified && !s.shownExpired)
                              ? const Icon(
                                Icons.fiber_new,
                                color: Colors.purple,
                              )
                              : const Icon(Icons.cancel, color: Colors.grey),
                      title: Text(s.name),
                      subtitle: Text("انتهت في: ${s.end!.toLocal()}"),
                    ),
                  ),
                ],
              ),
            if (expiring.isEmpty && expired.isEmpty)
              const Center(
                child: Text("لا توجد اشتراكات قريبة من الانتهاء أو منتهية"),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _checkExpiring, // تحديث يدوي
        child: const Icon(Icons.refresh),
      ),
    );
  }
}

/*
import 'package:flutter/material.dart';

import '../../core/NotificationsDb.dart';
import '../../core/models.dart';

class ExpiringSessionsPage extends StatefulWidget {
  const ExpiringSessionsPage({super.key});

  @override
  State<ExpiringSessionsPage> createState() => _ExpiringSessionsPageState();
}

class _ExpiringSessionsPageState extends State<ExpiringSessionsPage> {
  List<NotificationItem> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await NotificationsDb.getAll();
    setState(() {
      _items = data;
    });
  }

  Future<void> _markAllAsRead() async {
    await NotificationsDb.markAllAsRead();
    await _load();
  }

  Future<void> _clearAll() async {
    await NotificationsDb.clearAll();
    await _load();
  }

  Future<void> _markAsRead(int id) async {
    await NotificationsDb.markAsRead(id);
    await _load();
  }

  Future<void> _delete(int id) async {
    await NotificationsDb.delete(id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("الإشعارات"),
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all),
            tooltip: "اعتبار الكل مقروء",
            onPressed: _markAllAsRead,
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: "مسح الكل",
            onPressed: _clearAll,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _items.isEmpty
            ? const Center(child: Text("لا توجد إشعارات"))
            : ListView.builder(
          itemCount: _items.length,
          itemBuilder: (context, index) {
            final n = _items[index];
            return ListTile(
              leading: Icon(
                n.isRead == 0 ? Icons.fiber_new : Icons.notifications,
                color: n.isRead == 0 ? Colors.red : Colors.grey,
              ),
              title: Text(n.message),
              subtitle: Text(
                n.createdAt.toLocal().toString(),
                style: const TextStyle(fontSize: 12),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (n.isRead == 0)
                    IconButton(
                      icon: const Icon(Icons.visibility),
                      tooltip: "اعتبار كمقروء",
                      onPressed: () => _markAsRead(n.id!),
                    ),
                  IconButton(
                    icon: const Icon(Icons.delete),
                    tooltip: "حذف",
                    onPressed: () => _delete(n.id!),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _load,
        child: const Icon(Icons.refresh),
      ),
    );
  }
}
*/
