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
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return Scaffold(
      //  backgroundColor: const Color(0xFF071022),
      appBar: AppBar(
        title: const Text('إعدادات التسعير'),
        centerTitle: true,
        backgroundColor: Color(0xFF071022),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildCardField(_freeMinutes, 'عدد الدقائق المجانية'),
            const SizedBox(height: 12),
            _buildCardField(_firstHour, 'سعر الساعة الأولى'),
            const SizedBox(height: 12),
            _buildCardField(_perHourAfter, 'سعر كل ساعة بعد الأولى'),
            const SizedBox(height: 12),
            _buildCardField(_dailyCap, 'الحد اليومي الأعلى'),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saveSettings,
                icon: const Icon(Icons.save),
                label: const Text(
                  ' حفظ التغييرات',
                  style: TextStyle(color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF1E2334),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardField(TextEditingController controller, String label) {
    return Card(
      elevation: 3,
      shadowColor: Colors.black54,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: const Color(0xFF1A2233),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: Colors.white70),
            border: InputBorder.none,
          ),
        ),
      ),
    );
  }
}
