import 'package:flutter/material.dart';
import '../../core/models.dart';

class ExpiringSessionsPage extends StatefulWidget {
  final List<Session> allSessions;

  const ExpiringSessionsPage({super.key, required this.allSessions});

  @override
  State<ExpiringSessionsPage> createState() => _ExpiringSessionsPageState();
}

class _ExpiringSessionsPageState extends State<ExpiringSessionsPage> {
  List<Session> expiring = [];
  List<Session> expired = [];

  @override
  void initState() {
    super.initState();
    _checkExpiring(); // أول حساب
  }

  void _checkExpiring() {
    final now = DateTime.now();
    final e = <Session>[];
    final x = <Session>[];

    for (var s in widget.allSessions) {
      if (s.subscription == null || s.end == null) continue;
      final remaining = s.end!.difference(now);
      if (remaining.inMinutes <= 0) {
        x.add(s);
      } else if (remaining.inMinutes <= 60) {
        e.add(s);
      }
    }

    setState(() {
      expiring = e;
      expired = x;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("الاشتراكات القريبة من الانتهاء")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
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
                      title: Text(s.name),
                      subtitle: Text(
                        "ينتهي في: ${s.end!.toLocal()} - باقي: "
                        "${s.end!.difference(DateTime.now()).inMinutes} دقيقة",
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
