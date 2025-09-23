import 'package:flutter/material.dart';

import '../core/FinanceDb.dart';
import '../core/data_service.dart';
import '../core/db_helper_sessions.dart';
import '../core/models.dart';

class SubscriptionProductsDialog extends StatefulWidget {
  final Session session;
  const SubscriptionProductsDialog({super.key, required this.session});

  @override
  State<SubscriptionProductsDialog> createState() =>
      _SubscriptionProductsDialogState();
}

class _SubscriptionProductsDialogState
    extends State<SubscriptionProductsDialog> {
  final TextEditingController paidCtrl = TextEditingController();
  String paymentMethod = "cash";

  double _drawerBalance = 0.0;

  Future<void> _loadDrawerBalance() async {
    try {
      final bal = await FinanceDb.getDrawerBalance();
      if (mounted) setState(() => _drawerBalance = bal);
    } catch (e, st) {
      debugPrint("❌ Failed to load drawer balance: $e\n$st");
    }
  }

  @override
  void dispose() {
    paidCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;

    final productsTotal = s.cart.fold(0.0, (sum, item) => sum + item.total);
    double discountValue = 0.0;
    final finalTotal = productsTotal - discountValue;

    return AlertDialog(
      title: Text('منتجات المشترك - ${s.name}'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...s.cart.map(
              (item) =>
                  Text('${item.product.name} x${item.qty} = ${item.total} ج'),
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
              decoration: const InputDecoration(labelText: "المبلغ المدفوع"),
            ),
          ],
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: () async {
            final paidAmount = double.tryParse(paidCtrl.text) ?? 0.0;
            final diff = paidAmount - finalTotal;

            // حفظ البيع
            final sale = Sale(
              id: generateId(),
              description:
                  "منتجات ${s.name} | إجمالي ${productsTotal.toStringAsFixed(2)} ج",
              amount: paidAmount,
            );

            await AdminDataService.instance.addSale(
              sale,
              paymentMethod: paymentMethod,
              updateDrawer: paymentMethod == "cash",
            );

            await _loadDrawerBalance();

            // مسح الكارت بعد الدفع
            s.cart.clear();
            await SessionDb.updateSession(s);

            Navigator.pop(context, true);

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  diff >= 0
                      ? "✅ دفع ${paidAmount.toStringAsFixed(2)} ج (باقي ${diff.toStringAsFixed(2)} ج)"
                      : "⚠️ لسه عليه ${(diff.abs()).toStringAsFixed(2)} ج",
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
  }
}
