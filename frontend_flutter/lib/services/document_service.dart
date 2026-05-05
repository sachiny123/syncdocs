import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:diff_match_patch/diff_match_patch.dart';

class DocumentService {
  final String docId;
  final String username;
  final String color;
  final Function(String, {String? color}) onContentUpdate;
  final Function(List<Map<String, dynamic>>) onPresenceUpdate;
  final Function(Map<String, dynamic>) onCursorUpdate;

  WebSocketChannel? _channel;
  final dmp = DiffMatchPatch();
  String _currentText = '';
  bool _connected = false;

  DocumentService({
    required this.docId,
    required this.username,
    required this.color,
    required this.onContentUpdate,
    required this.onPresenceUpdate,
    required this.onCursorUpdate,
  });

  void connect() {
    final encodedUser = Uri.encodeComponent(username);
    final encodedColor = Uri.encodeComponent(color);
    final url =
        'ws://localhost:8000/ws/document/$docId?username=$encodedUser&color=$encodedColor';

    print('[WS] Connecting to $url');

    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _connected = true;

      _channel!.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message as String);
            _handleMessage(data);
          } catch (e) {
            print('[WS] Parse error: $e');
          }
        },
        onError: (error) => print('[WS] Error: $error'),
        onDone: () {
          print('[WS] Connection closed');
          _connected = false;
        },
      );
    } catch (e) {
      print('[WS] Setup failed: $e');
      _connected = false;
    }
  }

  void _handleMessage(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    switch (type) {
      case 'init':
        _currentText = (data['content'] as String?) ?? '';
        onContentUpdate(_currentText);
        onPresenceUpdate(
          List<Map<String, dynamic>>.from(data['active_users'] ?? []),
        );
        break;
      case 'presence':
        onPresenceUpdate(
          List<Map<String, dynamic>>.from(data['active_users'] ?? []),
        );
        break;
      case 'patch':
        try {
          final patches = patchFromText(data['patch'] as String);
          final results = dmp.patch_apply(patches, _currentText);
          _currentText = results[0] as String;
          onContentUpdate(_currentText, color: data['color'] as String?);
        } catch (e) {
          print('[WS] Patch apply error: $e');
        }
        break;
      case 'cursor':
        onCursorUpdate(data);
        break;
    }
  }

  void sendUpdate(String newText) {
    if (!_connected || _channel == null || newText == _currentText) return;
    try {
      final patches = dmp.patch(_currentText, newText);
      final patchText = patchToText(patches);
      _currentText = newText;
      _channel!.sink.add(jsonEncode({'type': 'patch', 'patch': patchText}));
    } catch (e) {
      print('[WS] Send update error: $e');
    }
  }

  void sendCursorUpdate(int position) {
    if (!_connected || _channel == null) return;
    try {
      _channel!.sink.add(jsonEncode({'type': 'cursor', 'cursor': position}));
    } catch (e) {
      print('[WS] Cursor error: $e');
    }
  }

  void disconnect() {
    _connected = false;
    _channel?.sink.close();
  }
}
