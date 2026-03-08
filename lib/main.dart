import 'package:flutter/material.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:developer' as dev;
import 'dart:typed_data';
import 'dart:io' show Platform;
import 'package:supabase_flutter/supabase_flutter.dart';

// --- INITIALISATION DES NOTIFICATIONS ---
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // INITIALISATION SUPABASE (Remplace par tes clés)
  await Supabase.initialize(
    url: 'https://xyzcompany.supabase.co', 
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...', 
  );
  
  const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
  const DarwinInitializationSettings initializationSettingsIOS = DarwinInitializationSettings();
  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsIOS,
  );
  
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
        cardTheme: CardThemeData( // Ajoute "Data" ici
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

// --- 1. SPLASH SCREEN ---
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const MainLogic()));
    });
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFF6366f1), Color(0xFF4f46e5)], begin: Alignment.topCenter, end: Alignment.bottomCenter)
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('🤝', style: TextStyle(fontSize: 100)),
        const SizedBox(height: 20),
        const Text('CoPassager', style: TextStyle(fontSize: 42, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1)),
        const Text('Voyagez mieux, ensemble.', style: TextStyle(color: Colors.white70, fontSize: 16)),
      ]),
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
  
  Map<String, String> user = {"name": "", "transport": "avion", "tripId": ""};
  Map<String, dynamic>? _activeRoom;
  
  final Map<String, List<String>> _history = {}; 
  String? _connectedPeerId;

  final List<Map<String, dynamic>> _rooms = [
    {"id": "test_1", "author": "Thomas", "title": "Taxi vers aéroport", "desc": "On partage les frais ?", "type": "DEMANDE", "transport": "avion", "isOnline": true, "isFake": true},
    {"id": "test_2", "author": "Sarah", "title": "Covoit Gare TGV", "desc": "Je pars à 18h", "type": "OFFRE", "transport": "train", "isOnline": true, "isFake": true},
    {"id": "test_3", "author": "Luc", "title": "Partage frais Flixbus", "desc": "Billets de groupe", "type": "OFFRE", "transport": "autocar", "isOnline": true, "isFake": true},
  ];

  List<String> _getMessagesFor(String roomId) => _history.putIfAbsent(roomId, () => []);

  Future<void> _showNotification(String title, String body) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'copassager_channel_id', 'Messages CoPassager',
      importance: Importance.max, priority: Priority.high,
    );
    const NotificationDetails platformDetails = NotificationDetails(android: androidDetails, iOS: DarwinNotificationDetails());
    await flutterLocalNotificationsPlugin.show(id: 0, title: title, body: body, notificationDetails: platformDetails);
  }

  void _onPayloadReceived(String id, Payload payload) {
    if (payload.type == PayloadType.BYTES) {
      String msg = String.fromCharCodes(payload.bytes!);
      setState(() => _getMessagesFor(id).add("Passager: $msg"));
      if (_currentStep != 5 || _activeRoom?['id'] != id) {
        String authorName = _rooms.firstWhere((r) => r['id'] == id, orElse: () => {"author": "Un passager"})['author'];
        _showNotification("Nouveau message de $authorName ✈️", msg);
      }
    }
  }

  Future<void> _fetchInternetRooms() async {
    setState(() => _isSyncing = true);
    try {
      final data = await Supabase.instance.client.from('rooms').select().order('created_at', ascending: false);
      setState(() {
        _rooms.removeWhere((r) => r['isOnline'] == true && r['isMine'] != true && r['isFake'] != true);
        for (var row in data) {
          _rooms.add({
            "id": row['id'], "author": row['author'], "title": row['title'],
            "desc": row['desc'], "type": row['type'], "transport": row['transport'], "isOnline": true, 
          });
        }
      });
    } catch (e) { dev.log("Erreur Supabase: $e"); }
    setState(() => _isSyncing = false);
  }

  void _startNearby() async {
    if (_isServiceRunning) return;
    await Permission.notification.request();
    if (Platform.isAndroid) {
      await [Permission.location, Permission.bluetoothScan, Permission.bluetoothAdvertise, Permission.bluetoothConnect, Permission.nearbyWifiDevices].request();
    }
    setState(() => _isServiceRunning = true);
    try {
      await Nearby().stopAdvertising();
      await Nearby().stopDiscovery();
      _fetchInternetRooms();
      await Nearby().startAdvertising(
        user['name']!, Strategy.P2P_CLUSTER,
        onConnectionInitiated: (id, info) => Nearby().acceptConnection(id, onPayLoadRecieved: _onPayloadReceived),
        onConnectionResult: (id, status) => dev.log("BT : $status"),
        onDisconnected: (id) => setState(() => _rooms.removeWhere((r) => r['id'] == id)),
        serviceId: "com.copassager.app",
      );
      await Nearby().startDiscovery(
        user['name']!, Strategy.P2P_CLUSTER,
        onEndpointFound: (id, name, serviceId) {
          if (!_rooms.any((r) => r['id'] == id)) {
            setState(() => _rooms.add({"id": id, "author": name, "title": "Salon de $name", "desc": "", "type": "OFFRE", "transport": user['transport']}));
          }
        },
        onEndpointLost: (id) => setState(() => _rooms.removeWhere((r) => r['id'] == id)),
        serviceId: "com.copassager.app",
      );
      setState(() => _currentStep = 4);
    } catch (e) { setState(() => _isServiceRunning = false); }
  }

  void _connectToPeer(Map<String, dynamic> room) async {
    setState(() { _activeRoom = room; _currentStep = 5; });
    if (room['isMine'] == true || room['isOnline'] == true) return;
    try {
      await Nearby().requestConnection(
        user['name']!, room['id'],
        onConnectionInitiated: (id, info) => Nearby().acceptConnection(id, onPayLoadRecieved: _onPayloadReceived),
        onConnectionResult: (id, status) { if (status == Status.CONNECTED) _connectedPeerId = id; },
        onDisconnected: (id) => setState(() => _connectedPeerId = null)
      );
    } catch (e) { dev.log("Erreur connexion", error: e); }
  }

  void _openModal() {
    if (_isModalOpen) return;
    setState(() => _isModalOpen = true);
    showModalBottomSheet(
      context: context, isScrollControlled: true, 
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CreateModal(
        activeFilter: _activeFilter,
        onPublish: (title, desc, type, transport) async {
          Navigator.pop(ctx);
          final id = "room_${DateTime.now().millisecondsSinceEpoch}";
          setState(() {
            _rooms.insert(0, {"id": id, "author": user['name'], "title": title, "desc": desc, "type": type, "transport": transport, "isMine": true, "isOnline": true});
          });
          try {
            await Supabase.instance.client.from('rooms').insert({"id": id, "author": user['name'], "title": title, "desc": desc, "type": type, "transport": transport});
          } catch (e) { dev.log("Erreur envoi: $e"); }
        }
      )
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
        return _DashboardStep(user: user, rooms: filtered, isSync: _isSyncing, activeFilter: _activeFilter, onFilterChanged: (f) => setState(() => _activeFilter = f), onAdd: _openModal, onSelect: _connectToPeer);
      case 5: 
        return _ChatStep(room: _activeRoom!, messages: _getMessagesFor(_activeRoom!['id']), onSend: (v) {
          setState(() => _getMessagesFor(_activeRoom!['id']).add("Moi: $v"));
          if (_connectedPeerId != null) Nearby().sendBytesPayload(_connectedPeerId!, Uint8List.fromList(v.codeUnits));
        }, onBack: () => setState(() => _currentStep = 4));
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
        style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 60), backgroundColor: const Color(0xFF6366f1), foregroundColor: Colors.white),
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
    body: Padding(padding: const EdgeInsets.all(30), child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Votre Profil', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: -1)),
      const SizedBox(height: 10),
      const Text('Comment souhaitez-vous apparaître ?', style: TextStyle(color: Colors.grey)),
      const SizedBox(height: 30),
      TextField(
        decoration: InputDecoration(hintText: 'Pseudo', filled: true, fillColor: Colors.grey.shade100, border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)),
        onChanged: (v) => user['name'] = v,
      ),
      const SizedBox(height: 30),
      const Text('VOTRE TRANSPORT FAVORI', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF6366f1))),
      const SizedBox(height: 15),
      Wrap(spacing: 10, children: ['avion', 'train', 'autocar', 'bateau'].map((m) => ChoiceChip(
        label: Text(m.toUpperCase()), 
        selected: user['transport'] == m, 
        onSelected: (_) { user['transport'] = m; (context as Element).markNeedsBuild(); }
      )).toList()),
      const SizedBox(height: 50),
      ElevatedButton(
        style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 60), backgroundColor: const Color(0xFF6366f1), foregroundColor: Colors.white),
        onPressed: onNext, child: const Text('CONTINUER')
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
      const SizedBox(height: 30),
      const Text('Activation du Radar', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      const Padding(padding: EdgeInsets.symmetric(horizontal: 50, vertical: 10), child: Text('Nous allons scanner les voyageurs à proximité et en ligne.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey))),
      const SizedBox(height: 40),
      ElevatedButton(onPressed: onJoin, child: const Text('REJOINDRE LE RÉSEAU')),
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

  // CORRECTION : 'required' bien écrit et suppression du 'super.key' inutile
  const _DashboardStep({
    required this.user, 
    required this.rooms, 
    required this.isSync, 
    required this.activeFilter, 
    required this.onFilterChanged, 
    required this.onAdd, 
    required this.onSelect
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(children: [
        Container(
          padding: const EdgeInsets.fromLTRB(25, 60, 25, 30),
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF6366f1), Color(0xFF8b5cf6)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(30))
          ),
          child: Row(children: [
            const CircleAvatar(radius: 25, backgroundColor: Colors.white24, child: Icon(Icons.person, color: Colors.white, size: 30)),
            const SizedBox(width: 15),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Bonjour,', style: TextStyle(color: Colors.white70)),
              Text(user['name']!, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            ])),
            if (isSync) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
          ]),
        ),
        
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Row(children: ['TOUS', 'AVION', 'TRAIN', 'AUTOCAR', 'BATEAU'].map((f) => Padding(
            padding: const EdgeInsets.only(right: 10),
            child: ChoiceChip(
              label: Text(f), 
              selected: activeFilter == f, 
              onSelected: (_) => onFilterChanged(f),
              selectedColor: const Color(0xFF6366f1),
              labelStyle: TextStyle(color: activeFilter == f ? Colors.white : const Color(0xFF6366f1), fontWeight: FontWeight.bold),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              showCheckmark: false,
            ),
          )).toList()),
        ),

        Expanded(child: ListView.builder(
          padding: const EdgeInsets.only(top: 0),
          itemCount: rooms.length, 
          itemBuilder: (ctx, i) {
            final r = rooms[i];
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white, 
                borderRadius: BorderRadius.circular(20), 
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10)] 
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.all(15),
                onTap: () => onSelect(r),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366f1).withValues(alpha: 0.1), 
                    borderRadius: BorderRadius.circular(15)
                  ),
                  child: Icon(r['transport'] == 'avion' ? Icons.flight : Icons.directions_bus, color: const Color(0xFF6366f1)),
                ),
                title: Text(r['title'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SizedBox(height: 5),
                  Text('${r['author']} • ${r['type']}', style: TextStyle(color: Colors.grey.shade600)),
                ]),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
              ),
            );
          }
        )),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: onAdd, 
        backgroundColor: const Color(0xFF6366f1),
        label: const Text("PUBLIER", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        icon: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
class _ChatStep extends StatelessWidget {
  final Map<String, dynamic> room;
  final List<String> messages;
  final Function(String) onSend;
  final VoidCallback onBack;
  const _ChatStep({ required this.room, required this.messages, required this.onSend, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final textController = TextEditingController();
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios), onPressed: onBack),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(room['title'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          Text(room['author'], style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ]),
      ),
      body: Column(children: [
        Expanded(child: ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: messages.length, 
          itemBuilder: (ctx, i) {
            bool isMe = messages[i].startsWith("Moi:");
            return Align(
              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 5),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isMe ? const Color(0xFF6366f1) : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Text(messages[i].replaceFirst(isMe ? "Moi: " : "Passager: ", ""), style: TextStyle(color: isMe ? Colors.white : Colors.black)),
              ),
            );
          }
        )),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10)]),
          child: Row(children: [
            Expanded(child: TextField(controller: textController, decoration: const InputDecoration(hintText: "Écrivez ici...", border: InputBorder.none))),
            IconButton(icon: const Icon(Icons.send, color: Color(0xFF6366f1)), onPressed: () {
              if (textController.text.isNotEmpty) {
                onSend(textController.text);
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
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 25, right: 25, top: 25),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Créer une annonce', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
        TextField(controller: _titleController, decoration: InputDecoration(hintText: 'Titre de l\'annonce', filled: true, fillColor: Colors.grey.shade100, border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none))),
        const SizedBox(height: 15),
        TextField(controller: _descController, maxLines: 2, decoration: InputDecoration(hintText: 'Description (Optionnel)', filled: true, fillColor: Colors.grey.shade100, border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none))),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: ChoiceChip(label: const Center(child: Text('PROPOSER')), selected: _selectedType == 'OFFRE', onSelected: (v) => setState(() => _selectedType = 'OFFRE'))),
          const SizedBox(width: 10),
          Expanded(child: ChoiceChip(label: const Center(child: Text('RECHERCHER')), selected: _selectedType == 'DEMANDE', onSelected: (v) => setState(() => _selectedType = 'DEMANDE'))),
        ]),
        const SizedBox(height: 20),
        ElevatedButton(
          style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 60), backgroundColor: const Color(0xFF6366f1), foregroundColor: Colors.white),
          onPressed: () {
            if (_titleController.text.isNotEmpty) {
              widget.onPublish(_titleController.text, _descController.text, _selectedType, _selectedTransport);
            }
          }, 
          child: const Text('PUBLIER MAINTENANT')
        ),
        const SizedBox(height: 30),
      ]),
    );
  }
}