import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class ShopSettingsScreen extends StatefulWidget {
  const ShopSettingsScreen({super.key});

  @override
  State<ShopSettingsScreen> createState() => _ShopSettingsScreenState();
}

class _ShopSettingsScreenState extends State<ShopSettingsScreen> {
  final _shopNameCtrl = TextEditingController(text: 'Veda Fashion Hub');
  final _addressCtrl =
      TextEditingController(text: 'Monnet Road, Mandir Hasaud, Raipur');
  final _phoneCtrl = TextEditingController();
  final _gstinCtrl = TextEditingController();
  bool _gstEnabled = false;
  double _defaultGstRate = 5.0;
  bool _gstInclusive = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('shop')
          .get();
      if (doc.exists && doc.data() != null) {
        final d = doc.data()!;
        _shopNameCtrl.text = (d['shopName'] ?? 'Veda Fashion Hub').toString();
        _addressCtrl.text =
            (d['address'] ?? 'Monnet Road, Mandir Hasaud, Raipur').toString();
        _phoneCtrl.text = (d['phone'] ?? '').toString();
        _gstinCtrl.text = (d['gstin'] ?? '').toString();
        _gstEnabled = d['gstEnabled'] == true;
        _defaultGstRate = (d['defaultGstRate'] ?? 5.0).toDouble();
        _gstInclusive = d['gstInclusive'] != false;
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _saveSettings() async {
    await FirebaseFirestore.instance.collection('settings').doc('shop').set({
      'shopName': _shopNameCtrl.text.trim(),
      'address': _addressCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      'gstin': _gstinCtrl.text.trim().toUpperCase(),
      'gstEnabled': _gstEnabled,
      'defaultGstRate': _defaultGstRate,
      'gstInclusive': _gstInclusive,
    }, SetOptions(merge: true));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shop & Invoice settings saved')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Shop & GST Settings')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _shopNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Shop Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _addressCtrl,
              decoration: const InputDecoration(
                labelText: 'Shop Address',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Shop Phone Number',
                border: OutlineInputBorder(),
              ),
            ),
            const Divider(height: 32),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Enable GST on Invoices',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                'Keep OFF until you get GSTIN (prints Retail Cash Memo)',
              ),
              value: _gstEnabled,
              onChanged: (v) => setState(() => _gstEnabled = v),
            ),
            if (_gstEnabled) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _gstinCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'GSTIN Number',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField(
                value: _defaultGstRate,
                decoration: const InputDecoration(
                  labelText: 'Default GST Rate (%)',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 5.0, child: Text('5% GST')),
                  DropdownMenuItem(value: 12.0, child: Text('12% GST')),
                  DropdownMenuItem(value: 18.0, child: Text('18% GST')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _defaultGstRate = v);
                },
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Prices Include GST (MRP Inclusive)'),
                value: _gstInclusive,
                onChanged: (v) => setState(() => _gstInclusive = v),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _saveSettings,
                child: const Text('Save Settings'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CartItem {
  final String barcode;
  final String name;
  final String size;
  final String color;
  final double price;
  final double costPrice;
  int qty;

  CartItem({
    required this.barcode,
    required this.name,
    required this.size,
    required this.color,
    required this.price,
    required this.costPrice,
    this.qty = 1,
  });

  double get total => price * qty;
}

class BillingTab extends StatefulWidget {
  final bool isOwner;
  const BillingTab({super.key, required this.isOwner});

  @override
  State<BillingTab> createState() => _BillingTabState();
}

class _BillingTabState extends State<BillingTab> {
  final List<CartItem> _cart = [];
  final _customerNameCtrl = TextEditingController();
  final _customerPhoneCtrl = TextEditingController();
  final _discountCtrl = TextEditingController(text: '0');
  String _paymentMode = 'Cash';
  bool _savingBill = false;

  double get _subTotal => _cart.fold(0.0, (sum, item) => sum + item.total);
  double get _discount => double.tryParse(_discountCtrl.text.trim()) ?? 0.0;
  double get _afterDiscount =>
      (_subTotal - _discount) < 0 ? 0.0 : (_subTotal - _discount);

  void _addProductToCart(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final idx = _cart.indexWhere((c) => c.barcode == doc.id);
    setState(() {
      if (idx >= 0) {
        _cart[idx].qty++;
      } else {
        _cart.add(
          CartItem(
            barcode: doc.id,
            name: (d['name'] ?? 'Item').toString(),
            size: (d['size'] ?? '').toString(),
            color: (d['color'] ?? '').toString(),
            price: (d['sellingPrice'] ?? 0).toDouble(),
            costPrice: (d['costPrice'] ?? 0).toDouble(),
            qty: 1,
          ),
        );
      }
    });
  }

  Future<void> _scanItemForBill() async {
    bool handled = false;
    final scannedCode = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SizedBox(
        height: 320,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Scan Item to Add to Bill',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: MobileScanner(
                onDetect: (capture) {
                  if (handled) return;
                  final codes = capture.barcodes;
                  if (codes.isNotEmpty && codes.first.rawValue != null) {
                    handled = true;
                    Navigator.pop(ctx, codes.first.rawValue!.trim());
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );

    if (scannedCode == null || !mounted) return;

    final ref =
        FirebaseFirestore.instance.collection('products').doc(scannedCode);
    DocumentSnapshot doc;
    try {
      doc = await ref
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      doc = await ref.get(const GetOptions(source: Source.cache));
    }

    if (!mounted) return;
    if (doc.exists) {
      _addProductToCart(doc);
      final data = doc.data() as Map<String, dynamic>;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added: ${data['name']}'),
          duration: const Duration(seconds: 1),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Barcode $scannedCode not found in inventory')),
      );
    }
  }

  Future<void> _pickItemFromList() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SizedBox(
              height: MediaQuery.of(context).size.height * 0.75,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'Search product name or SKU...',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) =>
                          setSheetState(() => query = v.trim().toLowerCase()),
                    ),
                  ),
                  Expanded(
                    child: StreamBuilder(
                      stream: FirebaseFirestore.instance
                          .collection('products')
                          .orderBy('name')
                          .snapshots(),
                      builder: (context, snap) {
                        if (!snap.hasData) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        final docs = snap.data!.docs.where((d) {
                          if (query.isEmpty) return true;
                          final data = d.data();
                          return '${d.id} ${data['name']} ${data['size']} ${data['color']}'
                              .toLowerCase()
                              .contains(query);
                        }).toList();

                        return ListView.builder(
                          itemCount: docs.length,
                          itemBuilder: (_, i) {
                            final doc = docs[i];
                            final d = doc.data();
                            return ListTile(
                              title: Text((d['name'] ?? '').toString()),
                              subtitle: Text(
                                'SKU: ${doc.id} | Size: ${d['size'] ?? '-'} | Stock: ${d['stock'] ?? 0}',
                              ),
                              trailing: Text(
                                '₹${d['sellingPrice'] ?? 0}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                              onTap: () {
                                _addProductToCart(doc);
                                Navigator.pop(ctx);
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _generateInvoice() async {
    if (_cart.isEmpty || _savingBill) return;
    setState(() => _savingBill = true);

    try {
      final Map<String, dynamic> shop = {
        'shopName': 'Veda Fashion Hub',
        'address': 'Monnet Road, Mandir Hasaud, Raipur',
        'phone': '',
        'gstin': '',
        'gstEnabled': false,
        'defaultGstRate': 5.0,
        'gstInclusive': true,
      };
      try {
        final sDoc = await FirebaseFirestore.instance
            .collection('settings')
            .doc('shop')
            .get()
            .timeout(const Duration(seconds: 2));
        if (sDoc.exists && sDoc.data() != null) {
          shop.addAll(sDoc.data()!);
        }
      } catch (_) {}

      final bool gstEnabled = shop['gstEnabled'] == true;
      final double gstRate = (shop['defaultGstRate'] ?? 5.0).toDouble();
      final bool gstInclusive = shop['gstInclusive'] != false;

      double taxableAmount = _afterDiscount;
      double totalGst = 0;
      double grandTotal = _afterDiscount;

      if (gstEnabled && gstRate > 0) {
        if (gstInclusive) {
          taxableAmount = _afterDiscount / (1 + (gstRate / 100));
          totalGst = _afterDiscount - taxableAmount;
          grandTotal = _afterDiscount;
        } else {
          taxableAmount = _afterDiscount;
          totalGst = _afterDiscount * (gstRate / 100);
          grandTotal = _afterDiscount + totalGst;
        }
      }

      final now = DateTime.now();
      final invoiceNo =
          'VFH-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${100 + Random().nextInt(899)}';

      final itemsList = _cart
          .map((c) => {
                'barcode': c.barcode,
                'name': c.name,
                'size': c.size,
                'color': c.color,
                'price': c.price,
                'costPrice': c.costPrice,
                'qty': c.qty,
                'total': c.total,
              })
          .toList();

      final totalCost =
          _cart.fold(0.0, (sum, c) => sum + (c.costPrice * c.qty));
      final profit = taxableAmount - totalCost;

      final billData = <String, dynamic>{
        'invoiceNo': invoiceNo,
        'createdAt': Timestamp.fromDate(now),
        'customerName': _customerNameCtrl.text.trim(),
        'customerPhone': _customerPhoneCtrl.text.trim(),
        'paymentMode': _paymentMode,
        'items': itemsList,
        'subTotal': _subTotal,
        'discount': _discount,
        'taxableAmount': taxableAmount,
        'gstEnabled': gstEnabled,
        'gstRate': gstRate,
        'totalGst': totalGst,
        'grandTotal': grandTotal,
        'profit': profit,
        'billedBy': FirebaseAuth.instance.currentUser?.email ?? '',
        'shopName': shop['shopName'],
        'shopAddress': shop['address'],
        'shopPhone': shop['phone'],
        'shopGstin': shop['gstin'],
      };

      FirebaseFirestore.instance
          .collection('invoices')
          .doc(invoiceNo)
          .set(billData);

      for (final item in _cart) {
        FirebaseFirestore.instance
            .collection('products')
            .doc(item.barcode)
            .update({'stock': FieldValue.increment(-item.qty)});
      }

      if (!mounted) return;
      setState(() {
        _cart.clear();
        _customerNameCtrl.clear();
        _customerPhoneCtrl.clear();
        _discountCtrl.text = '0';
      });

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => InvoicePreviewScreen(billData: billData),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingBill = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _scanItemForBill,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan Item'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickItemFromList,
                  icon: const Icon(Icons.list_alt),
                  label: const Text('Select Item'),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _customerNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Customer Name',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _customerPhoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: _cart.isEmpty
              ? const Center(
                  child: Text(
                    'Cart is empty.\nScan or Select Item to start billing.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.separated(
                  itemCount: _cart.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = _cart[index];
                    return ListTile(
                      title: Text(
                        item.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text('₹${item.price.toStringAsFixed(0)} each'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: () {
                              setState(() {
                                if (item.qty > 1) {
                                  item.qty--;
                                } else {
                                  _cart.removeAt(index);
                                }
                              });
                            },
                          ),
                          Text(
                            '${item.qty}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: () => setState(() => item.qty++),
                          ),
                          SizedBox(
                            width: 60,
                            child: Text(
                              '₹${item.total.toStringAsFixed(0)}',
                              textAlign: TextAlign.right,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.indigo.shade50,
          child: Column(
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: _discountCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Discount (₹)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField(
                      value: _paymentMode,
                      isDense: true,
                      decoration: const InputDecoration(
                        labelText: 'Payment',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                        DropdownMenuItem(value: 'UPI', child: Text('UPI / QR')),
                        DropdownMenuItem(value: 'Card', child: Text('Card')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _paymentMode = v);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Total', style: TextStyle(fontSize: 12)),
                      Text(
                        '₹${_afterDiscount.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: FilledButton.icon(
                  onPressed:
                      (_cart.isEmpty || _savingBill) ? null : _generateInvoice,
                  icon: const Icon(Icons.receipt),
                  label: const Text('Generate & Print Invoice'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class InvoicePreviewScreen extends StatefulWidget {
  final Map<String, dynamic> billData;
  const InvoicePreviewScreen({super.key, required this.billData});

  @override
  State<InvoicePreviewScreen> createState() => _InvoicePreviewScreenState();
}

class _InvoicePreviewScreenState extends State<InvoicePreviewScreen> {
  String _format = 'a4';

  Future<Uint8List> _buildInvoicePdf(PdfPageFormat pageFormat) async {
    final pdf = pw.Document();
    final b = widget.billData;
    final List items = List.from(b['items'] ?? []);
    final bool gstEnabled = b['gstEnabled'] == true;
    final double gstRate = (b['gstRate'] ?? 0).toDouble();
    final double totalGst = (b['totalGst'] ?? 0).toDouble();
    final double taxable = (b['taxableAmount'] ?? 0).toDouble();
    final double subTotal = (b['subTotal'] ?? 0).toDouble();
    final double discount = (b['discount'] ?? 0).toDouble();
    final double grandTotal = (b['grandTotal'] ?? 0).toDouble();
    final ts = b['createdAt'] is Timestamp
        ? (b['createdAt'] as Timestamp).toDate()
        : DateTime.now();
    final dateStr =
        '${ts.day.toString().padLeft(2, '0')}/${ts.month.toString().padLeft(2, '0')}/${ts.year} ${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';

    if (_format == 'a4') {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        (b['shopName'] ?? 'Veda Fashion Hub').toString(),
                        style: pw.TextStyle(
                          fontSize: 22,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text((b['shopAddress'] ?? '').toString()),
                      if ((b['shopPhone'] ?? '').toString().isNotEmpty)
                        pw.Text('Phone: ${b['shopPhone']}'),
                      if (gstEnabled &&
                          (b['shopGstin'] ?? '').toString().isNotEmpty)
                        pw.Text('GSTIN: ${b['shopGstin']}'),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        gstEnabled ? 'TAX INVOICE' : 'RETAIL INVOICE / CASH MEMO',
                        style: pw.TextStyle(
                          fontSize: 13,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text('Bill No: ${b['invoiceNo']}'),
                      pw.Text('Date: $dateStr'),
                      pw.Text('Mode: ${b['paymentMode']}'),
                    ],
                  ),
                ],
              ),
              pw.Divider(height: 24),
              if ((b['customerName'] ?? '').toString().isNotEmpty ||
                  (b['customerPhone'] ?? '').toString().isNotEmpty) ...[
                pw.Text(
                  'Customer: ${b['customerName']} ${(b['customerPhone'] ?? '').toString().isNotEmpty ? '(${b['customerPhone']})' : ''}',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 12),
              ],
              pw.Table.fromTextArray(
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headerDecoration:
                    const pw.BoxDecoration(color: PdfColors.grey200),
                headers: ['#', 'Item', 'Qty', 'Rate', 'Amount'],
                data: List.generate(items.length, (i) {
                  final it = items[i] as Map;
                  return [
                    '${i + 1}',
                    '${it['name']} ${it['size'] ?? ''}',
                    '${it['qty']}',
                    (it['price'] as num).toStringAsFixed(2),
                    (it['total'] as num).toStringAsFixed(2),
                  ];
                }),
              ),
              pw.SizedBox(height: 16),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.SizedBox(
                  width: 210,
                  child: pw.Column(
                    children: [
                      _row('Subtotal:', 'Rs. ${subTotal.toStringAsFixed(2)}'),
                      if (discount > 0)
                        _row('Discount:', '- Rs. ${discount.toStringAsFixed(2)}'),
                      if (gstEnabled) ...[
                        _row('Taxable:', 'Rs. ${taxable.toStringAsFixed(2)}'),
                        _row('CGST:', 'Rs. ${(totalGst / 2).toStringAsFixed(2)}'),
                        _row('SGST:', 'Rs. ${(totalGst / 2).toStringAsFixed(2)}'),
                      ],
                      pw.Divider(),
                      _row(
                        'Grand Total:',
                        'Rs. ${grandTotal.toStringAsFixed(2)}',
                        bold: true,
                      ),
                    ],
                  ),
                ),
              ),
              pw.Spacer(),
              pw.Center(
                child: pw.Text('Thank you for shopping at ${b['shopName']}!'),
              ),
            ],
          ),
        ),
      );
    } else {
      final double width =
          (_format == 'thermal_58' ? 58 : 80) * PdfPageFormat.mm;
      final rollFormat = PdfPageFormat(
        width,
        double.infinity,
        marginAll: 3 * PdfPageFormat.mm,
      );
      final fs = _format == 'thermal_58' ? 7.5 : 8.5;

      pdf.addPage(
        pw.Page(
          pageFormat: rollFormat,
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                (b['shopName'] ?? 'Veda Fashion Hub').toString(),
                style: pw.TextStyle(
                  fontSize: fs + 3,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                (b['shopAddress'] ?? '').toString(),
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: fs - 1),
              ),
              if ((b['shopPhone'] ?? '').toString().isNotEmpty)
                pw.Text('Ph: ${b['shopPhone']}',
                    style: pw.TextStyle(fontSize: fs - 1)),
              if (gstEnabled && (b['shopGstin'] ?? '').toString().isNotEmpty)
                pw.Text('GSTIN: ${b['shopGstin']}',
                    style: pw.TextStyle(fontSize: fs - 1)),
              pw.Divider(),
              pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Text(
                  'Bill: ${b['invoiceNo']}\nDate: $dateStr\nMode: ${b['paymentMode']}',
                  style: pw.TextStyle(fontSize: fs - 0.5),
                ),
              ),
              pw.Divider(),
              ...items.map((rawIt) {
                final it = rawIt as Map;
                return pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                      child: pw.Text('${it['name']} x${it['qty']}',
                          style: pw.TextStyle(fontSize: fs)),
                    ),
                    pw.Text((it['total'] as num).toStringAsFixed(2),
                        style: pw.TextStyle(fontSize: fs)),
                  ],
                );
              }),
              pw.Divider(),
              _row('Subtotal:', subTotal.toStringAsFixed(2), fontSize: fs),
              if (discount > 0)
                _row('Discount:', '-${discount.toStringAsFixed(2)}',
                    fontSize: fs),
              if (gstEnabled)
                _row('GST (${gstRate.toStringAsFixed(0)}%):',
                    totalGst.toStringAsFixed(2),
                    fontSize: fs),
              _row('TOTAL:', 'Rs.${grandTotal.toStringAsFixed(2)}',
                  bold: true, fontSize: fs + 1.5),
              pw.SizedBox(height: 8),
              pw.Text('Thank You! Visit Again',
                  style: pw.TextStyle(fontSize: fs)),
            ],
          ),
        ),
      );
    }

    return pdf.save();
  }

  pw.Widget _row(String l, String v, {bool bold = false, double fontSize = 11}) {
    final s = pw.TextStyle(
      fontSize: fontSize,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [pw.Text(l, style: s), pw.Text(v, style: s)],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text((widget.billData['invoiceNo'] ?? 'Invoice').toString()),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: DropdownButtonFormField(
              value: _format,
              isDense: true,
              decoration: const InputDecoration(
                labelText: 'Invoice Paper Size',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'a4', child: Text('A4 Full Invoice')),
                DropdownMenuItem(
                    value: 'thermal_80', child: Text('Thermal Roll (80 mm)')),
                DropdownMenuItem(
                    value: 'thermal_58', child: Text('Thermal Roll (58 mm)')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _format = v);
              },
            ),
          ),
          Expanded(
            child: PdfPreview(
              key: ValueKey(_format),
              build: _buildInvoicePdf,
              canChangeOrientation: false,
              canChangePageFormat: false,
              canDebug: false,
              pdfFileName: '${widget.billData['invoiceNo']}.pdf',
            ),
          ),
        ],
      ),
    );
  }
}

class BillsHistoryTab extends StatelessWidget {
  final bool isOwner;
  const BillsHistoryTab({super.key, required this.isOwner});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: FirebaseFirestore.instance
          .collection('invoices')
          .orderBy('createdAt', descending: true)
          .limit(100)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('No bills generated yet.'));
        }

        final docs = snapshot.data!.docs;
        final now = DateTime.now();
        double todaySales = 0;
        double todayProfit = 0;

        for (final doc in docs) {
          final d = doc.data();
          final ts = d['createdAt'] is Timestamp
              ? (d['createdAt'] as Timestamp).toDate()
              : null;
          if (ts != null &&
              ts.year == now.year &&
              ts.month == now.month &&
              ts.day == now.day) {
            todaySales += (d['grandTotal'] ?? 0).toDouble();
            todayProfit += (d['profit'] ?? 0).toDouble();
          }
        }

        return Column(
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      const Text("Today's Sales"),
                      Text(
                        '₹${todaySales.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo,
                        ),
                      ),
                    ],
                  ),
                  if (isOwner)
                    Column(
                      children: [
                        const Text("Today's Profit"),
                        Text(
                          '₹${todayProfit.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                itemCount: docs.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final d = docs[index].data();
                  final cust = (d['customerName'] ?? '').toString();
                  final total = (d['grandTotal'] ?? 0).toDouble();

                  return ListTile(
                    leading:
                        const Icon(Icons.receipt_long, color: Colors.indigo),
                    title: Text(
                      '${d['invoiceNo']} • ₹${total.toStringAsFixed(0)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${cust.isNotEmpty ? '$cust • ' : ''}${d['paymentMode']}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => InvoicePreviewScreen(billData: d),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
