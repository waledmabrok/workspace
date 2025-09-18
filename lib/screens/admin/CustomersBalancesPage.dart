import 'package:flutter/material.dart';
import '../../core/models.dart';
import '../../core/db_helper_customers.dart';
import '../../core/db_helper_customer_balance.dart';

class CustomersBalancesPage extends StatefulWidget {
  @override
  State<CustomersBalancesPage> createState() => _CustomersBalancesPageState();
}

class _CustomersBalancesPageState extends State<CustomersBalancesPage>
    with SingleTickerProviderStateMixin {
  List<Customer> customers = [];
  List<CustomerBalance> balances = [];
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final positiveCustomers =
        customers.where((c) {
          final balance =
              balances
                  .firstWhere(
                    (b) => b.customerId == c.id,
                    orElse:
                        () => CustomerBalance(customerId: c.id, balance: 0.0),
                  )
                  .balance;
          return balance > 0;
        }).toList();

    final negativeCustomers =
        customers.where((c) {
          final balance =
              balances
                  .firstWhere(
                    (b) => b.customerId == c.id,
                    orElse:
                        () => CustomerBalance(customerId: c.id, balance: 0.0),
                  )
                  .balance;
          return balance < 0;
        }).toList();

    return Scaffold(
      appBar: AppBar(
        forceMaterialTransparency: true,
        title: const Text('رصيد العملاء'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: 'باقي ليه'), Tab(text: '  عليه ليك')],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildList(positiveCustomers),
          _buildList(negativeCustomers),
        ],
      ),
    );
  }

  Widget _buildList(List<Customer> list) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final c = list[i];
        final balance =
            balances
                .firstWhere(
                  (b) => b.customerId == c.id,
                  orElse: () => CustomerBalance(customerId: c.id, balance: 0.0),
                )
                .balance;

        return Card(
          color: const Color(0xFF071022),
          child: ListTile(
            title: Text(c.name, style: const TextStyle(color: Colors.white)),
            subtitle: Text(
              'تليفون: ${c.phone ?? "-"}\nالرصيد: ${balance.toStringAsFixed(2)} ج',
              style: const TextStyle(color: Colors.white70),
            ),
            trailing: Text(
              balance > 0
                  ? "له ${balance.toStringAsFixed(2)} ج"
                  : "عليه ${balance.abs().toStringAsFixed(2)} ج",
              style: TextStyle(
                color: balance > 0 ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
            onTap: () => _adjustBalance(c, balance),
          ),
        );
      },
    );
  }

  Future<void> _adjustBalance(Customer customer, double balance) async {
    final controller = TextEditingController();
    final res = await showDialog<double>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: Text("تعديل رصيد ${customer.name}"),
            content: TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: "المبلغ (+ له | - عليه)",
              ),
              keyboardType: TextInputType.number,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("الغاء"),
              ),
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
      await CustomerBalanceDb.upsert(
        CustomerBalance(customerId: customer.id, balance: newBalance),
      );
      _loadCustomers();
    }
  }
}
