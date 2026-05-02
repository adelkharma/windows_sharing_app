class Peer {
  final String id;
  final String name;
  final String ip;
  final int port;

  Peer({
    required this.id,
    required this.name,
    required this.ip,
    required this.port,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Peer && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class ChatMessage {
  final String id;
  final String text;
  final bool isMine;
  final DateTime timestamp;
  final bool isFile;
  final String? fileName;
  final String? filePath;

  ChatMessage({
    required this.id,
    required this.text,
    required this.isMine,
    required this.timestamp,
    this.isFile = false,
    this.fileName,
    this.filePath,
  });
}
