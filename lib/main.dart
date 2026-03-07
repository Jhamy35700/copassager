import 'package:flutter/material.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:developer' as dev;
import 'dart:typed_data';
import 'dart:io' show Platform; // L'import est correctement placé en haut du fichier

void main() => runApp(const CoPassagerApp());

class CoPassagerApp extends StatelessWidget {
  const CoPassagerApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CoPassager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true, 
        colorSchemeSeed: const Color(0xFF6366f1)
      ),
      home: const SplashScreen(),
    );
  }
}

// --- 1. SPLASH SCREEN (1s de fluidité) ---
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // RÈGLE : Délai de 1s au démarrage
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const MainLogic()));
    });
  }
  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    const Text('🤝', style: TextStyle(fontSize: 80)),
    ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(colors: [Color(0xFF6366f1), Color(0xFF3b82f6)]).createShader(bounds),
      child: const Text('CoPassager', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: Colors.white)),
    ),
  ])));
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

  // Initialisation avec Groupes Tests variés
  final List<Map<String, dynamic>> _rooms = [
    {"id": "test_1", "author": "Thomas", "title": "Taxi vers aéroport", "desc": "On partage les frais ?", "type": "DEMANDE", "transport": "avion", "isOnline": true},
    {"id": "test_2", "author": "Sarah", "title": "Covoit Gare TGV", "desc": "Je pars à 18h", "type": "OFFRE", "transport": "train", "isOnline": true},
    {"id": "test_3", "author": "Luc", "title": "Partage frais Flixbus", "desc": "Billets de groupe", "type": "OFFRE", "transport": "autocar", "isOnline": true},
    {"id": "test_4", "author": "Marie", "title": "Traversée portuaire", "desc": "Recherche groupe", "type": "DEMANDE", "transport": "bateau", "isOnline": true},
  ];

  List<String> _getMessagesFor(String roomId) => _history.putIfAbsent(roomId, () => []);

  void _onPayloadReceived(String id, Payload payload) {
    if (payload.type == PayloadType.BYTES) {
      setState(() => _getMessagesFor(id).add("Passager: ${String.fromCharCodes(payload.bytes!)}"));
    }
  }

  Future<void> _fetchInternetRooms() async {
    setState(() => _isSyncing = true);
    await Future.delayed(const Duration(milliseconds: 800));
    setState(() => _isSyncing = false);
  }

  void _startNearby() async {
    if (_isServiceRunning) return;
    
    if (Platform.isAndroid) {
      await [
        Permission.location, Permission.bluetoothScan, Permission.bluetoothAdvertise, 
        Permission.bluetoothConnect, Permission.nearbyWifiDevices
      ].request();
    }

    setState(() => _isServiceRunning = true);
    
    try {
      await Nearby().stopAdvertising();
      await Nearby().stopDiscovery();
      _fetchInternetRooms();

      // Strategy cross-platform
      Strategy crossPlatformStrategy = Strategy.P2P_CLUSTER;

      await Nearby().startAdvertising(
        user['name']!, 
        crossPlatformStrategy,
        onConnectionInitiated: (id, info) => Nearby().acceptConnection(id, onPayLoadRecieved: _onPayloadReceived),
        onConnectionResult: (id, status) => dev.log("BT : $status"),
        onDisconnected: (id) => setState(() => _rooms.removeWhere((r) => r['id'] == id)),
        serviceId: "com.copassager.app",
      );

      await Nearby().startDiscovery(
        user['name']!, 
        crossPlatformStrategy,
        onEndpointFound: (id, name, serviceId) {
          if (!_rooms.any((r) => r['id'] == id)) {
            setState(() => _rooms.add({"id": id, "author": name, "title": "Salon de $name", "desc": "", "type": "OFFRE", "transport": user['transport']}));
          }
        },
        onEndpointLost: (id) => setState(() => _rooms.removeWhere((r) => r['id'] == id)),
        serviceId: "com.copassager.app",
      );
        
      setState(() => _currentStep = 4);
    } catch (e) {
      setState(() => _isServiceRunning = false);
      dev.log("Erreur Radar iOS/Android", error: e);
    }
  }

  void _connectToPeer(Map<String, dynamic> room) async {
    if (room['isMine'] == true) {
      setState(() { _activeRoom = room; _currentStep = 5; });
      if (_getMessagesFor(room['id']).isEmpty) {
        _getMessagesFor(room['id']).add("Système: Salon créé. En attente de voyageurs...");
      }
      return;
    }

    setState(() { _activeRoom = room; _currentStep = 5; });
    
    if (room['isOnline'] == true) {
      if (_getMessagesFor(room['id']).isEmpty) {
         _getMessagesFor(room['id']).add("Système: Bienvenue dans le groupe de ${room['author']}");
      }
      return;
    }

    try {
      await Nearby().requestConnection(
        user['name']!, 
        room['id'],
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
      context: context, 
      isScrollControlled: true, 
      builder: (ctx) => _CreateModal(
        activeFilter: _activeFilter,
        onPublish: (title, desc, type, selectedTransport) {
          setState(() {
            _rooms.insert(0, {
              "id": "my_room_${DateTime.now().millisecondsSinceEpoch}", 
              "author": user['name'], 
              "title": title, 
              "desc": desc,
              "type": type, 
              "transport": selectedTransport,
              "isMine": true
            });
            _activeFilter = selectedTransport.toUpperCase();
          });
          Navigator.pop(ctx);
        }
      )
    ).then((_) => setState(() => _isModalOpen = false));
  }

  @override
  Widget build(BuildContext context) => Scaffold(body: _buildStepView());

  Widget _buildStepView() {
    switch (_currentStep) {
      case 1: return _WelcomeStep(onNext: () => setState(() => _currentStep = 2));
      case 2: return _ProfileStep(user: user, onNext: () => setState(() => _currentStep = 3));
      case 3: return _TripStep(user: user, onJoin: _startNearby);
      case 4: 
        List<Map<String, dynamic>> filteredRooms = _rooms.where((r) => _activeFilter == 'TOUS' || r['transport'].toString().toUpperCase() == _activeFilter).toList();
        return _DashboardStep(user: user, rooms: filteredRooms, isSync: _isSyncing, activeFilter: _activeFilter, onFilterChanged: (f) => setState(() => _activeFilter = f), onAdd: _openModal, onSelect: _connectToPeer);
      case 5: {
        String rid = _activeRoom!['id'];
        return _ChatStep(room: _activeRoom!, messages: _getMessagesFor(rid), onSend: (v) {
          setState(() => _getMessagesFor(rid).add("Moi: $v"));
          if (_connectedPeerId != null) {
            Nearby().sendBytesPayload(_connectedPeerId!, Uint8List.fromList(v.codeUnits));
          } else if (_activeRoom?['isOnline'] == true) {
            Future.delayed(const Duration(seconds: 1), () { 
              if (mounted && _currentStep == 5) setState(() => _getMessagesFor(rid).add("${_activeRoom?['author']}: C'est noté !")); 
            });
          }
        }, onBack: () => setState(() => _currentStep = 4));
      }
      default: return const SizedBox();
    }
  }
}

// --- 3. COMPOSANTS DE VUE ---

class _WelcomeStep extends StatelessWidget {
  final VoidCallback onNext;
  const _WelcomeStep({required this.onNext});
  @override
  Widget build(BuildContext context) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    const Text('🤝', style: TextStyle(fontSize: 80)),
    ShaderMask(shaderCallback: (bounds) => const LinearGradient(colors: [Color(0xFF6366f1), Color(0xFF3b82f6)]).createShader(bounds), child: const Text('CoPassager', style: TextStyle(fontSize: 42, fontWeight: FontWeight.w900, color: Colors.white))),
    const SizedBox(height: 40),
    ElevatedButton(onPressed: onNext, child: const Text("Démarrer l'expérience", style: TextStyle(fontWeight: FontWeight.bold)))
  ]));
}

class _ProfileStep extends StatelessWidget {
  final Map<String, String> user;
  final VoidCallback onNext;
  const _ProfileStep({required this.user, required this.onNext});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.all(30), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    const Text('Votre profil', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
    const SizedBox(height: 20),
    TextField(decoration: const InputDecoration(hintText: 'Pseudo', border: OutlineInputBorder()), onChanged: (v) => user['name'] = v, onSubmitted: (_) => onNext()),
    const SizedBox(height: 30),
    const Text('MODE DE TRANSPORT', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
    const SizedBox(height: 10),
    Wrap(
      spacing: 8,
      children: ['avion', 'train', 'autocar', 'bateau'].map((m) => ChoiceChip(
        label: Text(m.toUpperCase()),
        selected: user['transport'] == m,
        onSelected: (_) { user['transport'] = m; (context as Element).markNeedsBuild(); },
      )).toList(),
    ),
    const SizedBox(height: 40),
    ElevatedButton(onPressed: onNext, child: const Text('Suivant')),
  ]));
}

class _TripStep extends StatelessWidget {
  final Map<String, String> user;
  final VoidCallback onJoin;
  const _TripStep({required this.user, required this.onJoin});
  @override
  Widget build(BuildContext context) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    const Icon(Icons.wifi_tethering, size: 80, color: Color(0xFF6366f1)),
    const SizedBox(height: 20),
    const Text('Bluetooth + Internet', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
    const Padding(padding: EdgeInsets.symmetric(horizontal: 40), child: Text('Recherche des voyageurs locaux et en ligne...', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey))),
    const SizedBox(height: 40),
    ElevatedButton(onPressed: onJoin, child: const Text('REJOINDRE LE RÉSEAU')),
  ]));
}

class _DashboardStep extends StatelessWidget {
  final Map<String, String> user;
  final List<Map<String, dynamic>> rooms;
  final bool isSync;
  final String activeFilter;
  final Function(String) onFilterChanged;
  final VoidCallback onAdd;
  final Function(Map<String, dynamic>) onSelect;

  const _DashboardStep({required this.user, required this.rooms, required this.isSync, required this.activeFilter, required this.onFilterChanged, required this.onAdd, required this.onSelect});
  
  @override
  Widget build(BuildContext context) => Column(children: [
    Container(padding: const EdgeInsets.fromLTRB(20, 50, 20, 20), color: const Color(0xFF6366f1), child: Row(children: [
      const CircleAvatar(backgroundColor: Colors.white, child: Icon(Icons.person)),
      const SizedBox(width: 15),
      Expanded(child: Text('Bonjour, ${user['name']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
      if (isSync) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
    ])),
    SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Row(
        children: ['TOUS', 'AVION', 'TRAIN', 'AUTOCAR', 'BATEAU'].map((f) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: ChoiceChip(
            label: Text(f), selected: activeFilter == f, onSelected: (_) => onFilterChanged(f),
            // CORRECTION : withValues() remplace withOpacity()
            selectedColor: const Color(0xFF6366f1).withValues(alpha: 0.2),
          ),
        )).toList(),
      ),
    ),
    Expanded(child: ListView.builder(itemCount: rooms.length, itemBuilder: (ctx, i) => Card(margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), child: ListTile(
      onTap: () => onSelect(rooms[i]),
      leading: Icon(rooms[i]['transport'] == 'avion' ? Icons.flight : rooms[i]['transport'] == 'train' ? Icons.train : rooms[i]['transport'] == 'autocar' ? Icons.directions_bus : Icons.directions_boat, color: const Color(0xFF6366f1)),
      title: Text(rooms[i]['title'], style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text('${rooms[i]['author']} • ${rooms[i]['type']}\n${rooms[i]['desc'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chat_bubble_outline, color: Colors.grey),
      isThreeLine: rooms[i]['desc'] != null && rooms[i]['desc'] != '',
    )))),
    Padding(padding: const EdgeInsets.all(20), child: FloatingActionButton(onPressed: onAdd, child: const Icon(Icons.add))),
  ]);
}

class _ChatStep extends StatelessWidget {
  final Map<String, dynamic> room;
  final List<String> messages;
  final Function(String) onSend;
  final VoidCallback onBack;
  const _ChatStep({required this.room, required this.messages, required this.onSend, required this.onBack});
  @override
  Widget build(BuildContext context) {
    final c = TextEditingController();
    return Scaffold(
      appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: onBack), title: Text(room['title']), backgroundColor: const Color(0xFF6366f1), foregroundColor: Colors.white,),
      body: Column(children: [
        Expanded(child: ListView.builder(itemCount: messages.length, itemBuilder: (ctx, i) => ListTile(title: Text(messages[i])))),
        Padding(padding: const EdgeInsets.all(20), child: TextField(controller: c, decoration: const InputDecoration(hintText: "Message..."), onSubmitted: (v) { onSend(v); c.clear(); })),
      ])
    );
  }
}

// --- MODALE DE CRÉATION DE SALON ---
class _CreateModal extends StatefulWidget {
  final String activeFilter;
  final Function(String, String, String, String) onPublish; // Titre, Desc, Type, Transport
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
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Nouveau Salon', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          
          Row(
            children: [
              Expanded(child: ChoiceChip(label: const Center(child: Text('PROPOSER')), selected: _selectedType == 'OFFRE', onSelected: (v) => setState(() => _selectedType = 'OFFRE'))),
              const SizedBox(width: 10),
              Expanded(child: ChoiceChip(label: const Center(child: Text('CHERCHER')), selected: _selectedType == 'DEMANDE', onSelected: (v) => setState(() => _selectedType = 'DEMANDE'))),
            ],
          ),
          const SizedBox(height: 15),

          TextField(controller: _titleController, decoration: const InputDecoration(hintText: 'Titre (ex: Taxi vers Rennes)', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: _descController, maxLines: 2, decoration: const InputDecoration(hintText: 'Détails, horaires...', border: OutlineInputBorder())),
          const SizedBox(height: 15),

          if (widget.activeFilter == 'TOUS') ...[
            const Text('Transport :', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
            Wrap(
              spacing: 8,
              children: ['avion', 'train', 'autocar', 'bateau'].map((m) => ChoiceChip(
                label: Text(m.toUpperCase()), selected: _selectedTransport == m, onSelected: (_) => setState(() => _selectedTransport = m),
              )).toList(),
            ),
          ] else ...[
             Text('Catégorie : ${widget.activeFilter}', style: const TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
          ],

          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {
              if (_titleController.text.isNotEmpty) {
                widget.onPublish(_titleController.text, _descController.text, _selectedType, _selectedTransport);
              }
            }, 
            child: const Text('Publier sur le radar local')
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}