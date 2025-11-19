import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Emergency Ping Prototype',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
        useMaterial3: true,
      ),
      home: const EmergencyScreen(),
    );
  }
}

class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key});

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen>
    with WidgetsBindingObserver {
  final Strategy _strategy = Strategy.P2P_STAR;
  final _nearby = Nearby();
  final _userName = 'EmergencyBeacon-${Random().nextInt(1000)}';

  String? _lastAlertTimestamp;
  String? _lastAlertId;

  // Store GPS coordinates
  String? _lastLat;
  String? _lastLong;

  bool _isBroadcasting = false;
  bool _isScanning = false;
  String _statusLog = "Initializing...";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initApp();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check permissions if user returns from Settings
    if (state == AppLifecycleState.resumed) {
      _checkPermissionsAndRestart();
    }
  }

  Future<void> _initApp() async {
    await _checkPermissionsAndRestart();
  }

  Future<void> _checkPermissionsAndRestart() async {
    bool ready = await _requestPermissions();
    if (ready && !_isScanning && !_isBroadcasting) {
      setState(() => _statusLog = "Permissions OK. Monitoring...");
      _startMonitoring();
    } else if (!ready) {
      setState(() => _statusLog = "Missing Permissions.");
    }
  }

  Future<bool> _requestPermissions() async {
    // 1. Location (Required for Discovery & GPS)
    if (!await Permission.location.isGranted) {
      await Permission.location.request();
    }

    // 2. Bluetooth Permissions
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetooth,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
    ].request();

    // 3. Nearby Wifi (Android 13+)
    PermissionStatus wifiStatus = await Permission.nearbyWifiDevices.request();

    if (wifiStatus.isPermanentlyDenied) {
      _showSettingsSnackBar(
        "Nearby Devices permission is blocked. Open Settings.",
      );
      return false;
    }

    if (await Permission.bluetoothScan.isDenied ||
        await Permission.bluetoothAdvertise.isDenied ||
        await Permission.bluetoothConnect.isDenied ||
        (Platform.isAndroid && await Permission.nearbyWifiDevices.isDenied)) {
      return false;
    }

    return true;
  }

  void _showSettingsSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        action: SnackBarAction(label: 'SETTINGS', onPressed: openAppSettings),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  // --- 1. MONITORING LOGIC (Receiver) ---

  Future<void> _startMonitoring() async {
    if (_isBroadcasting || _isScanning) return;

    try {
      bool result = await _nearby.startDiscovery(
        _userName,
        _strategy,
        onEndpointFound: (String id, String name, String serviceId) {
          _nearby.requestConnection(
            _userName,
            id,
            onConnectionInitiated: (id, info) =>
                _onConnectionInitiated(id, info),
            onConnectionResult: (id, status) {},
            onDisconnected: (id) {},
          );
        },
        onEndpointLost: (id) {},
      );

      setState(() {
        _isScanning = result;
        _statusLog = result ? "Scanning for SOS signals..." : "Scan failed.";
      });
    } catch (e) {
      _handleNearbyError(e);
    }
  }

  // --- 2. BROADCASTING LOGIC (Sender) ---

  Future<void> _sendEmergencyPing() async {
    if (_isScanning) {
      await _nearby.stopDiscovery();
      setState(() {
        _isScanning = false;
      });
    }

    if (_isBroadcasting) {
      _showSnackbar("Already broadcasting SOS!");
      return;
    }

    setState(() => _statusLog = "Acquiring GPS Location...");

    // Get Location BEFORE broadcasting
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showSnackbar("Location Services Disabled. Sending empty location.");
        _lastLat = "0.0";
        _lastLong = "0.0";
      } else {
        Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        _lastLat = position.latitude.toString();
        _lastLong = position.longitude.toString();
      }
    } catch (e) {
      _lastLat = "0.0";
      _lastLong = "0.0";
      _showSnackbar("GPS Error: $e");
    }

    try {
      bool result = await _nearby.startAdvertising(
        _userName,
        _strategy,
        onConnectionInitiated: (id, info) => _onConnectionInitiated(id, info),
        onConnectionResult: (id, status) {
          if (status == Status.CONNECTED) {
            _sendSOSPayload(id);
          }
        },
        onDisconnected: (id) {},
      );

      final timestamp = DateFormat(
        'yyyy-MM-dd HH:mm:ss',
      ).format(DateTime.now());
      final alertId = "ALERT-${Random().nextInt(9000) + 1000}";

      setState(() {
        _isBroadcasting = result;
        _lastAlertTimestamp = "Time: $timestamp";
        _lastAlertId = "ID: $alertId";
        _statusLog = "Broadcasting SOS Signal...";
      });

      _showSnackbar("SOS Broadcast Active!");
    } catch (e) {
      _handleNearbyError(e);
      setState(() {
        _isBroadcasting = false;
      });
    }
  }

  void _handleNearbyError(Object e) {
    String errorStr = e.toString();
    if (errorStr.contains("8029") ||
        errorStr.contains("MISSING_PERMISSION_NEARBY_WIFI_DEVICES")) {
      setState(() => _statusLog = "Error: Missing Nearby WiFi Permission");
      _showDialogError(
        "Permission Error",
        "Android 13+ requires 'Nearby Wi-Fi Devices' permission.",
        true,
      );
    } else {
      setState(() => _statusLog = "Error: $e");
    }
  }

  void _showDialogError(String title, String content, bool offerSettings) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(color: Colors.red)),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          if (offerSettings)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                openAppSettings();
              },
              child: const Text("Open Settings"),
            ),
        ],
      ),
    );
  }

  void _sendSOSPayload(String endpointId) {
    // Format: SOS_ALERT | User | ID | Time | Lat | Long
    String lat = _lastLat ?? "0.0";
    String long = _lastLong ?? "0.0";

    String sosMessage =
        "SOS_ALERT|$_userName|$_lastAlertId|$_lastAlertTimestamp|$lat|$long";

    _nearby.sendBytesPayload(
      endpointId,
      Uint8List.fromList(utf8.encode(sosMessage)),
    );
  }

  // --- 3. SHARED CONNECTION LOGIC ---

  void _onConnectionInitiated(
    String endpointId,
    ConnectionInfo connectionInfo,
  ) {
    _nearby.acceptConnection(
      endpointId,
      onPayLoadRecieved: (endpointId, payload) {
        if (payload.type == PayloadType.BYTES) {
          String msg = String.fromCharCodes(payload.bytes!);
          if (msg.startsWith("SOS_ALERT")) {
            _handleIncomingSOS(msg);
          }
        }
      },
    );
  }

  void _handleIncomingSOS(String message) async {
    // Expected: SOS_ALERT|User|ID|Time|Lat|Long
    List<String> parts = message.split('|');
    await AudioPlayer().play(AssetSource("ST_Siren.mp3"));
    if (parts.length >= 6) {
      String sender = parts[1];
      String alertId = parts[2];
      String time = parts[3];
      String lat = parts[4];
      String lng = parts[5];

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red, size: 30),
              SizedBox(width: 10),
              Text(
                "SOS RECEIVED",
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "From: $sender",
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 5),
              Text("Alert ID: $alertId"),
              Text("Time: $time"),
              const Divider(),
              const Text(
                "Location Coordinates:",
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              Text(
                "$lat, $lng",
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await AudioPlayer().stop();
              },
              child: const Text("CLOSE"),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.map),
              label: const Text("OPEN MAPS"),
              onPressed: () {
                // Open Google Maps with marker
                final url =
                    "https://www.google.com/maps/search/?api=1&query=$lat,$lng";
                launchUrlString(url, mode: LaunchMode.externalApplication);
              },
            ),
          ],
        ),
      );
    }
  }

  void _showSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nearby.stopAdvertising();
    _nearby.stopDiscovery();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Link'),
        backgroundColor: _isBroadcasting ? Colors.red : Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                _statusLog,
                style: const TextStyle(
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            const SizedBox(height: 20),

            SizedBox(
              width: 220,
              height: 220,
              child: ElevatedButton(
                onPressed: _sendEmergencyPing,
                style: ElevatedButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(20),
                  backgroundColor: _isBroadcasting
                      ? Colors.grey.shade800
                      : Colors.red,
                  foregroundColor: Colors.white,
                  elevation: 15,
                  shadowColor: Colors.redAccent,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _isBroadcasting ? Icons.wifi_tethering : Icons.sos,
                      size: 80,
                    ),
                    const SizedBox(height: 15),
                    Text(
                      _isBroadcasting ? 'BROADCASTING' : 'SEND SOS',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 40),

            if (_lastAlertTimestamp != null)
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 30),
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      const Text(
                        "My Status",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const Divider(),
                      Text("Sent: $_lastAlertTimestamp"),
                      const SizedBox(height: 4),
                      Text(
                        "Loc: ${(_lastLat != null) ? '$_lastLat, $_lastLong' : 'Acquiring...'}",
                        style: const TextStyle(color: Colors.blueGrey),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
