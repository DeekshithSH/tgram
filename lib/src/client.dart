import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:synchronized/synchronized.dart';
import 'package:socks5_proxy/socks.dart';
import 'package:t/t.dart' as t;
import 'package:tg/tg.dart' as tg;

class TGConnection {
  Socket socket;
  StreamController<Uint8List> sender;
  StreamController<Uint8List> receiver;
  TGConnection(this.socket, this.sender, this.receiver);

  Future<void> close() async {
    await sender.close();
    await receiver.close();
    await socket.close();
  }
}

class ClientState {
  int borrows = 1;
  bool isConnected = true;
  tg.Client client;
  TGConnection conn;
  ClientState(this.client, this.conn);
}

class DcManager {
  final Lock _lock = Lock();

  final Map<int, t.AuthorizationKey> authKeys = {};
  final Map<int, ClientState> dcClients = {};

  final List<t.DcOption> dcList;
  final tg.Client client;
  final bool useSocks;
  final t.InitConnection initRequest;

  DcManager(this.dcList, this.client, this.useSocks, this.initRequest);

  Future<ClientState> _getDcClient(int dcId) async {
    final dc = dcList.firstWhere(
      (d) => d.id == dcId && d.mediaOnly,
      orElse: () => dcList.firstWhere((d) => d.id == dcId),
    );

    print("Connecting to ${dc.ipAddress}:${dc.port}");
    final obf = tg.Obfuscation.random(false, 4);
    final socket = useSocks
        ? await SocksTCPClient.connect([
            ProxySettings(InternetAddress.loopbackIPv4, 1080),
          ], InternetAddress(dc.ipAddress), dc.port)
        : await Socket.connect(dc.ipAddress, dc.port);

    final sender = StreamController<Uint8List>();
    final receiver = StreamController<Uint8List>.broadcast();

    sender.stream.listen(socket.add);
    socket.listen(receiver.add);

    final ak = authKeys[dcId];

    final c = tg.Client(
      sender: sender.sink,
      receiver: receiver.stream,
      obfuscation: obf,
      authKey: ak,
    );

    if (ak == null) {
      print("Exporting auth");
      final cakResult = await client.auth.exportAuthorization(dcId: dcId);
      final cak = cakResult.result as t.AuthExportedAuthorization;
      await c.invokeWithLayer(layer: t.layer, query: initRequest);
      final authkey = c.authKey;
      if (authkey != null) {
        authKeys[dcId] = authkey;
      }
      await c.auth.importAuthorization(id: cak.id, bytes: cak.bytes);
    }

    return ClientState(c, TGConnection(socket, sender, receiver));
  }

  Future<tg.Client> borrowClient(int dcId) async {
    return await _lock.synchronized(() async {
      final dcClient = dcClients[dcId];
      if (dcClient != null) {
        dcClient.borrows += 1;
        return dcClient.client;
      }
      final cs = await _getDcClient(dcId);
      dcClients[dcId] = cs;
      return cs.client;
    });
  }

  void returnClient(tg.Client dcClient) {
    try {
      final cs = dcClients.values.firstWhere((e) => e.client == dcClient);
      cs.borrows -= 1;
      // ToDo: Close Connection if borrows equal to zero
    } catch (e) {
      print("got client that is not borrowed");
    }
  }

  Future<void> closeAll() async {
    for (final cs in dcClients.values) {
      await cs.conn.close();
      // await cd.client.close();
    }
    dcClients.clear();
    authKeys.clear();
  }
}

class TelegramClient {
  final int apiId;
  final String apiHash;
  final void Function(t.UpdatesBase update)? onUpdate;
  final Map<String, dynamic>? session;
  final bool useSocks;

  int dcId = 4;
  String dcIpAddress = "149.154.167.92";
  int dcPort = 443;

  Socket? _socket;
  StreamController<Uint8List>? _sender;
  StreamController<Uint8List>? _receiver;
  tg.Client? _client;
  DcManager? dcManager;

  t.InitConnection initRequest;

  bool isConnected = false;
  bool isAuthorized = false;

  List<t.DcOption> dcList = [
    t.DcOption(
      ipv6: false,
      mediaOnly: false,
      tcpoOnly: false,
      cdn: false,
      static: false,
      thisPortOnly: false,
      id: 4,
      ipAddress: '149.154.167.92',
      port: 443,
    )
  ];

  TelegramClient({
    required this.apiId,
    required this.apiHash,
    this.onUpdate,
    this.session,
    this.useSocks = false,
  }) : initRequest = t.InitConnection(
          apiId: apiId,
          deviceModel: Platform.operatingSystem,
          appVersion: "1.0.0",
          systemVersion: Platform.operatingSystemVersion,
          systemLangCode: "en",
          langCode: "en",
          langPack: "",
          proxy: null,
          params: null,
          query: t.HelpGetConfig(),
        );

  Future<tg.Client> connect([String? ip, int? port, int? dc]) async {
    await close();
    isConnected = false;
    final data = session;
    if (ip != null && port != null && dc != null) {
      dcIpAddress = ip;
      dcPort = port;
      dcId = dc;
    } else if (data != null) {
      dcIpAddress = data["ip"] as String;
      dcPort = data["port"] as int;
      dcId = data["dc_id"] as int;
    } else if (ip != null || port != null || dc != null) {
      throw ArgumentError("If any of ip, port, dc is provided, all three must be provided.");
    }

    ip ??= dcIpAddress;
    port ??= dcPort;
    dc ??= dcId;

    print("Connecting to $ip:$port");
    _socket = useSocks
        ? await SocksTCPClient.connect([
            ProxySettings(InternetAddress.loopbackIPv4, 1080),
          ], InternetAddress(ip), port)
        : await Socket.connect(ip, port);

    _sender = StreamController<Uint8List>();
    _receiver = StreamController<Uint8List>.broadcast();

    _sender!.stream.listen(_socket!.add);
    _socket!.listen(_receiver!.add);

    final c = _client = tg.Client(
      sender: _sender!.sink,
      receiver: _receiver!.stream,
      obfuscation: tg.Obfuscation.random(false, dcId),
      authKey: data != null ? t.AuthorizationKey.fromJson(data["auth_key"]) : null,
    );

    await c.connect();
    isConnected = true;
    if (data != null) isAuthorized = true;

    if (onUpdate != null) {
      c.stream.listen(onUpdate!);
    }
    print("Sending Init Connection request");

    final config = await c.invokeWithLayer<t.Config>(query: initRequest, layer: t.layer);
    if (config.result?.dcOptions is List) {
      dcList = List<t.DcOption>.from(config.result!.dcOptions);
    }

    dcManager = DcManager(dcList, c, useSocks, initRequest);

    return c;
  }

  Future<tg.Client> borrowDcClient(int dcId) async {
    if (dcManager == null) throw Exception("DcManager not initialized");
    if (!isAuthorized) throw Exception("Client is not authorized");
    return await dcManager!.borrowClient(dcId);
  }

  void returnDcClient(tg.Client dcClient) {
    dcManager?.returnClient(dcClient);
  }

  t.Result<S> convertResult<S extends t.TlObject>(t.Result original) {
    if (original.result == null) {
      return t.Result<S>.error(original.error!);
    } else {
      return t.Result<S>.ok(original.result as S);
    }
  }

  int get randomId {
    final random = Random.secure();
    final buffer = Uint8List(8);
    for (int i = 0; i < 8; i++) {
      buffer[i] = random.nextInt(256);
    }
    return ByteData.sublistView(buffer).getInt64(0, Endian.little);
  }

  Future<void> close() async {
    if (dcManager != null) {
      await dcManager!.closeAll();
      dcManager = null;
    }
    await _sender?.close();
    await _receiver?.close();
    await _socket?.close();
    // await _client.close();
    _client = null;
    _socket = null;
    _sender = null;
    _receiver = null;
  }

  Map<String, dynamic> exportSession() {
    final c = _client;
    if (c == null) {
      throw Exception("Client not started yet");
    }
    final ak = c.authKey;
    return {
      "auth_key": (ak != null) ? ak.toJson() : null,
      "api_id": apiId,
      "dc_id": dcId,
      "ip": dcIpAddress,
      "port": dcPort,
    };
  }

  tg.Client? get client => _client;
}
