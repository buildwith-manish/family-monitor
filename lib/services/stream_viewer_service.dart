import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Connection states for the stream viewer WebSocket.
enum StreamConnectionState {
  /// Not connected and not attempting to connect.
  disconnected,

  /// Currently attempting to establish a WebSocket connection.
  connecting,

  /// WebSocket is open and receiving frames.
  connected,

  /// The child device is not streaming (received child_disconnected message).
  childOffline,

  /// An error occurred that prevented the connection.
  error,
}

/// Dart-side WebSocket client that receives live screen frames from the
/// stream relay server and exposes them as a stream for the parent UI.
///
/// Replaces the slow Firebase RTDB base64 frame listener with a proper
/// low-latency WebSocket binary stream.
class StreamViewerService {
  final String relayUrl;

  StreamViewerService({required this.relayUrl});

  // ── Internal state ────────────────────────────────────────────────────

  WebSocket? _socket;
  String? _childUid;
  StreamSubscription<dynamic>? _socketSub;
  Timer? _reconnectTimer;
  Timer? _connectTimeoutTimer;

  bool _isConnected = false;
  bool _isChildStreaming = false;
  bool _disposed = false;
  int _reconnectAttempts = 0;

  static const int _maxReconnectAttempts = 15;
  static const Duration _initialBackoff = Duration(seconds: 1);
  static const Duration _maxBackoff = Duration(seconds: 30);
  static const Duration _connectTimeout = Duration(seconds: 10);

  Uint8List? _currentFrame;
  int _frameCount = 0;

  // Rolling window of frame timestamps for FPS calculation.
  final List<DateTime> _frameTimestamps = [];
  static const int _fpsWindowSize = 10;

  // ── Public streams ────────────────────────────────────────────────────

  final StreamController<StreamConnectionState> _connectionStateController =
      StreamController<StreamConnectionState>.broadcast();
  final StreamController<Uint8List> _frameStreamController =
      StreamController<Uint8List>.broadcast();

  StreamConnectionState _currentState = StreamConnectionState.disconnected;

  // ── Public API ────────────────────────────────────────────────────────

  /// Whether the WebSocket is currently connected.
  bool get isConnected => _isConnected;

  /// Whether the child device is actively streaming frames.
  bool get isChildStreaming => _isChildStreaming;

  /// The most recent JPEG frame received, or null if none yet.
  Uint8List? get currentFrame => _currentFrame;

  /// Total number of frames received since the last connect() call.
  int get frameCount => _frameCount;

  /// Estimated frames per second using a rolling average over the last
  /// [_fpsWindowSize] frames. Returns 0 if fewer than 2 frames have been
  /// received.
  double get currentFps {
    if (_frameTimestamps.length < 2) return 0.0;
    final window = _frameTimestamps;
    final span = window.last.difference(window.first).inMicroseconds;
    if (span <= 0) return 0.0;
    // (n-1) intervals over the span
    return (window.length - 1) * 1000000.0 / span;
  }

  /// Emits connection state changes.
  Stream<StreamConnectionState> get connectionState =>
      _connectionStateController.stream;

  /// Emits every new JPEG frame as it arrives.
  Stream<Uint8List> get frameStream => _frameStreamController.stream;

  // ── Connect / Disconnect ──────────────────────────────────────────────

  /// Connect to the stream relay for a specific [childUid].
  ///
  /// If already connected to the same child, this is a no-op.
  /// If connected to a different child, the existing connection is closed
  /// first.
  Future<void> connect(String childUid) async {
    if (_disposed) return;
    if (_isConnected && _childUid == childUid) return;

    await disconnect();
    _childUid = childUid;
    _reconnectAttempts = 0;
    await _doConnect();
  }

  /// Disconnect from the relay and cancel any pending reconnect attempts.
  Future<void> disconnect() async {
    _cancelReconnect();
    _cancelConnectTimeout();
    await _closeSocket();
    _childUid = null;
    _isChildStreaming = false;
    _frameTimestamps.clear();
    _setState(StreamConnectionState.disconnected);
  }

  /// Permanently tear down this service instance.
  Future<void> dispose() async {
    _disposed = true;
    await disconnect();
    await _connectionStateController.close();
    await _frameStreamController.close();
  }

  // ── Internal: connection lifecycle ────────────────────────────────────

  Future<void> _doConnect() async {
    if (_disposed || _childUid == null) return;

    _setState(StreamConnectionState.connecting);
    debugPrint('[StreamViewer] Connecting to relay for child=$_childUid '
        '(attempt ${_reconnectAttempts + 1}/$_maxReconnectAttempts)');

    // GATEWAY-PROXY-FIX: Properly append query parameters to the relay URL.
    // The relay URL may already contain query parameters like ?XTransformPort=3004
    // so we must use & instead of ? when appending role and uid.
    // Format: ws://HOST/?XTransformPort=3004&role=parent&uid=CHILD_UID
    final baseUri = Uri.parse(relayUrl);
    final newParams = Map<String, String>.from(baseUri.queryParameters);
    newParams['role'] = 'parent';
    newParams['uid'] = _childUid!;
    final uri = baseUri.replace(queryParameters: newParams);

    // Start connect timeout
    _startConnectTimeout();

    try {
      _socket = await WebSocket.connect(
        uri.toString(),
        protocols: null,
      ).timeout(_connectTimeout);

      _cancelConnectTimeout();
      _onConnected();
    } catch (e) {
      _cancelConnectTimeout();
      debugPrint('[StreamViewer] Connection error: $e');
      _isConnected = false;
      _setState(StreamConnectionState.error);
      _scheduleReconnect();
    }
  }

  void _onConnected() {
    if (_disposed) {
      _socket?.close();
      return;
    }

    _isConnected = true;
    _isChildStreaming = true; // assume streaming until told otherwise
    _frameCount = 0;
    _frameTimestamps.clear();
    _reconnectAttempts = 0;

    _setState(StreamConnectionState.connected);
    debugPrint('[StreamViewer] Connected to relay for child=$_childUid');

    _socketSub = _socket!.listen(
      _onData,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: false,
    );
  }

  // ── Internal: message handling ────────────────────────────────────────

  void _onData(dynamic message) {
    if (_disposed) return;

    if (message is List<int>) {
      // Binary frame – JPEG bytes
      _handleBinaryFrame(Uint8List.fromList(message));
    } else if (message is String) {
      // JSON control message
      _handleTextMessage(message);
    } else {
      debugPrint('[StreamViewer] Unexpected message type: ${message.runtimeType}');
    }
  }

  void _handleBinaryFrame(Uint8List frame) {
    if (frame.isEmpty) return;

    _currentFrame = frame;
    _frameCount++;
    _frameTimestamps.add(DateTime.now());

    // Trim FPS window
    while (_frameTimestamps.length > _fpsWindowSize) {
      _frameTimestamps.removeAt(0);
    }

    // Emit frame
    if (!_frameStreamController.isClosed) {
      _frameStreamController.add(frame);
    }

    // Periodic logging
    if (_frameCount % 50 == 0) {
      debugPrint('[StreamViewer] Received frame #$_frameCount '
          '(${frame.length} bytes, ${currentFps.toStringAsFixed(1)} FPS)');
    }
  }

  void _handleTextMessage(String text) {
    try {
      final json = jsonDecode(text) as Map<String, dynamic>;
      final type = json['type'] as String?;

      switch (type) {
        case 'child_disconnected':
          debugPrint('[StreamViewer] Child disconnected notification received');
          _isChildStreaming = false;
          _setState(StreamConnectionState.childOffline);
          break;
        default:
          debugPrint('[StreamViewer] Unknown control message type: $type');
      }
    } catch (e) {
      debugPrint('[StreamViewer] Invalid text message received: $e');
    }
  }

  // ── Internal: error / close handling ──────────────────────────────────

  void _onError(dynamic error) {
    if (_disposed) return;
    debugPrint('[StreamViewer] WebSocket error: $error');
    _isConnected = false;
    _setState(StreamConnectionState.error);
    // onDone will fire after onError, which triggers reconnect there.
  }

  void _onDone() {
    if (_disposed) return;
    debugPrint('[StreamViewer] WebSocket closed (child=$_childUid)');
    final wasConnected = _isConnected;
    _isConnected = false;
    _isChildStreaming = false;

    if (wasConnected || _currentState == StreamConnectionState.connecting) {
      _setState(StreamConnectionState.disconnected);
      _scheduleReconnect();
    }
  }

  // ── Internal: reconnect with exponential backoff ──────────────────────

  void _scheduleReconnect() {
    if (_disposed || _childUid == null) return;

    _reconnectAttempts++;
    if (_reconnectAttempts > _maxReconnectAttempts) {
      debugPrint('[StreamViewer] Max reconnect attempts ($_maxReconnectAttempts) '
          'reached. Giving up.');
      _setState(StreamConnectionState.error);
      return;
    }

    final backoffSeconds = _computeBackoff(_reconnectAttempts);
    debugPrint('[StreamViewer] Reconnecting in ${backoffSeconds}s '
        '(attempt $_reconnectAttempts/$_maxReconnectAttempts)');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: backoffSeconds), () {
      _reconnectTimer = null;
      if (!_disposed && _childUid != null) {
        _doConnect();
      }
    });
  }

  /// Exponential backoff: 1s, 2s, 4s, 8s, 16s, 30s, 30s, ...
  static int _computeBackoff(int attempt) {
    // attempt is 1-indexed
    final seconds = (1 << (attempt - 1)).clamp(1, 30);
    return seconds > 30 ? 30 : seconds;
  }

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  // ── Internal: connect timeout ─────────────────────────────────────────

  void _startConnectTimeout() {
    _cancelConnectTimeout();
    _connectTimeoutTimer = Timer(_connectTimeout, () {
      if (!_disposed && _currentState == StreamConnectionState.connecting) {
        debugPrint('[StreamViewer] Connect timeout – closing socket and retrying');
        _closeSocket();
        _scheduleReconnect();
      }
    });
  }

  void _cancelConnectTimeout() {
    _connectTimeoutTimer?.cancel();
    _connectTimeoutTimer = null;
  }

  // ── Internal: socket cleanup ──────────────────────────────────────────

  Future<void> _closeSocket() async {
    await _socketSub?.cancel();
    _socketSub = null;
    await _socket?.close();
    _socket = null;
    _isConnected = false;
  }

  // ── Internal: state management ────────────────────────────────────────

  void _setState(StreamConnectionState newState) {
    if (_currentState == newState) return;
    _currentState = newState;
    if (!_connectionStateController.isClosed) {
      _connectionStateController.add(newState);
    }
  }
}
