# Local Wi-Fi Chat App: Source of Truth

## Section 1: Developer Overview (For Humans)

### System Architecture
This is a peer-to-peer (P2P) local area network application built in Flutter. It consists of two main background services:
1.  **Discovery Service**: Uses UDP broadcasting on port 8888. It constantly announces its presence to the local network (`255.255.255.255`) and listens for announcements from other peers to build a list of available devices.
2.  **Chat Service**: Runs an HTTP server on port 9999. When a peer requests a connection, it holds the HTTP request until the user approves or rejects it. If approved, the connection is upgraded to a WebSocket for real-time, bidirectional communication (messages, typing indicators, and file transfers).

### Tech Stack
*   **Framework**: Flutter (Supports Windows, Linux, Android)
*   **State Management**: `provider` (ChangeNotifier)
*   **Networking**:
    *   `dart:io` (RawDatagramSocket for UDP, HttpServer for HTTP/WebSockets)
    *   `shelf` & `shelf_web_socket` (HTTP routing and WebSocket upgrade)
    *   `web_socket_channel` (WebSocket client implementation)
*   **Utilities**:
    *   `uuid` (Generating unique message and device IDs)
    *   `file_picker` (Selecting files from the OS)
    *   `path_provider` (Getting OS-specific storage directories)
    *   `open_filex` (Opening files with default OS applications)

### Data Flow
1.  **Discovery**: App starts -> Binds UDP socket -> Broadcasts JSON (id, name, port) -> Receives JSON from others -> Updates `DiscoveryService` state -> UI updates.
2.  **Connection**: User clicks "Connect" -> HTTP GET request sent to peer's port 9999 -> Peer's `ChatService` halts request, shows UI banner -> Peer clicks Accept -> Server responds with 101 Switching Protocols -> Both sides establish `WebSocketChannel` -> UI navigates to `ChatScreen`.
3.  **Messaging/Files**: User sends text or file -> Data is JSON serialized (files are Base64 encoded) -> Sent over WebSocket -> Receiver decodes JSON -> (If file, decodes Base64 and writes to disk) -> Updates `ChatService` state -> UI updates.

### Key Design Patterns
*   **Provider/ChangeNotifier**: Used extensively for reactive UI updates decoupled from business logic. Services act as ViewModels.
*   **Service Layer**: Network logic is isolated in `DiscoveryService` and `ChatService`, keeping the UI layer (`HomeScreen`, `ChatScreen`) clean.
*   **Completer/Bridge**: Used a `Completer` (`ErrorBridgeCompleter`) to bridge asynchronous HTTP request handling with synchronous user UI interaction for connection approvals.

---

## Section 2: AI Blueprint (For Machine Reproduction)

### Logic Specifications

#### 1. Peer Discovery (UDP)
*   **Bind**: `RawDatagramSocket.bind(InternetAddress.anyIPv4, 8888)`. Ensure `broadcastEnabled = true`.
*   **Listen**: On `RawSocketEvent.read`, `receive()` datagram. Decode UTF-8 -> Decode JSON. If `id` != `localPeerId` and not in list, add to list and notify listeners.
*   **Broadcast**: Run a continuous loop (`while(socket != null)`). Encode `{id, name, chatPort}` as JSON. `send()` to `255.255.255.255` on port 8888 every 3 seconds.

#### 2. Connection Handshake (HTTP to WebSocket)
*   **Server**: Bind `shelf_io` to port 9999.
*   **Router**: Listen on `/connect`. Require query params `id` and `name`.
*   **Approval Flow**:
    1. Check if already connected (return 403 if true).
    2. Create a `Completer<bool>`.
    3. Expose `ConnectionRequest(peer, accept(), reject())` to UI state.
    4. Wait for `completer.future`.
    5. If false, return 403.
    6. If true, use `webSocketHandler` to upgrade the request and attach the `WebSocketChannel`.
*   **Client**: Connect using `WebSocketChannel.connect(Uri.parse('ws://<ip>:9999/connect?id=<myId>&name=<myName>'))`. Await `ready`.

#### 3. WebSocket Data Handling
*   **Listen**: `channel.stream.listen()`. Parse JSON.
*   **Chat Message**: If `type == 'chat'`.
    *   If `isFile == true`: Get `fileName` and `fileData` (Base64). Decode Base64. Get `getApplicationDocumentsDirectory()`. Save file as `<timestamp>_<fileName>`.
    *   Add `ChatMessage` to memory list. Notify listeners.
*   **Typing**: If `type == 'typing'`. Update `peerIsTyping` boolean. Notify listeners.

#### 4. Sending Files
*   Read file as bytes: `file.readAsBytes()`.
*   Encode to Base64: `base64Encode(bytes)`.
*   Construct JSON payload: `{type: 'chat', id: <uuid>, text: '...', isFile: true, fileName: <name>, fileData: <base64>, timestamp: <iso8601>}`.
*   Send over WebSocket sink. Add to local message list.

### State Management
*   **`main.dart`**: Initializes `ChatService` and `DiscoveryService` with local device ID (UUID) and Hostname. Wraps app in `MultiProvider`.
*   **`DiscoveryService`**: Holds `List<Peer> discoveredPeers`. Notifies when a new unique peer is detected.
*   **`ChatService`**: Holds `List<ChatMessage> messages`, `ConnectionRequest? incomingRequest`, `Peer? connectedPeer`, `bool isTyping`, `bool peerIsTyping`. Notifies on message receipt, connection state changes, and typing state changes.
*   **Navigation**: `HomeScreen` listens to `ChatService`. If `connectedPeer` becomes non-null, it pushes `ChatScreen`.
*   **Disconnection**: `ChatScreen` uses `PopScope`. On pop (back button), it calls `ChatService.disconnect()`, which closes the socket and clears state.

### API & Schema Definitions

#### UDP Broadcast Payload
```json
{
  "id": "uuid-v4-string",
  "name": "Device Hostname",
  "chatPort": 9999
}
```

#### WebSocket Payload: Chat Message (Text)
```json
{
  "type": "chat",
  "id": "uuid-v4-string",
  "text": "Hello world",
  "timestamp": "2023-10-27T10:00:00.000Z",
  "isFile": false
}
```

#### WebSocket Payload: Chat Message (File)
```json
{
  "type": "chat",
  "id": "uuid-v4-string",
  "text": "Sent a file: image.png",
  "timestamp": "2023-10-27T10:00:00.000Z",
  "isFile": true,
  "fileName": "image.png",
  "fileData": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
}
```

#### WebSocket Payload: Typing Indicator
```json
{
  "type": "typing",
  "isTyping": true
}
```

### Edge Cases & Constraints
1.  **Duplicate Files**: When receiving a file, the app MUST prepend the current timestamp to the filename before saving to disk to prevent silent overwrites of files with the same name.
2.  **Navigation Lock**: The application MUST navigate the user to the `ChatScreen` immediately upon the `completer.future` resolving to true during the connection handshake.
3.  **Ghost Connections**: The application MUST explicitly close the `WebSocketChannel` (`sink.close()`) and clear the `connectedPeer` state when navigating away from the `ChatScreen` to free the port and allow future connections.
4.  **Network Permissions**: For Android, `<uses-permission android:name="android.permission.INTERNET"/>` MUST be present in `src/main/AndroidManifest.xml` for socket connections to succeed in release mode.
5.  **Symmetric Ports**: The design assumes the chat server always runs on port 9999 for both the initiator and receiver.
