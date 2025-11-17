import 'package:flutter/material.dart';
import 'package:workspace/utils/colors.dart';
import 'package:workspace/widget/buttom.dart';
import 'package:workspace/widget/form.dart';

import '../../core/data_service.dart';
import '../../core/db_helper_customer_balance.dart';
import '../../core/db_helper_customers.dart';
import '../../core/models.dart';

Future<void> showCustomerSearchDialog(BuildContext context) async {
  final TextEditingController searchCtrl = TextEditingController();
  AdminDataService.instance.customers = await CustomerDb.getAll();
  // جلب كل أرصدة العملاء
  List<CustomerBalance> allBalances = await CustomerBalanceDb.getAll();
  List<Customer> allCustomers = AdminDataService.instance.customers;

  // فلترة: نربط كل balance مع اسم العميل
  List<Map<String, dynamic>> combined = allBalances.map((b) {
    final customer = allCustomers.firstWhere((c) => c.id == b.customerId,
        orElse: () => Customer(id: b.customerId, name: "غير معروف"));
    return {
      'balance': b.balance,
      'customerId': b.customerId,
      'customerName': customer.name,
    };
  }).toList();

  List<Map<String, dynamic>> filtered = List.from(combined);

  await
      // مثال
      showDialog(
          context: context,
          builder: (ctx) {
            return StatefulBuilder(
              builder: (context, setState) {
                void filter(String query) {
                  setState(() {
                    filtered = combined
                        .where((b) => b['customerName']
                            .toString()
                            .toLowerCase()
                            .contains(query.toLowerCase()))
                        .toList();
                  });
                }

                return Dialog(
                  backgroundColor: AppColorsDark.bgColor,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  child: SizedBox(
                    width: 350, // عرض الـ dialog كله
                    height: 500, // ارتفاع اختياري
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            "بحث عن العملاء",
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: CustomFormField(
                            hint: "اسم العميل",
                            controller: searchCtrl,
                            onChanged: filter,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: filtered.isEmpty
                              ? const Center(
                                  child: Text(
                                    "لا يوجد سجلات",
                                    style: TextStyle(
                                        color: Colors.white70, fontSize: 16),
                                  ),
                                )
                              : ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: filtered.length,
                                  itemBuilder: (context, index) {
                                    final b = filtered[index];
                                    final hasBalance =
                                        (b['balance'] as double) > 0;
                                    return ListTile(
                                      title: Text(
                                        b['customerName'],
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 18),
                                      ),
                                      trailing: Text(
                                        (b['balance'] as double)
                                            .toStringAsFixed(2),
                                        style: TextStyle(
                                            color: hasBalance
                                                ? Colors.green
                                                : Colors.red,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 17),
                                      ),
                                    );
                                  },
                                ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: CustomButton(
                            text: "إغلاق",
                            onPressed: () => Navigator.pop(context),
                          ),
                        )
                      ],
                    ),
                  ),
                );
              },
            );
          });
}
