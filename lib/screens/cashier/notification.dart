import 'package:flutter/material.dart';
import '../../core/NotificationsDb.dart';
import '../../core/models.dart';

class ExpiringSessionsPage extends StatefulWidget {
  final List<Session> sessionsSub;
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
  List<Session> dailyLimitReached = [];

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    final allNotifs = await NotificationsDb.getAll();

    final e = <NotificationItem>[];
    final x = <NotificationItem>[];
    final daily = <NotificationItem>[];

    for (var n in allNotifs) {
      if (n.type == 'expiring') e.add(n);
      if (n.type == 'expired') x.add(n);
      if (n.type == 'dailyLimit') daily.add(n);
    }

    // تحويل الجلسات لقائمة فريدة حسب id لتجنب duplicates
    final sessionMap = {
      for (var s in widget.sessionsSub) s.id: s,
    };

    setState(() {
      expiring = e.map((n) => sessionMap[n.sessionId])
          .where((s) => s != null)
          .cast<Session>()
          .toList();

      expired = x.map((n) => sessionMap[n.sessionId])
          .where((s) => s != null)
          .cast<Session>()
          .toList();

      dailyLimitReached = daily.map((n) => sessionMap[n.sessionId])
          .where((s) => s != null)
          .cast<Session>()
          .toList();
    });
  }

  int _minutesOverlapWithDateSub(Session s, DateTime date) {
    if (s.type == 'حر') return 0;
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final now = DateTime.now();

    int consumedUntil(DateTime t) {
      final upto = t.isBefore(now) ? t : now;
      final effectiveEnd = s.end ?? upto;
      final end = effectiveEnd.isBefore(upto) ? effectiveEnd : upto;
      final totalSinceStart = end.difference(s.start).inMinutes;
      int frozen = s.frozenMinutes;
      if (s.isPaused && s.pauseStart != null && s.pauseStart!.isBefore(upto)) {
        final curFrozen = upto.difference(s.pauseStart!).inMinutes;
        if (curFrozen > 0) frozen += curFrozen;
      }
      final consumed = totalSinceStart - frozen;
      return consumed < 0 ? 0 : consumed;
    }

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

  Future<void> _markAllAsRead() async {
    await NotificationsDb.markAllAsRead();
    for (var s in widget.sessionsSub) {
      s.shownExpiring = true;
      s.shownExpired = true;
      s.shownDailyLimit = true;
    }
    if (mounted) setState(() {});
  }

  /*Future<void> _deleteAll() async {
    await NotificationsDb.clearAll();
    setState(() {
      expiring.clear();
      expired.clear();
      dailyLimitReached.clear();
    });
  }*/

  Future<void> _markOneAsRead(Session s, String type) async {
    await NotificationsDb.markAsReadBySessionAndType(s.id, type);
    if (type == 'expired') s.shownExpired = true;
    if (type == 'expiring') s.shownExpiring = true;
    if (type == 'dailyLimit') s.shownDailyLimit = true;
    widget.onViewed?.call();
    if (mounted) setState(() {});
  }

  Future<void> _deleteOne(Session s, String type) async {
    // Soft delete بدل حذف كامل
    await NotificationsDb.softDeleteBySessionAndType(s.id, type);
    setState(() {
      if (type == 'expired') expired.removeWhere((x) => x.id == s.id);
      if (type == 'expiring') expiring.removeWhere((x) => x.id == s.id);
      if (type == 'dailyLimit')
        dailyLimitReached.removeWhere((x) => x.id == s.id);
    });
  }

  Future<void> _deleteAll() async {
    final allSessions = [...expired, ...expiring, ...dailyLimitReached];
    for (var s in allSessions) {
      if (expired.contains(s))
        await NotificationsDb.softDeleteBySessionAndType(s.id, 'expired');
      if (expiring.contains(s))
        await NotificationsDb.softDeleteBySessionAndType(s.id, 'expiring');
      if (dailyLimitReached.contains(s))
        await NotificationsDb.softDeleteBySessionAndType(s.id, 'dailyLimit');
    }
    setState(() {
      expired.clear();
      expiring.clear();
      dailyLimitReached.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(forceMaterialTransparency: true,
        title: const Center(child:Text("الإشعارات")),
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all),
            tooltip: "اعتبار الكل مقروء",
            onPressed: _markAllAsRead,
          ),
          IconButton(
            icon: const Icon(Icons.delete_forever),
            tooltip: "مسح الكل",
            onPressed: _deleteAll,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadNotifications,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (dailyLimitReached.isNotEmpty) ...[
              const Text(
                "⚠️ الحد اليومي وصل",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              ...dailyLimitReached.map(
                (s) => ListTile(
                  leading: Icon(
                    s.shownDailyLimit ? Icons.check_circle : Icons.fiber_new,
                    color: s.shownDailyLimit ? Colors.grey : Colors.red,
                  ),
                  title: Text(s.name),
                  subtitle: const Text("وصل حد استخدام اليومي للباقة"),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.visibility),
                        tooltip: "اعتبار كمقروء",
                        onPressed: () => _markOneAsRead(s, 'dailyLimit'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        tooltip: "حذف",
                        onPressed: () => _deleteOne(s, 'dailyLimit'),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(),
            ],

            if (expiring.isNotEmpty) ...[
              const Text(
                "⏳ الاشتراكات القريبة من الانتهاء",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              ...expiring.map(
                (s) => ListTile(
                  leading: Icon(
                    s.shownExpiring ? Icons.hourglass_bottom : Icons.fiber_new,
                    color: s.shownExpiring ? Colors.grey : Colors.orange,
                  ),
                  title: Text(s.name),
                  subtitle: Text(
                    "ينتهي في: ${s.end!.toLocal()} - باقي: ${_formatRemainingTime(s)}",
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.visibility),
                        tooltip: "اعتبار كمقروء",
                        onPressed: () => _markOneAsRead(s, 'expiring'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        tooltip: "حذف",
                        onPressed: () => _deleteOne(s, 'expiring'),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(),
            ],

            if (expired.isNotEmpty) ...[
              const Text(
                "⛔ الاشتراكات المنتهية",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              ...expired.map(
                (s) => ListTile(
                  leading: Icon(
                    s.shownExpired ? Icons.cancel : Icons.fiber_new,
                    color: s.shownExpired ? Colors.grey : Colors.purple,
                  ),
                  title: Text(s.name),
                  subtitle: Text("انتهت في: ${s.end!.toLocal()}"),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.visibility),
                        tooltip: "اعتبار كمقروء",
                        onPressed: () => _markOneAsRead(s, 'expired'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        tooltip: "حذف",
                        onPressed: () => _deleteOne(s, 'expired'),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            if (expiring.isEmpty &&
                expired.isEmpty &&
                dailyLimitReached.isEmpty)
              const Center(child: Text("لا توجد إشعارات")),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _loadNotifications,
        child: const Icon(Icons.refresh),
      ),
    );
  }
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////
/*
import 'package:flutter/material.dart';
import '../../core/NotificationsDb.dart';
import '../../core/models.dart';

class ExpiringSessionsPage extends StatefulWidget {
  final List<Session> sessionsSub;
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
  List<Session> dailyLimitReached = [];

  @override
  void initState() {
    super.initState();
    _checkExpiring();
  }

  Future<void> _checkExpiring() async {
    final now = DateTime.now();
    final e = <Session>[];
    final x = <Session>[];
    final daily = <Session>[];

    for (var s in widget.sessionsSub) {
      if (s.subscription == null) continue;

      // منتهية
      if (s.end != null && now.isAfter(s.end!)) {
        final exists = await NotificationsDb.exists(s.id, 'expired');
        if (!exists) {
          await NotificationsDb.insertNotification(
            NotificationItem(
              sessionId: s.id,
              type: 'expired',
              message: 'انتهى الاشتراك ${s.name}',
            ),
          );
          s.expiredNotified = true;
        }
        x.add(s);
      }
      // هتنتهي خلال أقل من ساعة
      else if (s.end != null && s.end!.difference(now).inMinutes <= 58) {
        final exists = await NotificationsDb.exists(s.id, 'expiring');
        if (!exists) {
          await NotificationsDb.insertNotification(
            NotificationItem(
              sessionId: s.id,
              type: 'expiring',
              message: 'الاشتراك ${s.name} هينتهي قريب',
            ),
          );
          s.expiringNotified = true;
        }
        e.add(s);
      }

      // تعدي الحد اليومي
      if (s.subscription!.dailyUsageType == 'limited' &&
          s.subscription!.dailyUsageHours != null) {
        final spentToday = _minutesOverlapWithDateSub(s, now);
        final allowedToday = s.subscription!.dailyUsageHours! * 60;
        if (spentToday >= allowedToday) {
          final exists = await NotificationsDb.exists(s.id, 'dailyLimit');
          if (!exists) {
            await NotificationsDb.insertNotification(
              NotificationItem(
                sessionId: s.id,
                type: 'dailyLimit',
                message: 'العميل ${s.name} استهلك الحد اليومي',
              ),
            );
            s.dailyLimitNotified = true;
          }
          daily.add(s);
        }
      }
    }

    setState(() {
      expiring = e;
      expired = x;
      dailyLimitReached = daily;
    });
  }

  int _minutesOverlapWithDateSub(Session s, DateTime date) {
    if (s.type == 'حر') return 0;
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final now = DateTime.now();

    int consumedUntil(DateTime t) {
      final upto = t.isBefore(now) ? t : now;
      final effectiveEnd = s.end ?? upto;
      final end = effectiveEnd.isBefore(upto) ? effectiveEnd : upto;
      final totalSinceStart = end.difference(s.start).inMinutes;
      int frozen = s.frozenMinutes;
      if (s.isPaused && s.pauseStart != null && s.pauseStart!.isBefore(upto)) {
        final curFrozen = upto.difference(s.pauseStart!).inMinutes;
        if (curFrozen > 0) frozen += curFrozen;
      }
      final consumed = totalSinceStart - frozen;
      return consumed < 0 ? 0 : consumed;
    }

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

  Future<void> _deleteAll() async {
    await NotificationsDb.clearAll();
    setState(() {
      expiring.clear();
      expired.clear();
      dailyLimitReached.clear();
    });
  }

  Future<void> _deleteOne(Session s, String type) async {
    await NotificationsDb.softDeleteBySessionAndType(s.id, type);
    setState(() {
      if (type == 'expired') {
        expired.remove(s);
      } else if (type == 'expiring') {
        expiring.remove(s);
      } else if (type == 'dailyLimit') {
        dailyLimitReached.remove(s);
      }
    });
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
            onPressed: () async {
              for (var s in widget.sessionsSub) {
                s.shownExpiring = true;
                s.shownExpired = true;
                s.shownDailyLimit = true;
              }
              await NotificationsDb.markAllAsRead();
              setState(() {});
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_forever),
            tooltip: "مسح الكل",
            onPressed: _deleteAll,
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
                      subtitle: const Text("وصل حد استخدام اليومي للباقة"),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteOne(s, 'dailyLimit'),
                      ),
                      onTap: () async {
                        await NotificationsDb.markAsReadBySessionAndType(
                          s.id,
                          'dailyLimit',
                        );
                        s.shownDailyLimit = true;
                        widget.onViewed?.call();
                        if (mounted) setState(() {});
                      },
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
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              s.shownExpiring
                                  ? Icons.check_circle
                                  : Icons.mark_email_unread,
                              color:
                                  s.shownExpiring ? Colors.grey : Colors.orange,
                            ),
                            onPressed: () async {
                              await NotificationsDb.markAsReadBySessionAndType(
                                s.id,
                                'expiring',
                              );
                              s.shownExpiring = true;
                              widget.onViewed?.call();
                              if (mounted) setState(() {});
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteOne(s, 'expiring'),
                          ),
                        ],
                      ),
                      onTap: () async {
                        await NotificationsDb.markAsReadBySessionAndType(
                          s.id,
                          'expiring',
                        );
                        s.shownExpiring = true;
                        widget.onViewed?.call();
                        if (mounted) setState(() {});
                      },
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
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteOne(s, 'expired'),
                      ),
                      onTap: () async {
                        await NotificationsDb.markAsReadBySessionAndType(
                          s.id,
                          'expired',
                        );
                        s.shownExpired = true;
                        widget.onViewed?.call();
                        if (mounted) setState(() {});
                      },
                    ),
                  ),
                ],
              ),

            if (expiring.isEmpty &&
                expired.isEmpty &&
                dailyLimitReached.isEmpty)
              const Center(child: Text("لا توجد إشعارات")),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _checkExpiring,
        child: const Icon(Icons.refresh),
      ),
    );
  }
}
*/
////////////////////////////////////////////////////////////////////////////////////////////////////////////
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
