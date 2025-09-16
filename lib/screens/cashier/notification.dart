import 'package:flutter/material.dart';

import '../../core/models.dart';

class ExpiringSessionsPage extends StatelessWidget {
  final List<Session> expiring;
  final List<Session> expired;

  const ExpiringSessionsPage({
    super.key,
    required this.expiring,
    required this.expired,
  });

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
                        "ينتهي في: ${s.end!.toLocal()} - باقي: ${s.end!.difference(DateTime.now()).inMinutes} دقيقة",
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
    );
  }
}
