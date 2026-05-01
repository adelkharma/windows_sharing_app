import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'discovery_service.dart';
import 'chat_service.dart';
import 'home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final String deviceId = const Uuid().v4();
  final String deviceName = Platform.localHostname;

  final chatService = ChatService(
    localPeerId: deviceId,
    localPeerName: deviceName,
  );

  final discoveryService = DiscoveryService(
    localPeerId: deviceId,
    localPeerName: deviceName,
    chatPort: ChatService.port,
  );

  // Start background services
  await chatService.startServer();
  await discoveryService.start();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: discoveryService),
        ChangeNotifierProvider.value(value: chatService),
      ],
      child: const ChatApp(),
    ),
  );
}

class ChatApp extends StatelessWidget {
  const ChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Local Wi-Fi Chat',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
