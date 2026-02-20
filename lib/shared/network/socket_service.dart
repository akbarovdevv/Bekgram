import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import 'api_config.dart';

class SocketService {
  SocketService();

  io.Socket? _socket;
  String? _lastToken;
  bool _isConnecting = false;

  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _chatUpdateController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _presenceController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _messageReadController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _messageDeletedController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _chatDeletedController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  Stream<Map<String, dynamic>> get chatUpdateStream =>
      _chatUpdateController.stream;

  Stream<Map<String, dynamic>> get presenceStream => _presenceController.stream;
  Stream<Map<String, dynamic>> get messageReadStream =>
      _messageReadController.stream;
  Stream<Map<String, dynamic>> get messageDeletedStream =>
      _messageDeletedController.stream;
  Stream<Map<String, dynamic>> get chatDeletedStream =>
      _chatDeletedController.stream;

  bool get isConnected => _socket?.connected ?? false;

  void connect(String token) {
    final existing = _socket;
    if (existing != null) {
      final sameToken = _lastToken == token;
      final state = existing.io.engine?.readyState ?? '';
      final isOpening = state == 'opening';
      final isOpen = existing.connected || state == 'open';
      if (sameToken && (isOpen || isOpening || _isConnecting)) return;

      existing.disconnect();
      existing.dispose();
      _socket = null;
    }

    _lastToken = token;
    _isConnecting = true;

    final socket = io.io(
      ApiConfig.socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .enableReconnection()
          .disableAutoConnect()
          .setAuth({'token': token})
          .build(),
    );

    socket.on('connect', (_) {
      _isConnecting = false;
    });
    socket.on('connect_error', (_) {
      _isConnecting = false;
    });
    socket.on('disconnect', (_) {
      _isConnecting = false;
    });
    socket.on('message:new', (payload) {
      final map = _normalizePayload(payload);
      if (map != null) _messageController.add(map);
    });
    socket.on('chat:updated', (payload) {
      final map = _normalizePayload(payload);
      if (map != null) _chatUpdateController.add(map);
    });
    socket.on('presence:update', (payload) {
      final map = _normalizePayload(payload);
      if (map != null) _presenceController.add(map);
    });
    socket.on('message:read', (payload) {
      final map = _normalizePayload(payload);
      if (map != null) _messageReadController.add(map);
    });
    socket.on('message:deleted', (payload) {
      final map = _normalizePayload(payload);
      if (map != null) _messageDeletedController.add(map);
    });
    socket.on('chat:deleted', (payload) {
      final map = _normalizePayload(payload);
      if (map != null) _chatDeletedController.add(map);
    });

    socket.connect();
    _socket = socket;
  }

  void joinChat(String chatId) {
    _socket?.emit('chat:join', {'chatId': chatId});
  }

  void leaveChat(String chatId) {
    _socket?.emit('chat:leave', {'chatId': chatId});
  }

  void setPresence(bool isOnline) {
    _socket?.emit('presence:set', {'isOnline': isOnline});
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _isConnecting = false;
    _lastToken = null;
  }

  Map<String, dynamic>? _normalizePayload(dynamic payload) {
    if (payload is Map<String, dynamic>) return payload;
    if (payload is Map) {
      return payload.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }
}
