
//
//  Also add google-services.json to android/app/
//  Also add GoogleService-Info.plist to ios/Runner/ (for iOS)
// ============================================================
import 'dart:typed_data';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';


// ─── Firebase config (same as your web app) ───────────────────────────────────
const _firebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyAF8PGXm3fAhDm5efNuVSeerVSI7biMHYw',
  appId: '1:356288433221:web:c2c46b46d4dbe13977a72c',
  messagingSenderId: '356288433221',
  projectId: 'bridgehealth-1ebfe',
  storageBucket: 'bridgehealth-1ebfe.firebasestorage.app',
);

// ─── Notification plugin (global) ─────────────────────────────────────────────
final FlutterLocalNotificationsPlugin _notifPlugin =
FlutterLocalNotificationsPlugin();

// ─── Entry point ──────────────────────────────────────────────────────────────
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: _firebaseOptions);
  await _initNotifications();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  runApp(const BridgeGuardApp());
}

Future<void> _initNotifications() async {
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  const ios = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );
  await _notifPlugin.initialize(
    const InitializationSettings(android: android, iOS: ios),
  );
}

Future<void> _showAlarmNotification({
  required String bridgeName,
  required String bridgeId,
  required String status,
  required double distanceM,
}) async {
  final androidDetails = AndroidNotificationDetails(
    'bridge_critical_channel',
    'Bridge Critical Alerts',
    channelDescription: 'Alerts when you enter a critical bridge geofence',
    importance: Importance.max,
    priority: Priority.high,
    playSound: true,
    enableVibration: true,
    vibrationPattern: Int64List.fromList([0, 500, 200, 500, 200, 500]), // ✅ Fixed
    color: const Color(0xFFDC2626),
    ledColor: const Color(0xFFDC2626),
    ledOnMs: 300,
    ledOffMs: 200,
    icon: '@mipmap/ic_launcher',
    largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
    styleInformation: const BigTextStyleInformation(''),
  );

  const iosDetails = DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
    interruptionLevel: InterruptionLevel.critical,
  );

  await _notifPlugin.show(
    bridgeId.hashCode,
    '⚠️ DANGER — $bridgeName',
    'This bridge is $status. You are ${distanceM.toStringAsFixed(0)}m away. Avoid this route!',
    NotificationDetails(android: androidDetails, iOS: iosDetails),
  );

}

// ─── Haversine distance (metres) ──────────────────────────────────────────────
double _haversineMetres(
    double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  final dLat = _deg2rad(lat2 - lat1);
  final dLng = _deg2rad(lng2 - lng1);
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(_deg2rad(lat1)) * cos(_deg2rad(lat2)) *
          sin(dLng / 2) * sin(dLng / 2);
  return r * 2 * atan2(sqrt(a), sqrt(1 - a));
}

double _deg2rad(double deg) => deg * pi / 180;

// ─── Data model ───────────────────────────────────────────────────────────────
class GeoFence {
  final String docId;
  final String bridgeId;
  final String bridgeName;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final String status;

  GeoFence({
    required this.docId,
    required this.bridgeId,
    required this.bridgeName,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    required this.status,
  });

  factory GeoFence.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return GeoFence(
      docId: doc.id,
      bridgeId: (d['bridgeId'] ?? doc.id).toString(),
      bridgeName: (d['bridgeName'] ?? doc.id).toString(),
      latitude: _parseDouble(d['latitude']),
      longitude: _parseDouble(d['longitude']),
      radiusMeters: _parseDouble(d['radiusMeters'] ?? 1000),
      status: (d['status'] ?? 'CRITICAL').toString(),
    );
  }

  static double _parseDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }
}

class BridgeInfo {
  final String id;
  final String name;
  final String district;
  final String type;
  final int healthScore;
  final String status;
  final double latitude;
  final double longitude;

  BridgeInfo({
    required this.id,
    required this.name,
    required this.district,
    required this.type,
    required this.healthScore,
    required this.status,
    required this.latitude,
    required this.longitude,
  });

  factory BridgeInfo.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return BridgeInfo(
      id: doc.id,
      name: (d['name'] ?? doc.id).toString(),
      district: (d['district'] ?? '').toString(),
      type: (d['type'] ?? '').toString(),
      healthScore: (d['healthScore'] as num?)?.toInt() ?? 0,
      status: (d['status'] ?? 'SAFE').toString(),
      latitude: GeoFence._parseDouble(d['latitude']),
      longitude: GeoFence._parseDouble(d['longitude']),
    );
  }

  Color get statusColor {
    switch (status) {
      case 'CRITICAL':
        return const Color(0xFFDC2626);
      case 'WARNING':
        return const Color(0xFFD97706);
      default:
        return const Color(0xFF16A34A);
    }
  }

  Color get statusBg {
    switch (status) {
      case 'CRITICAL':
        return const Color(0xFFFEE2E2);
      case 'WARNING':
        return const Color(0xFFFEF3C7);
      default:
        return const Color(0xFFDCFCE7);
    }
  }
}

// ─── App ──────────────────────────────────────────────────────────────────────
class BridgeGuardApp extends StatelessWidget {
  const BridgeGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BridgeGuard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.light,
        ),
        fontFamily: 'sans-serif',
      ),
      home: const HomeScreen(),
    );
  }
}

// ─── Home Screen ──────────────────────────────────────────────────────────────
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int _tab = 0;

  // Location state
  Position? _currentPosition;
  bool _locationEnabled = false;
  StreamSubscription<Position>? _locationSub;
  Timer? _geoCheckTimer;

  // Firestore data
  List<GeoFence> _geofences = [];
  List<BridgeInfo> _bridges = [];
  List<Map<String, dynamic>> _alerts = [];
  StreamSubscription<QuerySnapshot>? _geoSub;
  StreamSubscription<QuerySnapshot>? _bridgeSub;
  StreamSubscription<QuerySnapshot>? _alertSub;

  // Alarm state
  final Set<String> _alarmedIds = {}; // avoid repeat alarms
  GeoFence? _activeAlarm; // currently inside this geofence
  BridgeInfo? _activeBridge;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _requestPermissionsAndStart();
    _listenFirestore();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _locationSub?.cancel();
    _geoCheckTimer?.cancel();
    _geoSub?.cancel();
    _bridgeSub?.cancel();
    _alertSub?.cancel();
    super.dispose();
  }

  // ── Permissions & location ────────────────────────────────────────────────
  Future<void> _requestPermissionsAndStart() async {
    await Permission.location.request();
    await Permission.locationWhenInUse.request();
    await Permission.notification.request();

    final svc = await Geolocator.isLocationServiceEnabled();
    if (!svc) {
      _showSnack('Please enable Location Services', isError: true);
      return;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) {
      _showSnack('Location permission denied. Enable in settings.', isError: true);
      return;
    }

    setState(() => _locationEnabled = true);
    _startLocationStream();
  }

  void _startLocationStream() {
    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // update every 10m moved
    );
    _locationSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen((pos) {
      setState(() => _currentPosition = pos);
      _checkGeofences(pos);
    });
  }

  // ── Firestore listeners ────────────────────────────────────────────────────
  void _listenFirestore() {
    final db = FirebaseFirestore.instance;

    _geoSub = db.collection('geofences').snapshots().listen((snap) {
      setState(() {
        _geofences = snap.docs
            .map((d) => GeoFence.fromDoc(d))
            .where((g) => g.latitude != 0 && g.longitude != 0)
            .toList();
      });
      if (_currentPosition != null) _checkGeofences(_currentPosition!);
    });

    _bridgeSub = db.collection('bridges').snapshots().listen((snap) {
      setState(() {
        _bridges = snap.docs.map((d) => BridgeInfo.fromDoc(d)).toList();
        _bridges.sort((a, b) => a.healthScore.compareTo(b.healthScore));
      });
    });

    _alertSub = db
        .collection('alerts')
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .listen((snap) {
      setState(() {
        _alerts = snap.docs.map((d) {
          final data = d.data() as Map<String, dynamic>;
          return {'id': d.id, ...data};
        }).toList();
      });
    });
  }

  // ── Geofence check ────────────────────────────────────────────────────────
  void _checkGeofences(Position pos) {
    GeoFence? insideGeo;
    BridgeInfo? insideBridge;

    for (final geo in _geofences) {
      final dist = _haversineMetres(
          pos.latitude, pos.longitude, geo.latitude, geo.longitude);
      if (dist <= geo.radiusMeters) {
        insideGeo = geo;
        // Find matching bridge
        try {
          insideBridge = _bridges.firstWhere(
                (b) => b.id == geo.bridgeId || b.id == geo.docId,
          );
        } catch (_) {}

        // Trigger alarm if not already alarmed for this geo
        if (!_alarmedIds.contains(geo.docId)) {
          _alarmedIds.add(geo.docId);
          _triggerAlarm(geo, insideBridge, dist);
        }
        break;
      }
    }

    // Reset alarmed state when leaving geofence
    if (insideGeo == null) {
      // Re-enable alarm for geofences we've left
      for (final geo in _geofences) {
        final dist = _haversineMetres(
            pos.latitude, pos.longitude, geo.latitude, geo.longitude);
        if (dist > geo.radiusMeters * 1.2) {
          _alarmedIds.remove(geo.docId);
        }
      }
    }

    setState(() {
      _activeAlarm = insideGeo;
      _activeBridge = insideBridge;
    });
  }

  void _triggerAlarm(GeoFence geo, BridgeInfo? bridge, double distM) {
    _showAlarmNotification(
      bridgeName: geo.bridgeName,
      bridgeId: geo.bridgeId,
      status: bridge?.status ?? geo.status,
      distanceM: distM,
    );
    // Also show in-app dialog
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => _AlarmDialog(
          geo: geo,
          bridge: bridge,
          distanceM: distM,
          onDismiss: () => Navigator.pop(context),
        ),
      );
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F4F0),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            if (_activeAlarm != null) _buildAlarmBanner(),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: [
                  _buildDashboardTab(),
                  _buildBridgesTab(),
                  _buildAlertsTab(),
                  _buildGeofencesTab(),
                ],
              ),
            ),
            _buildBottomNav(),
          ],
        ),
      ),
    );
  }

  // ── Top bar ───────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Container(
      height: 56,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2DDD6))),
        boxShadow: [BoxShadow(color: Color(0x0A000000), blurRadius: 4)],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1D4ED8), Color(0xFF2563EB)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [BoxShadow(color: Color(0x402563EB), blurRadius: 8)],
            ),
            child: const Center(child: Text('🌉', style: TextStyle(fontSize: 16))),
          ),
          const SizedBox(width: 10),
          RichText(
            text: const TextSpan(
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF1A1714), letterSpacing: -0.5),
              children: [
                TextSpan(text: 'Bridge'),
                TextSpan(text: 'Guard', style: TextStyle(color: Color(0xFF2563EB))),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFDCFCE7),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFBBF7D0)),
            ),
            child: Row(
              children: [
                _PulseDot(color: const Color(0xFF16A34A)),
                const SizedBox(width: 5),
                const Text('LIVE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFF16A34A), letterSpacing: 0.5)),
              ],
            ),
          ),
          const Spacer(),
          // Location indicator
          GestureDetector(
            onTap: _requestPermissionsAndStart,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _locationEnabled ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _locationEnabled ? const Color(0xFFBBF7D0) : const Color(0xFFFECACA),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _locationEnabled ? Icons.location_on : Icons.location_off,
                    size: 13,
                    color: _locationEnabled ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    _locationEnabled ? 'ON' : 'OFF',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: _locationEnabled ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Alarm banner (shown when inside geofence) ──────────────────────────────
  Widget _buildAlarmBanner() {
    final geo = _activeAlarm!;
    final bridge = _activeBridge;
    final dist = _currentPosition != null
        ? _haversineMetres(_currentPosition!.latitude,
        _currentPosition!.longitude, geo.latitude, geo.longitude)
        .toStringAsFixed(0)
        : '–';

    return ScaleTransition(
      scale: _pulseAnim,
      child: GestureDetector(
        onTap: () => showDialog(
          context: context,
          builder: (_) => _AlarmDialog(
            geo: geo,
            bridge: bridge,
            distanceM: _currentPosition != null
                ? _haversineMetres(_currentPosition!.latitude,
                _currentPosition!.longitude, geo.latitude, geo.longitude)
                : 0,
            onDismiss: () => Navigator.pop(context),
          ),
        ),
        child: Container(
          margin: const EdgeInsets.all(10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFFEE2E2),
            border: Border.all(color: const Color(0xFFFCA5A5), width: 1.5),
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [BoxShadow(color: Color(0x20DC2626), blurRadius: 12, offset: Offset(0, 4))],
          ),
          child: Row(
            children: [
              const Text('🚨', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DANGER ZONE — ${geo.bridgeName}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFFDC2626)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'You are ${dist}m from a ${bridge?.status ?? geo.status} bridge. Avoid this route!',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF7F1D1D)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFFDC2626)),
            ],
          ),
        ),
      ),
    );
  }

  // ── Dashboard tab ─────────────────────────────────────────────────────────
  Widget _buildDashboardTab() {
    final total = _bridges.length;
    final safe = _bridges.where((b) => b.status == 'SAFE').length;
    final warn = _bridges.where((b) => b.status == 'WARNING').length;
    final crit = _bridges.where((b) => b.status == 'CRITICAL').length;
    final activeAlerts = _alerts.where((a) => a['resolved'] != true).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Location card
          _buildLocationCard(),
          const SizedBox(height: 14),

          // Stats grid
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.7,
            children: [
              _StatCard(label: 'Total Bridges', value: '$total', icon: '🌉', color: const Color(0xFF2563EB), bg: const Color(0xFFDBEAFE)),
              _StatCard(label: 'Safe', value: '$safe', icon: '✓', color: const Color(0xFF16A34A), bg: const Color(0xFFDCFCE7)),
              _StatCard(label: 'Warning', value: '$warn', icon: '⚡', color: const Color(0xFFD97706), bg: const Color(0xFFFEF3C7)),
              _StatCard(label: 'Critical', value: '$crit', icon: '⚠', color: const Color(0xFFDC2626), bg: const Color(0xFFFEE2E2)),
              _StatCard(label: 'Active Alerts', value: '$activeAlerts', icon: '🔔', color: const Color(0xFFEA580C), bg: const Color(0xFFFFEDD5)),
              _StatCard(label: 'Geofences', value: '${_geofences.length}', icon: '◈', color: const Color(0xFF0D9488), bg: const Color(0xFFCCFBF1)),
            ],
          ),
          const SizedBox(height: 16),

          // Critical bridges
          if (crit > 0) ...[
            const _SectionHeader(label: 'Critical Bridges'),
            const SizedBox(height: 8),
            ..._bridges
                .where((b) => b.status == 'CRITICAL')
                .map((b) => _BridgeListCard(bridge: b, currentPos: _currentPosition)),
            const SizedBox(height: 16),
          ],

          // Nearby geofences
          if (_geofences.isNotEmpty && _currentPosition != null) ...[
            const _SectionHeader(label: 'Nearby Geofences'),
            const SizedBox(height: 8),
            ..._buildNearbyGeoCards(),
          ],
        ],
      ),
    );
  }

  Widget _buildLocationCard() {
    final pos = _currentPosition;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2DDD6)),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x06000000), blurRadius: 4)],
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: _locationEnabled ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _locationEnabled ? Icons.my_location : Icons.location_off,
              color: _locationEnabled ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _locationEnabled ? 'Location Active' : 'Location Disabled',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: _locationEnabled ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  pos != null
                      ? '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}'
                      : _locationEnabled ? 'Acquiring position…' : 'Tap to enable',
                  style: const TextStyle(fontSize: 10, color: Color(0xFFB0A89E), fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
          if (!_locationEnabled)
            TextButton(
              onPressed: _requestPermissionsAndStart,
              child: const Text('Enable', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildNearbyGeoCards() {
    if (_currentPosition == null) return [];
    final withDist = _geofences.map((g) {
      final d = _haversineMetres(_currentPosition!.latitude,
          _currentPosition!.longitude, g.latitude, g.longitude);
      return (geo: g, dist: d);
    }).toList();
    withDist.sort((a, b) => a.dist.compareTo(b.dist));
    return withDist.take(3).map((item) {
      final bridge = _bridges.cast<BridgeInfo?>().firstWhere(
            (b) => b?.id == item.geo.bridgeId || b?.id == item.geo.docId,
        orElse: () => null,
      );
      return _GeoProximityCard(
        geo: item.geo,
        bridge: bridge,
        distanceM: item.dist,
        isInside: item.dist <= item.geo.radiusMeters,
      );
    }).toList();
  }

  // ── Bridges tab ───────────────────────────────────────────────────────────
  Widget _buildBridgesTab() {
    if (_bridges.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('🌉', style: TextStyle(fontSize: 48)),
            SizedBox(height: 12),
            Text('Loading bridges…', style: TextStyle(color: Color(0xFFB0A89E), fontSize: 13)),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: _bridges.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _BridgeListCard(
        bridge: _bridges[i],
        currentPos: _currentPosition,
      ),
    );
  }

  // ── Alerts tab ─────────────────────────────────────────────────────────────
  Widget _buildAlertsTab() {
    if (_alerts.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('🔔', style: TextStyle(fontSize: 48)),
            SizedBox(height: 12),
            Text('No alerts yet', style: TextStyle(color: Color(0xFFB0A89E), fontSize: 13)),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: _alerts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _AlertCard(alert: _alerts[i], bridges: _bridges),
    );
  }

  // ── Geofences tab ──────────────────────────────────────────────────────────
  Widget _buildGeofencesTab() {
    if (_geofences.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('◈', style: TextStyle(fontSize: 48, color: Color(0xFF0D9488))),
            SizedBox(height: 12),
            Text('No geofences active', style: TextStyle(color: Color(0xFFB0A89E), fontSize: 13)),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: _geofences.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final geo = _geofences[i];
        final bridge = _bridges.cast<BridgeInfo?>().firstWhere(
              (b) => b?.id == geo.bridgeId || b?.id == geo.docId,
          orElse: () => null,
        );
        final dist = _currentPosition != null
            ? _haversineMetres(_currentPosition!.latitude,
            _currentPosition!.longitude, geo.latitude, geo.longitude)
            : null;
        final isInside = dist != null && dist <= geo.radiusMeters;
        return _GeoProximityCard(
          geo: geo,
          bridge: bridge,
          distanceM: dist ?? -1,
          isInside: isInside,
          showFull: true,
        );
      },
    );
  }

  // ── Bottom nav ─────────────────────────────────────────────────────────────
  Widget _buildBottomNav() {
    final critAlert = _alerts.where((a) => a['resolved'] != true).length;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE2DDD6))),
        boxShadow: [BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, -2))],
      ),
      child: Row(
        children: [
          _NavItem(icon: Icons.dashboard, label: 'Dashboard', index: 0, current: _tab, onTap: (i) => setState(() => _tab = i)),
          _NavItem(icon: Icons.account_balance, label: 'Bridges', index: 1, current: _tab, onTap: (i) => setState(() => _tab = i)),
          _NavItem(icon: Icons.notifications, label: 'Alerts', index: 2, current: _tab, badge: critAlert > 0 ? '$critAlert' : null, onTap: (i) => setState(() => _tab = i)),
          _NavItem(icon: Icons.radar, label: 'Geofences', index: 3, current: _tab, onTap: (i) => setState(() => _tab = i)),
        ],
      ),
    );
  }
}

// ─── Alarm Dialog ─────────────────────────────────────────────────────────────
class _AlarmDialog extends StatelessWidget {
  final GeoFence geo;
  final BridgeInfo? bridge;
  final double distanceM;
  final VoidCallback onDismiss;

  const _AlarmDialog({
    required this.geo,
    required this.bridge,
    required this.distanceM,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final status = bridge?.status ?? geo.status;
    final score = bridge?.healthScore ?? 0;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Color(0x30000000), blurRadius: 32, offset: Offset(0, 8))],
          border: Border.all(color: const Color(0xFFFCA5A5), width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Red header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFFFEE2E2),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                ),
              ),
              child: Column(
                children: [
                  const Text('🚨', style: TextStyle(fontSize: 48)),
                  const SizedBox(height: 8),
                  const Text(
                    'DANGER — AVOID THIS ROUTE',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFFDC2626), letterSpacing: 0.5),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Next bridge is $status',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7F1D1D), fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),

            // Details
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _InfoRow(label: 'Bridge', value: geo.bridgeName),
                  _InfoRow(label: 'Bridge ID', value: geo.bridgeId),
                  _InfoRow(label: 'Status', value: status,
                      valueColor: status == 'CRITICAL' ? const Color(0xFFDC2626) : const Color(0xFFD97706)),
                  if (score > 0) _InfoRow(label: 'Health Score', value: '$score%',
                      valueColor: score < 50 ? const Color(0xFFDC2626) : const Color(0xFFD97706)),
                  _InfoRow(label: 'Distance', value: '${distanceM.toStringAsFixed(0)}m away'),
                  _InfoRow(label: 'Radius', value: '${geo.radiusMeters.toStringAsFixed(0)}m geofence'),
                  if (bridge?.district.isNotEmpty == true)
                    _InfoRow(label: 'District', value: bridge!.district),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      border: Border.all(color: const Color(0xFFFED7AA)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      children: [
                        Text('⚠️', style: TextStyle(fontSize: 16)),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'This bridge has been flagged as structurally unsafe. Please use an alternate route immediately.',
                            style: TextStyle(fontSize: 11, color: Color(0xFF92400E), fontWeight: FontWeight.w600, height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Actions
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onDismiss,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFE2DDD6)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Dismiss', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: onDismiss,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                      ),
                      child: const Text('✓ I will avoid this', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _InfoRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFFB0A89E), fontWeight: FontWeight.w500)),
          const Spacer(),
          Text(value,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                fontFamily: 'monospace',
                color: valueColor ?? const Color(0xFF3D3830),
              )),
        ],
      ),
    );
  }
}

// ─── Reusable widgets ─────────────────────────────────────────────────────────

class _PulseDot extends StatefulWidget {
  final Color color;
  const _PulseDot({required this.color});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
    _anim = Tween(begin: 0.5, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: 7, height: 7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withOpacity(_anim.value),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label, value, icon;
  final Color color, bg;
  const _StatCard({required this.label, required this.value, required this.icon, required this.color, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2DDD6)),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x06000000), blurRadius: 4)],
      ),
      child: Row(
        children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(9)),
            child: Center(child: Text(icon, style: const TextStyle(fontSize: 15))),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color, height: 1.1, letterSpacing: -1, fontFamily: 'monospace')),
              Text(label, style: const TextStyle(fontSize: 9, color: Color(0xFFB0A89E), fontWeight: FontWeight.w700, letterSpacing: 0.3)),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFFB0A89E), letterSpacing: 1, wordSpacing: 1)),
        const SizedBox(width: 8),
        Expanded(child: Container(height: 1, color: const Color(0xFFE2DDD6))),
      ],
    );
  }
}

class _BridgeListCard extends StatelessWidget {
  final BridgeInfo bridge;
  final Position? currentPos;
  const _BridgeListCard({required this.bridge, required this.currentPos});

  @override
  Widget build(BuildContext context) {
    String? distStr;
    if (currentPos != null && bridge.latitude != 0) {
      final d = _haversineMetres(currentPos!.latitude, currentPos!.longitude,
          bridge.latitude, bridge.longitude);
      distStr = d < 1000 ? '${d.toStringAsFixed(0)}m' : '${(d / 1000).toStringAsFixed(1)}km';
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
          color: bridge.status == 'CRITICAL' ? const Color(0xFFFECACA) : const Color(0xFFE2DDD6),
          width: bridge.status == 'CRITICAL' ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x06000000), blurRadius: 4)],
      ),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(bridge.name,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF1A1714)),
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                _StatusBadge(status: bridge.status),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text('${bridge.district} · ${bridge.type}',
                    style: const TextStyle(fontSize: 10, color: Color(0xFFB0A89E))),
                const Spacer(),
                if (distStr != null)
                  Text(distStr, style: const TextStyle(fontSize: 10, color: Color(0xFFB0A89E), fontFamily: 'monospace')),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: bridge.healthScore / 100,
                      backgroundColor: const Color(0xFFF0EDE8),
                      valueColor: AlwaysStoppedAnimation(bridge.statusColor),
                      minHeight: 4,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('${bridge.healthScore}%',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: bridge.statusColor, fontFamily: 'monospace')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GeoProximityCard extends StatelessWidget {
  final GeoFence geo;
  final BridgeInfo? bridge;
  final double distanceM;
  final bool isInside;
  final bool showFull;

  const _GeoProximityCard({
    required this.geo,
    required this.bridge,
    required this.distanceM,
    required this.isInside,
    this.showFull = false,
  });

  @override
  Widget build(BuildContext context) {
    final distStr = distanceM < 0
        ? '–'
        : distanceM < 1000
        ? '${distanceM.toStringAsFixed(0)}m'
        : '${(distanceM / 1000).toStringAsFixed(1)}km';

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: isInside ? const Color(0xFFFEE2E2) : Colors.white,
        border: Border.all(
          color: isInside ? const Color(0xFFFCA5A5) : const Color(0xFFE2DDD6),
          width: isInside ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x06000000), blurRadius: 4)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: isInside ? const Color(0xFFFEE2E2) : const Color(0xFFCCFBF1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.radar, size: 16,
                    color: isInside ? const Color(0xFFDC2626) : const Color(0xFF0D9488)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(geo.bridgeName,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF1A1714)),
                        overflow: TextOverflow.ellipsis),
                    Text('ID: ${geo.bridgeId}',
                        style: const TextStyle(fontSize: 9, color: Color(0xFFB0A89E), fontFamily: 'monospace')),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (isInside)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('INSIDE', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                    ),
                  if (!isInside && distanceM >= 0)
                    Text(distStr,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF0D9488), fontFamily: 'monospace')),
                ],
              ),
            ],
          ),
          if (showFull) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                _GeoChip(label: '${geo.radiusMeters.toStringAsFixed(0)}m radius', icon: Icons.circle_outlined),
                const SizedBox(width: 6),
                if (bridge != null) _StatusBadge(status: bridge!.status),
                const SizedBox(width: 6),
                if (distanceM >= 0) _GeoChip(label: distStr, icon: Icons.near_me),
              ],
            ),
            if (bridge != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: bridge!.healthScore / 100,
                        backgroundColor: const Color(0xFFF0EDE8),
                        valueColor: AlwaysStoppedAnimation(bridge!.statusColor),
                        minHeight: 4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${bridge!.healthScore}%',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: bridge!.statusColor, fontFamily: 'monospace')),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _GeoChip extends StatelessWidget {
  final String label;
  final IconData icon;
  const _GeoChip({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF0EDE8),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE2DDD6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 9, color: const Color(0xFFB0A89E)),
          const SizedBox(width: 3),
          Text(label, style: const TextStyle(fontSize: 9, color: Color(0xFF7A7268), fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color fg, bg, border;
    switch (status) {
      case 'CRITICAL':
        fg = const Color(0xFFDC2626); bg = const Color(0xFFFEE2E2); border = const Color(0xFFFECACA);
      case 'WARNING':
        fg = const Color(0xFFD97706); bg = const Color(0xFFFEF3C7); border = const Color(0xFFFDE68A);
      default:
        fg = const Color(0xFF16A34A); bg = const Color(0xFFDCFCE7); border = const Color(0xFFBBF7D0);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(status,
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: fg, letterSpacing: 0.4, fontFamily: 'monospace')),
    );
  }
}

class _AlertCard extends StatelessWidget {
  final Map<String, dynamic> alert;
  final List<BridgeInfo> bridges;
  const _AlertCard({required this.alert, required this.bridges});

  @override
  Widget build(BuildContext context) {
    final sev = (alert['severity'] ?? 'LOW').toString();
    final resolved = alert['resolved'] == true;
    final bridgeId = (alert['bridgeId'] ?? '').toString();
    final bridge = bridges.cast<BridgeInfo?>().firstWhere(
          (b) => b?.id == bridgeId,
      orElse: () => null,
    );

    Color sevColor, sevBg;
    String sevIcon;
    switch (sev) {
      case 'HIGH' || 'CRITICAL':
        sevColor = const Color(0xFFDC2626); sevBg = const Color(0xFFFEE2E2); sevIcon = '🔴';
      case 'MEDIUM':
        sevColor = const Color(0xFFD97706); sevBg = const Color(0xFFFEF3C7); sevIcon = '🟡';
      default:
        sevColor = const Color(0xFF16A34A); sevBg = const Color(0xFFDCFCE7); sevIcon = '🟢';
    }

    return Opacity(
      opacity: resolved ? 0.5 : 1.0,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            left: BorderSide(color: sevColor, width: 3),
            top: const BorderSide(color: Color(0xFFE2DDD6)),
            right: const BorderSide(color: Color(0xFFE2DDD6)),
            bottom: const BorderSide(color: Color(0xFFE2DDD6)),
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Color(0x06000000), blurRadius: 4)],
        ),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34, height: 34,
                decoration: BoxDecoration(color: sevBg, borderRadius: BorderRadius.circular(9)),
                child: Center(child: Text(sevIcon, style: const TextStyle(fontSize: 16))),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            (alert['type'] ?? 'ALERT').toString(),
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, fontFamily: 'monospace', color: Color(0xFF1A1714)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        _StatusBadge(status: resolved ? 'SAFE' : (sev == 'HIGH' ? 'CRITICAL' : sev == 'MEDIUM' ? 'WARNING' : 'SAFE')),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      (alert['message'] ?? '–').toString(),
                      style: const TextStyle(fontSize: 11, color: Color(0xFF7A7268), height: 1.4),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      bridge != null ? bridge.name : bridgeId,
                      style: const TextStyle(fontSize: 10, color: Color(0xFFB0A89E), fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index, current;
  final String? badge;
  final ValueChanged<int> onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.index,
    required this.current,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final active = index == current;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap(index),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, size: 22, color: active ? const Color(0xFF2563EB) : const Color(0xFFB0A89E)),
                  if (badge != null)
                    Positioned(
                      top: -4, right: -8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(color: const Color(0xFFDC2626), borderRadius: BorderRadius.circular(8)),
                        child: Text(badge!, style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                  color: active ? const Color(0xFF2563EB) : const Color(0xFFB0A89E),
                ),
              ),
              const SizedBox(height: 2),
              if (active)
                Container(width: 20, height: 2, decoration: BoxDecoration(color: const Color(0xFF2563EB), borderRadius: BorderRadius.circular(2))),
            ],
          ),
        ),
      ),
    );
  }
}