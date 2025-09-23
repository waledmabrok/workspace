/*
import 'package:flutter/material.dart';
import 'dart:math';

import '../../core/data_service.dart';
import '../../core/models.dart';

class ProductsPage extends StatefulWidget {
  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  final AdminDataService ds = AdminDataService.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('اداره المنتجات')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ElevatedButton.icon(
              onPressed: _addProduct,
              icon: const Icon(Icons.add),
              label: const Text('اضف منتج جديد'),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: ds.products.length,
                itemBuilder: (context, i) {
                  final p = ds.products[i];
                  return Card(
                    color: const Color(0xFF071022),
                    child: ListTile(
                      title: Text(p.name),
                      subtitle: Text(
                        'سعر: ${p.price.toStringAsFixed(2)} - مخزون: ${p.stock}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => _editProduct(p),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () => _deleteProduct(p),
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

  Future<void> _addProduct() async {
    final res = await showDialog<Product?>(
      context: context,
      builder: (_) => ProductDialog(),
    );
    if (res != null) {
      setState(() => ds.products.add(res));
    }
  }

  Future<void> _editProduct(Product p) async {
    final res = await showDialog<Product?>(
      context: context,
      builder: (_) => ProductDialog(product: p),
    );
    if (res != null) {
      setState(() {
        p.name = res.name;
        p.price = res.price;
        p.stock = res.stock;
      });
    }
  }

  void _deleteProduct(Product p) {
    setState(() => ds.products.remove(p));
  }
}

class ProductDialog extends StatefulWidget {
  final Product? product;
  const ProductDialog({this.product, super.key});

  @override
  State<ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<ProductDialog> {
  late TextEditingController _name;
  late TextEditingController _price;
  late TextEditingController _stock;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.product?.name ?? '');
    _price = TextEditingController(
      text: widget.product?.price.toString() ?? '',
    );
    _stock = TextEditingController(
      text: widget.product?.stock.toString() ?? '',
    );
  }

  void _save() {
    final name = _name.text.trim();
    final price = double.tryParse(_price.text) ?? 0.0;
    final stock = int.tryParse(_stock.text) ?? 0;

    if (name.isEmpty || price < 0 || stock < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("❌ تأكد من إدخال البيانات بشكل صحيح")),
      );
      return;
    }

    final p = Product(
      id: widget.product?.id ?? generateId(),
      name: name,
      price: price,
      stock: stock,
    );
    Navigator.pop(context, p);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.product == null ? '➕ اضف منتج' : '✏️ تعديل المنتج'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'الاسم',
                prefixIcon: Icon(Icons.inventory_2),
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _price,
              decoration: const InputDecoration(
                labelText: 'السعر',
                prefixIcon: Icon(Icons.attach_money),
              ),
              keyboardType: TextInputType.number,
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _stock,
              decoration: const InputDecoration(
                labelText: 'المخزون',
                prefixIcon: Icon(Icons.storage),
              ),
              keyboardType: TextInputType.number,
              onSubmitted: (_) => _save(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save),
          label: const Text('حفظ'),
        ),
      ],
    );
  }
}
*/

import 'package:flutter/material.dart';
import 'package:workspace/utils/colors.dart';
import 'package:workspace/widget/buttom.dart';
import 'dart:math';
import '../../core/data_service.dart'; // <-- هذا يضيف AdminDataService

import '../../core/models.dart';
import '../../core/product_db.dart';
import '../../widget/form.dart'; // هنا كلاس التعامل مع SQLite

class ProductsPage extends StatefulWidget {
  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  List<Product> _products = [];

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    final data = await ProductDb.getProducts();
    setState(() => _products = data);

    // تحديث البيانات الحية في AdminDataService
    AdminDataService.instance.products
      ..clear()
      ..addAll(data);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Center(child: const Text('اداره المنتجات')),
        forceMaterialTransparency: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            CustomButton(
              infinity: false,
              text: "اضف منتج جديد",
              onPressed: _addProduct,
              border: true,
            ),
            /*     ElevatedButton.icon(
              onPressed: _addProduct,
              icon: const Icon(Icons.add),
              label: const Text('اضف منتج جديد'),
            ),*/
            const SizedBox(height: 12),
            Expanded(
              child:
                  _products.isEmpty
                      ? const Center(child: Text("لا توجد منتجات"))
                      : ListView.builder(
                        itemCount: _products.length,
                        itemBuilder: (context, i) {
                          final p = _products[i];
                          return Card(
                            color: AppColorsDark.bgCardColor,
                            child: ListTile(
                              title: Text(p.name),
                              subtitle: Text(
                                'سعر: ${p.price.toStringAsFixed(2)} - مخزون: ${p.stock}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit),
                                    onPressed: () => _editProduct(p),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete),
                                    onPressed: () => _deleteProduct(p),
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

  Future<void> _addProduct() async {
    final res = await showDialog<Product?>(
      context: context,
      builder: (_) => ProductDialog(),
    );
    if (res != null) {
      await ProductDb.insertProduct(res);

      // تحديث AdminDataService مباشرة
      AdminDataService.instance.products.add(res);

      _loadProducts();
    }
  }

  Future<void> _editProduct(Product p) async {
    final res = await showDialog<Product?>(
      context: context,
      builder: (_) => ProductDialog(product: p),
    );
    if (res != null) {
      await ProductDb.insertProduct(res); // استبدال/تحديث

      final index = AdminDataService.instance.products.indexWhere(
        (prod) => prod.id == res.id,
      );
      if (index != -1) AdminDataService.instance.products[index] = res;

      _loadProducts();
    }
  }

  Future<void> _deleteProduct(Product p) async {
    await ProductDb.deleteProduct(p.id);

    AdminDataService.instance.products.removeWhere((prod) => prod.id == p.id);

    _loadProducts();
  }
}

class ProductDialog extends StatefulWidget {
  final Product? product;
  const ProductDialog({this.product, super.key});

  @override
  State<ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<ProductDialog> {
  late TextEditingController _name;
  late TextEditingController _price;
  late TextEditingController _stock;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.product?.name ?? '');
    _price = TextEditingController(
      text: widget.product?.price.toString() ?? '',
    );
    _stock = TextEditingController(
      text: widget.product?.stock.toString() ?? '',
    );
  }

  void _save() {
    final name = _name.text.trim();
    final price = double.tryParse(_price.text) ?? 0.0;
    final stock = int.tryParse(_stock.text) ?? 0;

    if (name.isEmpty || price < 0 || stock < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("❌ تأكد من إدخال البيانات بشكل صحيح")),
      );
      return;
    }

    final p = Product(
      id: widget.product?.id ?? generateId(),
      name: name,
      price: price,
      stock: stock,
    );
    Navigator.pop(context, p);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.product == null ? '➕ اضف منتج' : '✏️ تعديل المنتج'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomFormField(
              hint: 'الاسم',
              controller: _name,
              // onChanged: (_) => _save(),
            ),
            const SizedBox(height: 12),
            CustomFormField(
              hint: "السعر",
              controller: _price,
              keyboardType: TextInputType.number,
            ),
            /*TextField(
              controller: _price,
              decoration: const InputDecoration(
                labelText: 'السعر',
                prefixIcon: Icon(Icons.attach_money),
              ),
              keyboardType: TextInputType.number,
              onSubmitted: (_) => _save(),
            ),
            */
            const SizedBox(height: 12),
            CustomFormField(hint: "الكميه", controller: _stock),
            /*  TextField(
              controller: _stock,
              decoration: const InputDecoration(
                labelText: 'المخزون',
                prefixIcon: Icon(Icons.storage),
              ),
              keyboardType: TextInputType.number,
              onSubmitted: (_) => _save(),
            ),*/
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        CustomButton(text: "الحفظ", onPressed: _save, infinity: false),
        /* ElevatedButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save),
          label: const Text('حفظ'),
        ),*/
      ],
    );
  }
}
