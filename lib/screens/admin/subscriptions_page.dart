/*
import 'package:flutter/material.dart';
import 'dart:math';

import '../../core/data_service.dart';
import '../../core/models.dart';

// ------------------------- Subscriptions Page (CRUD) -------------------------
class SubscriptionsPage extends StatefulWidget {
  @override
  State<SubscriptionsPage> createState() => _SubscriptionsPageState();
}

class _SubscriptionsPageState extends State<SubscriptionsPage> {
  final AdminDataService ds = AdminDataService.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('اداره الاشتراكات')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ElevatedButton.icon(
              onPressed: _addPlan,
              icon: const Icon(Icons.add),
              label: const Text('اضف باقه'),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: ds.subscriptions.length,
                itemBuilder: (context, i) {
                  final s = ds.subscriptions[i];
                  return Card(
                    color: const Color(0xFF071022),
                    child: ListTile(
                      title: Text(s.name),
                      subtitle: Text(
                        'سعر الساعة: ${s.pricePerHour.toStringAsFixed(2)}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => _editPlan(s),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () => _deletePlan(s),
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
      ),
    );
  }

  Future<void> _addPlan() async {
    final res = await showDialog<SubscriptionPlan?>(
      context: context,
      builder: (_) => SubscriptionDialog(),
    );
    if (res != null) setState(() => ds.subscriptions.add(res));
  }

  Future<void> _editPlan(SubscriptionPlan p) async {
    final res = await showDialog<SubscriptionPlan?>(
      context: context,
      builder: (_) => SubscriptionDialog(plan: p),
    );
    if (res != null)
      setState(() {
        p.name = res.name;
        p.pricePerHour = res.pricePerHour;
      });
  }

  void _deletePlan(SubscriptionPlan p) {
    setState(() => ds.subscriptions.remove(p));
  }
}

class SubscriptionDialog extends StatefulWidget {
  final SubscriptionPlan? plan;
  SubscriptionDialog({this.plan});
  @override
  State<SubscriptionDialog> createState() => _SubscriptionDialogState();
}

class _SubscriptionDialogState extends State<SubscriptionDialog> {
  late TextEditingController _name;
  late TextEditingController _price;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.plan?.name ?? '');
    _price = TextEditingController(
      text: widget.plan?.pricePerHour.toString() ?? '0',
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.plan == null ? 'اضف باقة' : 'تعديل الباقة'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'اسم الباقة'),
          ),
          TextField(
            controller: _price,
            decoration: const InputDecoration(labelText: 'سعر الساعة'),
            keyboardType: TextInputType.number,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('الغاء'),
        ),
        ElevatedButton(
          onPressed: () {
            final name = _name.text.trim();
            final price = double.tryParse(_price.text) ?? 0.0;
            if (name.isEmpty) return;
            final plan = SubscriptionPlan(
              id: widget.plan?.id ?? generateId(),
              name: name,
              pricePerHour: price,
            );
            Navigator.pop(context, plan);
          },
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}
*/

import 'package:flutter/material.dart';
import 'dart:math';
import '../../core/data_service.dart'; // <-- هذا يضيف AdminDataService

import '../../core/db_helper_Subscribe.dart'; // الكلاس اللي عامل فيه SQLite
import '../../core/models.dart'; // فيه SubscriptionPlan

// ------------------------- Subscriptions Page (CRUD) -------------------------
class SubscriptionsPage extends StatefulWidget {
  @override
  State<SubscriptionsPage> createState() => _SubscriptionsPageState();
}

class _SubscriptionsPageState extends State<SubscriptionsPage> {
  List<SubscriptionPlan> subscriptions = [];

  @override
  void initState() {
    super.initState();
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    final data = await SubscriptionDb.getPlans();

    setState(() => subscriptions = data);

    // تحديث البيانات الحية في AdminDataService
    AdminDataService.instance.subscriptions
      ..clear()
      ..addAll(data);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('اداره الاشتراكات')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ElevatedButton.icon(
              onPressed: _addPlan,
              icon: const Icon(Icons.add),
              label: const Text('اضف باقه'),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: subscriptions.length,
                itemBuilder: (context, i) {
                  final s = subscriptions[i];
                  return Card(
                    color: const Color(0xFF071022),
                    child: ListTile(
                      title: Text(
                        s.name,
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        s.isUnlimited
                            ? "غير محدودة"
                            : "${s.durationValue ?? ''} ${s.durationType} - ${s.price} ج",
                        style: const TextStyle(color: Colors.white70),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit),
                            color: Colors.white,
                            onPressed: () => _editPlan(s),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete),
                            color: Colors.red,
                            onPressed: () => _deletePlan(s),
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
      ),
    );
  }

  Future<void> _addPlan() async {
    final res = await showDialog<SubscriptionPlan?>(
      context: context,
      builder: (_) => SubscriptionDialog(),
    );
    if (res != null) {
      await SubscriptionDb.insertPlan(res);

      // تحديث AdminDataService مباشرة
      AdminDataService.instance.subscriptions.add(res);

      _loadPlans();
    }
  }

  Future<void> _editPlan(SubscriptionPlan p) async {
    final res = await showDialog<SubscriptionPlan?>(
      context: context,
      builder: (_) => SubscriptionDialog(plan: p),
    );
    if (res != null) {
      final index = AdminDataService.instance.subscriptions.indexWhere(
        (s) => s.id == res.id,
      );
      if (index != -1) {
        AdminDataService.instance.subscriptions[index] = res;
      }

      _loadPlans(); // لتحديث واجهة المستخدم
    }
  }

  void _deletePlan(SubscriptionPlan p) async {
    await SubscriptionDb.deletePlan(p.id);

    AdminDataService.instance.subscriptions.removeWhere((s) => s.id == p.id);

    _loadPlans();
  }
}

// ------------------------- Dialog -------------------------
class SubscriptionDialog extends StatefulWidget {
  final SubscriptionPlan? plan;
  SubscriptionDialog({this.plan});

  @override
  State<SubscriptionDialog> createState() => _SubscriptionDialogState();
}

class _SubscriptionDialogState extends State<SubscriptionDialog> {
  late TextEditingController _name;
  late TextEditingController _price;
  late TextEditingController _durationValue;
  late TextEditingController _dailyHours;

  String _durationType = "hour";
  bool _isUnlimited = false;
  String _dailyUsageType = "full"; // ✅ كامل / ساعات محدودة

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.plan?.name ?? '');
    _price = TextEditingController(text: widget.plan?.price.toString() ?? '0');
    _durationType = widget.plan?.durationType ?? "hour";
    _durationValue = TextEditingController(
      text: widget.plan?.durationValue?.toString() ?? '',
    );
    _isUnlimited = widget.plan?.isUnlimited ?? false;
    _dailyUsageType = widget.plan?.dailyUsageType ?? "full";
    _dailyHours = TextEditingController(
      text: widget.plan?.dailyUsageHours?.toString() ?? '',
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.plan == null ? 'اضف باقة' : 'تعديل الباقة'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'اسم الباقة'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _durationType,
              items:
                  ['hour', 'day', 'week', 'month', 'unlimited']
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
              onChanged:
                  (val) => setState(() {
                    _durationType = val!;
                    _isUnlimited = (val == "unlimited");
                  }),
              decoration: const InputDecoration(labelText: 'نوع المدة'),
            ),
            if (!_isUnlimited)
              TextField(
                controller: _durationValue,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'عدد الوحدات'),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _price,
              decoration: const InputDecoration(labelText: 'السعر'),
              keyboardType: TextInputType.number,
            ),
            const Divider(height: 20, thickness: 1),

            // ✅ اختيار نوع الاستخدام اليومي
            DropdownButtonFormField<String>(
              value: _dailyUsageType,
              items: [
                DropdownMenuItem(value: "full", child: Text("مفتوح طول اليوم")),
                DropdownMenuItem(value: "limited", child: Text("ساعات محدودة")),
              ],
              onChanged:
                  (val) => setState(() {
                    _dailyUsageType = val!;
                  }),
              decoration: const InputDecoration(labelText: 'الاستخدام اليومي'),
            ),

            if (_dailyUsageType == "limited")
              TextField(
                controller: _dailyHours,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'عدد الساعات في اليوم',
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('الغاء'),
        ),
        ElevatedButton(
          onPressed: () {
            final name = _name.text.trim();
            final price = double.tryParse(_price.text) ?? 0.0;
            final durationVal = int.tryParse(_durationValue.text);
            final dailyHours = int.tryParse(_dailyHours.text);
            if (name.isEmpty) return;

            final plan = SubscriptionPlan(
              id: widget.plan?.id ?? Random().nextInt(999999).toString(),
              name: name,
              durationType: _durationType,
              durationValue: _isUnlimited ? null : durationVal,
              price: price,
              dailyUsageType: _dailyUsageType,
              dailyUsageHours: _dailyUsageType == "limited" ? dailyHours : null,
              isUnlimited: _isUnlimited,
            );

            Navigator.pop(context, plan);
          },
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}
