import 'package:flutter/material.dart';
import '../../core/models.dart';
import '../../core/db_helper_customers.dart';
import '../../core/db_helper_customer_balance.dart';

class CustomersBalancesPage extends StatefulWidget {
  @override
  State<CustomersBalancesPage> createState() => _CustomersBalancesPageState();
}

class _CustomersBalancesPageState extends State<CustomersBalancesPage> {
  List<Customer> customers = [];
  List<CustomerBalance> balances = [];

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    final c = await CustomerDb.getAll();
    final b = await CustomerBalanceDb.getAll();
    setState(() {
      customers = c;
      balances = b;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('أرصدة العملاء')),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: customers.length,
        itemBuilder: (context, i) {
          final c = customers[i];
          final balance = balances.firstWhere(
                (b) => b.customerId == c.id,
            orElse: () => CustomerBalance(customerId: c.id, balance: 0.0),
          ).balance;

          return Card(
            color: const Color(0xFF071022),
            child: ListTile(
              title: Text(c.name, style: const TextStyle(color: Colors.white)),
              subtitle: Text(
                'تليفون: ${c.phone ?? "-"}\nالرصيد: ${balance.toStringAsFixed(2)} ج',
                style: const TextStyle(color: Colors.white70),
              ),
              trailing: Text(
                balance >= 0 ? "له ${balance.toStringAsFixed(2)} ج" : "عليه ${balance.abs().toStringAsFixed(2)} ج",
                style: TextStyle(
                  color: balance >= 0 ? Colors.green : Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onTap: () => _adjustBalance(c, balance),
            ),
          );
        },
      ),
    );
  }

  Future<void> _adjustBalance(Customer customer, double balance) async {
    final controller = TextEditingController();
    final res = await showDialog<double>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("تعديل رصيد ${customer.name}"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: "المبلغ (+ له | - عليه)"),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("الغاء")),
          ElevatedButton(
            onPressed: () {
              final val = double.tryParse(controller.text) ?? 0.0;
              Navigator.pop(context, val);
            },
            child: const Text("حفظ"),
          ),
        ],
      ),
    );

    if (res != null && res != 0.0) {
      final newBalance = balance + res;
      await CustomerBalanceDb.upsert(CustomerBalance(customerId: customer.id, balance: newBalance));
      _loadCustomers();
    }
  }
}
