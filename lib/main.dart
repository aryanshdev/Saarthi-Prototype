import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:geolocator/geolocator.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;

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

  final AudioPlayer _audioPlayer = AudioPlayer();

  // Controller for Server IP Input
  final TextEditingController _serverIpController = TextEditingController();

  String? _lastAlertTimestamp;
  String? _lastAlertId;
  String? _lastLat;
  String? _lastLong;

  bool _isBroadcasting = false;
  bool _isScanning = false;
  String _statusLog = "Initializing...";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Pre-fill with the IP you mentioned, but allow editing
    _serverIpController.text = "10.43.24.89";
    _initApp();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
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
      setState(() => _statusLog = "Ready. Set Server IP & Monitor.");
      _startMonitoring();
    } else if (!ready) {
      setState(() => _statusLog = "Missing Permissions.");
    }
  }

  Future<bool> _requestPermissions() async {
    if (!await Permission.location.isGranted) await Permission.location.request();

    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetooth,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
    ].request();

    PermissionStatus wifiStatus = await Permission.nearbyWifiDevices.request();
    if (wifiStatus.isPermanentlyDenied) return false;

    if (await Permission.bluetoothScan.isDenied ||
        await Permission.bluetoothAdvertise.isDenied ||
        await Permission.bluetoothConnect.isDenied ||
        (Platform.isAndroid && await Permission.nearbyWifiDevices.isDenied)) {
      return false;
    }
    return true;
  }

  // --- SERVER UPLOAD LOGIC ---
  // MODIFIED: Accepts 'sender' to support relaying messages for others
  Future<void> _uploadToServer(String sender, String alertId, String time, String lat, String long) async {
    String ip = _serverIpController.text.trim();
    if (ip.isEmpty) return;

    // Format URL correctly
    String url = "http://10.43.24.89:3000/api/sos";

    try {
      _showSnackbar("Relaying data to Command Center...");

      final response = await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "sender": sender,      // The original sender's name
          "alert_id": alertId,   // The original alert ID
          "timestamp": time,     // The original timestamp
          "latitude": lat,       // The original coordinates
          "longitude": long
        }),
      );

      if (response.statusCode == 200) {
        _showSnackbar("✔ Data relayed to Server.");
      } else {
        print("Server Error: ${response.statusCode} ${response.body}");
      }
    } catch (e) {
      print("Upload failed: $e");
    }
  }

  // --- BROADCASTING LOGIC (Sender) ---
  Future<void> _sendEmergencyPing() async {
    if (_isScanning) {
      await _nearby.stopDiscovery();
      setState(() => _isScanning = false);
    }
    if (_isBroadcasting) {
      _showSnackbar("Already broadcasting SOS!");
      return;
    }

    setState(() => _statusLog = "Acquiring GPS...");

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _lastLat = "0.0"; _lastLong = "0.0";
      } else {
        Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        _lastLat = position.latitude.toString();
        _lastLong = position.longitude.toString();
      }
    } catch (e) {
      _lastLat = "0.0"; _lastLong = "0.0";
    }

    try {
      bool result = await _nearby.startAdvertising(
        _userName,
        _strategy,
        onConnectionInitiated: (id, info) => _onConnectionInitiated(id, info),
        onConnectionResult: (id, status) {
          if (status == Status.CONNECTED) _sendSOSPayload(id);
        },
        onDisconnected: (id) {},
      );

      final timestamp = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
      final alertId = "ALERT-${Random().nextInt(9000) + 1000}";


      // Upload MY OWN alert to server
      _uploadToServer(_userName, alertId, timestamp, _lastLat!, _lastLong!);

      setState(() {
        _isBroadcasting = result;
        _lastAlertTimestamp = timestamp;
        _lastAlertId = alertId;
        _statusLog = "Broadcasting Signal...";
      });
    } catch (e) {
      _handleNearbyError(e);
      setState(() => _isBroadcasting = false);
    }
  }

  void _sendSOSPayload(String endpointId) {
    String lat = _lastLat ?? "0.0";
    String long = _lastLong ?? "0.0";
    String sosMessage = "SOS_ALERT|$_userName|$_lastAlertId|$_lastAlertTimestamp|$lat|$long";
    _nearby.sendBytesPayload(endpointId, Uint8List.fromList(utf8.encode(sosMessage)));
  }

  // --- MONITORING LOGIC (Receiver) ---
  Future<void> _startMonitoring() async {
    if (_isBroadcasting || _isScanning) return;
    try {
      bool result = await _nearby.startDiscovery(
        _userName,
        _strategy,
        onEndpointFound: (id, name, serviceId) {
          _nearby.requestConnection(
            _userName,
            id,
            onConnectionInitiated: (id, info) => _onConnectionInitiated(id, info),
            onConnectionResult: (id, status) {},
            onDisconnected: (id) {},
          );
        },
        onEndpointLost: (id) {},
      );
      setState(() {
        _isScanning = result;
        _statusLog = result ? "Scanning..." : "Scan failed.";
      });
    } catch (e) {
      _handleNearbyError(e);
    }
  }

  void _onConnectionInitiated(String endpointId, ConnectionInfo connectionInfo) {
    _nearby.acceptConnection(
      endpointId,
      onPayLoadRecieved: (endpointId, payload) {
        if (payload.type == PayloadType.BYTES) {
          String msg = String.fromCharCodes(payload.bytes!);
          if (msg.startsWith("SOS_ALERT")) _handleIncomingSOS(msg);
        }
      },
    );
  }

  void _handleIncomingSOS(String message) async {
    // 1. Audio/Haptics
    try {
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.play(AssetSource('ST_Siren.mp3'));
    } catch (e) { debugPrint("$e"); }


    // 2. Parse Message
    List<String> parts = message.split('|');

    if (parts.length >= 6) {
      String sender = parts[1];
      String alertId = parts[2];
      String time = parts[3];
      String lat = parts[4];
      String lng = parts[5];

      // 3. RELAY TO SERVER (Mesh Gateway Feature)
      // This sends the data received via Bluetooth to the Internet DB
      _uploadToServer(sender, alertId, time, lat, lng);

      // 4. Show UI
      _showSOSDialog(sender, alertId, time, lat, lng);
    }
  }

  void _showSOSDialog(String sender, String id, String time, String lat, String lng) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.red.shade50,
        title: const Text("SOS ALERT", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("From: $sender"),
            Text("Time: $time"),
            Text("Loc: $lat, $lng"),
            const SizedBox(height: 10),
            const Text("(Data relayed to HQ)", style: TextStyle(fontSize: 10, color: Colors.grey),textAlign: TextAlign.start,),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () { _stopAlert(); Navigator.pop(ctx); },
            child: const Text("STOP ALARM"),
          ),
          ElevatedButton(
            onPressed: () {
              _stopAlert();
              launchUrlString("https://www.google.com/maps/search/?api=1&query=$lat,$lng", mode: LaunchMode.externalApplication);
              Navigator.pop(ctx);
            },
            child: const Text("MAPS"),
          ),
        ],
      ),
    );
  }

  void _stopAlert() {
    _audioPlayer.stop();
  }

  void _handleNearbyError(Object e) {
    if (e.toString().contains("8029")) {
      _showSnackbar("Error: Missing Nearby WiFi Permission (Android 13+)");
      openAppSettings();
    } else {
      setState(() => _statusLog = "Error: $e");
    }
  }

  void _showSnackbar(String message) {
    if (!mounted) return;
    // ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nearby.stopAdvertising();
    _nearby.stopDiscovery();
    _audioPlayer.dispose();
    _serverIpController.dispose();
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
      body: SingleChildScrollView(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                  controller: _serverIpController,
                  decoration: const InputDecoration(
                    labelText: "Server IP (e.g., 10.43.24.89)",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.computer),
                  ),
                  keyboardType: TextInputType.text, // Changed to text to allow dots
                ),
              ),
              Text(_statusLog, style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 20),
              SizedBox(
                width: 220, height: 220,
                child: ElevatedButton(
                  onPressed: _sendEmergencyPing,
                  style: ElevatedButton.styleFrom(
                    shape: const CircleBorder(),
                    backgroundColor: _isBroadcasting ? Colors.grey.shade800 : Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(_isBroadcasting ? Icons.wifi_tethering : Icons.sos, size: 80),
                      Text(_isBroadcasting ? 'BROADCASTING' : 'SEND SOS', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (_lastAlertTimestamp != null)
                Text("Sent: $_lastAlertTimestamp \nLoc: $_lastLat, $_lastLong", textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}