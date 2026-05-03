import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:mime/mime.dart';
import 'chat_service.dart';
import 'models.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final TextEditingController _textController = TextEditingController();
  bool _isDragging = false;
  String? _editingMsgId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ChatService>().setChatFocus(true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) {
      context.read<ChatService>().setChatFocus(state == AppLifecycleState.resumed);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _textController.dispose();
    super.dispose();
  }

  void _showContextMenu(BuildContext context, ChatMessage msg) {
    if (!msg.isMine || msg.isDeleted) return;

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Edit'),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _editingMsgId = msg.id;
                    _textController.text = msg.text;
                  });
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Delete', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  context.read<ChatService>().deleteMessage(msg.id);
                },
              ),
            ],
          ),
        );
      }
    );
  }

  Widget _buildStatusIcon(MessageStatus status) {
    switch (status) {
      case MessageStatus.pending:
        return const Icon(Icons.access_time, size: 12, color: Colors.grey);
      case MessageStatus.sent:
        return const Icon(Icons.check, size: 12, color: Colors.grey);
      case MessageStatus.delivered:
        return const Icon(Icons.done_all, size: 12, color: Colors.grey);
      case MessageStatus.read:
        return const Icon(Icons.done_all, size: 12, color: Colors.blue);
    }
  }

  Widget _buildFileAttachment(FileAttachment attach, bool isMine) {
    return ListenableBuilder(
      listenable: attach,
      builder: (context, _) {
        final isImage = lookupMimeType(attach.fileName)?.startsWith('image/') ?? false;

        Widget content;
        if (isImage && attach.isComplete && attach.filePath != null) {
          content = Image.file(
            File(attach.filePath!),
            height: 150,
            fit: BoxFit.cover,
          );
        } else {
          content = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.insert_drive_file, color: isMine ? Colors.white : Colors.black),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  attach.fileName,
                  style: TextStyle(
                    color: isMine ? Colors.white : Colors.black,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          );
        }

        return InkWell(
          onTap: attach.isComplete && attach.filePath != null ? () => OpenFilex.open(attach.filePath!) : null,
          child: Container(
            margin: const EdgeInsets.only(top: 4),
            padding: isImage ? EdgeInsets.zero : const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isMine ? Colors.blue.shade700 : Colors.grey.shade400,
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                content,
                if (!attach.isComplete)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Column(
                      children: [
                        LinearProgressIndicator(
                          value: attach.totalBytes == 0 ? 0 : attach.transferredBytes / attach.totalBytes,
                          backgroundColor: Colors.white24,
                          valueColor: AlwaysStoppedAnimation<Color>(isMine ? Colors.white : Colors.blue),
                        ),
                        // Omitted speed calculation text for brevity, but progress bar is present
                      ],
                    ),
                  )
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          context.read<ChatService>().setChatFocus(false);
          context.read<ChatService>().disconnect();
        }
      },
      child: DropTarget(
        onDragEntered: (details) => setState(() => _isDragging = true),
        onDragExited: (details) => setState(() => _isDragging = false),
        onDragDone: (details) {
          setState(() => _isDragging = false);
          if (details.files.isNotEmpty) {
            final files = details.files.map((x) => File(x.path)).toList();
            context.read<ChatService>().sendFiles(files);
          }
        },
        child: Scaffold(
          appBar: AppBar(
            title: Consumer<ChatService>(
              builder: (context, chatService, child) {
                final peerName = chatService.connectedPeer?.name ?? 'Unknown';
                return Text('Chat with $peerName');
              },
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.exit_to_app),
                onPressed: () {
                  context.read<ChatService>().setChatFocus(false);
                  context.read<ChatService>().disconnect();
                  Navigator.pop(context);
                },
              )
            ],
          ),
          body: Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: Consumer<ChatService>(
                      builder: (context, chatService, child) {
                        final messages = chatService.messages;
                        return ListView.builder(
                          reverse: true,
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final msg = messages[messages.length - 1 - index];
                            return ListenableBuilder(
                              listenable: msg,
                              builder: (context, _) {
                                return GestureDetector(
                                  onLongPress: () => _showContextMenu(context, msg),
                                  child: Align(
                                    alignment: msg.isMine ? Alignment.centerRight : Alignment.centerLeft,
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: msg.isMine ? Colors.blue : Colors.grey[300],
                                        borderRadius: BorderRadius.circular(16),
                                        border: msg.isDeleted ? Border.all(color: Colors.red, width: 1) : null,
                                      ),
                                      child: Column(
                                        crossAxisAlignment: msg.isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                        children: [
                                          if (msg.text.isNotEmpty)
                                            Text(
                                              msg.text,
                                              style: TextStyle(
                                                color: msg.isMine ? Colors.white : Colors.black,
                                                fontStyle: msg.isDeleted ? FontStyle.italic : FontStyle.normal,
                                              ),
                                            ),
                                          if (msg.files.isNotEmpty)
                                            ...msg.files.map((f) => _buildFileAttachment(f, msg.isMine)),
                                          const SizedBox(height: 4),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (msg.isEdited && !msg.isDeleted)
                                                Text(
                                                  '(edited) ',
                                                  style: TextStyle(fontSize: 10, color: msg.isMine ? Colors.white70 : Colors.black54),
                                                ),
                                              Text(
                                                '${msg.timestamp.hour}:${msg.timestamp.minute.toString().padLeft(2, '0')}',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: msg.isMine ? Colors.white70 : Colors.black54,
                                                ),
                                              ),
                                              if (msg.isMine) ...[
                                                const SizedBox(width: 4),
                                                _buildStatusIcon(msg.status),
                                              ]
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }
                            );
                          },
                        );
                      },
                    ),
                  ),
                  Consumer<ChatService>(
                    builder: (context, chatService, child) {
                      if (chatService.peerIsTyping) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text('Typing...', style: TextStyle(fontStyle: FontStyle.italic)),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                  if (_editingMsgId != null)
                    Container(
                      color: Colors.yellow.shade100,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.edit, size: 16),
                          const SizedBox(width: 8),
                          const Expanded(child: Text('Editing message')),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              setState(() {
                                _editingMsgId = null;
                                _textController.clear();
                              });
                            },
                          )
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.attach_file),
                          onPressed: () async {
                            FilePickerResult? result = await FilePicker.pickFiles(allowMultiple: true);
                            if (result != null) {
                              final files = result.paths.whereType<String>().map((p) => File(p)).toList();
                              if (context.mounted && files.isNotEmpty) {
                                context.read<ChatService>().sendFiles(files);
                              }
                            }
                          },
                        ),
                        Expanded(
                          child: TextField(
                            controller: _textController,
                            onChanged: (text) {
                              context.read<ChatService>().setTyping(text.isNotEmpty);
                            },
                            decoration: const InputDecoration(
                              hintText: 'Enter message...',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.send),
                          onPressed: () {
                            final text = _textController.text;
                            if (text.trim().isNotEmpty) {
                              if (_editingMsgId != null) {
                                context.read<ChatService>().editMessage(_editingMsgId!, text);
                                setState(() => _editingMsgId = null);
                              } else {
                                context.read<ChatService>().sendMessage(text);
                              }
                              _textController.clear();
                              context.read<ChatService>().setTyping(false);
                            }
                          },
                        )
                      ],
                    ),
                  ),
                ],
              ),
              if (_isDragging)
                Container(
                  color: Colors.black54,
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.upload_file, size: 64, color: Colors.white),
                        SizedBox(height: 16),
                        Text('Drop files to send', style: TextStyle(color: Colors.white, fontSize: 24)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
