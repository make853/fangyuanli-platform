import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

abstract interface class RealtimeSocket {
  Stream<dynamic> get stream;
  Future<void> get ready;
  int? get closeCode;
  void send(String value);
  Future<void> close();
}

abstract interface class RealtimeSocketConnector {
  RealtimeSocket connect(Uri uri, {required String accessToken});
}

class IoRealtimeSocketConnector implements RealtimeSocketConnector {
  const IoRealtimeSocketConnector();

  @override
  RealtimeSocket connect(Uri uri, {required String accessToken}) {
    return _IoRealtimeSocket(
      IOWebSocketChannel.connect(
        uri,
        headers: {'authorization': 'Bearer $accessToken'},
        connectTimeout: const Duration(seconds: 12),
      ),
    );
  }
}

class _IoRealtimeSocket implements RealtimeSocket {
  const _IoRealtimeSocket(this._channel);

  final WebSocketChannel _channel;

  @override
  int? get closeCode => _channel.closeCode;

  @override
  Future<void> get ready => _channel.ready;

  @override
  Stream<dynamic> get stream => _channel.stream;

  @override
  void send(String value) => _channel.sink.add(value);

  @override
  Future<void> close() => _channel.sink.close();
}
