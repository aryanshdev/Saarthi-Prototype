import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Emergency Ping Prototype',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.pink),
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

class _EmergencyScreenState extends State<EmergencyScreen> {
  final Strategy _strategy = Strategy.P2P_STAR;
  final _nearby = Nearby();
  final _userName = 'EmergencyBeacon-${Random().nextInt(1000)}';

  String? _lastAlertTimestamp;
  String? _lastAlertId;

  bool _isBroadcasting = false; // Sending Help
  bool _isScanning = false;     // Listening for Help

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    await _requestPermissions();
    // Default to monitoring (listening) mode when app starts
    _startMonitoring();
  }

  Future<void> _requestPermissions() async {
    if (await Permission.location.request().isDenied) {
      _showSnackbar("Location permission is required.");
      return;
    }

    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetooth,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
    ].request();

    if (statuses.values.any((status) => status.isDenied)) {
      _showSnackbar("Bluetooth permissions are required.");
    }
  }

  // --- 1. MONITORING LOGIC (Receiver) ---

  Future<void> _startMonitoring() async {
    if (_isBroadcasting || _isScanning) return;

    try {
      bool result = await _nearby.startDiscovery(
        _userName,
        _strategy,
        onEndpointFound: (String id, String name, String serviceId) {
          // Found someone! Connect automatically to receive their status.
          _nearby.requestConnection(
            _userName,
            id,
            onConnectionInitiated: (id, info) => _onConnectionInitiated(id, info),
            onConnectionResult: (id, status) {
              if (status == Status.CONNECTED) {
                // We are connected to an emergency beacon.
                // Waiting for payload...
              }
            },
            onDisconnected: (id) {},
          );
        },
        onEndpointLost: (id) {},
      );

      setState(() {
        _isScanning = result;
      });
    } catch (e) {
      _showSnackbar("Failed to start monitoring: $e");
    }
  }

  // --- 2. BROADCASTING LOGIC (Sender) ---

  Future<void> _sendEmergencyPing() async {
    // If we are scanning, stop it first to switch to broadcast mode
    if (_isScanning) {
      await _nearby.stopDiscovery();
      setState(() { _isScanning = false; });
    }

    if (_isBroadcasting) {
      _showSnackbar("Already broadcasting SOS!");
      return;
    }

    try {
      bool result = await _nearby.startAdvertising(
        _userName,
        _strategy,
        onConnectionInitiated: (id, info) => _onConnectionInitiated(id, info),
        onConnectionResult: (id, status) {
          if (status == Status.CONNECTED) {
            // Someone connected to us! Send them the SOS payload immediately.
            _sendSOSPayload(id);
          }
        },
        onDisconnected: (id) {},
      );

      final timestamp = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
      final alertId = "ALERT-${Random().nextInt(9000) + 1000}";

      setState(() {
        _isBroadcasting = result;
        _lastAlertTimestamp = "Time: $timestamp";
        _lastAlertId = "ID: $alertId";
      });

      _showSnackbar("SOS Signal Broadcasting...");
    } catch (e) {
      _showSnackbar("Failed to start broadcast: $e");
    }
  }

  void _sendSOSPayload(String endpointId) {
    String sosMessage = "SOS_ALERT|$_userName|$_lastAlertId|$_lastAlertTimestamp";
    _nearby.sendBytesPayload(endpointId, Uint8List.fromList(utf8.encode(sosMessage)));
  }

  // --- 3. SHARED CONNECTION LOGIC ---

  void _onConnectionInitiated(String endpointId, ConnectionInfo connectionInfo) {
    // Always accept connections in emergency mode
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

  void _handleIncomingSOS(String message) {
    // Format: SOS_ALERT|User|ID|Time
    List<String> parts = message.split('|');
    if (parts.length >= 4) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("🚨 EMERGENCY RECEIVED", style: TextStyle(color: Colors.red)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("From: ${parts[1]}"),
              Text("Alert ID: ${parts[2]}"),
              Text("Time: ${parts[3]}"),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK"))
          ],
        ),
      );
    }
  }

  // --- 4. UI HELPERS ---

  void _showSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  void dispose() {
    _nearby.stopAdvertising();
    _nearby.stopDiscovery();
    _nearby.stopAllEndpoints();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Link'),
        backgroundColor: _isBroadcasting ? Colors.red : Colors.blueAccent,
        foregroundColor: Colors.white,
        actions: [
          // Indicator showing if we are listening
          if (_isScanning)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Icon(Icons.radar, color: Colors.white),
            )
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isScanning)
              const Padding(
                padding: EdgeInsets.only(bottom: 20.0),
                child: Text("Scanning for distress signals...", style: TextStyle(color: Colors.grey)),
              ),

            // Main Button
            SizedBox(
              width: 220,
              height: 220,
              child: ElevatedButton(
                onPressed: _sendEmergencyPing,
                style: ElevatedButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(20),
                  backgroundColor: _isBroadcasting ? Colors.grey.shade800 : Colors.red,
                  foregroundColor: Colors.white,
                  elevation: 15,
                  shadowColor: Colors.redAccent,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_isBroadcasting ? Icons.wifi_tethering : Icons.sos, size: 80),
                    const SizedBox(height: 15),
                    Text(
                      _isBroadcasting ? 'BROADCASTING' : 'SEND SOS',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 40),

            // Status Card
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
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
                      ),
                      const Divider(),
                      Text("Sent: $_lastAlertTimestamp"),
                      Text("ID: $_lastAlertId"),
                      const SizedBox(height: 5),
                      const Text("Broadcasting location...", style: TextStyle(fontSize: 12, color: Colors.green)),
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