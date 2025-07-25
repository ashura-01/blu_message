import 'dart:typed_data';
import 'dart:io'; // for unique device name
import 'package:flutter/material.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: NearbyChatApp(),
      );
}

class NearbyChatApp extends StatefulWidget {
  const NearbyChatApp({super.key});
  @override
  State<NearbyChatApp> createState() => _NearbyChatAppState();
}

class _NearbyChatAppState extends State<NearbyChatApp> {
  final Strategy strategy = Strategy.P2P_CLUSTER;
  final List<String> messages = [];
  final TextEditingController _controller = TextEditingController();

  String? connectedId;
  String? connectedDeviceName;

  @override
  void initState() {
    super.initState();
    _initNearby();
  }

  Future<void> _initNearby() async {
    // Request all required permissions including nearbyWifiDevices (important for Android 12+)
    await [
      Permission.bluetooth,
      Permission.location,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.nearbyWifiDevices,
    ].request();

    // Create a unique device name based on hostname (or fallback)
    final deviceName = Platform.localHostname.isNotEmpty
        ? 'Device_${Platform.localHostname}'
        : 'Device_${DateTime.now().millisecondsSinceEpoch}';

    // Start advertising (make device discoverable)
    try {
      await Nearby().startAdvertising(
        deviceName,
        strategy,
        onConnectionInitiated: _onConnectionInit,
        onConnectionResult: (id, status) {
          print("Advertiser Connection Result: $status");
          if (status == Status.CONNECTED) {
            setState(() => connectedId = id);
          }
        },
        onDisconnected: (id) {
          print("Disconnected from: $id");
          setState(() {
            connectedId = null;
            connectedDeviceName = null;
          });
        },
      );
    } catch (e) {
      print('Error starting advertising: $e');
    }

    // Start discovery (search for other devices)
    try {
      await Nearby().startDiscovery(
        deviceName,
        strategy,
        onEndpointFound: (id, name, serviceId) {
          print("Found endpoint: $name");
          Nearby().requestConnection(
            deviceName,
            id,
            onConnectionInitiated: _onConnectionInit,
            onConnectionResult: (id, status) {
              print("Discovery Connection Result: $status");
              if (status == Status.CONNECTED) {
                setState(() => connectedId = id);
              }
            },
            onDisconnected: (id) {
              print("Disconnected from: $id");
              setState(() {
                connectedId = null;
                connectedDeviceName = null;
              });
            },
          );
        },
        onEndpointLost: (id) => print("Lost endpoint: $id"),
      );
    } catch (e) {
      print('Error starting discovery: $e');
    }
  }

  void _onConnectionInit(String id, ConnectionInfo info) {
    print("Connecting to ${info.endpointName}");

    setState(() {
      connectedDeviceName = info.endpointName;
    });

    Nearby().acceptConnection(
      id,
      onPayLoadRecieved: (endid, payload) {
        if (payload.type == PayloadType.BYTES) {
          String msg = String.fromCharCodes(payload.bytes!);
          setState(() => messages.add("🟢 ${connectedDeviceName ?? 'Friend'}: $msg"));
        }
      },
      onPayloadTransferUpdate: (endid, update) {},
    );
  }

  void _sendMessage(String msg) async {
    if (connectedId != null && msg.isNotEmpty) {
      try {
        await Nearby().sendBytesPayload(
          connectedId!,
          Uint8List.fromList(msg.codeUnits),
        );
        setState(() => messages.add("🔵 Me: $msg"));
      } catch (e) {
        print('Send message error: $e');
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    Nearby().stopAdvertising();
    Nearby().stopDiscovery();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text("Nearby Chat"),
          backgroundColor: const Color.fromARGB(255, 238, 75, 0),
        ),
        body: Column(
          children: [
            if (connectedDeviceName != null)
              Container(
                width: double.infinity,
                color: Colors.black12,
                padding: const EdgeInsets.all(12),
                child: Text(
                  "🔗 Connected to: $connectedDeviceName",
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                ),
              ),
            Expanded(
              child: ListView.builder(
                itemCount: messages.length,
                padding: const EdgeInsets.all(10),
                itemBuilder: (_, i) => Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  alignment: messages[i].startsWith("🔵") ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: messages[i].startsWith("🔵") ? Colors.blue[100] : Colors.green[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(messages[i].replaceFirst(RegExp(r'^🔵 |^🟢 '), '')),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: "Enter message",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () {
                    _sendMessage(_controller.text.trim());
                    _controller.clear();
                  },
                ),
              ]),
            ),
          ],
        ),
      );
}
