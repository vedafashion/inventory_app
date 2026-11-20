import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );
  runApp(const InventoryApp());
}

class InventoryApp extends StatelessWidget {
  const InventoryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Veda Fashion Hub',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasData) {
            return const HomeScreen();
          }
          return const LoginScreen();
        },
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userController = TextEditingController();
  final _passController = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _signIn() async {
    final rawId = _userController.text.trim().toLowerCase();
    final password = _passController.text.trim();
    if (rawId.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter User ID and Password');
      return;
    }

    final email = rawId.contains('@') ? rawId : '$rawId@shop.local';
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? 'Sign in failed');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.asset(
                  'logo.png',
                  width: 96,
                  height: 96,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.storefront,
                    size: 72,
                    color: Colors.indigo,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Veda Fashion Hub',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _userController,
                decoration: const InputDecoration(
                  labelText: 'User ID (e.g. owner or staff1)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _loading ? null : _signIn,
                  child: _loading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Sign In'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tabIndex = 0;

  bool get isOwner {
    final email = FirebaseAuth.instance.currentUser?.email?.toLowerCase() ?? '';
    return email == 'owner@shop.local';
  }

  @override
  Widget build(BuildContext context) {
    final roleLabel = isOwner ? 'Owner' : 'Staff';
    final titles = [
      'Scan ($roleLabel)',
      'Billing ($roleLabel)',
      'Inventory ($roleLabel)',
      'Bills ($roleLabel)',
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_tabIndex]),
        actions: [
          IconButton(
            tooltip: 'Barcode Maker & Print',
            icon: const Icon(Icons.qr_code_2),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const BarcodePrintScreen(),
                ),
              );
            },
          ),
          if (isOwner)
            IconButton(
              tooltip: 'Shop & GST Settings',
              icon: const Icon(Icons.settings),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ShopSettingsScreen(),
                  ),
                );
              },
            ),
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: IndexedStack(
        index: _tabIndex,
        children: [
          ScanTab(isOwner: isOwner),
          BillingTab(isOwner: isOwner),
          InventoryTab(isOwner: isOwner),
          BillsHistoryTab(isOwner: isOwner),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.qr_code_scanner),
            label: 'Scan',
          ),
          NavigationDestination(
            icon: Icon(Icons.point_of_sale),
            label: 'Billing',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2),
            label: 'Inventory',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long),
            label: 'Bills',
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// SHOP & GST SETTINGS SCREEN (Ready for future GSTIN activation)
// ============================================================================
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
        _shopNameCtrl.text = d['shopName'] ?? 'Veda Fashion Hub';
        _addressCtrl.text =
            d['address'] ?? 'Monnet Road, Mandir Hasaud, Raipur';
        _phoneCtrl.text = d['phone'] ?? '';
        _gstinCtrl.text = d['gstin'] ?? '';
        _gstEnabled = d['gstEnabled'] ?? false;
        _defaultGstRate = (d['defaultGstRate'] ?? 5.0).toDouble();
        _gstInclusive = d['gstInclusive'] ?? true;
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
                labelText: 'Shop Phone Number (printed on bill)',
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
                'Keep OFF until you receive your GSTIN (prints Retail Cash Memo)',
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
              DropdownButtonFormField<double>(
                value: _defaultGstRate,
                decoration: const InputDecoration(
                  labelText: 'Default GST Rate (%)',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 5.0, child: Text('5% (2.5% CGST + 2.5% SGST)')),
                  DropdownMenuItem(value: 12.0, child: Text('12% (6% CGST + 6% SGST)')),
                  DropdownMenuItem(value: 18.0, child: Text('18% (9% CGST + 9% SGST)')),
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

// ============================================================================
// BILLING / INVOICE MAKER TAB
// ============================================================================
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
  bool _isInterstate = false;
  bool _savingBill = false;

  double get _subTotal => _cart.fold(0, (sum, item) => sum + item.total);
  double get _discount => double.tryParse(_discountCtrl.text.trim()) ?? 0;
  double get _afterDiscount => (_subTotal - _discount).clamp(0, double.infinity);

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

    final ref = FirebaseFirestore.instance.collection('products').doc(scannedCode);
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added: ${(doc.data() as Map)['name']}'),
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
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('products')
                          .orderBy('name')
                          .snapshots(),
                      builder: (context, snap) {
                        if (!snap.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final docs = snap.data!.docs.where((d) {
                          if (query.isEmpty) return true;
                          final data = d.data() as Map<String, dynamic>;
                          return '${d.id} ${data['name']} ${data['size']} ${data['color']}'
                              .toLowerCase()
                              .contains(query);
                        }).toList();

                        return ListView.builder(
                          itemCount: docs.length,
                          itemBuilder: (_, i) {
                            final doc = docs[i];
                            final d = doc.data() as Map<String, dynamic>;
                            return ListTile(
                              title: Text(d['name'] ?? ''),
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
      // Load shop settings (defaults to non-GST Cash Memo if not configured)
      Map<String, dynamic> shop = {
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
          _cart.fold<double>(0, (sum, c) => sum + (c.costPrice * c.qty));
      final profit = taxableAmount - totalCost;

      final billData = {
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
        'isInterstate': _isInterstate,
        'totalGst': totalGst,
        'grandTotal': grandTotal,
        'profit': profit,
        'billedBy': FirebaseAuth.instance.currentUser?.email ?? '',
        'shopName': shop['shopName'],
        'shopAddress': shop['address'],
        'shopPhone': shop['phone'],
        'shopGstin': shop['gstin'],
      };

      // Save invoice & deduct stock in Firestore (works offline via cache too)
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
                    labelText: 'Customer Name (Optional)',
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
                    labelText: 'Phone (Optional)',
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
                    'Cart is empty.\nScan a barcode or tap "Select Item" to start billing.',
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
                      subtitle: Text(
                        '₹${item.price.toStringAsFixed(0)} each${item.size.isNotEmpty ? ' • Size: ${item.size}' : ''}',
                      ),
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
                            width: 64,
                            child: Text(
                              '₹${item.total.toStringAsFixed(0)}',
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
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
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 115,
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
                    child: DropdownButtonFormField<String>(
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
                      const Text('Net Total', style: TextStyle(fontSize: 12)),
                      Text(
                        '₹${_afterDiscount.toStringAsFixed(2)}',
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

// ============================================================================
// INVOICE PDF PREVIEW & PRINT SCREEN (58mm / 80mm Thermal & A4 Invoice)
// ============================================================================
class InvoicePreviewScreen extends StatefulWidget {
  final Map<String, dynamic> billData;
  const InvoicePreviewScreen({super.key, required this.billData});

  @override
  State<InvoicePreviewScreen> createState() => _InvoicePreviewScreenState();
}

class _InvoicePreviewScreenState extends State<InvoicePreviewScreen> {
  String _format = 'a4'; // a4, thermal_80, thermal_58

  Future<Uint8List> _buildInvoicePdf(PdfPageFormat pageFormat) async {
    final pdf = pw.Document();
    final b = widget.billData;
    final items = List>.from(b['items'] ?? []);
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
                        b['shopName'] ?? 'Veda Fashion Hub',
                        style: pw.TextStyle(
                          fontSize: 22,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(b['shopAddress'] ?? ''),
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
                          fontSize: 14,
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
                  'Customer: ${b['customerName']}   ${(b['customerPhone'] ?? '').toString().isNotEmpty ? '(${b['customerPhone']})' : ''}',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 12),
              ],
              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headerDecoration:
                    const pw.BoxDecoration(color: PdfColors.grey200),
                cellAlignment: pw.Alignment.centerLeft,
                headers: ['#', 'Item Description', 'Qty', 'Rate (Rs.)', 'Amount (Rs.)'],
                data: List.generate(items.length, (i) {
                  final it = items[i];
                  final desc = [
                    it['name'],
                    if ((it['size'] ?? '').toString().isNotEmpty)
                      'Size: ${it['size']}',
                    if ((it['color'] ?? '').toString().isNotEmpty) it['color'],
                  ].join(' | ');
                  return [
                    '${i + 1}',
                    desc,
                    '${it['qty']}',
                    (it['price'] as num).toStringAsFixed(2),
                    (it['total'] as num).toStringAsFixed(2),
                  ];
                }),
              ),
              pw.SizedBox(height: 16),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.SizedBox(
                    width: 220,
                    child: pw.Column(
                      children: [
                        _pdfSummaryRow('Subtotal:', 'Rs. ${subTotal.toStringAsFixed(2)}'),
                        if (discount > 0)
                          _pdfSummaryRow('Discount:', '- Rs. ${discount.toStringAsFixed(2)}'),
                        if (gstEnabled) ...[
                          _pdfSummaryRow('Taxable Value:', 'Rs. ${taxable.toStringAsFixed(2)}'),
                          _pdfSummaryRow(
                            'CGST (${(gstRate / 2).toStringAsFixed(1)}%):',
                            'Rs. ${(totalGst / 2).toStringAsFixed(2)}',
                          ),
                          _pdfSummaryRow(
                            'SGST (${(gstRate / 2).toStringAsFixed(1)}%):',
                            'Rs. ${(totalGst / 2).toStringAsFixed(2)}',
                          ),
                        ],
                        pw.Divider(),
                        _pdfSummaryRow(
                          'Grand Total:',
                          'Rs. ${grandTotal.toStringAsFixed(2)}',
                          bold: true,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.Spacer(),
              pw.Center(
                child: pw.Text(
                  'Thank you for shopping at ${b['shopName']}!',
                  style: pw.TextStyle(fontStyle: pw.FontStyle.italic),
                ),
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
      final fontSize = _format == 'thermal_58' ? 7.5 : 8.5;

      pdf.addPage(
        pw.Page(
          pageFormat: rollFormat,
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                b['shopName'] ?? 'Veda Fashion Hub',
                style: pw.TextStyle(
                  fontSize: fontSize + 3,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                b['shopAddress'] ?? '',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: fontSize - 1),
              ),
              if ((b['shopPhone'] ?? '').toString().isNotEmpty)
                pw.Text('Ph: ${b['shopPhone']}',
                    style: pw.TextStyle(fontSize: fontSize - 1)),
              if (gstEnabled && (b['shopGstin'] ?? '').toString().isNotEmpty)
                pw.Text('GSTIN: ${b['shopGstin']}',
                    style: pw.TextStyle(fontSize: fontSize - 1)),
              pw.Divider(),
              pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Text(
                  'Bill: ${b['invoiceNo']}\nDate: $dateStr\nMode: ${b['paymentMode']}',
                  style: pw.TextStyle(fontSize: fontSize - 0.5),
                ),
              ),
              pw.Divider(),
              ...items.map((it) => pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Expanded(
                          child: pw.Text(
                            '${it['name']} x${it['qty']}',
                            style: pw.TextStyle(fontSize: fontSize),
                          ),
                        ),
                        pw.Text(
                          (it['total'] as num).toStringAsFixed(2),
                          style: pw.TextStyle(fontSize: fontSize),
                        ),
                      ],
                    ),
                  )),
              pw.Divider(),
              _pdfSummaryRow(
                'Subtotal:',
                subTotal.toStringAsFixed(2),
                fontSize: fontSize,
              ),
              if (discount > 0)
                _pdfSummaryRow(
                  'Discount:',
                  '-${discount.toStringAsFixed(2)}',
                  fontSize: fontSize,
                ),
              if (gstEnabled)
                _pdfSummaryRow(
                  'GST (${gstRate.toStringAsFixed(0)}%):',
                  totalGst.toStringAsFixed(2),
                  fontSize: fontSize,
                ),
              _pdfSummaryRow(
                'TOTAL:',
                'Rs.${grandTotal.toStringAsFixed(2)}',
                bold: true,
                fontSize: fontSize + 1.5,
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                'Thank You! Visit Again',
                style: pw.TextStyle(fontSize: fontSize),
              ),
            ],
          ),
        ),
      );
    }

    return pdf.save();
  }

  pw.Widget _pdfSummaryRow(
    String label,
    String value, {
    bool bold = false,
    double fontSize = 11,
  }) {
    final style = pw.TextStyle(
      fontSize: fontSize,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: style),
          pw.Text(value, style: style),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.billData['invoiceNo'] ?? 'Invoice'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: DropdownButtonFormField<String>(
              value: _format,
              isDense: true,
              decoration: const InputDecoration(
                labelText: 'Invoice Paper Size',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'a4',
                  child: Text('A4 Full Invoice (Print / Share on WhatsApp)'),
                ),
                DropdownMenuItem(
                  value: 'thermal_80',
                  child: Text('Thermal Receipt Roll (80 mm)'),
                ),
                DropdownMenuItem(
                  value: 'thermal_58',
                  child: Text('Thermal Receipt Roll (58 mm)'),
                ),
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

// ============================================================================
// BILLS / SALES HISTORY TAB
// ============================================================================
class BillsHistoryTab extends StatelessWidget {
  final bool isOwner;
  const BillsHistoryTab({super.key, required this.isOwner});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('invoices')
          .orderBy('createdAt', descending: true)
          .limit(100)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: Text('No bills generated yet.'));
        }

        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(child: Text('No bills generated yet.'));
        }

        final now = DateTime.now();
        double todaySales = 0;
        double todayProfit = 0;

        for (final doc in docs) {
          final d = doc.data() as Map<String, dynamic>;
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
                border: Border.all(color: Colors.indigo.shade100),
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
                  final d = docs[index].data() as Map<String, dynamic>;
                  final cust = (d['customerName'] ?? '').toString();
                  final itemsCount = (d['items'] as List?)?.length ?? 0;
                  final total = (d['grandTotal'] ?? 0).toDouble();

                  return ListTile(
                    leading: const Icon(Icons.receipt_long, color: Colors.indigo),
                    title: Text(
                      '${d['invoiceNo']}  •  ₹${total.toStringAsFixed(0)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${cust.isNotEmpty ? '$cust • ' : ''}$itemsCount item(s) • ${d['paymentMode']}',
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

// ============================================================================
// SCAN TAB
// ============================================================================
class ScanTab extends StatefulWidget {
  final bool isOwner;
  const ScanTab({super.key, required this.isOwner});

  @override
  State<ScanTab> createState() => _ScanTabState();
}

class _ScanTabState extends State<ScanTab> {
  bool _processing = false;

  Future<DocumentSnapshot> _fetchDocWithFallback(String code) async {
    final ref = FirebaseFirestore.instance.collection('products').doc(code);
    try {
      return await ref
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      return await ref.get(const GetOptions(source: Source.cache));
    }
  }

  Future<void> _handleBarcode(String rawCode) async {
    final code = rawCode.trim();
    if (code.isEmpty || _processing) return;
    setState(() => _processing = true);

    try {
      final doc = await _fetchDocWithFallback(code);
      if (!mounted) return;

      if (doc.exists) {
        await _showProductActionSheet(doc);
      } else {
        await _showNotFoundDialog(code);
      }
    } catch (_) {
      if (mounted) {
        await _showNotFoundDialog(code);
      }
    } finally {
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _showNotFoundDialog(String code) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Barcode Not Found'),
        content: Text('No item registered for barcode:\n$code'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          if (widget.isOwner)
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AddEditProductScreen(initialBarcode: code),
                  ),
                );
              },
              child: const Text('Add New Item'),
            ),
        ],
      ),
    );
  }

  Future<void> _showProductActionSheet(DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final name = data['name'] ?? 'Unnamed';
    final size = data['size'] ?? '';
    final color = data['color'] ?? '';
    final sellingPrice = data['sellingPrice'] ?? 0;
    final costPrice = data['costPrice'] ?? 0;
    int stock = (data['stock'] ?? 0) as int;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            Future<void> updateStock(int delta) async {
              if (stock + delta < 0) return;
              doc.reference.update({'stock': FieldValue.increment(delta)});
              FirebaseFirestore.instance.collection('stock_logs').add({
                'barcode': doc.id,
                'name': name,
                'change': delta,
                'by': FirebaseAuth.instance.currentUser?.email ?? '',
                'timestamp': FieldValue.serverTimestamp(),
              });
              setSheetState(() => stock += delta);
            }

            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Print Barcode Label',
                        icon: const Icon(Icons.print, color: Colors.indigo),
                        onPressed: () {
                          Navigator.pop(ctx);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => BarcodePrintScreen(
                                initialBarcode: doc.id,
                                initialName: name,
                                initialSubtext: [size, color]
                                    .where((e) => e.isNotEmpty)
                                    .join(' • '),
                                initialPrice: sellingPrice.toString(),
                                initialCopies: stock > 0 ? stock : 1,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  Text('Barcode: ${doc.id}'),
                  if (size.isNotEmpty || color.isNotEmpty)
                    Text('Size: $size  |  Color: $color'),
                  const SizedBox(height: 8),
                  Text(
                    'Selling Price: ₹$sellingPrice',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.green,
                    ),
                  ),
                  if (widget.isOwner)
                    Text(
                      'Cost Price: ₹$costPrice',
                      style: const TextStyle(color: Colors.deepOrange),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    'Available Stock: $stock',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red.shade600,
                          ),
                          onPressed: stock > 0 ? () => updateStock(-1) : null,
                          icon: const Icon(Icons.remove),
                          label: const Text('Sell (-1)'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.green.shade600,
                          ),
                          onPressed: () => updateStock(1),
                          icon: const Icon(Icons.add),
                          label: const Text('Restock (+1)'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _manualEntryDialog() async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter Barcode Manually'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Barcode / SKU',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _handleBarcode(ctrl.text);
            },
            child: const Text('Search'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        MobileScanner(
          onDetect: (capture) {
            final barcodes = capture.barcodes;
            if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
              _handleBarcode(barcodes.first.rawValue!);
            }
          },
        ),
        Positioned(
          bottom: 24,
          left: 24,
          right: 24,
          child: FilledButton.icon(
            onPressed: _manualEntryDialog,
            icon: const Icon(Icons.keyboard),
            label: const Text('Type Barcode Manually'),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// INVENTORY TAB
// ============================================================================
class InventoryTab extends StatefulWidget {
  final bool isOwner;
  const InventoryTab({super.key, required this.isOwner});

  @override
  State<InventoryTab> createState() => _InventoryTabState();
}

class _InventoryTabState extends State<InventoryTab> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search by name, barcode, size, or color...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('products')
                  .orderBy('name')
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                    child: Text('No items yet. Tap + Add Item.'),
                  );
                }

                final docs = snapshot.data!.docs.where((doc) {
                  if (_search.isEmpty) return true;
                  final d = doc.data() as Map<String, dynamic>;
                  final text =
                      '${doc.id} ${d['name']} ${d['size']} ${d['color']}'
                          .toLowerCase();
                  return text.contains(_search);
                }).toList();

                if (docs.isEmpty) {
                  return const Center(child: Text('No items found.'));
                }

                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final d = doc.data() as Map<String, dynamic>;
                    final name = d['name'] ?? '';
                    final size = d['size'] ?? '';
                    final color = d['color'] ?? '';
                    final stock = d['stock'] ?? 0;
                    final selling = d['sellingPrice'] ?? 0;
                    final cost = d['costPrice'] ?? 0;

                    return ListTile(
                      onTap: widget.isOwner
                          ? () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      AddEditProductScreen(existingDoc: doc),
                                ),
                              );
                            }
                          : null,
                      title: Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SKU: ${doc.id}${size.isNotEmpty ? ' | Size: $size' : ''}${color.isNotEmpty ? ' | $color' : ''}',
                          ),
                          Row(
                            children: [
                              Text(
                                'Price: ₹$selling',
                                style: const TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (widget.isOwner) ...[
                                const SizedBox(width: 12),
                                Text(
                                  'Cost: ₹$cost',
                                  style: const TextStyle(
                                    color: Colors.deepOrange,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Print Barcode Label',
                            icon: const Icon(Icons.print, color: Colors.indigo),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => BarcodePrintScreen(
                                    initialBarcode: doc.id,
                                    initialName: name,
                                    initialSubtext: [size, color]
                                        .where((e) => e.isNotEmpty)
                                        .join(' • '),
                                    initialPrice: selling.toString(),
                                    initialCopies: (stock is int && stock > 0)
                                        ? stock
                                        : 1,
                                  ),
                                ),
                              );
                            },
                          ),
                          Chip(
                            label: Text(
                              'Qty: $stock',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: (stock as int) <= 2
                                    ? Colors.red
                                    : Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: widget.isOwner
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AddEditProductScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.add),
              label: const Text('Add Item'),
            )
          : null,
    );
  }
}

// ============================================================================
// ADD / EDIT PRODUCT SCREEN
// ============================================================================
class AddEditProductScreen extends StatefulWidget {
  final String? initialBarcode;
  final DocumentSnapshot? existingDoc;
  const AddEditProductScreen({
    super.key,
    this.initialBarcode,
    this.existingDoc,
  });

  @override
  State<AddEditProductScreen> createState() => _AddEditProductScreenState();
}

class _AddEditProductScreenState extends State<AddEditProductScreen> {
  final _barcodeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _sizeCtrl = TextEditingController();
  final _colorCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  final _sellingCtrl = TextEditingController();
  final _stockCtrl = TextEditingController(text: '1');
  bool _saving = false;

  bool get isEditing => widget.existingDoc != null;

  @override
  void initState() {
    super.initState();
    if (widget.existingDoc != null) {
      final d = widget.existingDoc!.data() as Map<String, dynamic>;
      _barcodeCtrl.text = widget.existingDoc!.id;
      _nameCtrl.text = (d['name'] ?? '').toString();
      _sizeCtrl.text = (d['size'] ?? '').toString();
      _colorCtrl.text = (d['color'] ?? '').toString();
      _costCtrl.text = (d['costPrice'] ?? '').toString();
      _sellingCtrl.text = (d['sellingPrice'] ?? '').toString();
      _stockCtrl.text = (d['stock'] ?? 0).toString();
    } else if (widget.initialBarcode != null) {
      _barcodeCtrl.text = widget.initialBarcode!;
    }
  }

  void _generateBarcode() {
    final rand = Random();
    final digits = List.generate(9, (_) => rand.nextInt(10)).join();
    setState(() {
      _barcodeCtrl.text = '890$digits';
    });
  }

  Future<void> _scanBarcodeIntoField() async {
    final scanned = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SizedBox(
        height: 320,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Scan Item Barcode',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: MobileScanner(
                onDetect: (capture) {
                  final codes = capture.barcodes;
                  if (codes.isNotEmpty && codes.first.rawValue != null) {
                    Navigator.pop(ctx, codes.first.rawValue!);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (scanned != null && mounted) {
      setState(() => _barcodeCtrl.text = scanned.trim());
    }
  }

  Future<void> _save({bool openPrint = false}) async {
    final barcode = _barcodeCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    if (barcode.isEmpty || name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Barcode and Product Name are required')),
      );
      return;
    }

    setState(() => _saving = true);
    final stock = int.tryParse(_stockCtrl.text.trim()) ?? 0;
    final selling = num.tryParse(_sellingCtrl.text.trim()) ?? 0;
    final size = _sizeCtrl.text.trim();
    final color = _colorCtrl.text.trim();

    FirebaseFirestore.instance.collection('products').doc(barcode).set({
      'name': name,
      'size': size,
      'color': color,
      'costPrice': num.tryParse(_costCtrl.text.trim()) ?? 0,
      'sellingPrice': selling,
      'stock': stock,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!mounted) return;
    if (openPrint) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => BarcodePrintScreen(
            initialBarcode: barcode,
            initialName: name,
            initialSubtext:
                [size, color].where((e) => e.isNotEmpty).join(' • '),
            initialPrice: selling.toString(),
            initialCopies: stock > 0 ? stock : 1,
          ),
        ),
      );
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _deleteProduct() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Product?'),
        content: Text('Remove ${_nameCtrl.text} from inventory?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true && widget.existingDoc != null) {
      widget.existingDoc!.reference.delete();
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Product' : 'Add New Product'),
        actions: [
          if (isEditing)
            IconButton(
              tooltip: 'Delete Product',
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: _deleteProduct,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _barcodeCtrl,
              readOnly: isEditing,
              decoration: InputDecoration(
                labelText: 'Barcode / SKU *',
                border: const OutlineInputBorder(),
                suffixIcon: isEditing
                    ? null
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Scan Barcode',
                            icon: const Icon(Icons.qr_code_scanner),
                            onPressed: _scanBarcodeIntoField,
                          ),
                          IconButton(
                            tooltip: 'Auto-Generate Barcode',
                            icon: const Icon(Icons.auto_awesome),
                            onPressed: _generateBarcode,
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Product Name *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _sizeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Size (e.g. M)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _colorCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Color',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _costCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Cost Price (₹)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _sellingCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Selling Price (₹)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _stockCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: isEditing ? 'Current Stock Qty' : 'Opening Stock Qty',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _saving ? null : () => _save(openPrint: false),
                child: const Text('Save Product'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _saving ? null : () => _save(openPrint: true),
                icon: const Icon(Icons.print),
                label: const Text('Save & Print Barcode Labels'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// BARCODE MAKER & PRINT SCREEN
// ============================================================================
class BarcodePrintScreen extends StatefulWidget {
  final String? initialBarcode;
  final String? initialName;
  final String? initialSubtext;
  final String? initialPrice;
  final int initialCopies;

  const BarcodePrintScreen({
    super.key,
    this.initialBarcode,
    this.initialName,
    this.initialSubtext,
    this.initialPrice,
    this.initialCopies = 1,
  });

  @override
  State<BarcodePrintScreen> createState() => _BarcodePrintScreenState();
}

class _BarcodePrintScreenState extends State<BarcodePrintScreen> {
  late final TextEditingController _codeCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _subtextCtrl;
  late final TextEditingController _priceCtrl;

  String _paperType = 'thermal_50x25';
  int _copies = 1;

  @override
  void initState() {
    super.initState();
    _codeCtrl = TextEditingController(
      text: widget.initialBarcode ??
          '890${100000000 + Random().nextInt(899999999)}',
    );
    _nameCtrl =
        TextEditingController(text: widget.initialName ?? 'Veda Fashion Hub');
    _subtextCtrl = TextEditingController(text: widget.initialSubtext ?? '');
    _priceCtrl = TextEditingController(text: widget.initialPrice ?? '');
    _copies = widget.initialCopies < 1 ? 1 : widget.initialCopies;
  }

  void _generateNewCode() {
    final rand = Random();
    final digits = List.generate(9, (_) => rand.nextInt(10)).join();
    setState(() {
      _codeCtrl.text = '890$digits';
    });
  }

  pw.Widget _buildSingleSticker(double width, double height) {
    final code = _codeCtrl.text.trim().isEmpty ? '000000' : _codeCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    final sub = _subtextCtrl.text.trim();
    final price = _priceCtrl.text.trim();

    return pw.Container(
      width: width,
      height: height,
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: _paperType == 'a4_sheet'
          ? pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
            )
          : null,
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          if (name.isNotEmpty)
            pw.Text(
              name,
              maxLines: 1,
              overflow: pw.TextOverflow.clip,
              style: pw.TextStyle(
                fontSize: _paperType == 'thermal_38x25' ? 6.5 : 7.5,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          if (sub.isNotEmpty || price.isNotEmpty)
            pw.Text(
              [
                if (sub.isNotEmpty) sub,
                if (price.isNotEmpty) 'MRP: Rs.$price',
              ].join('  |  '),
              maxLines: 1,
              style: pw.TextStyle(
                fontSize: _paperType == 'thermal_38x25' ? 6 : 6.8,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          pw.SizedBox(height: 2),
          pw.BarcodeWidget(
            barcode: pw.Barcode.code128(),
            data: code,
            width: width - 10,
            height: height * 0.48,
            drawText: true,
            textStyle: const pw.TextStyle(fontSize: 6.5),
          ),
        ],
      ),
    );
  }

  Future<Uint8List> _generatePdf(PdfPageFormat format) async {
    final pdf = pw.Document();

    if (_paperType == 'a4_sheet') {
      const labelW = 62 * PdfPageFormat.mm;
      const labelH = 32 * PdfPageFormat.mm;

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(8 * PdfPageFormat.mm),
          build: (ctx) => [
            pw.Wrap(
              spacing: 4 * PdfPageFormat.mm,
              runSpacing: 3 * PdfPageFormat.mm,
              children: List.generate(
                _copies,
                (_) => _buildSingleSticker(labelW, labelH),
              ),
            ),
          ],
        ),
      );
    } else {
      final w = (_paperType == 'thermal_38x25' ? 38 : 50) * PdfPageFormat.mm;
      final h = 25 * PdfPageFormat.mm;
      final stickerFormat = PdfPageFormat(w, h, marginAll: 1 * PdfPageFormat.mm);

      for (int i = 0; i < _copies; i++) {
        pdf.addPage(
          pw.Page(
            pageFormat: stickerFormat,
            build: (ctx) => pw.Center(
              child: _buildSingleSticker(
                w - 2 * PdfPageFormat.mm,
                h - 2 * PdfPageFormat.mm,
              ),
            ),
          ),
        );
      }
    }

    return pdf.save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Barcode Maker & Print'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _codeCtrl,
                        decoration: InputDecoration(
                          labelText: 'Barcode Number / Text',
                          isDense: true,
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: 'Generate Random Barcode',
                            icon: const Icon(Icons.auto_awesome),
                            onPressed: _generateNewCode,
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 110,
                      child: TextField(
                        controller: _priceCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Price (₹)',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Title / Product Name',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _subtextCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Size / Color',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _paperType,
                        isDense: true,
                        decoration: const InputDecoration(
                          labelText: 'Label / Paper Size',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'thermal_50x25',
                            child: Text('Thermal Label (50×25 mm)'),
                          ),
                          DropdownMenuItem(
                            value: 'thermal_38x25',
                            child: Text('Thermal Label (38×25 mm)'),
                          ),
                          DropdownMenuItem(
                            value: 'a4_sheet',
                            child: Text('A4 Sticker Sheet (3×8)'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _paperType = v);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      children: [
                        IconButton(
                          onPressed: _copies > 1
                              ? () => setState(() => _copies--)
                              : null,
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        Text(
                          '$_copies',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          onPressed: () => setState(() => _copies++),
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: PdfPreview(
              key: ValueKey(
                '${_codeCtrl.text}_${_nameCtrl.text}_${_subtextCtrl.text}_${_priceCtrl.text}_${_paperType}_$_copies',
              ),
              build: _generatePdf,
              canChangeOrientation: false,
              canChangePageFormat: false,
              canDebug: false,
              pdfFileName: 'barcode_${_codeCtrl.text.trim()}.pdf',
            ),
          ),
        ],
      ),
    );
  }
}
