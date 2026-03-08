import 'package:flutter/material.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:developer' as dev;
import 'dart:typed_data';
import 'dart:io' show Platform;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';

// --- INITIALISATION DES SERVICES ---
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // INITIALISATION SUPABASE
  await Supabase.initialize(
    url: 'https://nfufnqxkgjzhmqbzuhec.supabase.co', 
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5mdWZucXhrZ2p6aG1xYnp1aGVjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI5NTQ0MjYsImV4cCI6MjA4ODUzMDQyNn0.YuFMcYw7vVDY9bADyMV9EhykunZywIfKWHmQ1eOQB3g', 
  );
  
  const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
  const DarwinInitializationSettings initializationSettingsIOS = DarwinInitializationSettings();
  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsIOS,
  );
  
  // CORRECTION : Paramètre nommé 'settings' requis ici
  await flutterLocalNotificationsPlugin.initialize(
    settings: initializationSettings,
  );

  runApp(const CoPassagerApp());
}

class CoPassagerApp extends StatelessWidget {
  const CoPassagerApp({super.key});
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CoPassager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366f1),
          brightness: Brightness.light,
        ),
        cardTheme: CardThemeData( 
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          color: Colors.white,
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

// --- 1. SPLASH SCREEN (CORRIGÉ ET PROPRE) ---
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Délai de 2 secondes avant de passer à la logique principale
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.pushReplacement(
          context, 
          MaterialPageRoute(builder: (context) => const MainLogic())
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF6366f1), Color(0xFF4f46e5)], 
          begin: Alignment.topCenter, 
          end: Alignment.bottomCenter
        ),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center, 
        children: [
          Text('🤝', style: TextStyle(fontSize: 100)),
          SizedBox(height: 20),
          Text('CoPassager', 
            style: TextStyle(
              fontSize: 42, 
              fontWeight: FontWeight.w900, 
              color: Colors.white, 
              letterSpacing: -1
            )
          ),
          Text('Voyagez mieux, ensemble.', 
            style: TextStyle(color: Colors.white70, fontSize: 16)
          ),
        ],
      ),
    ),
  );
}

// --- 2. LOGIQUE PRINCIPALE ---
class MainLogic extends StatefulWidget {
  const MainLogic({super.key});
  @override
  State<MainLogic> createState() => _MainLogicState();
}

class _MainLogicState extends State<MainLogic> {
  int _currentStep = 1; 
  bool _isModalOpen = false;
  bool _isServiceRunning = false;
  bool _isSyncing = false;
  String _activeFilter = 'TOUS';
  String _appVersion = "0.0.0"; 

  Map<String, String> user = {"name": "", "transport": "avion", "tripId": ""};
  Map<String, dynamic>? _activeRoom;
  
  final Map<String, List<String>> _history = {}; 
  String? _connectedPeerId;

  final List<Map<String, dynamic>> _rooms = [
    {"id": "test_1", "author": "Thomas", "title": "Taxi vers aéroport", "desc": "On partage les frais ?", "type": "DEMANDE", "transport": "avion", "isOnline": true, "isFake": true},
    {"id": "test_2", "author": "Sarah", "title": "Covoit Gare TGV", "desc": "Je pars à 18h", "type": "OFFRE", "transport": "train", "isOnline": true, "isFake": true},
  ];

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      setState(() => _appVersion = "${packageInfo.version}+${packageInfo.buildNumber}");
    } catch (e) { dev.log("Erreur version: $e"); }
  }

  List<String> _getMessagesFor(String roomId) => _history.putIfAbsent(roomId, () => []);

  // CORRECTION : Arguments nommés requis pour 'show'
  Future<void> _showNotification(String title, String body) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'cp_channel', 'Messages', importance: Importance.max, priority: Priority.high,
    );
    await flutterLocalNotificationsPlugin.show(
      id: 0, 
      title: title, 
      body: body, 
      notificationDetails: const NotificationDetails(android: androidDetails)
    );
  }

  void _onPayloadReceived(String id, Payload payload) {
    if (payload.type == PayloadType.BYTES) {
      String msg = String.fromCharCodes(payload.bytes!);
      setState(() => _getMessagesFor(id).add("Passager: $msg"));
      if (_currentStep != 5) _showNotification("Nouveau message", msg);
    }
  }

  Future<void> _fetchInternetRooms() async {
    setState(() => _isSyncing = true);
    try {
      final data = await Supabase.instance.client.from('rooms').select().order('created_at', ascending: false);
      setState(() {
        _rooms.removeWhere((r) => r['isOnline'] == true && r['isMine'] != true && r['isFake'] != true);
        for (var row in data) {
          _rooms.add({"id": row['id'], "author": row['author'], "title": row['title'], "desc": row['desc'], "type": row['type'], "transport": row['transport'], "isOnline": true});
        }
      });
    } catch (e) { dev.log("Erreur Supabase: $e"); }
    setState(() => _isSyncing = false);
  }

  void _startNearby() async {
    if (_isServiceRunning) return;
    if (Platform.isAndroid) await [Permission.location, Permission.bluetoothScan, Permission.bluetoothAdvertise, Permission.bluetoothConnect, Permission.nearbyWifiDevices].request();
    setState(() => _isServiceRunning = true);
    try {
      await Nearby().stopAdvertising();
      await Nearby().stopDiscovery();
      _fetchInternetRooms();
      
      await Nearby().startAdvertising(
        user['name']!, Strategy.P2P_CLUSTER,
        onConnectionInitiated: (id, info) => Nearby().acceptConnection(id, onPayLoadRecieved: _onPayloadReceived),
        onConnectionResult: (id, status) => dev.log("BT : $status"),
        onDisconnected: (id) => setState(() => _connectedPeerId = null), // Paramètre requis
        serviceId: "com.copassager.app",
      );
      
      await Nearby().startDiscovery(
        user['name']!, Strategy.P2P_CLUSTER,
        onEndpointFound: (id, name, serviceId) {
          if (!_rooms.any((r) => r['id'] == id)) setState(() => _rooms.add({"id": id, "author": name, "title": "Salon de $name", "transport": user['transport']}));
        },
        onEndpointLost: (id) => setState(() => _rooms.removeWhere((r) => r['id'] == id)),
        serviceId: "com.copassager.app",
      );
      setState(() => _currentStep = 4);
    } catch (e) { setState(() => _isServiceRunning = false); }
  }

  Future<void> _goBackToProfile() async {
    await Nearby().stopAdvertising();
    await Nearby().stopDiscovery();
    setState(() {
      _isServiceRunning = false;
      _currentStep = 2; 
    });
  }

  void _connectToPeer(Map<String, dynamic> room) async {
    setState(() { _activeRoom = room; _currentStep = 5; });
    if (room['isMine'] == true || room['isOnline'] == true) return;
    try {
      await Nearby().requestConnection(
        user['name']!, room['id'],
        onConnectionInitiated: (id, info) => Nearby().acceptConnection(id, onPayLoadRecieved: _onPayloadReceived),
        onConnectionResult: (id, status) { if (status == Status.CONNECTED) _connectedPeerId = id; },
        onDisconnected: (id) => setState(() => _connectedPeerId = null) // Requis
      );
    } catch (e) { dev.log("Erreur connexion", error: e); }
  }

  void _openModal() {
    if (_isModalOpen) return;
    setState(() => _isModalOpen = true);
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (ctx) => _CreateModal(activeFilter: _activeFilter, onPublish: (title, desc, type, transport) async {
          Navigator.pop(ctx);
          final id = "room_${DateTime.now().millisecondsSinceEpoch}";
          setState(() => _rooms.insert(0, {"id": id, "author": user['name'], "title": title, "desc": desc, "type": type, "transport": transport, "isMine": true, "isOnline": true}));
          try {
            await Supabase.instance.client.from('rooms').insert({"id": id, "author": user['name'], "title": title, "desc": desc, "type": type, "transport": transport});
          } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur Cloud: $e"), backgroundColor: Colors.red)); }
      })
    ).then((_) => setState(() => _isModalOpen = false));
  }

  @override
  Widget build(BuildContext context) {
    switch (_currentStep) {
      case 1: return _WelcomeStep(onNext: () => setState(() => _currentStep = 2));
      case 2: return _ProfileStep(user: user, onNext: () => setState(() => _currentStep = 3));
      case 3: return _TripStep(user: user, onJoin: _startNearby);
      case 4: 
        List<Map<String, dynamic>> filtered = _rooms.where((r) => _activeFilter == 'TOUS' || r['transport'].toString().toUpperCase() == _activeFilter).toList();
        return _DashboardStep(
          user: user, rooms: filtered, isSync: _isSyncing, activeFilter: _activeFilter, appVersion: _appVersion,
          onFilterChanged: (f) => setState(() => _activeFilter = f), onAdd: _openModal, onSelect: _connectToPeer, onEditProfile: _goBackToProfile
        );
      case 5: 
        return _ChatStep(
          room: _activeRoom!, 
          messages: _getMessagesFor(_activeRoom!['id']), 
          onBack: () => setState(() => _currentStep = 4),
          onSend: (v) async {
            setState(() => _getMessagesFor(_activeRoom!['id']).add("Moi: $v"));
            if (_connectedPeerId != null) Nearby().sendBytesPayload(_connectedPeerId!, Uint8List.fromList(v.codeUnits));
            try {
              await Supabase.instance.client.from('messages').insert({'room_id': _activeRoom!['id'], 'sender_name': user['name'], 'content': v});
            } catch (e) { dev.log("Erreur Cloud Message: $e"); }
          },
        );
      default: return const SizedBox();
    }
  }
}

// --- 3. COMPOSANTS DE VUE ---

class _WelcomeStep extends StatelessWidget {
  final VoidCallback onNext;
  const _WelcomeStep({required this.onNext});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Padding(padding: const EdgeInsets.all(40), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Text('🤝', style: TextStyle(fontSize: 80)),
      const SizedBox(height: 20),
      const Text('Partagez plus qu\'un trajet', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      const Text('Rejoignez des voyageurs autour de vous en temps réel.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
      const SizedBox(height: 50),
      ElevatedButton(
        style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 60), backgroundColor: const Color(0xFF6366f1), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
        onPressed: onNext, child: const Text("COMMENCER", style: TextStyle(fontWeight: FontWeight.bold))
      )
    ])),
  );
}

class _ProfileStep extends StatelessWidget {
  final Map<String, String> user;
  final VoidCallback onNext;
  const _ProfileStep({required this.user, required this.onNext});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Padding(padding: const EdgeInsets.all(35), child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Votre Profil', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
      const SizedBox(height: 30),
      TextFormField(
        initialValue: user['name'],
        decoration: InputDecoration(hintText: 'Pseudo', filled: true, fillColor: Colors.grey.shade100, border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none)),
        onChanged: (v) => user['name'] = v,
      ),
      const SizedBox(height: 30),
      Wrap(spacing: 12, children: ['avion', 'train', 'autocar', 'bateau'].map((m) => ChoiceChip(
        label: Text(m.toUpperCase()), selected: user['transport'] == m, 
        onSelected: (_) { user['transport'] = m; (context as Element).markNeedsBuild(); }
      )).toList()),
      const SizedBox(height: 50),
      ElevatedButton(
        style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 65), backgroundColor: const Color(0xFF6366f1), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
        onPressed: onNext, child: const Text('CONTINUER', style: TextStyle(fontWeight: FontWeight.bold))
      ),
    ])),
  );
}

class _TripStep extends StatelessWidget {
  final Map<String, String> user;
  final VoidCallback onJoin;
  const _TripStep({required this.user, required this.onJoin});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.radar, size: 100, color: Color(0xFF6366f1)),
      const SizedBox(height: 40),
      const Text('Radar Activé', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      const SizedBox(height: 50),
      ElevatedButton(
        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20), backgroundColor: const Color(0xFF6366f1), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
        onPressed: onJoin, child: const Text('REJOINDRE LE RÉSEAU', style: TextStyle(fontWeight: FontWeight.bold))
      ),
    ])),
  );
}

class _DashboardStep extends StatelessWidget {
  final Map<String, String> user;
  final List<Map<String, dynamic>> rooms;
  final bool isSync;
  final String activeFilter;
  final Function(String) onFilterChanged;
  final VoidCallback onAdd;
  final Function(Map<String, dynamic>) onSelect;
  final String appVersion;
  final VoidCallback onEditProfile;

  const _DashboardStep({required this.user, required this.rooms, required this.isSync, required this.activeFilter, required this.onFilterChanged, required this.onAdd, required this.appVersion, required this.onSelect, required this.onEditProfile});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(children: [
      Container(
        padding: const EdgeInsets.fromLTRB(25, 65, 25, 35),
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Color(0xFF6366f1), Color(0xFF8b5cf6)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(35))
        ),
        child: Row(children: [
          GestureDetector(onTap: onEditProfile, child: const CircleAvatar(radius: 28, backgroundColor: Colors.white24, child: Icon(Icons.edit, color: Colors.white))),
          const SizedBox(width: 15),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(appVersion, style: const TextStyle(color: Colors.white70, fontSize: 10)),
            Text(user['name']!, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          ])),
          if (isSync) const SizedBox(width: 25, height: 25, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
        ]),
      ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
        child: Row(children: ['TOUS', 'AVION', 'TRAIN', 'AUTOCAR', 'BATEAU'].map((f) => Padding(
          padding: const EdgeInsets.only(right: 12),
          child: ChoiceChip(
            label: Text(f), selected: activeFilter == f, onSelected: (_) => onFilterChanged(f),
            selectedColor: const Color(0xFF6366f1),
            labelStyle: TextStyle(color: activeFilter == f ? Colors.white : const Color(0xFF6366f1), fontWeight: FontWeight.bold),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)), showCheckmark: false,
          ),
        )).toList()),
      ),
      Expanded(child: ListView.builder(
        padding: const EdgeInsets.only(top: 0),
        itemCount: rooms.length, 
        itemBuilder: (ctx, i) {
          final r = rooms[i];
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)]),
            child: ListTile(
              contentPadding: const EdgeInsets.all(20),
              onTap: () => onSelect(r),
              leading: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFF6366f1).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(18)),
                child: Icon(r['transport'] == 'avion' ? Icons.flight_takeoff : Icons.directions_bus, color: const Color(0xFF6366f1)),
              ),
              title: Text(r['title'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              subtitle: Text('${r['author']} • ${r['type']}', style: TextStyle(color: Colors.grey.shade500)),
              trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            ),
          );
        }
      )),
    ]),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: onAdd, backgroundColor: const Color(0xFF6366f1),
      label: const Text("PUBLIER", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      icon: const Icon(Icons.add, color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
  );
}

class _ChatStep extends StatelessWidget {
  final Map<String, dynamic> room;
  final List<String> messages;
  final Function(String) onSend;
  final VoidCallback onBack;
  const _ChatStep({required this.room, required this.messages, required this.onSend, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final textController = TextEditingController();
    return Scaffold(
      appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, size: 20), onPressed: onBack), title: Text(room['title'])),
      body: Column(children: [
        Expanded(child: ListView.builder(
          padding: const EdgeInsets.all(25),
          itemCount: messages.length, 
          itemBuilder: (ctx, i) {
            bool isMe = messages[i].startsWith("Moi:");
            return Align(
              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 6),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  color: isMe ? const Color(0xFF6366f1) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 5)]
                ),
                child: Text(messages[i].replaceFirst(isMe ? "Moi: " : "Passager: ", ""), style: TextStyle(color: isMe ? Colors.white : Colors.black87)),
              ),
            );
          }
        )),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
          child: Row(children: [
            Expanded(child: TextField(controller: textController, decoration: const InputDecoration(hintText: "Message...", border: InputBorder.none))),
            IconButton(icon: const Icon(Icons.send, color: Color(0xFF6366f1)), onPressed: () {
              if (textController.text.trim().isNotEmpty) {
                onSend(textController.text.trim());
                textController.clear();
              }
            }),
          ]),
        )
      ]),
    );
  }
}

class _CreateModal extends StatefulWidget {
  final String activeFilter;
  final Function(String, String, String, String) onPublish; 
  const _CreateModal({required this.activeFilter, required this.onPublish});
  @override
  State<_CreateModal> createState() => _CreateModalState();
}

class _CreateModalState extends State<_CreateModal> {
  late String _selectedTransport;
  String _selectedType = 'OFFRE';
  final _titleController = TextEditingController();
  final _descController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedTransport = widget.activeFilter == 'TOUS' ? 'avion' : widget.activeFilter.toLowerCase();
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 30, left: 30, right: 30, top: 30),
    decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(35))),
    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Créer une annonce', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      const SizedBox(height: 25),
      TextField(controller: _titleController, decoration: InputDecoration(hintText: 'Titre', filled: true, fillColor: Colors.grey.shade50, border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none))),
      const SizedBox(height: 25),
      Row(children: [
        Expanded(child: ChoiceChip(label: const Center(child: Text('OFFRE')), selected: _selectedType == 'OFFRE', onSelected: (_) => setState(() => _selectedType = 'OFFRE'))),
        const SizedBox(width: 15),
        Expanded(child: ChoiceChip(label: const Center(child: Text('DEMANDE')), selected: _selectedType == 'DEMANDE', onSelected: (_) => setState(() => _selectedType = 'DEMANDE'))),
      ]),
      const SizedBox(height: 35),
      ElevatedButton(
        style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 65), backgroundColor: const Color(0xFF6366f1), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
        onPressed: () {
          if (_titleController.text.isNotEmpty) widget.onPublish(_titleController.text, _descController.text, _selectedType, _selectedTransport);
        }, 
        child: const Text('PUBLIER', style: TextStyle(fontWeight: FontWeight.bold))
      ),
    ]),
  );
}