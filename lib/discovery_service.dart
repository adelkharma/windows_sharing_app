import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'models.dart';

class DiscoveryService extends ChangeNotifier {
  static const int port = 8888;
  RawDatagramSocket? _socket;

  final String localPeerId;
  final String localPeerName;
  final int chatPort;

  final List<Peer> _discoveredPeers = [];
  List<Peer> get discoveredPeers => _discoveredPeers;

  DiscoveryService({
    required this.localPeerId,
    required this.localPeerName,
    required this.chatPort,
  });

  Future<void> start() async {
    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
      _socket?.broadcastEnabled = true;
      _socket?.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          Datagram? datagram = _socket?.receive();
          if (datagram != null) {
            _handleDatagram(datagram);
          }
        }
      });
      _broadcastPresence();
    } catch (e) {
      debugPrint('Discovery bind error: $e');
    }
  }

  void _handleDatagram(Datagram datagram) {
    try {
      final String message = utf8.decode(datagram.data);
      final Map<String, dynamic> data = jsonDecode(message);

      if (data['id'] != localPeerId) {
        final peer = Peer(
          id: data['id'],
          name: data['name'],
          ip: datagram.address.address,
          port: data['chatPort'],
        );

        if (!_discoveredPeers.contains(peer)) {
          _discoveredPeers.add(peer);
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Datagram handle error: $e');
    }
  }

  void _broadcastPresence() async {
    while (_socket != null) {
      try {
        final message = jsonEncode({
          'id': localPeerId,
          'name': localPeerName,
          'chatPort': chatPort,
        });
        final List<int> data = utf8.encode(message);

        // Broadcast to 255.255.255.255
        _socket?.send(data, InternetAddress('255.255.255.255'), port);

        // Also broadcast to network-specific broadcast addresses if possible
        // This is a simple broadcast that usually works on local networks
      } catch (e) {
        debugPrint('Broadcast error: $e');
      }
      await Future.delayed(const Duration(seconds: 3));
    }
  }

  @override
  void dispose() {
    _socket?.close();
    _socket = null;
    super.dispose();
  }
}
