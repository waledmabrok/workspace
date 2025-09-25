import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/Db_helper.dart';
import '../../core/data_service.dart';

class ShiftCloseScreen extends StatefulWidget {
  final String? cashierName;
  const ShiftCloseScreen({Key? key, this.cashierName}) : super(key: key);

  @override
  State<ShiftCloseScreen> createState() => _ShiftCloseScreenState();
}

class _ShiftCloseScreenState extends State<ShiftCloseScreen> {
  bool loading = true;
  List<Map<String, dynamic>> openShifts = [];
  Map<String, dynamic>? selectedShift;
  double? countedValue;
  Map<String, dynamic>? lastReport;
  bool processing = false;

  @override
  void initState() {
    super.initState();
    _loadOpenShifts();
  }

  Future<void> _loadOpenShifts() async {
    setState(() => loading = true);
    final all = await DbHelper.instance.getShifts();
    final open =
        all.where((s) {
          final closed = s['closedAt'];
          return closed == null || closed == 'null' || closed == '';
        }).toList();
    setState(() {
      openShifts = open;
      loading = false;
      if (openShifts.isNotEmpty && selectedShift == null)
        selectedShift = openShifts.first;
    });
    if (selectedShift != null) await _refreshSelectedSummary();
  }

  Future<void> _refreshSelectedSummary() async {
    if (selectedShift == null) return;
    final summary = await DbHelper.instance.getShiftSummary(
      selectedShift!['id'] as int

      ,
    );
    setState(() {
      selectedShift = {...selectedShift!, 'summary': summary};
    });
  }

  Future<void> _onClosePressed() async {
    if (selectedShift == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('تأكيد إغلاق الشيفت'),
            content: const Text(
              'هل تريد إغلاق الشيفت الآن؟ تأكد من الرصيد بعد العدّ.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('نعم، إغلاق'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;

    setState(() => processing = true);
    try {
      final report = await AdminDataService.instance.closeShiftAndRefresh(
        shiftId: selectedShift!['id'].int

        ,
        countedClosingBalance: countedValue,
        cashierName: widget.cashierName,
      );
      setState(() {
        lastReport = report;
      });
      await _showReportDialog(report);
      await _loadOpenShifts();
    } catch (e) {
      await showDialog(
        context: context,
        builder:
            (_) => AlertDialog(
              title: const Text('خطأ'),
              content: Text('حدث خطأ أثناء إغلاق الشيفت: $e'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('حسناً'),
                ),
              ],
            ),
      );
    } finally {
      setState(() => processing = false);
    }
  }

  Future<void> _showReportDialog(Map<String, dynamic> report) async {
    await showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('تقرير تقفيل الشيفت'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildReportRow('الشيفت', report['shiftId']),
                    _buildReportRow('فتح عند', report['openedAt']),
                    _buildReportRow('أغلق عند', report['closedAt']),
                    const Divider(),
                    _buildReportRow(
                      'رصيد الافتتاح',
                      _fmt(report['openingBalance']),
                    ),
                    _buildReportRow(
                      'رصيد العدّ (counted)',
                      _fmt(report['countedClosingBalance']),
                    ),
                    _buildReportRow(
                      'الرصيد المحسوب',
                      _fmt(report['computedClosingBalance']),
                    ),
                    _buildReportRow(
                      'الرصيد النهائي',
                      _fmt(report['finalClosingBalance']),
                    ),
                    const Divider(),
                    _buildReportRow(
                      'إجمالي المبيعات',
                      _fmt(report['totalSales']),
                    ),
                    _buildSalesByMethod(report['salesByPaymentMethod'] ?? {}),
                    const Divider(),
                    _buildReportRow(
                      'إجمالي المصروفات',
                      _fmt(report['totalExpenses']),
                    ),
                    _buildReportRow('ايداعات', _fmt(report['deposits'])),
                    _buildReportRow('سحوبات', _fmt(report['withdrawals'])),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إغلاق'),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('تصدير PDF'),
                onPressed: () async {
                  Navigator.pop(context);
                  await _exportReportPdf(report);
                },
              ),
            ],
          ),
    );
  }

  Widget _buildReportRow(String title, Object? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text('$title: ', style: const TextStyle(fontWeight: FontWeight.w600)),
          Expanded(child: Text(value?.toString() ?? '-')),
        ],
      ),
    );
  }

  Widget _buildSalesByMethod(Map sales) {
    if (sales.isEmpty) return const SizedBox();
    final entries = sales.entries.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'تفصيل المبيعات:',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        for (final e in entries) Text('${e.key}: ${_fmt(e.value)}'),
      ],
    );
  }

  String _fmt(Object? v) {
    if (v == null) return '-';
    if (v is double) return v.toStringAsFixed(2);
    return v.toString();
  }

  Future<void> _exportReportPdf(Map<String, dynamic> report) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'تقرير تقفيل الشيفت',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Text('الشيفت: ${report['shiftId']}'),
              pw.Text('فتح عند: ${report['openedAt']}'),
              pw.Text('أغلق عند: ${report['closedAt']}'),
              pw.SizedBox(height: 8),
              pw.Divider(),
              pw.Text('رصيد الافتتاح: ${_fmt(report['openingBalance'])}'),
              pw.Text('رصيد العدّ: ${_fmt(report['countedClosingBalance'])}'),
              pw.Text(
                'الرصيد المحسوب: ${_fmt(report['computedClosingBalance'])}',
              ),
              pw.Text('الرصيد النهائي: ${_fmt(report['finalClosingBalance'])}'),
              pw.SizedBox(height: 8),
              pw.Text('إجمالي المبيعات: ${_fmt(report['totalSales'])}'),
              pw.SizedBox(height: 6),
              pw.Text('تفصيل المبيعات:'),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children:
                    (report['salesByPaymentMethod'] as Map? ?? {}).entries
                        .map<pw.Widget>((e) {
                          return pw.Text('${e.key}: ${_fmt(e.value)}');
                        })
                        .toList(),
              ),
              pw.SizedBox(height: 8),
              pw.Text('إجمالي المصروفات: ${_fmt(report['totalExpenses'])}'),
              pw.Text('ايداعات: ${_fmt(report['deposits'])}'),
              pw.Text('سحوبات: ${_fmt(report['withdrawals'])}'),
              pw.SizedBox(height: 12),
              pw.Text(
                'تقرير محفوظ في النظام: ${report['savedAt'] ?? ''}',
                style: pw.TextStyle(fontSize: 10),
              ),
            ],
          );
        },
      ),
    );

    final bytes = await pdf.save();
    // استخدم printing لعرض/حفظ/طباعة
    await Printing.layoutPdf(onLayout: (format) async => bytes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تقفيل الشيفت'),
        actions: [
          IconButton(
            onPressed: _loadOpenShifts,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body:
          loading
              ? const Center(child: CircularProgressIndicator())
              : Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    if (openShifts.isEmpty)
                      const Text(
                        'لا توجد شيفتات مفتوحة.',
                        style: TextStyle(fontSize: 16),
                      ),
                    if (openShifts.isNotEmpty)
                      Expanded(
                        child: ListView.builder(
                          itemCount: openShifts.length,
                          itemBuilder: (context, i) {
                            final s = openShifts[i];
                            final isSelected =
                                selectedShift != null &&
                                selectedShift!['id'] == s['id'];
                            return Card(
                              color: isSelected ? Colors.blue.shade50 : null,
                              child: ListTile(
                                title: Text('شيفت: ${s['id']}'),
                                subtitle: Text(
                                  'كاشير: ${s['cashierName'] ?? '-'}\nفتح عند: ${s['openedAt'] ?? '-'}',
                                ),
                                onTap: () {
                                  setState(() => selectedShift = s);
                                  _refreshSelectedSummary();
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 8),
                    if (selectedShift != null) ...[
                      FutureBuilder(
                        future: DbHelper.instance.getShiftSummary(
                          selectedShift!['id'] as int
                          ,
                        ),
                        builder: (context, snap) {
                          if (!snap.hasData) return const SizedBox();
                          final sm = snap.data as Map<String, double>;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('إجمالي المبيعات: ${_fmt(sm['sales'])}'),
                              Text('إجمالي المصروفات: ${_fmt(sm['expenses'])}'),
                              Text('الربح: ${_fmt(sm['profit'])}'),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'الرصيد بعد العد (اختياري)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.account_balance_wallet),
                        ),
                        onChanged:
                            (v) => setState(
                              () => countedValue = double.tryParse(v),
                            ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: processing ? null : _onClosePressed,
                              child:
                                  processing
                                      ? const SizedBox(
                                        height: 18,
                                        width: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                      : const Text('إغلاق الشيفت'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (lastReport != null) ...[
                        const Divider(),
                        const Text('آخر تقرير مقفول:'),
                        Text('شيفت: ${lastReport!['shiftId']}'),
                        Text(
                          'الرصيد النهائي: ${_fmt(lastReport!['finalClosingBalance'])}',
                        ),
                        Text('وقت الحفظ: ${lastReport!['savedAt']}'),
                        const SizedBox(height: 6),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.picture_as_pdf),
                          label: const Text('طباعة/تصدير آخر تقرير'),
                          onPressed: () => _exportReportPdf(lastReport!),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
    );
  }
}
