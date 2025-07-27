import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // for orientation lock
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp, // lock portrait only
  ]).then((_) {
    runApp(const MyApp());
  });
}

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
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<String> messages = [];
  final Map<String, String> discoveredDevices = {};
  String? connectedId;
  String? connectedName;
  bool isDiscovering = false;

  @override
  void initState() {
    super.initState();
    _initializeNearby();
  }

  Future<void> _initializeNearby() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.location
    ].request();

    _startAdvertising();
    _startDiscovery();
  }

  Future<void> _startAdvertising() async {
    try {
      await Nearby().startAdvertising(
        'User',
        strategy,
        onConnectionInitiated: _onConnectionInit,
        onConnectionResult: (id, status) {
          if (status == Status.CONNECTED) {
            setState(() => connectedId = id);
          }
        },
        onDisconnected: (id) {
          setState(() {
            connectedId = null;
            connectedName = null;
          });
        },
      );
    } catch (e) {
      debugPrint("Error starting advertising: $e");
    }
  }

  Future<void> _startDiscovery() async {
    if (isDiscovering) return;
    setState(() => isDiscovering = true);

    discoveredDevices.clear();
    try {
      await Nearby().startDiscovery(
        'User',
        strategy,
        onEndpointFound: (id, name, _) {
          setState(() {
            discoveredDevices[id] = name;
          });
        },
        onEndpointLost: (id) {
          setState(() {
            discoveredDevices.remove(id);
          });
        },
      );
    } catch (e) {
      debugPrint("Discovery failed: $e");
    }
  }

  void _rescanDevices() async {
    setState(() {
      discoveredDevices.clear();
      isDiscovering = false;
    });
    await Nearby().stopDiscovery();
    _startDiscovery();
  }

  void _onConnectionInit(String id, ConnectionInfo info) {
    Nearby().acceptConnection(
      id,
      onPayLoadRecieved: (endid, payload) {
        if (payload.type == PayloadType.BYTES) {
          String msg = String.fromCharCodes(payload.bytes!);
          setState(() => messages.add("🟢 ${info.endpointName}: $msg"));
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        }
      },
      onPayloadTransferUpdate: (endid, update) {},
    );
    setState(() {
      connectedId = id;
      connectedName = info.endpointName;
    });
  }

  void _connectToDevice(String id) {
    Nearby().requestConnection(
      'User',
      id,
      onConnectionInitiated: _onConnectionInit,
      onConnectionResult: (id, status) {
        if (status == Status.CONNECTED) {
          setState(() => connectedId = id);
        }
      },
      onDisconnected: (id) {
        setState(() {
          connectedId = null;
          connectedName = null;
        });
      },
    );
  }

  void _sendMessage() {
    final msg = _controller.text.trim();
    if (msg.isNotEmpty && connectedId != null) {
      final bytes = Uint8List.fromList(msg.codeUnits);
      Nearby().sendBytesPayload(connectedId!, bytes);
      setState(() {
        messages.add(msg);  // Sender's message without icon or "Me"
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      _controller.clear();
    }
  }

  void _showDeviceList() {
    if (discoveredDevices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No nearby devices found")),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: discoveredDevices.entries
            .map(
              (entry) => ListTile(
                title: Text(entry.value),
                subtitle: Text(entry.key),
                onTap: () {
                  Navigator.pop(context);
                  _connectToDevice(entry.key);
                },
              ),
            )
            .toList(),
      ),
    );
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    Nearby().stopAdvertising();
    Nearby().stopDiscovery();
    Nearby().stopAllEndpoints();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 46, 48, 56),
      appBar: AppBar(
        foregroundColor: const Color.fromARGB(255, 160, 195, 255),
        backgroundColor: const Color.fromARGB(255, 24, 27, 43),
        title: Text(
          connectedName != null ? "Chat with $connectedName" : "Blue",
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.devices),
            onPressed: _showDeviceList,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _rescanDevices,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: messages.length,
              itemBuilder: (context, i) {
                final isMe = !messages[i].startsWith("🟢"); // If no green icon, it's sender
                return Align(
                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isMe
                          ? const Color.fromARGB(255, 30, 37, 53)
                          : const Color.fromARGB(255, 68, 77, 107),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Text(
                      // Remove icon from sender message display
                      isMe ? messages[i] : messages[i].substring(2),
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            color: const Color.fromARGB(255, 24, 27, 43),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: "Type a message...",
                      hintStyle: const TextStyle(color: Colors.white60),
                      enabledBorder: OutlineInputBorder(
                        borderSide: const BorderSide(
                            color: Color.fromARGB(255, 160, 195, 255)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(
                            color: Color.fromARGB(255, 160, 195, 255)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send,
                      color: Color.fromARGB(255, 160, 195, 255)),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}




// import 'dart:typed_data';
// import 'package:flutter/material.dart';
// import 'package:nearby_connections/nearby_connections.dart';
// import 'package:permission_handler/permission_handler.dart';

// void main() => runApp(const MyApp());

// class MyApp extends StatelessWidget {
//   const MyApp({super.key});

//   @override
//   Widget build(BuildContext context) => const MaterialApp(
//         debugShowCheckedModeBanner: false,
//         home: NearbyChatApp(),
//       );
// }

// class NearbyChatApp extends StatefulWidget {
//   const NearbyChatApp({super.key});

//   @override
//   State<NearbyChatApp> createState() => _NearbyChatAppState();
// }

// class _NearbyChatAppState extends State<NearbyChatApp> {
//   final Strategy strategy = Strategy.P2P_CLUSTER;
//   final TextEditingController _controller = TextEditingController();
//   final List<String> messages = [];
//   final Map<String, String> discoveredDevices = {};
//   String? connectedId;
//   String? connectedName;
//   bool isDiscovering = false;

//   @override
//   void initState() {
//     super.initState();
//     _initializeNearby();
//   }

//   Future<void> _initializeNearby() async {
//     await [
//       Permission.bluetooth,
//       Permission.bluetoothAdvertise,
//       Permission.bluetoothConnect,
//       Permission.location
//     ].request();

//     _startAdvertising();
//     _startDiscovery();
//   }

//   Future<void> _startAdvertising() async {
//     try {
//       await Nearby().startAdvertising(
//         'User',
//         strategy,
//         onConnectionInitiated: _onConnectionInit,
//         onConnectionResult: (id, status) {
//           if (status == Status.CONNECTED) {
//             setState(() => connectedId = id);
//           }
//         },
//         onDisconnected: (id) {
//           setState(() {
//             connectedId = null;
//             connectedName = null;
//           });
//         },
//       );
//     } catch (e) {
//       debugPrint("Error starting advertising: $e");
//     }
//   }

//   Future<void> _startDiscovery() async {
//     if (isDiscovering) return;
//     setState(() => isDiscovering = true);

//     discoveredDevices.clear();
//     try {
//       await Nearby().startDiscovery(
//         'User',
//         strategy,
//         onEndpointFound: (id, name, _) {
//           setState(() {
//             discoveredDevices[id] = name;
//           });
//         },
//         onEndpointLost: (id) {
//           setState(() {
//             discoveredDevices.remove(id);
//           });
//         },
//       );
//     } catch (e) {
//       debugPrint("Discovery failed: $e");
//     }
//   }

//   void _rescanDevices() async {
//     setState(() {
//       discoveredDevices.clear();
//       isDiscovering = false;
//     });
//     await Nearby().stopDiscovery();
//     _startDiscovery();
//   }

//   void _onConnectionInit(String id, ConnectionInfo info) {
//     Nearby().acceptConnection(
//       id,
//       onPayLoadRecieved: (endid, payload) {
//         if (payload.type == PayloadType.BYTES) {
//           String msg = String.fromCharCodes(payload.bytes!);
//           setState(() => messages.add("🟢 ${info.endpointName}: $msg"));
//         }
//       },
//       onPayloadTransferUpdate: (endid, update) {},
//     );
//     setState(() {
//       connectedId = id;
//       connectedName = info.endpointName;
//     });
//   }

//   void _connectToDevice(String id) {
//     Nearby().requestConnection(
//       'User',
//       id,
//       onConnectionInitiated: _onConnectionInit,
//       onConnectionResult: (id, status) {
//         if (status == Status.CONNECTED) {
//           setState(() => connectedId = id);
//         }
//       },
//       onDisconnected: (id) {
//         setState(() {
//           connectedId = null;
//           connectedName = null;
//         });
//       },
//     );
//   }

//   void _sendMessage() {
//     final msg = _controller.text.trim();
//     if (msg.isNotEmpty && connectedId != null) {
//       final bytes = Uint8List.fromList(msg.codeUnits);
//       Nearby().sendBytesPayload(connectedId!, bytes);
//       setState(() => messages.add("🔵 Me: $msg"));
//       _controller.clear();
//     }
//   }

//   void _showDeviceList() {
//     if (discoveredDevices.isEmpty) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(content: Text("No nearby devices found")),
//       );
//       return;
//     }

//     showModalBottomSheet(
//       context: context,
//       builder: (context) => Column(
//         mainAxisSize: MainAxisSize.min,
//         children: discoveredDevices.entries
//             .map(
//               (entry) => ListTile(
//                 title: Text(entry.value),
//                 subtitle: Text(entry.key),
//                 onTap: () {
//                   Navigator.pop(context);
//                   _connectToDevice(entry.key);
//                 },
//               ),
//             )
//             .toList(),
//       ),
//     );
//   }

//   @override
//   void dispose() {
//     _controller.dispose();
//     Nearby().stopAdvertising();
//     Nearby().stopDiscovery();
//     Nearby().stopAllEndpoints();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: const Color.fromARGB(255, 46, 48, 56),
//       appBar: AppBar(
//         foregroundColor: const Color.fromARGB(255, 160, 195, 255),
//         backgroundColor: const Color.fromARGB(255, 24, 27, 43),
//         title: Text(
//           connectedName != null
//               ? "Chat with $connectedName"
//               : "Blue", style: TextStyle(fontSize: 16),
//         ),
//         actions: [
//           IconButton(
//             icon: const Icon(Icons.devices),
//             onPressed: _showDeviceList,
//           ),
//           IconButton(
//             icon: const Icon(Icons.refresh),
//             onPressed: _rescanDevices,
//           ),
//         ],
//       ),
//       body: Column(
//         children: [
//           Expanded(
//             child: ListView.builder(
//               itemCount: messages.length,
//               itemBuilder: (context, i) {
//                 final isMe = messages[i].startsWith("🔵");
//                 return Align(
//                   alignment:
//                       isMe ? Alignment.centerRight : Alignment.centerLeft,
//                   child: Container(
//                     margin:
//                         const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
//                     padding: const EdgeInsets.all(12),
//                     decoration: BoxDecoration(
//                       color: isMe ?  const Color.fromARGB(255, 30, 37, 53) : const Color.fromARGB(255, 68, 77, 107),
//                       borderRadius: BorderRadius.circular(15),
//                     ),
//                     child: Text(
//                       messages[i],
//                       style:
//                           const TextStyle(color: Colors.white, fontSize: 16),
//                     ),
//                   ),
//                 );
//               },
//             ),
//           ),
//           Container(
//             padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
//             color:  Color.fromARGB(255, 24, 27, 43),
//             child: Row(
//               children: [
//                 Expanded(
//                   child: TextField(
//                     controller: _controller,
//                     style: const TextStyle(color: Colors.white),
//                     decoration: InputDecoration(
//                       hintText: "Type a message...",
//                       hintStyle: const TextStyle(color: Colors.white60),
//                       enabledBorder: OutlineInputBorder(
//                         borderSide: const BorderSide(color: const Color.fromARGB(255, 160, 195, 255)),
//                         borderRadius: BorderRadius.circular(10),
//                       ),
//                       focusedBorder: OutlineInputBorder(
//                         borderSide:
//                             const BorderSide(color: const Color.fromARGB(255, 160, 195, 255)),
//                         borderRadius: BorderRadius.circular(10),
//                       ),
//                       contentPadding: const EdgeInsets.symmetric(
//                           horizontal: 12, vertical: 10),
//                     ),
//                   ),
//                 ),
//                 const SizedBox(width: 8),
//                 IconButton(
//                   icon: const Icon(Icons.send, color: const Color.fromARGB(255, 160, 195, 255)),
//                   onPressed: _sendMessage,
//                 ),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

