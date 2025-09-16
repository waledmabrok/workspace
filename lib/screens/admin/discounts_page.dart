import 'package:flutter/material.dart';
import 'dart:math';

import '../../core/data_service.dart';
import '../../core/models.dart';
import '../../core/db_helper_discounts.dart'; // ✅ DB Helper

class DiscountsPage extends StatefulWidget {
  @override
  State<DiscountsPage> createState() => _DiscountsPageState();
}

class _DiscountsPageState extends State<DiscountsPage> {
  final AdminDataService ds = AdminDataService.instance;

  @override
  void initState() {
    super.initState();
    _loadDiscounts();
  }

  Future<void> _loadDiscounts() async {
    final data = await DiscountDb.getAll();
    setState(() {
      ds.discounts
        ..clear()
        ..addAll(data);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الخصومات')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ElevatedButton.icon(
              onPressed: _addDiscount,
              icon: const Icon(Icons.add),
              label: const Text('اضف خصم'),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: ds.discounts.length,
                itemBuilder: (context, i) {
                  final d = ds.discounts[i];
                  return Card(
                    color: const Color(0xFF071022),
                    child: ListTile(
                      title: Text(
                        d.code,
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        'خصم: ${d.percent}% - صلاحية: ${d.expiry?.toLocal().toString().split(' ').first ?? 'غير محددة'}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit),
                            color: Colors.white,
                            onPressed: () => _editDiscount(d),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete),
                            color: Colors.red,
                            onPressed: () => _deleteDiscount(d),
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

  Future<void> _addDiscount() async {
    final res = await showDialog<Discount?>(
      context: context,
      builder: (_) => DiscountDialog(),
    );
    if (res != null) {
      await DiscountDb.insert(res); // ✅ حفظ DB
      _loadDiscounts();
    }
  }

  Future<void> _editDiscount(Discount d) async {
    final res = await showDialog<Discount?>(
      context: context,
      builder: (_) => DiscountDialog(discount: d),
    );
    if (res != null) {
      await DiscountDb.update(res); // ✅ تعديل DB
      _loadDiscounts();
    }
  }

  void _deleteDiscount(Discount d) async {
    await DiscountDb.delete(d.id); // ✅ حذف DB
    _loadDiscounts();
  }
}

// ------------------------- Dialog -------------------------
class DiscountDialog extends StatefulWidget {
  final Discount? discount;
  DiscountDialog({this.discount});
  @override
  State<DiscountDialog> createState() => _DiscountDialogState();
}

class _DiscountDialogState extends State<DiscountDialog> {
  late TextEditingController _code;
  late TextEditingController _percent;
  DateTime? _expiry;
  bool _single = false;

  @override
  void initState() {
    super.initState();
    _code = TextEditingController(text: widget.discount?.code ?? '');
    _percent = TextEditingController(
      text: widget.discount?.percent.toString() ?? '0',
    );
    _expiry = widget.discount?.expiry;
    _single = widget.discount?.singleUse ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.discount == null ? 'اضف خصم' : 'تعديل الخصم'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _code,
              decoration: const InputDecoration(labelText: 'كود الخصم'),
            ),
            TextField(
              controller: _percent,
              decoration: const InputDecoration(labelText: 'نسبة الخصم'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  _expiry == null
                      ? 'لا توجد صلاحية'
                      : 'صلاحية حتى: ${_expiry!.toLocal().toString().split(' ').first}',
                ),
                const Spacer(),
                TextButton(
                  onPressed: _pickExpiry,
                  child: const Text('اختيار تاريخ'),
                ),
              ],
            ),
            Row(
              children: [
                const Text('استخدام مرة واحدة'),
                Checkbox(
                  value: _single,
                  onChanged: (v) => setState(() => _single = v ?? false),
                ),
              ],
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
            final code = _code.text.trim();
            final percent = double.tryParse(_percent.text) ?? 0.0;
            if (code.isEmpty) return;
            Navigator.pop(
              context,
              Discount(
                id: widget.discount?.id ?? Random().nextInt(999999).toString(),
                code: code,
                percent: percent,
                expiry: _expiry,
                singleUse: _single,
              ),
            );
          },
          child: const Text('حفظ'),
        ),
      ],
    );
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiry ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 3650)),
    );
    if (picked != null) setState(() => _expiry = picked);
  }
}
