// Paste into lib/main.dart
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await DemoData.ensureInitialData(prefs);
  runApp(const MainApp());
}

/// Demo data manager: creates 5 UIDs, stores passcodes, bookings, etc.
class DemoData {
  static const _uidsKey = 'uids';
  static const _passcodesKey = 'passcodes';
  static const _bookingsKey = 'bookings'; // {shop: {slot: uid}}

  static Future<void> ensureInitialData(SharedPreferences prefs) async {
    if (!prefs.containsKey(_uidsKey)) {
      final rnd = Random();
      final types = ['NPHH', 'PHH', 'AAY'];
      final uids = <String>[];
      final passcodes = <String, String>{};
      for (int i = 0; i < 5; i++) {
        final prefix = types[rnd.nextInt(types.length)];
        final num = rnd.nextInt(900000) + 100000; // 6 digits
        final uid = '$prefix${num.toString().padLeft(6, '0')}';
        uids.add(uid);
        passcodes[uid] = (rnd.nextInt(900000) + 100000).toString();
      }
      await prefs.setStringList(_uidsKey, uids);
      await prefs.setString(_passcodesKey, json.encode(passcodes));
      await prefs.setString(_bookingsKey, json.encode({}));
    }
  }

  static Future<List<String>> getUIDs(SharedPreferences prefs) async {
    return prefs.getStringList(_uidsKey) ?? [];
  }

  static Future<Map<String, String>> getPasscodes(SharedPreferences prefs) async {
    final raw = prefs.getString(_passcodesKey);
    if (raw == null) return {};
    return Map<String, String>.from(json.decode(raw));
  }

  static Future<Map<String, Map<String, String>>> getBookings(SharedPreferences prefs) async {
    final raw = prefs.getString(_bookingsKey);
    if (raw == null) return {};
    final decoded = Map<String, dynamic>.from(json.decode(raw));
    return decoded.map((k, v) => MapEntry(k, Map<String, String>.from(v)));
  }

  static Future<void> saveBooking(SharedPreferences prefs, String shop, String slot, String uid) async {
    final b = await getBookings(prefs);
    b.putIfAbsent(shop, () => {});
    b[shop]![slot] = uid;
    await prefs.setString(_bookingsKey, json.encode(b));
  }

  static Future<bool> isSlotTaken(SharedPreferences prefs, String shop, String slot) async {
    final b = await getBookings(prefs);
    return b[shop] != null && b[shop]![slot] != null;
  }
}

/// Basic model for ration items
class RationItem {
  final String name;
  final String quantity;
  final double price;
  RationItem(this.name, this.quantity, this.price);
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Automated Ration App Demo',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const SplashOrLogin(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class SplashOrLogin extends StatefulWidget {
  const SplashOrLogin({super.key});

  @override
  State<SplashOrLogin> createState() => _SplashOrLoginState();
}

class _SplashOrLoginState extends State<SplashOrLogin> {
  late SharedPreferences prefs;
  List<String> uids = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future _init() async {
    prefs = await SharedPreferences.getInstance();
    uids = await DemoData.getUIDs(prefs);
    // show sample uids in a small dialog so developer/tester can see them
    Future.microtask(() {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Demo UIDs (for testing)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: uids.map((u) => Text(u)).toList(),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))
          ],
        ),
      );
    });
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (uids.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return LoginScreen(prefs: prefs);
  }
}

class LoginScreen extends StatefulWidget {
  final SharedPreferences prefs;
  const LoginScreen({required this.prefs, super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final uidController = TextEditingController();
  final passController = TextEditingController();
  final otpController = TextEditingController();

  String? generatedOtp;
  Map<String, String> passcodes = {};

  @override
  void initState() {
    super.initState();
    _loadPasscodes();
  }

  Future _loadPasscodes() async {
    passcodes = await DemoData.getPasscodes(widget.prefs);
    setState(() {});
  }

  Future<void> _loginWithPasscode() async {
    final uid = uidController.text.trim();
    final pass = passController.text.trim();
    if (uid.isEmpty || pass.isEmpty) {
      _showMsg('Enter UID and passcode');
      return;
    }
    final stored = passcodes[uid];
    if (stored == null) {
      _showMsg('Unknown UID');
      return;
    }
    if (stored != pass) {
      _showMsg('Incorrect passcode');
      return;
    }
    _goHome(uid);
  }

  Future<void> _requestOtp() async {
    final uid = uidController.text.trim();
    if (uid.isEmpty) {
      _showMsg('Enter UID to request OTP');
      return;
    }
    final uids = await DemoData.getUIDs(widget.prefs);
    if (!uids.contains(uid)) {
      _showMsg('Unknown UID');
      return;
    }
    final rnd = Random();
    generatedOtp = (rnd.nextInt(900000) + 100000).toString();
    // Simulate sending: show dialog with OTP
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('OTP sent (simulated)'),
        content: Text('Your OTP is: $generatedOtp\n(For demo purposes it is shown here)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))
        ],
      ),
    );
  }

  Future<void> _loginWithOtp() async {
    final uid = uidController.text.trim();
    final otp = otpController.text.trim();
    if (uid.isEmpty || otp.isEmpty) {
      _showMsg('Enter UID and OTP');
      return;
    }
    if (generatedOtp == null) {
      _showMsg('Request an OTP first');
      return;
    }
    if (otp != generatedOtp) {
      _showMsg('Invalid OTP');
      return;
    }
    _goHome(uid);
  }

  void _goHome(String uid) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => HomeScreen(prefs: widget.prefs, uid: uid)),
    );
  }

  void _showMsg(String t) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('APDS Ration App (Demo)')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // logo preview center
            Center(child: Image.asset('assets/logo.png', height: 120)),
            const SizedBox(height: 12),
            TextField(
              controller: uidController,
              decoration: const InputDecoration(labelText: 'UID (e.g. NPHH123456)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: passController,
              decoration: const InputDecoration(labelText: 'Passcode (for UID login)', border: OutlineInputBorder()),
              obscureText: true,
            ),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _loginWithPasscode, child: const Text('Login with UID + Passcode')),
            const SizedBox(height: 8),
            const Divider(),
            TextField(
              controller: otpController,
              decoration: const InputDecoration(labelText: 'OTP (for OTP login)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: ElevatedButton(onPressed: _requestOtp, child: const Text('Request OTP'))),
                const SizedBox(width: 8),
                Expanded(child: ElevatedButton(onPressed: _loginWithOtp, child: const Text('Login with OTP'))),
              ],
            ),
            const SizedBox(height: 12),
            const Text('If you forgot passcode: request OTP and login, then update passcode in settings (demo).'),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final SharedPreferences prefs;
  final String uid;
  const HomeScreen({required this.prefs, required this.uid, super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late List<RationItem> items;
  final allShops = [
    'anna nagar',
    'krishna nagar',
    'mudichur',
    'perungakathur',
    'vetri nagar',
    'kulam',
    'bharathi nagar'
  ];
  List<String> shownShops = [];
  String? selectedShop;
  List<String> slots = [];
  Map<String, bool> slotTaken = {};
  Set<String> selectedSlotsForThisUser = {}; // track user's bookings
  double total = 0.0;
  Map<String, int> cartQty = {};

  @override
  void initState() {
    super.initState();
    items = _itemsForUid(widget.uid);
    _chooseShops();
    _generateSlots();
    _loadSlotStates();
  }

  // Choose 3 random shops per login session
  void _chooseShops() {
    final rnd = Random();
    final copy = List<String>.from(allShops);
    for (int i = 0; i < 3; i++) {
      final idx = rnd.nextInt(copy.length);
      shownShops.add(copy.removeAt(idx));
    }
  }

  void _generateSlots() {
    // 9:00 to 15:00 with 15-min gap -> 24 slots
    slots = [];
    final start = DateTime(0, 0, 0, 9, 0);
    for (int i = 0; i < 24; i++) {
      final t = start.add(Duration(minutes: 15 * i));
      final label = '${_two(t.hour % 12 == 0 ? 12 : t.hour % 12)}:${_two(t.minute)} ${t.hour < 12 ? 'AM' : 'PM'}';
      slots.add(label);
    }
  }

  String _two(int v) => v.toString().padLeft(2, '0');

  Future _loadSlotStates() async {
    final bookings = await DemoData.getBookings(widget.prefs);
    final map = <String, bool>{};
    for (final s in slots) {
      bool taken = false;
      // if any shown shop has this slot taken, mark taken per shop separately
      // but for UI we'll look up per selectedShop when needed
      map[s] = false;
    }
    setState(() {
      slotTaken = map;
    });
  }

  List<RationItem> _itemsForUid(String uid) {
    final list = <RationItem>[];
    if (uid.startsWith('NPHH')) {
      list.add(RationItem('Rice', '25 kg (free)', 0.0));
      list.add(RationItem('Sugar', '2 kg', 20.0));
      list.add(RationItem('Oil', '1 L', 30.0));
      list.add(RationItem('Kerosene', '1 L', 20.0));
      list.add(RationItem('Dhal', '2 kg', 20.0));
      list.add(RationItem('Wheat', '20 kg (free)', 0.0));
    } else if (uid.startsWith('PHH')) {
      list.add(RationItem('Rice', '50 kg (free)', 0.0));
      list.add(RationItem('Sugar', '2 kg', 20.0));
      list.add(RationItem('Oil', '1 L', 30.0));
      list.add(RationItem('Kerosene', '1 L', 20.0));
      list.add(RationItem('Dhal', '2 kg', 20.0));
      list.add(RationItem('Wheat', '20 kg (free)', 0.0));
    } else if (uid.startsWith('AAY') || uid.startsWith('PHH-AAY') || uid.contains('AAY')) {
      // treat as AAY
      list.add(RationItem('Grains', '35 kg (subsidized)', 0.0));
      list.add(RationItem('Other essentials', 'various', 10.0));
    } else {
      // fallback
      list.add(RationItem('Sugar', '2 kg', 20.0));
      list.add(RationItem('Wheat', '20 kg (free)', 0.0));
    }
    // initialize quantities
    for (var it in list) cartQty[it.name] = 0;
    return list;
  }

  Future<bool> _isSlotTaken(String shop, String slot) async {
    return await DemoData.isSlotTaken(widget.prefs, shop, slot);
  }

  Future<void> _bookSlot(String shop, String slot) async {
    // persist booking
    await DemoData.saveBooking(widget.prefs, shop, slot, widget.uid);
    setState(() {
      selectedSlotsForThisUser.add('$shop::$slot');
    });
    _showMsg('Slot booked. Proceed to payment.');
  }

  void _showMsg(String t) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  void _updateTotal() {
    double t = 0.0;
    for (var it in items) {
      final qty = cartQty[it.name] ?? 0;
      t += it.price * qty;
    }
    setState(() {
      total = t;
    });
  }

  void _openPayment() {
    if (selectedShop == null) {
      _showMsg('Select nearest shop first.');
      return;
    }
    // ensure at least one item or slot booked
    if (selectedSlotsForThisUser.isEmpty) {
      _showMsg('Book a time slot for selected shop first.');
      return;
    }
    showModalBottomSheet(
      context: context,
      builder: (_) => SizedBox(
        height: 220,
        child: Column(
          children: [
            const ListTile(title: Text('Payment'), subtitle: Text('Choose payment method (simulated)')),
            ListTile(
              leading: const Icon(Icons.payment),
              title: const Text('GPay'),
              onTap: () {
                Navigator.pop(context);
                _simulatePayment('GPay');
              },
            ),
            ListTile(
              leading: const Icon(Icons.phone_android),
              title: const Text('PhonePe'),
              onTap: () {
                Navigator.pop(context);
                _simulatePayment('PhonePe');
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _simulatePayment(String method) async {
    await Future.delayed(const Duration(milliseconds: 800));
    _showMsg('Payment via $method successful (simulated).');
    // clear cart, but keep booking
    for (var k in cartQty.keys) cartQty[k] = 0;
    _updateTotal();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Welcome, ${widget.uid}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => LoginScreen(prefs: widget.prefs)));
            },
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Image.asset('assets/logo.png', height: 120)),
            const SizedBox(height: 12),
            const Text('Select nearest available shops (3 shown):', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: shownShops.map((s) {
                final isSelected = s == selectedShop;
                return ChoiceChip(
                  label: Text(s),
                  selected: isSelected,
                  onSelected: (sel) async {
                    if (!sel) return;
                    setState(() {
                      selectedShop = s;
                    });
                    // when selecting shop, refresh slot availability
                    setState(() {});
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            const Text('Ration Items (select quantities):', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Column(
              children: items.map((it) {
                return Card(
                  child: ListTile(
                    title: Text('${it.name} — ${it.quantity}'),
                    subtitle: it.price > 0 ? Text('Price: ₹${it.price.toStringAsFixed(2)}') : const Text('Free/Subsidized'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () {
                            final cur = cartQty[it.name] ?? 0;
                            if (cur > 0) {
                              cartQty[it.name] = cur - 1;
                              _updateTotal();
                              setState(() {});
                            }
                          },
                        ),
                        Text('${cartQty[it.name] ?? 0}'),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () {
                            final cur = cartQty[it.name] ?? 0;
                            cartQty[it.name] = cur + 1;
                            _updateTotal();
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            Text('Total: ₹${total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text('Available time slots (select one):', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (selectedShop == null) const Text('Please select a shop to see slot availability.')
            else FutureBuilder(
              future: DemoData.getBookings(widget.prefs),
              builder: (context, snap) {
                if (!snap.hasData) return const CircularProgressIndicator();
                final bookings = snap.data as Map<String, Map<String, String>>;
                return Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: slots.map((s) {
                    final takenBy = bookings[selectedShop!]?[s];
                    final isTaken = takenBy != null;
                    final isMine = takenBy == widget.uid;
                    return SizedBox(
                      width: 110,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isMine ? Colors.green : (isTaken ? Colors.grey : null),
                        ),
                        onPressed: isTaken && !isMine ? null : () async {
                          // if not taken, book
                          if (!isTaken) {
                            await _bookSlot(selectedShop!, s);
                            setState(() {});
                          } else {
                            _showMsg(isMine ? 'You already booked this slot' : 'Slot taken');
                          }
                        },
                        child: Text(s, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _openPayment,
              icon: const Icon(Icons.payment),
              label: const Text('Proceed to Pay (dummy)'),
            ),
            const SizedBox(height: 20),
            const Text('Notes:', style: TextStyle(fontWeight: FontWeight.bold)),
            const Text('- This is a demo. Replace SharedPreferences with a backend for production.'),
            const Text('- To make APK use your APDS logo as app icon (see instructions).'),
          ],
        ),
      ),
    );
  }
}
