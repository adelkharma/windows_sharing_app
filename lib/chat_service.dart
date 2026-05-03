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
import 'package:path/path.dart' as p;
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

  // Track active file transfers
  final Map<String, FileAttachment> _activeTransfers = {};
  final Map<String, IOSink> _activeSinks = {};
  final Map<String, String> _activeFilePaths = {};

  bool _isChatFocused = true;

  ChatService({
    required this.localPeerId,
    required this.localPeerName,
  });

  void setChatFocus(bool focused) {
    _isChatFocused = focused;
    if (focused && _channel != null) {
      _sendReadReceipts();
    }
  }

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
          final type = data['type'];

          if (type == 'chat') {
            _handleChatData(data);
          } else if (type == 'file_meta') {
            _handleFileMeta(data);
          } else if (type == 'file_chunk') {
            _handleFileChunk(data);
          } else if (type == 'typing') {
            _peerIsTyping = data['isTyping'];
            notifyListeners();
          } else if (type == 'edit') {
            _handleEdit(data['id'], data['text']);
          } else if (type == 'delete') {
            _handleDelete(data['id']);
          } else if (type == 'ack') {
            _updateMessageStatus(data['id'], MessageStatus.delivered);
          } else if (type == 'read') {
            _updateMessageStatus(data['id'], MessageStatus.read);
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

  void _handleChatData(Map<String, dynamic> data) {
    final msgId = data['id'];
    List<FileAttachment> attachments = [];

    if (data['files'] != null) {
      for (var f in data['files']) {
        final attach = FileAttachment(
          id: f['id'],
          fileName: f['name'],
          totalBytes: f['size'],
        );
        attachments.add(attach);
        _activeTransfers[attach.id] = attach;
      }
    }

    final chatMsg = ChatMessage(
      id: msgId,
      text: data['text'] ?? '',
      isMine: false,
      timestamp: DateTime.parse(data['timestamp']),
      status: _isChatFocused ? MessageStatus.read : MessageStatus.delivered,
      files: attachments,
    );

    _messages.add(chatMsg);
    notifyListeners();

    // Send Ack
    _channel?.sink.add(jsonEncode({'type': 'ack', 'id': msgId}));

    if (_isChatFocused) {
      _channel?.sink.add(jsonEncode({'type': 'read', 'id': msgId}));
    }
  }

  Future<void> _handleFileMeta(Map<String, dynamic> data) async {
    final fileId = data['fileId'];
    final fileName = data['fileName'];

    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = p.join(dir.path, '${timestamp}_$fileName');

    final file = File(path);
    _activeSinks[fileId] = file.openWrite();
    _activeFilePaths[fileId] = path;
  }

  void _handleFileChunk(Map<String, dynamic> data) {
    final fileId = data['fileId'];
    final chunkBase64 = data['chunk'];
    final bytes = base64Decode(chunkBase64);
    final transferred = data['transferred'];
    final total = data['total'];

    final sink = _activeSinks[fileId];
    sink?.add(bytes);

    final attach = _activeTransfers[fileId];
    if (attach != null) {
      // Basic speed calc could go here, omitting for brevity
      attach.updateProgress(transferred, 0.0);

      if (transferred >= total) {
        sink?.close();
        _activeSinks.remove(fileId);
        final path = _activeFilePaths.remove(fileId);
        if (path != null) {
          attach.complete(path);
        }
        _activeTransfers.remove(fileId);
      }
    }
  }

  void _handleEdit(String id, String text) {
    final msg = _messages.cast<ChatMessage?>().firstWhere((m) => m?.id == id, orElse: () => null);
    if (msg != null) {
      msg.edit(text);
    }
  }

  void _handleDelete(String id) {
    final msg = _messages.cast<ChatMessage?>().firstWhere((m) => m?.id == id, orElse: () => null);
    if (msg != null) {
      msg.delete();
    }
  }

  void _updateMessageStatus(String id, MessageStatus status) {
    final msg = _messages.cast<ChatMessage?>().firstWhere((m) => m?.id == id, orElse: () => null);
    if (msg != null) {
      msg.updateStatus(status);
    }
  }

  void _sendReadReceipts() {
    for (var msg in _messages.where((m) => !m.isMine && m.status != MessageStatus.read)) {
      msg.updateStatus(MessageStatus.read);
      _channel?.sink.add(jsonEncode({'type': 'read', 'id': msg.id}));
    }
  }

  Future<void> sendFiles(List<File> files, {String text = ''}) async {
    if (_channel == null) return;

    final msgId = const Uuid().v4();
    List<FileAttachment> attachments = [];
    List<Map<String, dynamic>> filesMeta = [];

    for (var file in files) {
      final fileId = const Uuid().v4();
      final length = await file.length();
      final name = p.basename(file.path);

      final attach = FileAttachment(
        id: fileId,
        fileName: name,
        totalBytes: length,
        filePath: file.path,
        transferredBytes: length,
        isComplete: true,
      );
      attachments.add(attach);

      filesMeta.add({
        'id': fileId,
        'name': name,
        'size': length,
      });
    }

    final chatMsg = ChatMessage(
      id: msgId,
      text: text,
      isMine: true,
      timestamp: DateTime.now(),
      status: MessageStatus.sent,
      files: attachments,
    );

    _messages.add(chatMsg);
    notifyListeners();

    // 1. Send the chat message frame
    final payload = jsonEncode({
      'type': 'chat',
      'id': msgId,
      'text': text,
      'timestamp': chatMsg.timestamp.toIso8601String(),
      'files': filesMeta.isNotEmpty ? filesMeta : null,
    });
    _channel?.sink.add(payload);

    // 2. Send file data in chunks
    for (var i = 0; i < files.length; i++) {
      await _sendFileChunks(files[i], filesMeta[i]['id'], attachments[i]);
    }
  }

  Future<void> _sendFileChunks(File file, String fileId, FileAttachment attachment) async {
    final length = attachment.totalBytes;

    _channel?.sink.add(jsonEncode({
      'type': 'file_meta',
      'fileId': fileId,
      'fileName': attachment.fileName,
      'total': length,
    }));

    final stream = file.openRead();
    int transferred = 0;

    await for (var chunk in stream) {
      transferred += chunk.length;
      final base64Chunk = base64Encode(chunk);

      _channel?.sink.add(jsonEncode({
        'type': 'file_chunk',
        'fileId': fileId,
        'chunk': base64Chunk,
        'transferred': transferred,
        'total': length,
      }));

      // Let the event loop breathe
      await Future.delayed(Duration.zero);
    }
  }

  void sendMessage(String text) {
    if (_channel == null || text.trim().isEmpty) return;
    sendFiles([], text: text);
  }

  void editMessage(String id, String newText) {
    if (_channel == null) return;
    _handleEdit(id, newText);
    _channel?.sink.add(jsonEncode({
      'type': 'edit',
      'id': id,
      'text': newText,
    }));
  }

  void deleteMessage(String id) {
    if (_channel == null) return;
    _handleDelete(id);
    _channel?.sink.add(jsonEncode({
      'type': 'delete',
      'id': id,
    }));
  }

  void setTyping(bool isTyping) {
    if (_isTyping == isTyping || _channel == null) return;
    _isTyping = isTyping;
    _channel?.sink.add(jsonEncode({
      'type': 'typing',
      'isTyping': isTyping,
    }));
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
    _connectedPeer = null;
    _messages.clear();
    _incomingRequest = null;
    _peerIsTyping = false;
    _isTyping = false;
    for (var sink in _activeSinks.values) {
      sink.close();
    }
    _activeSinks.clear();
    _activeTransfers.clear();
    _activeFilePaths.clear();
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
