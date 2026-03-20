import 'package:flutter/material.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:developer' as dev;
import 'dart:typed_data';
import 'dart:io' show Platform;
import 'dart:async'; 
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart'; 

// 👇 NOUVEAUX IMPORTS POUR LA CARTE 👇
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

// --- INITIALISATION DES SERVICES ---
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
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
    Future.delayed(const Duration(seconds: 1), () {
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
  bool _isOffline = false; 
  String _activeFilter = 'TOUS';
  String _searchQuery = ''; 
  String _appVersion = "0.0.0"; 

  Map<String, String> user = {"name": "", "password": "", "transport": "avion", "firstName": "", "lastName": "", "address": ""};
  Map<String, dynamic>? _activeRoom;
  
  final Map<String, List<String>> _history = {}; 
  String? _connectedPeerId;

  final List<Map<String, dynamic>> _rooms = [];
  
  StreamSubscription<List<Map<String, dynamic>>>? _roomsSubscription;
  final Map<String, StreamSubscription<List<Map<String, dynamic>>>> _chatSubscriptions = {};
  List<String> _subscribedRooms = []; 
  
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _requestNotificationPermission();
    _loadVersion();
    _loadSavedProfile(); 
    
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      if (mounted) {
        setState(() {
          _isOffline = results.contains(ConnectivityResult.none);
        });
      }
    });
  }

  Future<void> _requestNotificationPermission() async {
    if (Platform.isAndroid) {
      await Permission.notification.request();
    }
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel(); 
    _roomsSubscription?.cancel();
    for (var sub in _chatSubscriptions.values) {
      sub.cancel();
    }
    super.dispose();
  }

  String _formatTime(DateTime dt) {
    return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  Future<void> _loadVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      setState(() => _appVersion = "${packageInfo.version}+${packageInfo.buildNumber}");
    } catch (e) { dev.log("Erreur version: $e"); }
  }

  Future<void> _loadSavedProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      user['name'] = prefs.getString('saved_pseudo') ?? "";
      user['password'] = prefs.getString('saved_password') ?? ""; 
      user['transport'] = prefs.getString('saved_transport') ?? "avion";
      user['firstName'] = prefs.getString('saved_firstname') ?? "";
      user['lastName'] = prefs.getString('saved_lastname') ?? "";
      user['address'] = prefs.getString('saved_address') ?? "";
    });
    
    if (user['name']!.isNotEmpty) {
      _loadUserSubscriptions();
    }
  }

  Future<void> _loadUserSubscriptions() async {
    try {
      final data = await Supabase.instance.client
          .from('participants')
          .select('room_id')
          .eq('pseudo', user['name']!);
          
      setState(() {
        _subscribedRooms = data.map<String>((row) => row['room_id'] as String).toList();
      });
      
      for (String roomId in _subscribedRooms) {
        _listenToCloudMessages(roomId);
      }
    } catch (e) {
      dev.log("Erreur chargement abonnements: $e");
    }
  }

  Future<void> _toggleSubscription(String roomId) async {
    bool isSub = _subscribedRooms.contains(roomId);
    
    setState(() {
      if (isSub) {
        _subscribedRooms.remove(roomId); 
      } else {
        _subscribedRooms.add(roomId); 
      }
    });

    try {
      if (isSub) {
        await Supabase.instance.client.from('participants').delete().eq('room_id', roomId).eq('pseudo', user['name']!);
      } else {
        await Supabase.instance.client.from('participants').insert({'room_id': roomId, 'pseudo': user['name']!});
      }
    } catch (e) {
      dev.log("Erreur modification abonnement: $e");
    }
  }

  Future<bool> _saveAndValidateProfile(String newPseudo, String pwd, String transport, String fName, String lName, String addr) async {
    final prefs = await SharedPreferences.getInstance();

    try {
      final data = await Supabase.instance.client
          .from('users')
          .select() 
          .eq('pseudo', newPseudo)
          .maybeSingle();

      if (data != null) {
        String dbPwd = data['password'] != null ? data['password'].toString().trim() : "";
        
        if (dbPwd.isNotEmpty && dbPwd != pwd) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("Ce pseudo existe déjà. Mot de passe incorrect !"), 
              backgroundColor: Colors.red,
            ));
          }
          return false; 
        }
      }

      await Supabase.instance.client.from('users').upsert({
        'pseudo': newPseudo,
        'password': pwd, 
        'prenom': fName,
        'nom': lName,
        'adresse': addr
      });

    } catch (e) {
      dev.log("Erreur Connexion Supabase: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur serveur : $e"), backgroundColor: Colors.orange));
      return false;
    }

    await prefs.setString('saved_pseudo', newPseudo);
    await prefs.setString('saved_password', pwd);
    await prefs.setString('saved_transport', transport);
    await prefs.setString('saved_firstname', fName);
    await prefs.setString('saved_lastname', lName);
    await prefs.setString('saved_address', addr);

    setState(() {
      user['name'] = newPseudo;
      user['password'] = pwd;
      user['transport'] = transport;
      user['firstName'] = fName;
      user['lastName'] = lName;
      user['address'] = addr;
      _activeFilter = transport.toUpperCase();
      _currentStep = 3;
    });
    
    _loadUserSubscriptions();
    
    return true; 
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear(); 

    _roomsSubscription?.cancel();
    for (var sub in _chatSubscriptions.values) {
      sub.cancel();
    }
    _chatSubscriptions.clear();
    _subscribedRooms.clear();
    _history.clear();
    
    try {
      await Nearby().stopAdvertising();
      await Nearby().stopDiscovery();
    } catch (e) {
      dev.log("Erreur arrêt Nearby: $e");
    }

    setState(() {
      user = {"name": "", "password": "", "transport": "avion", "firstName": "", "lastName": "", "address": ""};
      _isServiceRunning = false;
      _currentStep = 2; 
    });
  }

  List<String> _getMessagesFor(String roomId) => _history.putIfAbsent(roomId, () => []);

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
      if (_currentStep != 5) _showNotification("Nouveau message Bluetooth", msg);
    }
  }

  void _listenToInternetRooms() {
    setState(() => _isSyncing = true);
    _roomsSubscription?.cancel();
    
    try {
      _roomsSubscription = Supabase.instance.client
          .from('rooms')
          .stream(primaryKey: ['id'])
          .order('created_at', ascending: false)
          .listen((List<Map<String, dynamic>> data) {
            
        if (!mounted) return;
        
        setState(() {
          _rooms.removeWhere((r) => r['isOnline'] == true && r['isMine'] != true);
          
          for (var row in data) {
            if (!_rooms.any((r) => r['id'] == row['id'])) {
              _rooms.add({
                "id": row['id'], 
                "author": row['author'], 
                "title": row['title'], 
                "desc": row['desc'], 
                "type": row['type'], 
                "transport": row['transport'], 
                "trip_number": row['trip_number'],
                "lat": row['lat'], // 👈 Récupère la latitude
                "lng": row['lng'], // 👈 Récupère la longitude
                "isOnline": true
              });
            }
          }
          _isSyncing = false;
        });
      }, onError: (error) {
        dev.log("Erreur Stream Supabase: $error");
        setState(() => _isSyncing = false);
      });
      
    } catch (e) { 
      dev.log("Erreur init Stream: $e");
      setState(() => _isSyncing = false);
    }
  }

  void _listenToCloudMessages(String roomId) {
    if (_chatSubscriptions.containsKey(roomId)) return;

    try {
      _chatSubscriptions[roomId] = Supabase.instance.client
          .from('messages')
          .stream(primaryKey: ['id'])
          .eq('room_id', roomId)
          .order('created_at', ascending: true)
          .listen((data) {
        if (!mounted) return;
        
        int previousMessageCount = _history[roomId]?.length ?? 0;
        
        setState(() {
          _history[roomId] = data.map<String>((m) {
            String prefix = m['sender_name'] == user['name'] ? "Moi: " : "Passager: ";
            return "$prefix${m['content']}";
          }).toList();
        });

        if (data.length > previousMessageCount && previousMessageCount > 0) {
          var lastMessage = data.last;
          bool isLookingAtThisChat = (_currentStep == 5 && _activeRoom?['id'] == roomId);
          
          if (lastMessage['sender_name'] != user['name'] && !isLookingAtThisChat) {
            String roomTitle = "Nouveau message";
            try { roomTitle = _rooms.firstWhere((r) => r['id'] == roomId)['title']; } catch(e) { dev.log("Titre introuvable"); }
            
            _showNotification(roomTitle, lastMessage['content']);
          }
        }
      }, onError: (err) => dev.log("Erreur stream msg: $err"));
    } catch (e) {
      dev.log("Erreur init stream msg: $e");
    }
  }

  Future<void> _deleteRoom(String roomId) async {
    setState(() {
      _rooms.removeWhere((r) => r['id'] == roomId);
    });

    try {
      await Supabase.instance.client.from('rooms').delete().eq('id', roomId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Annonce supprimée avec succès"), backgroundColor: Colors.green)
        );
      }
    } catch (e) {
      dev.log("Erreur suppression Cloud: $e");
    }
  }

  void _startNearby() async {
    if (_isServiceRunning) return;
    
    if (Platform.isIOS) {
      dev.log("iPhone détecté : Passage direct au Cloud Supabase");
      _listenToInternetRooms(); 
      setState(() => _currentStep = 4);
      return;
    }

    if (Platform.isAndroid) {
      await [Permission.location, Permission.bluetoothScan, Permission.bluetoothAdvertise, Permission.bluetoothConnect, Permission.nearbyWifiDevices].request();
    }
    
    setState(() => _isServiceRunning = true);
    
    try {
      await Nearby().stopAdvertising();
      await Nearby().stopDiscovery();
      _listenToInternetRooms(); 
      
      await Nearby().startAdvertising(
        user['name']!, Strategy.P2P_CLUSTER,
        onConnectionInitiated: (id, info) => Nearby().acceptConnection(id, onPayLoadRecieved: _onPayloadReceived),
        onConnectionResult: (id, status) => dev.log("BT : $status"),
        onDisconnected: (id) => setState(() => _connectedPeerId = null),
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
      
    } catch (e) { 
      setState(() {
        _isServiceRunning = false;
        _currentStep = 4;
      });
      dev.log("Erreur Nearby: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Bluetooth non disponible, mode Cloud activé."), backgroundColor: Colors.orange));
    }
  }

  Future<void> _goBackToProfile() async {
    _roomsSubscription?.cancel(); 
    for (var sub in _chatSubscriptions.values) {
      sub.cancel();
    }
    _chatSubscriptions.clear();
    _subscribedRooms.clear();
    
    try {
      await Nearby().stopAdvertising();
      await Nearby().stopDiscovery();
    } catch (e) {
      dev.log("Erreur arrêt Nearby: $e");
    }
    setState(() {
      _isServiceRunning = false;
      _currentStep = 2; 
    });
  }

  void _connectToPeer(Map<String, dynamic> room) async {
    _activeRoom = room;
    _listenToCloudMessages(room['id']);
    setState(() { _currentStep = 5; });
    
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
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      // 👇 La signature onPublish inclut maintenant lat et lng 👇
      builder: (ctx) => _CreateModal(activeFilter: _activeFilter, onPublish: (title, desc, type, transport, tripNumber, lat, lng) async { 
          Navigator.pop(ctx);
          final id = "room_${DateTime.now().millisecondsSinceEpoch}";
          
          try {
            await Supabase.instance.client.from('rooms').insert({
              "id": id, "author": user['name'], "title": title, "desc": desc, "type": type, "transport": transport, "trip_number": tripNumber,
              "lat": lat, "lng": lng // 👈 Sauvegarde dans Supabase
            });
            _toggleSubscription(id);
            _listenToInternetRooms();
          } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur Cloud: $e"), backgroundColor: Colors.red)); }
      })
    ).then((_) => setState(() => _isModalOpen = false));
  }

  @override
  Widget build(BuildContext context) {
    Widget currentWidget;
    switch (_currentStep) {
      case 1: currentWidget = _WelcomeStep(onNext: () => setState(() => _currentStep = 2)); break;
      case 2: currentWidget = _ProfileStep(user: user, onSave: _saveAndValidateProfile); break;
      case 3: currentWidget = _TripStep(onJoin: _startNearby); break;
      case 4: 
        List<Map<String, dynamic>> filtered = _rooms.where((r) {
          bool matchFilter = _activeFilter == 'TOUS' || r['transport'].toString().toUpperCase() == _activeFilter;
          bool matchSearch = _searchQuery.isEmpty || 
                             r['title'].toString().toLowerCase().contains(_searchQuery.toLowerCase()) || 
                             r['desc'].toString().toLowerCase().contains(_searchQuery.toLowerCase()) ||
                             r['author'].toString().toLowerCase().contains(_searchQuery.toLowerCase()) ||
                             (r['trip_number'] != null && r['trip_number'].toString().toLowerCase().contains(_searchQuery.toLowerCase()));
          return matchFilter && matchSearch;
        }).toList();
        
        currentWidget = _DashboardStep(
          user: user, rooms: filtered, isSync: _isSyncing, activeFilter: _activeFilter, appVersion: _appVersion, isOffline: _isOffline,
          onFilterChanged: (f) => setState(() => _activeFilter = f), 
          onSearchChanged: (s) => setState(() => _searchQuery = s),
          onAdd: _openModal, 
          onSelect: _connectToPeer, 
          onEditProfile: _goBackToProfile,
          onRefresh: () async => _listenToInternetRooms(), 
          onDelete: _deleteRoom,
          onLogout: _logout, 
        );
        break;
      case 5: 
        currentWidget = _ChatStep(
          room: _activeRoom!, 
          messages: _getMessagesFor(_activeRoom!['id']), 
          isSubscribed: _subscribedRooms.contains(_activeRoom!['id']), 
          isOffline: _isOffline,
          onToggleSubscribe: () => _toggleSubscription(_activeRoom!['id']), 
          onBack: () {
            setState(() {
              if (!_subscribedRooms.contains(_activeRoom!['id'])) {
                _chatSubscriptions[_activeRoom!['id']]?.cancel();
                _chatSubscriptions.remove(_activeRoom!['id']);
              }
              _currentStep = 4;
            });
          },
          onSend: (v) async {
            if (!_subscribedRooms.contains(_activeRoom!['id'])) {
              _toggleSubscription(_activeRoom!['id']);
            }
            
            setState(() => _getMessagesFor(_activeRoom!['id']).add("Moi: $v"));
            
            if (_connectedPeerId != null) Nearby().sendBytesPayload(_connectedPeerId!, Uint8List.fromList(v.codeUnits));
            try { 
              await Supabase.instance.client.from('messages').insert({'room_id': _activeRoom!['id'], 'sender_name': user['name'], 'content': v});
            } catch (e) { dev.log("Erreur Cloud Message: $e"); }
          },
        );
        break;
      default: currentWidget = const SizedBox();
    }

    return PopScope(
      canPop: _currentStep == 1, 
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return; 
        
        setState(() {
          if (_currentStep == 5) {
            if (!_subscribedRooms.contains(_activeRoom!['id'])) {
              _chatSubscriptions[_activeRoom!['id']]?.cancel();
              _chatSubscriptions.remove(_activeRoom!['id']);
            }
            _currentStep = 4; 
          }
          else if (_currentStep == 4) { _goBackToProfile(); } 
          else if (_currentStep == 3) { _currentStep = 2; } 
          else if (_currentStep == 2) { _currentStep = 1; } 
        });
      },
      child: currentWidget,
    );
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

class _ProfileStep extends StatefulWidget {
  final Map<String, String> user;
  final Future<bool> Function(String, String, String, String, String, String) onSave; 

  const _ProfileStep({required this.user, required this.onSave});

  @override
  State<_ProfileStep> createState() => _ProfileStepState();
}

class _ProfileStepState extends State<_ProfileStep> {
  late TextEditingController _nameCtrl;
  late TextEditingController _pwdCtrl; 
  late TextEditingController _fNameCtrl;
  late TextEditingController _lNameCtrl;
  late TextEditingController _addrCtrl;
  late String _currentTransport;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.user['name']);
    _pwdCtrl = TextEditingController(text: widget.user['password']);
    _fNameCtrl = TextEditingController(text: widget.user['firstName']);
    _lNameCtrl = TextEditingController(text: widget.user['lastName']);
    _addrCtrl = TextEditingController(text: widget.user['address']);
    _currentTransport = widget.user['transport'] ?? 'avion';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pwdCtrl.dispose();
    _fNameCtrl.dispose();
    _lNameCtrl.dispose();
    _addrCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitProfile() async {
    final pseudo = _nameCtrl.text.trim();
    final pwd = _pwdCtrl.text.trim();
    
    if (pseudo.isEmpty || pwd.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Le pseudo et le mot de passe sont obligatoires."), backgroundColor: Colors.orange));
      return;
    }
    
    setState(() => _isLoading = true);
    bool success = await widget.onSave(pseudo, pwd, _currentTransport, _fNameCtrl.text.trim(), _lNameCtrl.text.trim(), _addrCtrl.text.trim());
    if (mounted && !success) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF6366f1), Color(0xFF8b5cf6)], 
          begin: Alignment.topLeft, end: Alignment.bottomRight
        ),
      ),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 20), 
            child: Card(
              elevation: 15,
              shadowColor: Colors.black26,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(35)),
              child: Padding(
                padding: const EdgeInsets.all(35),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  
                  CircleAvatar(
                    radius: 45,
                    backgroundColor: const Color(0xFF6366f1).withValues(alpha: 0.1),
                    child: const Icon(Icons.person_pin, size: 50, color: Color(0xFF6366f1)),
                  ),
                  const SizedBox(height: 20),
                  const Text('Votre Profil', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
                  const SizedBox(height: 5),
                  Text('Connectez-vous pour rejoindre la communauté', style: TextStyle(fontSize: 13, color: Colors.grey.shade500), textAlign: TextAlign.center,),
                  const SizedBox(height: 35),
                  
                  TextField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.none, 
                    autocorrect: false, 
                    enableSuggestions: false, 
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.alternate_email, color: Colors.grey),
                      hintText: 'Pseudo', filled: true, fillColor: Colors.grey.shade100, 
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none)
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pwdCtrl,
                    obscureText: true, 
                    textCapitalization: TextCapitalization.none, 
                    autocorrect: false, 
                    enableSuggestions: false, 
                    keyboardType: TextInputType.visiblePassword, 
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.lock_outline, color: Colors.grey),
                      hintText: 'Mot de passe', filled: true, fillColor: Colors.grey.shade100, 
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none)
                    ),
                  ),
                  
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Divider(color: Colors.black12),
                  ),
                  
                  Row(
                    children: [
                      Expanded(child: TextField(controller: _fNameCtrl, decoration: InputDecoration(hintText: 'Prénom', filled: true, fillColor: Colors.grey.shade50, border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none)))),
                      const SizedBox(width: 12),
                      Expanded(child: TextField(controller: _lNameCtrl, decoration: InputDecoration(hintText: 'Nom', filled: true, fillColor: Colors.grey.shade50, border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none)))),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _addrCtrl,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.place_outlined, color: Colors.grey),
                      hintText: 'Ville / Adresse', filled: true, fillColor: Colors.grey.shade50, border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none)
                    ),
                  ),
                  const SizedBox(height: 25),
                  
                  const Align(alignment: Alignment.centerLeft, child: Text('Transport favori :', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: ['avion', 'train', 'autocar', 'bateau'].map((m) => ChoiceChip(
                    label: Text(m.toUpperCase(), style: const TextStyle(fontSize: 12)), 
                    selected: _currentTransport == m, 
                    showCheckmark: false,
                    selectedColor: const Color(0xFF6366f1),
                    labelStyle: TextStyle(color: _currentTransport == m ? Colors.white : Colors.black87, fontWeight: FontWeight.bold),
                    onSelected: (_) => setState(() => _currentTransport = m),
                  )).toList()),
                  const SizedBox(height: 40),
                  
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 60), backgroundColor: const Color(0xFF6366f1), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                    onPressed: _isLoading ? null : _submitProfile,
                    child: _isLoading 
                        ? const SizedBox(width: 25, height: 25, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                        : const Text('CONTINUER', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _TripStep extends StatelessWidget {
  final VoidCallback onJoin;
  const _TripStep({required this.onJoin});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.radar, size: 100, color: Color(0xFF6366f1)),
      const SizedBox(height: 40),
      const Text('Activation Bluetooth', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      const SizedBox(height: 50),
      ElevatedButton(
        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20), backgroundColor: const Color(0xFF6366f1), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
        onPressed: onJoin, child: const Text('REJOINDRE LE RÉSEAU', style: TextStyle(fontWeight: FontWeight.bold))
      ),
    ])),
  );
}

class _DashboardStep extends StatefulWidget {
  final Map<String, String> user;
  final List<Map<String, dynamic>> rooms;
  final bool isSync;
  final bool isOffline; 
  final String activeFilter;
  final Function(String) onFilterChanged;
  final Function(String) onSearchChanged;
  final VoidCallback onAdd;
  final Function(Map<String, dynamic>) onSelect;
  final String appVersion;
  final VoidCallback onEditProfile;
  final Future<void> Function() onRefresh; 
  final Function(String) onDelete;
  final VoidCallback onLogout; 

  const _DashboardStep({
    required this.user, required this.rooms, required this.isSync, required this.isOffline,
    required this.activeFilter, required this.onFilterChanged, 
    required this.onSearchChanged, required this.onAdd, 
    required this.appVersion, required this.onSelect, 
    required this.onEditProfile, required this.onRefresh, required this.onDelete,
    required this.onLogout,
  });

  @override
  State<_DashboardStep> createState() => _DashboardStepState();
}

class _DashboardStepState extends State<_DashboardStep> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(children: [
        Container(
          padding: const EdgeInsets.fromLTRB(25, 65, 25, 20), 
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF6366f1), Color(0xFF8b5cf6)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(35))
          ),
          child: Column(
            children: [
              Row(children: [
                GestureDetector(onTap: widget.onEditProfile, child: const CircleAvatar(radius: 28, backgroundColor: Colors.white24, child: Icon(Icons.edit, color: Colors.white))),
                const SizedBox(width: 15),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.appVersion, style: const TextStyle(color: Colors.white70, fontSize: 10)),
                  Text(widget.user['name']!, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                ])),
                if (widget.isSync) const SizedBox(width: 25, height: 25, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                const SizedBox(width: 10),
                
                IconButton(
                  icon: const Icon(Icons.logout, color: Colors.white),
                  onPressed: widget.onLogout,
                  tooltip: 'Se déconnecter',
                )
              ]),
              if (widget.isOffline)
                Container(
                  margin: const EdgeInsets.only(top: 20),
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                  decoration: BoxDecoration(color: Colors.orange.shade400, borderRadius: BorderRadius.circular(15)),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.wifi_off, color: Colors.white, size: 16),
                      SizedBox(width: 8),
                      Text("Mode Bluetooth (Réseau perdu)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    ]
                  )
                ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
          child: Row(children: ['TOUS', 'AVION', 'TRAIN', 'AUTOCAR', 'BATEAU'].map((f) => Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ChoiceChip(
              label: Text(f), selected: widget.activeFilter == f, 
              onSelected: (_) {
                widget.onFilterChanged(f);
                if (f == 'TOUS') {
                  _searchController.clear();
                  widget.onSearchChanged('');
                }
              },
              selectedColor: const Color(0xFF6366f1),
              labelStyle: TextStyle(color: widget.activeFilter == f ? Colors.white : const Color(0xFF6366f1), fontWeight: FontWeight.bold),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)), showCheckmark: false,
            ),
          )).toList()),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20).copyWith(bottom: 15),
          child: TextField(
            controller: _searchController, 
            onChanged: widget.onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Rechercher une destination, un mot...',
              prefixIcon: const Icon(Icons.search, color: Color(0xFF6366f1)),
              suffixIcon: _searchController.text.isNotEmpty 
                ? IconButton(
                    icon: const Icon(Icons.clear, color: Colors.grey),
                    onPressed: () {
                      _searchController.clear(); 
                      widget.onSearchChanged(''); 
                    },
                  ) 
                : null,
              filled: true,
              fillColor: Colors.grey.shade100,
              contentPadding: const EdgeInsets.all(15),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: widget.onRefresh,
            color: const Color(0xFF6366f1),
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 0),
              itemCount: widget.rooms.length, 
              itemBuilder: (ctx, i) {
                final r = widget.rooms[i];
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)]),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(20),
                    onTap: () => widget.onSelect(r),
                    leading: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFF6366f1).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(18)),
                      child: Icon(r['transport'] == 'avion' ? Icons.flight_takeoff : Icons.directions_bus, color: const Color(0xFF6366f1)),
                    ),
                    title: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(child: Text(r['title'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17), overflow: TextOverflow.ellipsis)),
                              // 👇 Icône Map dans la liste si position définie
                              if (r['lat'] != null && r['lng'] != null)
                                const Padding(
                                  padding: EdgeInsets.only(left: 6),
                                  child: Icon(Icons.location_on, size: 16, color: Colors.redAccent),
                                )
                            ],
                          )
                        ),
                        if (r['trip_number'] != null && r['trip_number'].toString().isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(10)),
                            child: Text(r['trip_number'], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
                          )
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 5),
                        Text(r['desc'] ?? '', style: TextStyle(color: Colors.grey.shade700, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 5),
                        Text('${r['author']} • ${r['type']}', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                      ],
                    ),
                    trailing: r['author'] == widget.user['name'] 
                      ? IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text("Supprimer l'annonce ?"),
                                content: const Text("Cette action est irréversible."),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ANNULER")),
                                  TextButton(
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      widget.onDelete(r['id']);
                                    }, 
                                    child: const Text("SUPPRIMER", style: TextStyle(color: Colors.red))
                                  ),
                                ],
                              )
                            );
                          },
                        )
                      : const Icon(Icons.chevron_right, color: Colors.grey),
                  ),
                );
              }
            ),
          )
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: widget.onAdd, backgroundColor: const Color(0xFF6366f1),
        label: const Text("CRÉER UN SALON", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        icon: const Icon(Icons.add, color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}

class _ChatStep extends StatelessWidget {
  final Map<String, dynamic> room;
  final List<String> messages; 
  final bool isSubscribed; 
  final bool isOffline;
  final VoidCallback onToggleSubscribe; 
  final Function(String) onSend;
  final VoidCallback onBack;

  const _ChatStep({
    required this.room, required this.messages, required this.isSubscribed, required this.isOffline,
    required this.onToggleSubscribe, required this.onSend, required this.onBack
  });

  @override
  Widget build(BuildContext context) {
    final textController = TextEditingController();
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, size: 20), onPressed: onBack), 
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(room['title'], style: const TextStyle(fontSize: 18)),
            if (isOffline)
              const Text("Mode Bluetooth", style: TextStyle(fontSize: 11, color: Colors.orange)),
          ],
        ),
        actions: [
          // ✅ BOUTON CARTE CORRIGÉ
          if (room['lat'] != null && room['lng'] != null)
            IconButton(
              icon: const Icon(Icons.map_outlined, color: Colors.blueAccent),
              tooltip: "Voir le point de rendez-vous",
              onPressed: () async {
                // Utilisation de l'URL de recherche Google Maps officielle
                final String googleMapsUrl = "https://www.google.com/maps/search/?api=1&query=${room['lat']},${room['lng']}";
                final Uri uri = Uri.parse(googleMapsUrl);

                try {
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } else {
                    // Si canLaunchUrl bloque, on tente quand même le lancement forcé
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Erreur lors de l'ouverture de la carte : $e"))
                    );
                  }
                }
              },
            ),
          IconButton(
            icon: Icon(isSubscribed ? Icons.notifications_active : Icons.notifications_off_outlined),
            color: isSubscribed ? Colors.green : Colors.grey,
            onPressed: onToggleSubscribe,
            tooltip: isSubscribed ? "Désactiver les notifications" : "Activer les notifications",
          )
        ],
      ),
      body: Column(children: [
        Expanded(
          child: ListView.builder(
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
                  child: Text(
                    messages[i].replaceFirst(isMe ? "Moi: " : "Passager: ", ""), 
                    style: TextStyle(color: isMe ? Colors.white : Colors.black87)
                  ),
                ),
              );
            }
          ),
        ),
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
  // 👇 NOUVELLE SIGNATURE avec lat et lng
  final Function(String, String, String, String, String, double?, double?) onPublish; 
  const _CreateModal({required this.activeFilter, required this.onPublish});
  @override
  State<_CreateModal> createState() => _CreateModalState();
}

class _CreateModalState extends State<_CreateModal> {
  late String _selectedTransport;
  String _selectedType = 'OFFRE';
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _tripNumberController = TextEditingController();
  
  // 👇 NOUVEAU: Variables pour la carte
  double _selectedLat = 48.1173; // Centré sur Rennes par défaut !
  double _selectedLng = -1.6778; 

  @override
  void initState() {
    super.initState();
    _selectedTransport = widget.activeFilter == 'TOUS' ? 'avion' : widget.activeFilter.toLowerCase();
  }

  String getHintForTransport() {
    switch (_selectedTransport) {
      case 'avion': return 'N° de Vol (Ex: AF123)';
      case 'train': return 'N° de Train (Ex: TGV 8765)';
      case 'autocar': return 'N° ou Compagnie (Ex: FlixBus)';
      case 'bateau': return 'Nom du Navire ou Ligne';
      default: return 'N° de transport';
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 30, left: 30, right: 30, top: 30),
    decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(35))),
    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Créer un Salon', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      const SizedBox(height: 25),
      
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: ['avion', 'train', 'autocar', 'bateau'].map((m) => Padding(
          padding: const EdgeInsets.only(right: 10),
          child: ChoiceChip(
            label: Text(m.toUpperCase(), style: const TextStyle(fontSize: 12)), 
            selected: _selectedTransport == m, 
            onSelected: (_) => setState(() => _selectedTransport = m)
          ),
        )).toList()),
      ),
      const SizedBox(height: 15),

      TextField(controller: _tripNumberController, decoration: InputDecoration(hintText: getHintForTransport(), filled: true, fillColor: Colors.blue.shade50, prefixIcon: const Icon(Icons.confirmation_number_outlined), border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none))),
      const SizedBox(height: 15),

      TextField(controller: _titleController, decoration: InputDecoration(hintText: 'Titre de l\'annonce', filled: true, fillColor: Colors.grey.shade50, border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none))),
      const SizedBox(height: 15),
      
      TextField(
        controller: _descController, 
        maxLines: 2, 
        decoration: InputDecoration(
          hintText: 'Description (Ex: Je cherche quelqu\'un pour partager les frais...)', 
          filled: true, 
          fillColor: Colors.grey.shade50, 
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none)
        )
      ),
      const SizedBox(height: 15),

      // 👇 INTÉGRATION DE LA CARTE 👇
      const Text('Point de rendez-vous (Optionnel) :', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 13)),
      const SizedBox(height: 10),
      SizedBox(
        height: 150,
        width: double.infinity,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              FlutterMap(
                options: MapOptions(
                  initialCenter: LatLng(_selectedLat, _selectedLng),
                  initialZoom: 13.0,
                  onPositionChanged: (camera, hasGesture) {
                    _selectedLat = camera.center.latitude;
                    _selectedLng = camera.center.longitude;
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.copassager.app',
                  ),
                ],
              ),
              // Épingle fixe au centre
              const Center(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 40), // Décale légèrement l'icône vers le haut pour pointer le centre
                  child: Icon(Icons.location_on, size: 40, color: Colors.red),
                ),
              ),
              // Petit bandeau d'instruction
              Positioned(
                top: 8, left: 8, right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(10)),
                  child: const Text("Glissez pour placer l'épingle", textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              )
            ],
          ),
        ),
      ),
      const SizedBox(height: 20),

      Row(children: [
        Expanded(child: ChoiceChip(label: const Center(child: Text('OFFRE')), selected: _selectedType == 'OFFRE', onSelected: (_) => setState(() => _selectedType = 'OFFRE'))),
        const SizedBox(width: 15),
        Expanded(child: ChoiceChip(label: const Center(child: Text('DEMANDE')), selected: _selectedType == 'DEMANDE', onSelected: (_) => setState(() => _selectedType = 'DEMANDE'))),
      ]),
      const SizedBox(height: 35),
      
      ElevatedButton(
        style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 65), backgroundColor: const Color(0xFF6366f1), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
        onPressed: () {
          if (_titleController.text.isNotEmpty) {
            // Envoi des coordonnées avec le reste des infos
            widget.onPublish(_titleController.text, _descController.text, _selectedType, _selectedTransport, _tripNumberController.text.trim(), _selectedLat, _selectedLng);
          }
        }, 
        child: const Text('CRÉER LE SALON', style: TextStyle(fontWeight: FontWeight.bold))
      ),
    ]),
  );
}