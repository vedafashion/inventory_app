import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const InventoryApp());
}

class InventoryApp extends StatelessWidget {
  const InventoryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shop Inventory',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.hasData && snapshot.data != null) {
            final isOwner = snapshot.data!.email?.toLowerCase() == 'owner@shop.local';
            return HomeShell(isOwner: isOwner);
          }
          return const LoginScreen();
        },
      ),
    );
  }
}

// ==================== 1. LOGIN SCREEN (USER ID + PASSWORD) ====================
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userIdController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rawId = _userIdController.text.trim().toLowerCase();
      final email = rawId.contains('@') ? rawId : '$rawId@shop.local';
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: _passwordController.text.trim(),
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? 'Invalid User ID or Password');
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
              const Icon(Icons.inventory_2_rounded, size: 72, color: Colors.indigo),
              const SizedBox(height: 16),
              const Text('Shop Inventory', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              TextField(
                controller: _userIdController,
                decoration: const InputDecoration(
                  labelText: 'User ID (e.g. owner or staff1)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
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
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _loading ? null : _login,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: _loading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Sign In', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==================== 2. HOME SHELL (SCANNER FIRST) ====================
class HomeShell extends StatefulWidget {
  final bool isOwner;
  const HomeShell({super.key, required this.isOwner});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final screens = [
      BarcodeScannerScreen(isOwner: widget.isOwner),
      InventoryListScreen(isOwner: widget.isOwner),
    ];

    return Scaffold(
      body: screens[_tabIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.qr_code_scanner), label: 'Scan'),
          NavigationDestination(icon: Icon(Icons.list_alt), label: 'Inventory'),
        ],
      ),
    );
  }
}

// ==================== 3. BARCODE SCANNER SCREEN ====================
class BarcodeScannerScreen extends StatefulWidget {
  final bool isOwner;
  const BarcodeScannerScreen({super.key, required this.isOwner});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  final MobileScannerController _cameraController = MobileScannerController();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  bool _isProcessing = false;
  bool _torchOn = false;

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null || code.isEmpty) return;

    setState(() => _isProcessing = true);
    await _lookupBarcode(code);
  }

  Future<void> _lookupBarcode(String barcode) async {
    try {
      final query = await _db
          .collection('products')
          .where('barcode', isEqualTo: barcode)
          .limit(1)
          .get();

      if (!mounted) return;
      if (query.docs.isEmpty) {
        await _showNotFoundDialog(barcode);
      } else {
        await _showProductSheet(query.docs.first);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _showProductSheet(DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final name = data['name'] ?? 'Unnamed';
    final size = data['size'] ?? '-';
    final color = data['color'] ?? '-';
    final sellingPrice = data['selling_price'] ?? 0;
    final costPrice = data['cost_price'] ?? 0;
    final currentStock = (data['stock_qty'] ?? 0) as int;
    int qty = 1;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
                  Chip(
                    label: Text('Stock: $currentStock', style: const TextStyle(fontWeight: FontWeight.bold)),
                    backgroundColor: currentStock <= 3 ? Colors.red.shade100 : Colors.green.shade100,
                  ),
                ],
              ),
              Text('Size: $size  •  Color: $color  •  SKU: ${data['barcode']}',
                  style: TextStyle(color: Colors.grey.shade700)),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Selling Price', style: TextStyle(color: Colors.grey)),
                      Text('₹$sellingPrice', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  if (widget.isOwner)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('Cost Price (Owner)', style: TextStyle(color: Colors.grey)),
                        Text('₹$costPrice', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.blueGrey)),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.outlined(
                    onPressed: qty > 1 ? () => setSheetState(() => qty--) : null,
                    icon: const Icon(Icons.remove),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text('$qty', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  ),
                  IconButton.outlined(
                    onPressed: () => setSheetState(() => qty++),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.shopping_bag_outlined),
                      label: Text('Sell (-$qty)'),
                      onPressed: currentStock >= qty
                          ? () async {
                              await _updateStock(doc.id, '$name ($size)', -qty, 'sale');
                              if (context.mounted) Navigator.pop(context);
                            }
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.add_box_outlined),
                      label: Text('Restock (+$qty)'),
                      onPressed: () async {
                        await _updateStock(doc.id, '$name ($size)', qty, 'restock');
                        if (context.mounted) Navigator.pop(context);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _updateStock(String docId, String productName, int changeQty, String type) async {
    final batch = _db.batch();
    batch.update(_db.collection('products').doc(docId), {
      'stock_qty': FieldValue.increment(changeQty),
      'updated_at': FieldValue.serverTimestamp(),
    });
    batch.set(_db.collection('stock_logs').doc(), {
      'product_id': docId,
      'product_name': productName,
      'change': changeQty,
      'type': type,
      'updated_by': FirebaseAuth.instance.currentUser?.email ?? 'Unknown',
      'timestamp': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(changeQty < 0 ? 'Sold ${changeQty.abs()}x $productName' : 'Added +$changeQty to $productName')),
      );
    }
  }

  Future<void> _showNotFoundDialog(String barcode) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Item Not Found'),
        content: Text('No product matches barcode:\n$barcode'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Scan Again')),
          if (widget.isOwner)
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => AddProductScreen(initialBarcode: barcode)),
                );
              },
              child: const Text('Add New Item'),
            ),
        ],
      ),
    );
  }

  Future<void> _showManualEntry() async {
    final ctrl = TextEditingController();
    setState(() => _isProcessing = true);
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter Barcode'),
        content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Search')),
        ],
      ),
    );
    if (code != null && code.isNotEmpty) {
      await _lookupBarcode(code);
    } else if (mounted) {
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Barcode'),
        actions: [
          IconButton(
            icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
            onPressed: () {
              _cameraController.toggleTorch();
              setState(() => _torchOn = !_torchOn);
            },
          ),
          IconButton(icon: const Icon(Icons.keyboard), onPressed: _showManualEntry),
          IconButton(icon: const Icon(Icons.logout), onPressed: () => FirebaseAuth.instance.signOut()),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _cameraController, onDetect: _onDetect),
          Center(
            child: Container(
              width: 260,
              height: 160,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.greenAccent, width: 3),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                child: Text(
                  _isProcessing ? 'Checking stock...' : 'Point camera at barcode',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== 4. LIVE INVENTORY LIST SCREEN ====================
class InventoryListScreen extends StatefulWidget {
  final bool isOwner;
  const InventoryListScreen({super.key, required this.isOwner});

  @override
  State<InventoryListScreen> createState() => _InventoryListScreenState();
}

class _InventoryListScreenState extends State<InventoryListScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isOwner ? 'Inventory (Owner)' : 'Inventory (Staff)'),
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: () => FirebaseAuth.instance.signOut()),
        ],
      ),
      floatingActionButton: widget.isOwner
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddProductScreen())),
              icon: const Icon(Icons.add),
              label: const Text('Add Item'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search by name or barcode...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('products').orderBy('name').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final docs = snapshot.data!.docs.where((d) {
                  final data = d.data() as Map<String, dynamic>;
                  final name = (data['name'] ?? '').toString().toLowerCase();
                  final code = (data['barcode'] ?? '').toString().toLowerCase();
                  return name.contains(_search) || code.contains(_search);
                }).toList();

                if (docs.isEmpty) return const Center(child: Text('No items found.'));

                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final data = docs[i].data() as Map<String, dynamic>;
                    final stock = (data['stock_qty'] ?? 0) as int;
                    return ListTile(
                      title: Text(data['name'] ?? 'Unnamed', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        'Size: ${data['size'] ?? '-'} • Color: ${data['color'] ?? '-'}\n'
                        'Sell: ₹${data['selling_price'] ?? 0}'
                        '${widget.isOwner ? '  •  Cost: ₹${data['cost_price'] ?? 0}' : ''}',
                      ),
                      trailing: Chip(
                        label: Text('$stock', style: const TextStyle(fontWeight: FontWeight.bold)),
                        backgroundColor: stock <= 3 ? Colors.red.shade100 : Colors.green.shade100,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== 5. ADD PRODUCT SCREEN (OWNER ONLY) ====================
class AddProductScreen extends StatefulWidget {
  final String? initialBarcode;
  const AddProductScreen({super.key, this.initialBarcode});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _nameCtrl = TextEditingController();
  final _barcodeCtrl = TextEditingController();
  final _sizeCtrl = TextEditingController();
  final _colorCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  final _sellCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialBarcode != null) _barcodeCtrl.text = widget.initialBarcode!;
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty || _barcodeCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    await FirebaseFirestore.instance.collection('products').add({
      'name': _nameCtrl.text.trim(),
      'barcode': _barcodeCtrl.text.trim(),
      'size': _sizeCtrl.text.trim(),
      'color': _colorCtrl.text.trim(),
      'cost_price': num.tryParse(_costCtrl.text.trim()) ?? 0,
      'selling_price': num.tryParse(_sellCtrl.text.trim()) ?? 0,
      'stock_qty': int.tryParse(_qtyCtrl.text.trim()) ?? 0,
      'updated_at': FieldValue.serverTimestamp(),
    });
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add New Product')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _barcodeCtrl, decoration: const InputDecoration(labelText: 'Barcode / SKU *', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Product Name *', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: TextField(controller: _sizeCtrl, decoration: const InputDecoration(labelText: 'Size (e.g. M)', border: OutlineInputBorder()))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: _colorCtrl, decoration: const InputDecoration(labelText: 'Color', border: OutlineInputBorder()))),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: TextField(controller: _costCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cost Price (₹)', border: OutlineInputBorder()))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: _sellCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Selling Price (₹)', border: OutlineInputBorder()))),
            ],
          ),
          const SizedBox(height: 12),
          TextField(controller: _qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Opening Stock Qty', border: OutlineInputBorder())),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            child: _saving ? const CircularProgressIndicator(color: Colors.white) : const Text('Save Product'),
          ),
        ],
      ),
    );
  }
}
