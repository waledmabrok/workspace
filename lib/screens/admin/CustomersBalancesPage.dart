import 'package:flutter/material.dart';
import 'package:workspace/utils/colors.dart';
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
  DateTime _selectedDate = DateTime.now();

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

  // فلترة العملاء حسب التاريخ
  List<Customer> _filterByDate(List<Customer> list) {
    return list.where((c) {
      final balanceEntry = balances.firstWhere(
        (b) => b.customerId == c.id,
        orElse: () => CustomerBalance(
          customerId: c.id,
          balance: 0.0,
          updatedAt: DateTime.now(),
        ),
      );
      final lastUpdate = balanceEntry.updatedAt ?? DateTime.now();
      return lastUpdate.year == _selectedDate.year &&
          lastUpdate.month == _selectedDate.month &&
          lastUpdate.day == _selectedDate.day;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    // تصنيف العملاء إيجابيين/سلبيين
    final positiveCustomers = customers.where((c) {
      final balance = balances
          .firstWhere(
            (b) => b.customerId == c.id,
            orElse: () => CustomerBalance(customerId: c.id, balance: 0.0),
          )
          .balance;
      return balance > 0;
    }).toList();

    final negativeCustomers = customers.where((c) {
      final balance = balances
          .firstWhere(
            (b) => b.customerId == c.id,
            orElse: () => CustomerBalance(customerId: c.id, balance: 0.0),
          )
          .balance;
      return balance < 0;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        forceMaterialTransparency: true,
        title: Center(child: const Text('رصيد العملاء')),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60), // ارتفاع التاب بار
          child: Container(
            margin: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: AppColorsDark.bgCardColor, // خلفية الـ TabBar
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.transparent,
                width: 0,
              ),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorColor: Colors.transparent,
              indicatorWeight: 0,
              indicatorPadding: EdgeInsets.zero,
              dividerColor: Colors.transparent,
              indicator: BoxDecoration(
                color: AppColorsDark.mainColor,
                borderRadius: BorderRadius.circular(12),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              overlayColor: MaterialStateProperty.all(
                Colors.transparent,
              ),
              tabs: const [
                Tab(text: 'المتبقي ليه من المره الي فاتت'),
                Tab(text: 'الشكك'),
              ],
            ),
          ),
        ),
        actions: [
          // زر اختيار التاريخ
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) setState(() => _selectedDate = picked);
            },
            tooltip: "اختيار التاريخ",
          ),
          IconButton(
            icon: const Icon(Icons.today),
            onPressed: () => setState(() => _selectedDate = DateTime.now()),
            tooltip: "اليوم",
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildList(_filterByDate(positiveCustomers)),
          _buildList(_filterByDate(negativeCustomers)),
        ],
      ),
    );
  }

  Widget _buildList(List<Customer> list) {
    return list.isEmpty
        ? const Center(
            child:
                Text('لا يوجد سجلات', style: TextStyle(color: Colors.white70)),
          )
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            itemBuilder: (context, i) {
              final c = list[i];
              final balance = balances
                  .firstWhere(
                    (b) => b.customerId == c.id,
                    orElse: () =>
                        CustomerBalance(customerId: c.id, balance: 0.0),
                  )
                  .balance; /*
            تليفون: ${c.phone ?? "-"}*/
              return Card(
                color: AppColorsDark.bgCardColor,
                child: ListTile(
                  title: Text(
                    c.name,
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    '\nالرصيد: ${balance.toStringAsFixed(2)} ج',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  trailing: Text(
                    balance > 0
                        ? "له ${balance.toStringAsFixed(2)} ج"
                        : "عليه ${balance.abs().toStringAsFixed(2)} ج",
                    style: TextStyle(
                      color: balance > 0 ? Colors.greenAccent : Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
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
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A2233),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          "تعديل رصيد ${customer.name}",
          style: const TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: "المبلغ (+ له | - عليه)",
            labelStyle: TextStyle(color: Colors.white70),
          ),
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("الغاء"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5387FF),
            ),
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
        CustomerBalance(
          customerId: customer.id,
          balance: newBalance,
          updatedAt: DateTime.now(),
        ),
      );
      _loadCustomers();
    }
  }
}
