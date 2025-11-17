import 'package:flutter/material.dart';
import '../../core/FinanceDb.dart';
import '../../core/data_service.dart';
import '../../core/db_helper_cart.dart';
import '../../core/models.dart';

class CustomerCreditPage extends StatelessWidget {
  final ds = AdminDataService.instance;

  @override
  Widget build(BuildContext context) {
    final balances = ds.customerBalances.where((b) => b.balance != 0).toList();

    return Scaffold(
      appBar: AppBar(title: const Text("الحسابات الجارية")),
      body: balances.isEmpty
          ? const Center(child: Text("لا يوجد عملاء على الحساب"))
          : ListView.builder(
              itemCount: balances.length,
              itemBuilder: (context, i) {
                final b = balances[i];
                final customer = ds.customers.firstWhere(
                  (c) => c.id == b.customerId,
                  orElse: () =>
                      Customer(id: b.customerId, name: "عميل غير معروف"),
                );

                return Card(
                  child: ListTile(
                    title: Text(customer.name),
                    trailing: Text(
                      b.balance.toStringAsFixed(2),
                      style: TextStyle(
                        color: b.balance > 0 ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      b.balance > 0 ? "له رصيد عندك" : "عليه رصيد لك",
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CustomerSalesPage(customer: customer),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}

class CustomerSalesPage extends StatefulWidget {
  final Customer customer;
  const CustomerSalesPage({super.key, required this.customer});

  @override
  State<CustomerSalesPage> createState() => _CustomerSalesPageState();
}

class _CustomerSalesPageState extends State<CustomerSalesPage> {
  List<Sale> customerSales = [];

  @override
  void initState() {
    super.initState();
    _loadSales();
  }

  Map<String, List<CartItem>> salesItems = {}; // 🟢 نخزن المنتجات هنا مؤقت

  Future<void> _loadSales() async {
    final allSales = await FinanceDb.getSales();
    setState(() {
      customerSales =
          allSales.where((s) => s.customerId == widget.customer.id).toList();
    });
  }

  Future<void> _loadItemsForSale(String saleId) async {
    if (!salesItems.containsKey(saleId)) {
      final items = await CartDb.getCartBySession(saleId);
      setState(() {
        salesItems[saleId] = items;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("فواتير ${widget.customer.name}")),
      body: customerSales.isEmpty
          ? const Center(child: Text("لا توجد فواتير لهذا العميل"))
          : ListView.builder(
              itemCount: customerSales.length,
              itemBuilder: (context, i) {
                final s = customerSales[i];
                return Card(
                  child: ExpansionTile(
                    title: Text(
                      "فاتورة #${s.id.substring(0, 6)}",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.date.toLocal().toString(),
                          style: const TextStyle(fontSize: 12),
                        ),
                        Text(
                          s.description, // 🟢 تفاصيل الوقت + الجلسة
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                    trailing: Text(
                      "${s.amount.toStringAsFixed(2)} ج",
                      style: TextStyle(
                        color: s.amount >= 0 ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    onExpansionChanged: (expanded) {
                      if (expanded) {
                        _loadItemsForSale(
                            s.id); // 🟢 لما يفتح الفاتورة يجيب المنتجات
                      }
                    },
                    children: s.items.isEmpty
                        ? [
                            const ListTile(
                              title: Text("لا توجد منتجات في هذه الفاتورة"),
                            )
                          ]
                        : s.items.map((item) {
                            return ListTile(
                              leading: const Icon(Icons.shopping_cart),
                              title: Text(item.product.name),
                              subtitle: Text("الكمية: ${item.qty}"),
                              trailing: Text(
                                "${(item.product.price * item.qty).toStringAsFixed(2)} ج",
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                            );
                          }).toList(),
                  ),
                );
              },
            ),
    );
  }
}
