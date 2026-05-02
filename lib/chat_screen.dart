import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'chat_service.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          context.read<ChatService>().disconnect();
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
              context.read<ChatService>().disconnect();
              Navigator.pop(context);
            },
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Consumer<ChatService>(
              builder: (context, chatService, child) {
                final messages = chatService.messages;
                return ListView.builder(
                  reverse: true, // Show latest at the bottom
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    // Reversed index
                    final msg = messages[messages.length - 1 - index];
                    return Align(
                      alignment: msg.isMine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: msg.isMine ? Colors.blue : Colors.grey[300],
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: msg.isFile
                            ? InkWell(
                                onTap: () {
                                  if (msg.filePath != null) {
                                    OpenFilex.open(msg.filePath!);
                                  }
                                },
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.insert_drive_file,
                                      color: msg.isMine ? Colors.white : Colors.black,
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        msg.fileName ?? 'Unknown file',
                                        style: TextStyle(
                                          color: msg.isMine ? Colors.white : Colors.black,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : Text(
                                msg.text,
                                style: TextStyle(
                                  color: msg.isMine ? Colors.white : Colors.black,
                                ),
                              ),
                      ),
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
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file),
                  onPressed: () async {
                    FilePickerResult? result = await FilePicker.pickFiles();
                    if (result != null && result.files.single.path != null) {
                      File file = File(result.files.single.path!);
                      String fileName = result.files.single.name;
                      if (context.mounted) {
                        context.read<ChatService>().sendFile(file, fileName);
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
                      context.read<ChatService>().sendMessage(text);
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
    ));
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }
}
