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
              const Icon(Icons.storefront, size: 72, color: Colors.indigo),
              const SizedBox(height: 12),
              const Text(
                'Shop Inventory',
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
    final title = _tabIndex == 0
        ? 'Scan Barcode ($roleLabel)'
        : 'Inventory ($roleLabel)';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
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
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: _tabIndex == 0
          ? ScanTab(isOwner: isOwner)
          : InventoryTab(isOwner: isOwner),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.qr_code_scanner),
            label: 'Scan',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2),
            label: 'Inventory',
          ),
        ],
      ),
    );
  }
}

class ScanTab extends StatefulWidget {
  final bool isOwner;
  const ScanTab({super.key, required this.isOwner});

  @override
  State<ScanTab> createState() => _ScanTabState();
}

class _ScanTabState extends State<ScanTab> {
  bool _processing = false;

  Future<void> _handleBarcode(String rawCode) async {
    final code = rawCode.trim();
    if (code.isEmpty || _processing) return;
    setState(() => _processing = true);

    try {
      final doc = await FirebaseFirestore.instance
          .collection('products')
          .doc(code)
          .get();

      if (!mounted) return;

      if (doc.exists) {
        await _showProductActionSheet(doc);
      } else {
        await _showNotFoundDialog(code);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
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
              await doc.reference.update({'stock': FieldValue.increment(delta)});
              await FirebaseFirestore.instance.collection('stock_logs').add({
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
                                initialSubtext:
                                    [size, color].where((e) => e.isNotEmpty).join(' • '),
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
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
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
    try {
      final stock = int.tryParse(_stockCtrl.text.trim()) ?? 0;
      final selling = num.tryParse(_sellingCtrl.text.trim()) ?? 0;
      final size = _sizeCtrl.text.trim();
      final color = _colorCtrl.text.trim();

      await FirebaseFirestore.instance
          .collection('products')
          .doc(barcode)
          .set({
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
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
      await widget.existingDoc!.reference.delete();
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
                child: _saving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Save Product'),
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

  String _paperType = 'thermal_50x25'; // thermal_50x25, thermal_38x25, a4_sheet
  int _copies = 1;
  bool _showPrice = true;

  @override
  void initState() {
    super.initState();
    _codeCtrl = TextEditingController(
      text: widget.initialBarcode ?? '890${100000000 + Random().nextInt(899999999)}',
    );
    _nameCtrl = TextEditingController(text: widget.initialName ?? 'Veda Fashion Hub');
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
          if (sub.isNotEmpty || (_showPrice && price.isNotEmpty))
            pw.Text(
              [
                if (sub.isNotEmpty) sub,
                if (_showPrice && price.isNotEmpty) 'MRP: Rs.$price',
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
              child: _buildSingleSticker(w - 2 * PdfPageFormat.mm, h - 2 * PdfPageFormat.mm),
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
