import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/services/tcp_transport_service_native.dart';

const _ioTimeout = Duration(seconds: 5);

// Keep these checks on the existing transport before adding an overlay dialer.
// Literal companion bytes make changes to framing visible independently of the
// encoder used by the implementation. All sockets stay on loopback.
void main() {
  late _TcpFixture fixture;

  setUp(() async {
    fixture = await _TcpFixture.create();
    addTearDown(fixture.close);
  });

  test('concurrent writes preserve companion bytes and call order', () async {
    final peer = await fixture.connect();
    final received = _readBytes(peer, 15);

    await Future.wait<void>(<Future<void>>[
      fixture.service.write(Uint8List.fromList(<int>[0x01, 0xa5])),
      fixture.service.write(Uint8List.fromList(<int>[0x0a])),
      fixture.service.write(Uint8List.fromList(<int>[0x03, 0xfe, 0x80])),
    ]);

    expect(
      await received,
      orderedEquals(<int>[
        0x3c, 0x02, 0x00, 0x01, 0xa5,
        0x3c, 0x01, 0x00, 0x0a,
        0x3c, 0x03, 0x00, 0x03, 0xfe, 0x80,
      ]),
    );
  });

  test('split RX header and coalesced frames preserve payloads', () async {
    final frames = StreamIterator<Uint8List>(fixture.service.frameStream);
    addTearDown(frames.cancel);
    final peer = await fixture.connect();

    // The first complete frame acknowledges consumption of this chunk before
    // the rest of the second header is sent; no timing-based sleep is needed.
    peer.add(<int>[0x3e, 0x01, 0x00, 0x70, 0x3e, 0x04]);
    await peer.flush();
    expect(await _nextFrame(frames), orderedEquals(<int>[0x70]));

    peer.add(<int>[
      0x00, 0x80, 0x3e, 0x3c, 0x00,
      0x3c, 0x01, 0x00, 0xff,
      0x3e, 0x01, 0x00, 0x0a,
    ]);
    await peer.flush();

    expect(
      await _nextFrame(frames),
      orderedEquals(<int>[0x80, 0x3e, 0x3c, 0x00]),
    );
    // A TX-direction frame between the two RX frames must not be delivered.
    expect(await _nextFrame(frames), orderedEquals(<int>[0x0a]));
  });

  test('reconnect discards an incomplete frame from the old peer', () async {
    final frames = StreamIterator<Uint8List>(fixture.service.frameStream);
    addTearDown(frames.cancel);
    final oldPeer = await fixture.connect();

    oldPeer.add(<int>[
      0x3e, 0x01, 0x00, 0x71,
      0x3e, 0x03, 0x00, 0xaa,
    ]);
    await oldPeer.flush();
    expect(await _nextFrame(frames), orderedEquals(<int>[0x71]));

    await fixture.service.disconnect();
    final newPeer = await fixture.connect();
    newPeer.add(<int>[0x3e, 0x02, 0x00, 0x72, 0x73]);
    await newPeer.flush();

    expect(await _nextFrame(frames), orderedEquals(<int>[0x72, 0x73]));
    expect(fixture.service.status, TcpTransportStatus.connected);
  });

  test('oversized write leaves the connection usable for valid frames', () async {
    final peer = await fixture.connect();
    final received = _readBytes(peer, 4);

    await expectLater(
      fixture.service.write(Uint8List(177)),
      throwsArgumentError,
    );
    await fixture.service.write(Uint8List.fromList(<int>[0x0a]));

    expect(await received, orderedEquals(<int>[0x3c, 0x01, 0x00, 0x0a]));
  });

  test('late cancelled connect cannot replace a newer connection', () async {
    final overrides = _GatedFirstConnectOverrides();
    final frames = StreamIterator<Uint8List>(fixture.service.frameStream);
    addTearDown(frames.cancel);

    await IOOverrides.runWithIOOverrides(() async {
      final oldConnect = fixture.service.connect(
        host: InternetAddress.loopbackIPv4.address,
        port: fixture.server.port,
      );
      try {
        await overrides.started.future.timeout(_ioTimeout);
        await fixture.service.disconnect();
        final currentPeer = await fixture.connect();

        overrides.release.complete();
        await oldConnect.timeout(_ioTimeout);
        // The cancelled dial really connected after the new one, and must be
        // discarded without closing or replacing the current session.
        final cancelledPeer = await fixture.acceptPeer();
        await expectLater(cancelledPeer, emitsDone).timeout(_ioTimeout);

        expect(fixture.service.status, TcpTransportStatus.connected);
        expect(
          fixture.service.activeEndpoint,
          '${InternetAddress.loopbackIPv4.address}:${fixture.server.port}',
        );
        currentPeer.add(<int>[0x3e, 0x01, 0x00, 0x74]);
        await currentPeer.flush();
        expect(await _nextFrame(frames), orderedEquals(<int>[0x74]));
      } finally {
        if (!overrides.release.isCompleted) overrides.release.complete();
        await oldConnect.timeout(_ioTimeout);
      }
    }, overrides);
  });

  // New failure-path regression: overlay authentication can finish after the
  // user has cancelled and connected again. The earlier baseline stays above.
  test('late failed connect cannot tear down a newer connection', () async {
    final overrides = _GatedFirstConnectOverrides(failFirst: true);
    final frames = StreamIterator<Uint8List>(fixture.service.frameStream);
    addTearDown(frames.cancel);
    await IOOverrides.runWithIOOverrides(() async {
      final oldConnect = fixture.service.connect(
        host: InternetAddress.loopbackIPv4.address,
        port: fixture.server.port,
      );
      final oldFailure = expectLater(oldConnect, throwsA(isA<SocketException>()));
      try {
        await overrides.started.future.timeout(_ioTimeout);
        await fixture.service.disconnect();
        final currentPeer = await fixture.connect();
        overrides.release.complete();
        await oldFailure.timeout(_ioTimeout);

        expect(fixture.service.status, TcpTransportStatus.connected);
        currentPeer.add(<int>[0x3e, 1, 0, 0x75]);
        await currentPeer.flush();
        expect(await _nextFrame(frames), orderedEquals(<int>[0x75]));
      } finally {
        if (!overrides.release.isCompleted) overrides.release.complete();
        await oldFailure.timeout(_ioTimeout);
      }
    }, overrides);
  });

  test('remote close reports an error and clears the active endpoint', () async {
    final peer = await fixture.connect();
    final errorCheck = expectLater(
      fixture.service.frameStream.first,
      throwsStateError,
    );

    await peer.close();
    await errorCheck.timeout(_ioTimeout);
    // The public stream reports the error before async socket cleanup finishes.
    await (() async {
      while (fixture.service.status != TcpTransportStatus.disconnected) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    })().timeout(_ioTimeout);

    expect(fixture.service.isConnected, isFalse);
    expect(fixture.service.activeEndpoint, isNull);
    await expectLater(
      fixture.service.write(Uint8List.fromList(<int>[0x0a])),
      throwsStateError,
    );
  });

  test('disconnect closes an idle read adapter and permits a clean reconnect', () async {
    final overrides = _IdleReadOverrides();
    final frames = StreamIterator<Uint8List>(fixture.service.frameStream);
    await IOOverrides.runWithIOOverrides(() async {
      try {
        final oldPeer = await fixture.connect();
        oldPeer.add(<int>[0x3e, 1, 0, 0x76]);
        await oldPeer.flush();
        expect(await _nextFrame(frames), <int>[0x76]);
        // The adapter is now suspended in moveNext(), not at a yield.
        await Future<void>.delayed(Duration.zero);
        final disconnecting = fixture.service.disconnect();
        final joined = fixture.service.disconnect();
        expect(identical(disconnecting, joined), isTrue);
        await disconnecting.timeout(_ioTimeout);
        expect(fixture.service.status, TcpTransportStatus.disconnected);

        final currentPeer = await fixture.connect();
        currentPeer.add(<int>[0x3e, 1, 0, 0x77]);
        await currentPeer.flush();
        expect(await _nextFrame(frames), <int>[0x77]);
        expect(fixture.service.status, TcpTransportStatus.connected);
      } finally {
        // Even the pre-fix implementation must not hang this test's cleanup.
        final finishing = fixture.service.disconnect();
        for (final socket in overrides.sockets) { socket.destroy(); }
        await finishing.timeout(_ioTimeout);
        await frames.cancel();
      }
    }, overrides);
  });

  test('a stalled old flush cannot block or write into the replacement socket', () async {
    final overrides = _GatedFlushOverrides();
    await IOOverrides.runWithIOOverrides(() async {
      await fixture.connect();
      final oldWrite = fixture.service.write(Uint8List.fromList([0x10]));
      final oldQueued = fixture.service.write(Uint8List.fromList([0x11]));
      final rejected = expectLater(oldQueued, throwsStateError);
      try {
        await overrides.flushing.future.timeout(_ioTimeout);
        await fixture.service.disconnect().timeout(_ioTimeout);
        final currentPeer = await fixture.connect();
        final bytes = _readBytes(currentPeer, 8);
        // This write must not wait for the old flush to finish.
        await fixture.service.write(Uint8List.fromList([0x12])).timeout(_ioTimeout);
        overrides.release.complete();
        await oldWrite.timeout(_ioTimeout);
        await rejected.timeout(_ioTimeout);
        await fixture.service.write(Uint8List.fromList([0x13]));
        expect(await bytes, [0x3c, 1, 0, 0x12, 0x3c, 1, 0, 0x13]);
      } finally {
        if (!overrides.release.isCompleted) {
          overrides.release.complete();
        }
        await oldWrite.timeout(_ioTimeout);
        await rejected.timeout(_ioTimeout);
      }
    }, overrides);
  });
}

Future<List<int>> _readBytes(Socket peer, int count) => peer
    .expand((bytes) => bytes)
    .take(count)
    .toList()
    .timeout(_ioTimeout);

Future<Uint8List> _nextFrame(StreamIterator<Uint8List> frames) async {
  expect(await frames.moveNext().timeout(_ioTimeout), isTrue);
  return frames.current;
}

final class _TcpFixture {
  _TcpFixture._(this.server) {
    _accepted = StreamIterator<Socket>(_incoming.stream);
    _serverSubscription = server.listen((peer) {
      _peers.add(peer);
      _incoming.add(peer);
    });
  }

  final ServerSocket server;
  final TcpTransportService service = TcpTransportService();
  final List<Socket> _peers = <Socket>[];
  final StreamController<Socket> _incoming = StreamController<Socket>();
  late final StreamIterator<Socket> _accepted;
  late final StreamSubscription<Socket> _serverSubscription;

  static Future<_TcpFixture> create() async => _TcpFixture._(
    await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
  );

  Future<Socket> connect() async {
    await service.connect(
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
    );
    return acceptPeer();
  }

  Future<Socket> acceptPeer() async {
    expect(await _accepted.moveNext().timeout(_ioTimeout), isTrue);
    return _accepted.current;
  }

  Future<void> close() async {
    await service.disconnect();
    for (final peer in _peers) {
      peer.destroy();
    }
    await _serverSubscription.cancel();
    await server.close();
    await _accepted.cancel();
    await _incoming.close();
    service.dispose();
  }
}

// Release the first dial explicitly so the cancellation race is repeatable on
// slow machines as well as fast ones, without depending on TCP timing.
final class _GatedFirstConnectOverrides extends IOOverrides {
  _GatedFirstConnectOverrides({this.failFirst = false});

  final bool failFirst;
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<Socket> socketConnect(
    host,
    int port, {
    sourceAddress,
    int sourcePort = 0,
    Duration? timeout,
  }) async {
    if (!started.isCompleted) {
      started.complete();
      await release.future;
      if (failFirst) throw const SocketException('cancelled test dial failed');
    }
    return super.socketConnect(
      host,
      port,
      sourceAddress: sourceAddress,
      sourcePort: sourcePort,
      timeout: timeout,
    );
  }
}

// Model an adapter waiting for a silent peer, without importing premium code.
// An async* subscription cannot finish cancellation until its await completes.
final class _IdleReadOverrides extends IOOverrides {
  final sockets = <Socket>[];
  @override
  Future<Socket> socketConnect(host, int port, {sourceAddress,
      int sourcePort = 0, Duration? timeout}) async {
    final socket = await super.socketConnect(host, port, sourceAddress: sourceAddress,
        sourcePort: sourcePort, timeout: timeout);
    sockets.add(socket);
    return _IdleReadSocket(socket);
  }
}

class _IdleReadSocket extends StreamView<Uint8List> implements Socket {
  _IdleReadSocket(this.socket) : super(_read(socket));
  final Socket socket;
  static Stream<Uint8List> _read(Socket socket) async* {
    final chunks = StreamIterator<Uint8List>(socket);
    try {
      while (await chunks.moveNext()) { yield chunks.current; }
    } finally {
      await chunks.cancel();
    }
  }
  @override
  bool setOption(SocketOption option, bool enabled) => socket.setOption(option, enabled);
  @override
  void setRawOption(RawSocketOption option) => socket.setRawOption(option);
  @override
  void add(List<int> data) => socket.add(data);
  @override
  Future<void> flush() => socket.flush();
  @override
  Future<void> close() async { await socket.close(); }
  @override
  void destroy() => socket.destroy();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _GatedFlushOverrides extends IOOverrides {
  final flushing = Completer<void>();
  final release = Completer<void>();
  bool _first = true;
  @override
  Future<Socket> socketConnect(host, int port, {sourceAddress,
      int sourcePort = 0, Duration? timeout}) async {
    final socket = await super.socketConnect(host, port, sourceAddress: sourceAddress,
        sourcePort: sourcePort, timeout: timeout);
    if (!_first) {
      return socket;
    }
    _first = false;
    return _GatedFlushSocket(socket, flushing, release.future);
  }
}

class _GatedFlushSocket extends _IdleReadSocket {
  _GatedFlushSocket(super.socket, this.flushing, this.release);
  final Completer<void> flushing;
  final Future<void> release;
  @override
  Future<void> flush() async {
    if (!flushing.isCompleted) {
      flushing.complete();
    }
    await release;
  }
}
