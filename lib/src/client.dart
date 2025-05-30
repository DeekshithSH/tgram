import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:socks5_proxy/socks.dart';
import 'package:t/t.dart' as t;
import 'package:tg/tg.dart' as tg;

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
  late tg.Obfuscation _obf;
  tg.Client? _client;

  bool isConnected = false;
  bool isAuthorized = false;

  List<t.DcOption> dcList = [t.DcOption(
    ipv6: false,
    mediaOnly: false,
    tcpoOnly: false,
    cdn: false,
    static: false,
    thisPortOnly: false,
    id: 4,
    ipAddress: '149.154.167.92',
    port: 443,
  )];

  TelegramClient({
    required this.apiId,
    required this.apiHash,
    this.onUpdate,
    this.session,
    this.useSocks = false
  });

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
    _obf = tg.Obfuscation.random(false, 4);
    if (useSocks){
      _socket = await SocksTCPClient.connect(
        [
          ProxySettings(InternetAddress.loopbackIPv4, 1080),
        ],
        InternetAddress(ip),
        port,
      );
    } else {
      _socket = await Socket.connect(ip, port);
    }

    _sender = StreamController<Uint8List>();
    _receiver = StreamController<Uint8List>.broadcast();

    _sender!.stream.listen(_socket!.add);
    _socket!.listen(_receiver!.add);

    final c =_client = tg.Client(
      sender: _sender!.sink,
      receiver: _receiver!.stream,
      obfuscation: _obf,
      authKey: data != null? t.AuthorizationKey.fromJson(data["auth_key"]): null
    );

    await c.connect();
    isConnected = true;

    if (onUpdate != null) {
      c.stream.listen(onUpdate!);
    }
    print("Sending Init Connection request");
    final config = await c.initConnection<t.Config>(
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
    if (config.result?.dcOptions is List) {
      dcList = List<t.DcOption>.from(config.result!.dcOptions);
    }
    return c;
  }

  Future<t.Result<t.TlObject>> invoke(t.TlMethod method) async {
    if (!isConnected) connect();
    final c = client;
    if(c==null) throw Exception("Client is not started yet");
    return c.invoke(method);
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
    await _sender?.close();
    await _receiver?.close();
    await _socket?.close();
    _client = null;
    _socket = null;
    _sender = null;
    _receiver = null;
  }

  Map<String, dynamic> exportSession(){
    final c = _client;
    if (c == null){
      throw Exception("Client not started yet");
    }
    final ak = c.authKey;
    return {
      "auth_key": (ak!=null)?ak.toJson():null,
      "api_id": apiId,
      "dc_id": dcId,
      "ip": dcIpAddress,
      "port": dcPort
    };
  }

  tg.Client? get client => _client;
}
