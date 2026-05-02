import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'discovery_service.dart';
import 'chat_service.dart';
import 'chat_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Listen to changes in ChatService to navigate when a connection is established (e.g., when receiving a request and accepting it)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chatService = context.read<ChatService>();
      chatService.addListener(_onChatServiceChanged);
    });
  }

  void _onChatServiceChanged() {
    final chatService = context.read<ChatService>();
    if (chatService.connectedPeer != null && ModalRoute.of(context)?.isCurrent == true) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const ChatScreen()),
      );
    }
  }

  @override
  void dispose() {
    // Only remove the listener if we are actually disposing the HomeScreen (which shouldn't happen often as it's the root)
    // However, for completeness:
    // context.read<ChatService>().removeListener(_onChatServiceChanged); // This might fail if provider is already disposed
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Local Chat'),
      ),
      body: Column(
        children: [
          // Connection Request Banner
          Consumer<ChatService>(
            builder: (context, chatService, child) {
              if (chatService.incomingRequest != null) {
                return Material(
                  color: Colors.blue.shade100,
                  child: ListTile(
                    title: Text('${chatService.incomingRequest!.peer.name} wants to connect'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.check, color: Colors.green),
                          onPressed: chatService.incomingRequest!.accept,
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.red),
                          onPressed: chatService.incomingRequest!.reject,
                        ),
                      ],
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),

          Expanded(
            child: Consumer2<DiscoveryService, ChatService>(
              builder: (context, discoveryService, chatService, child) {
                final peers = discoveryService.discoveredPeers;

                if (peers.isEmpty) {
                  return const Center(child: Text('Searching for peers...'));
                }

                return ListView.builder(
                  itemCount: peers.length,
                  itemBuilder: (context, index) {
                    final peer = peers[index];
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(peer.name),
                      subtitle: Text('${peer.ip}:${peer.port}'),
                      trailing: ElevatedButton(
                        onPressed: chatService.connectedPeer != null ? null : () async {
                          // Show loading indicator or handle connect
                          bool success = await chatService.connectTo(peer);
                          if (!success && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Connection failed or rejected')),
                            );
                          }
                          // Navigation is handled by the listener in initState
                        },
                        child: const Text('Connect'),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
