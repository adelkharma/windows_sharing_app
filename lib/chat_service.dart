import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';
import 'models.dart';

class ConnectionRequest {
  final Peer peer;
  final Function() accept;
  final Function() reject;

  ConnectionRequest({required this.peer, required this.accept, required this.reject});
}

class ChatService extends ChangeNotifier {
  static const int port = 9999;

  final String localPeerId;
  final String localPeerName;

  HttpServer? _server;
  WebSocketChannel? _channel;

  Peer? _connectedPeer;
  Peer? get connectedPeer => _connectedPeer;

  final List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => _messages;

  ConnectionRequest? _incomingRequest;
  ConnectionRequest? get incomingRequest => _incomingRequest;

  bool _isTyping = false;
  bool get isTyping => _isTyping;

  bool _peerIsTyping = false;
  bool get peerIsTyping => _peerIsTyping;

  ChatService({
    required this.localPeerId,
    required this.localPeerName,
  });

  Future<void> startServer() async {
    var handler = const Pipeline().addHandler(_router);
    try {
      _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
      debugPrint('Chat server listening on port ${_server?.port}');
    } catch (e) {
      debugPrint('Chat server error: $e');
    }
  }

  Future<Response> _router(Request request) async {
    if (request.url.path == 'connect') {
      final peerId = request.url.queryParameters['id'];
      final peerName = request.url.queryParameters['name'];

      if (peerId == null || peerName == null) {
        return Response.badRequest(body: 'Missing parameters');
      }

      final peer = Peer(
        id: peerId,
        name: peerName,
        ip: (request.context['shelf.io.connection_info'] as HttpConnectionInfo).remoteAddress.address,
        port: port, // Assume symmetric ports
      );

      return _handleConnectionRequest(peer, request);
    }

    return Response.notFound('Not found');
  }

  Future<Response> _handleConnectionRequest(Peer peer, Request request) async {
    if (_connectedPeer != null) {
      return Response.forbidden('Already connected');
    }

    // Await user approval
    var completer = ErrorBridgeCompleter<bool>();

    _incomingRequest = ConnectionRequest(
      peer: peer,
      accept: () {
        completer.complete(true);
      },
      reject: () {
        completer.complete(false);
      }
    );
    notifyListeners();

    final accepted = await completer.future;

    _incomingRequest = null;
    notifyListeners();

    if (accepted) {
      _connectedPeer = peer;
      notifyListeners();

      var wsHandler = webSocketHandler((WebSocketChannel webSocket, String? protocol) {
        _setupChannel(webSocket);
      });
      return await wsHandler(request);
    } else {
      return Response.forbidden('Rejected');
    }
  }

  Future<bool> connectTo(Peer peer) async {
    try {
      final uri = Uri.parse('ws://${peer.ip}:${peer.port}/connect?id=$localPeerId&name=${Uri.encodeComponent(localPeerName)}');
      final channel = WebSocketChannel.connect(uri);

      // Wait a bit to see if connection is established or rejected
      await channel.ready;

      _connectedPeer = peer;
      _setupChannel(channel);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Connection error: $e');
      return false;
    }
  }

  void _setupChannel(WebSocketChannel channel) {
    _channel = channel;
    _channel?.stream.listen(
      (message) async {
        try {
          final data = jsonDecode(message);
          if (data['type'] == 'chat') {
            final isFile = data['isFile'] == true;
            String? savedFilePath;

            if (isFile) {
              final fileName = data['fileName'];
              final fileData = data['fileData']; // Base64

              if (fileName != null && fileData != null) {
                try {
                  final dir = await getApplicationDocumentsDirectory();
                  final timestamp = DateTime.now().millisecondsSinceEpoch;
                  final uniqueFileName = '${timestamp}_$fileName';
                  final file = File('${dir.path}/$uniqueFileName');
                  await file.writeAsBytes(base64Decode(fileData));
                  savedFilePath = file.path;
                } catch (e) {
                  debugPrint('Error saving file: $e');
                }
              }
            }

            final chatMsg = ChatMessage(
              id: data['id'],
              text: data['text'],
              isMine: false,
              timestamp: DateTime.parse(data['timestamp']),
              isFile: isFile,
              fileName: data['fileName'],
              filePath: savedFilePath,
            );
            _messages.add(chatMsg);
            notifyListeners();
          } else if (data['type'] == 'typing') {
            _peerIsTyping = data['isTyping'];
            notifyListeners();
          }
        } catch (e) {
          debugPrint('Error parsing message: $e');
        }
      },
      onDone: () {
        disconnect();
      },
      onError: (error) {
        debugPrint('WebSocket error: $error');
        disconnect();
      }
    );
  }

  void sendMessage(String text) {
    if (_channel == null || text.trim().isEmpty) return;

    final chatMsg = ChatMessage(
      id: const Uuid().v4(),
      text: text,
      isMine: true,
      timestamp: DateTime.now(),
    );

    _messages.add(chatMsg);
    notifyListeners();

    final payload = jsonEncode({
      'type': 'chat',
      'id': chatMsg.id,
      'text': chatMsg.text,
      'timestamp': chatMsg.timestamp.toIso8601String(),
      'isFile': false,
    });

    _channel?.sink.add(payload);
  }

  Future<void> sendFile(File file, String fileName) async {
    if (_channel == null) return;

    try {
      final bytes = await file.readAsBytes();
      final base64Data = base64Encode(bytes);

      final chatMsg = ChatMessage(
        id: const Uuid().v4(),
        text: 'Sent a file: $fileName',
        isMine: true,
        timestamp: DateTime.now(),
        isFile: true,
        fileName: fileName,
        filePath: file.path,
      );

      _messages.add(chatMsg);
      notifyListeners();

      final payload = jsonEncode({
        'type': 'chat',
        'id': chatMsg.id,
        'text': chatMsg.text,
        'timestamp': chatMsg.timestamp.toIso8601String(),
        'isFile': true,
        'fileName': fileName,
        'fileData': base64Data,
      });

      _channel?.sink.add(payload);
    } catch (e) {
      debugPrint('Error sending file: $e');
    }
  }

  void setTyping(bool isTyping) {
    if (_isTyping == isTyping || _channel == null) return;

    _isTyping = isTyping;

    final payload = jsonEncode({
      'type': 'typing',
      'isTyping': isTyping,
    });

    _channel?.sink.add(payload);
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
    _connectedPeer = null;
    _messages.clear();
    _incomingRequest = null;
    _peerIsTyping = false;
    _isTyping = false;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    _server?.close();
    super.dispose();
  }
}

class ErrorBridgeCompleter<T> {
  final Completer<T> _completer = Completer<T>();
  Future<T> get future => _completer.future;
  void complete(T value) {
    if (!_completer.isCompleted) {
      _completer.complete(value);
    }
  }
}
