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
      home: StreamBuilder(
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
              DropdownButtonFormField(
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
                          return '${d.id}${data['name']} ${data['size']}${data['color']}'
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
                                'SKU: ${doc.id} | Size: ${d['size'] ?? '-'} \vert{} Stock:${d['stock'] ?? 0}',
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
                    labelText: 'Customer Name (
