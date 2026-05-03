# Local Wi-Fi Chat App: Source of Truth

## Section 1: Developer Overview (For Humans)

### System Architecture
This is a peer-to-peer (P2P) local area network application built in Flutter. It consists of two main background services:
1.  **Discovery Service**: Uses UDP broadcasting on port 8888. It constantly announces its presence to the local network (`255.255.255.255`) and listens for announcements from other peers to build a list of available devices.
2.  **Chat Service**: Runs an HTTP server on port 9999. When a peer requests a connection, it holds the HTTP request until the user approves or rejects it. If approved, the connection is upgraded to a WebSocket for real-time, bidirectional communication.

### Tech Stack
*   **Framework**: Flutter (Supports Windows, Linux, Android)
*   **State Management**: `provider` (ChangeNotifier)
*   **Networking**:
    *   `dart:io` (RawDatagramSocket, HttpServer)
    *   `shelf` & `shelf_web_socket` (HTTP routing and WebSocket upgrade)
    *   `web_socket_channel` (WebSocket client)
*   **Utilities**:
    *   `uuid` (Unique IDs)
    *   `file_picker` & `desktop_drop` (File selection and drag-and-drop)
    *   `path_provider` & `path` (File system management)
    *   `open_filex` & `mime` (Opening files and detecting images for inline preview)

### Data Flow
1.  **Discovery**: Binds UDP socket -> Broadcasts JSON -> Receives JSON -> Updates `DiscoveryService`.
2.  **Connection**: Client sends HTTP GET -> Server pauses -> User accepts -> Upgrades to WebSocket -> UI navigates to `ChatScreen`.
3.  **Messaging**: Text and meta-data are sent via JSON. File transfers are broken into Base64 encoded chunks.
4.  **Message Status**: Messages support `pending`, `sent`, `delivered` (ack), and `read` statuses. Focus events in the `ChatScreen` trigger read receipts.
5.  **Edit/Delete**: Sending an edit or delete frame updates the local memory model, which triggers a UI rebuild via `ListenableBuilder` on the specific `ChatMessage`.

### Key Design Patterns
*   **Provider/ChangeNotifier**: Services act as ViewModels. Individual `ChatMessage` and `FileAttachment` objects are also `ChangeNotifier`s to allow granular UI updates (like file progress) without rebuilding the entire list.
*   **Chunked Transfer**: Large files are sent in 64KB Base64 chunks to prevent memory exhaustion and allow progress tracking.

---

## Section 2: AI Blueprint (For Machine Reproduction)

### Logic Specifications

#### 1. Peer Discovery (UDP)
*   `RawDatagramSocket.bind(InternetAddress.anyIPv4, 8888)` with `broadcastEnabled = true`. Send `{id, name, chatPort}` to `255.255.255.255` every 3s.

#### 2. Connection Handshake (HTTP to WebSocket)
*   Bind `shelf_io` to 9999. Route `/connect` requiring `id` and `name`. Bridge UI acceptance using `Completer`. Upgrade with `webSocketHandler`.

#### 3. Message Status & Read Receipts
*   **Ack**: Receiver parses `chat` frame, immediately replies with `{type: 'ack', id: <msgId>}`.
*   **Read**: If receiver's `ChatScreen` has focus (tracked via `AppLifecycleState` and `WidgetsBindingObserver`), reply with `{type: 'read', id: <msgId>}`. When sender receives these, it updates `MessageStatus` enum.

#### 4. File Transfers (Chunked)
1.  Sender creates UUID for each file.
2.  Sender sends `chat` frame with `files` metadata array `[{id, name, size}]`.
3.  Sender iterates files, sending `file_meta` frame `{fileId, fileName, total}`.
4.  Receiver opens `IOSink` at `getApplicationDocumentsDirectory() / <timestamp>_<fileName>`.
5.  Sender reads file in 64KB chunks, Base64 encodes, and sends `file_chunk` frame `{fileId, chunk, transferred, total}`.
6.  Receiver decodes Base64, adds to sink, updates `FileAttachment` progress. If `transferred >= total`, closes sink and marks complete.

#### 5. Edit and Delete
*   **Edit**: Send `{type: 'edit', id: <msgId>, text: <newText>}`. Receiver finds message by ID, updates text, sets `isEdited = true`.
*   **Delete**: Send `{type: 'delete', id: <msgId>}`. Receiver finds message, clears files, sets `text = "This message was deleted"`, sets `isDeleted = true`.

### State Management
*   **`ChatService`**: Manages `List<ChatMessage>`, `_activeTransfers`, `_activeSinks`.
*   **`ChatMessage` (ChangeNotifier)**: Notifies on edit, delete, or status change.
*   **`FileAttachment` (ChangeNotifier)**: Notifies on progress bytes update or completion.

### API & Schema Definitions

#### WebSocket Payload: Chat Message (Multiple Files)
```json
{
  "type": "chat",
  "id": "msg-uuid",
  "text": "Check these out",
  "timestamp": "2023-10-27T10:00:00.000Z",
  "files": [
    {"id": "file1-uuid", "name": "image.png", "size": 102400},
    {"id": "file2-uuid", "name": "doc.pdf", "size": 5000}
  ]
}
```

#### WebSocket Payload: File Chunking
```json
// Meta
{"type": "file_meta", "fileId": "file1-uuid", "fileName": "image.png", "total": 102400}
// Chunk
{"type": "file_chunk", "fileId": "file1-uuid", "chunk": "iVBORw0K...", "transferred": 65536, "total": 102400}
```

#### WebSocket Payload: Status Updates
```json
{"type": "ack", "id": "msg-uuid"}
{"type": "read", "id": "msg-uuid"}
{"type": "edit", "id": "msg-uuid", "text": "New text"}
{"type": "delete", "id": "msg-uuid"}
```

### Edge Cases & Constraints
1.  **Duplicate Files**: Receiver MUST prepend `DateTime.now().millisecondsSinceEpoch` to incoming filenames.
2.  **Navigation Lock**: The app MUST navigate to `ChatScreen` dynamically on approval and MUST explicitly `disconnect()` on route pop to free resources.
3.  **UI Updates**: `ChatScreen` MUST use `ListenableBuilder` for individual `ChatMessage` and `FileAttachment` objects to prevent massive list re-renders during high-frequency chunk transfers.
4.  **Drag and Drop**: `DropTarget` from `desktop_drop` handles external files, passing paths directly to `sendFiles(List<File>)`.