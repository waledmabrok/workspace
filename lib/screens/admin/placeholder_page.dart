import 'package:flutter/material.dart';
import '../../core/data_service.dart'; // فيه PricingSettings
import '../../core/db_helper_main_time.dart'; // فيه PricingDb

class PricingSettingsPage extends StatefulWidget {
  @override
  State<PricingSettingsPage> createState() => _PricingSettingsPageState();
}

class _PricingSettingsPageState extends State<PricingSettingsPage> {
  late TextEditingController _freeMinutes;
  late TextEditingController _firstHour;
  late TextEditingController _perHourAfter;
  late TextEditingController _dailyCap;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final s = await PricingDb.loadSettings();

    _freeMinutes = TextEditingController(text: s.firstFreeMinutes.toString());
    _firstHour = TextEditingController(text: s.firstHourFee.toString());
    _perHourAfter = TextEditingController(text: s.perHourAfterFirst.toString());
    _dailyCap = TextEditingController(text: s.dailyCap.toString());

    // نحفظ نسخة في AdminDataService كمان
    AdminDataService.instance.pricingSettings = s;

    setState(() => _loading = false);
  }

  Future<void> _saveSettings() async {
    final newSettings = PricingSettings(
      firstFreeMinutes: int.tryParse(_freeMinutes.text) ?? 15,
      firstHourFee: double.tryParse(_firstHour.text) ?? 30,
      perHourAfterFirst: double.tryParse(_perHourAfter.text) ?? 20,
      dailyCap: double.tryParse(_dailyCap.text) ?? 150,
    );

    // تحديث في AdminDataService
    AdminDataService.instance.pricingSettings = newSettings;

    // تخزين في قاعدة البيانات
    await PricingDb.saveSettings(newSettings);

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('✅ تم تحديث التسعير')));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('إعدادات التسعير')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _freeMinutes,
              decoration: const InputDecoration(
                labelText: 'عدد الدقائق المجانية',
              ),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: _firstHour,
              decoration: const InputDecoration(labelText: 'سعر الساعة الأولى'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: _perHourAfter,
              decoration: const InputDecoration(
                labelText: 'سعر كل ساعة بعد الأولى',
              ),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: _dailyCap,
              decoration: const InputDecoration(
                labelText: 'الحد اليومي الأعلى',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _saveSettings,
              child: const Text('💾 حفظ التغييرات'),
            ),
          ],
        ),
      ),
    );
  }
}
