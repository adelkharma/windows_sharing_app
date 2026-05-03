import 'package:flutter/foundation.dart';

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

enum MessageStatus { pending, sent, delivered, read }

class FileAttachment extends ChangeNotifier {
  final String id;
  final String fileName;
  final int totalBytes;

  String? filePath;
  int transferredBytes;
  double speedBytesPerSecond;
  bool isComplete;

  FileAttachment({
    required this.id,
    required this.fileName,
    required this.totalBytes,
    this.filePath,
    this.transferredBytes = 0,
    this.speedBytesPerSecond = 0.0,
    this.isComplete = false,
  });

  void updateProgress(int transferred, double speed) {
    transferredBytes = transferred;
    speedBytesPerSecond = speed;
    if (transferredBytes >= totalBytes) {
      isComplete = true;
    }
    notifyListeners();
  }

  void complete(String path) {
    filePath = path;
    isComplete = true;
    transferredBytes = totalBytes;
    notifyListeners();
  }
}

class ChatMessage extends ChangeNotifier {
  final String id;
  String text;
  final bool isMine;
  final DateTime timestamp;

  MessageStatus status;
  bool isEdited;
  bool isDeleted;

  List<FileAttachment> files;

  ChatMessage({
    required this.id,
    required this.text,
    required this.isMine,
    required this.timestamp,
    this.status = MessageStatus.pending,
    this.isEdited = false,
    this.isDeleted = false,
    List<FileAttachment>? files,
  }) : files = files ?? [];

  void edit(String newText) {
    text = newText;
    isEdited = true;
    notifyListeners();
  }

  void delete() {
    isDeleted = true;
    text = "This message was deleted";
    files.clear();
    notifyListeners();
  }

  void updateStatus(MessageStatus newStatus) {
    if (status.index < newStatus.index) {
      status = newStatus;
      notifyListeners();
    }
  }
}
