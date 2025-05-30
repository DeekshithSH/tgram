// src/auth.dart
import 'client.dart';
import 'package:t/t.dart' as t;

extension AuthMethods on TelegramClient {
  Future<t.AuthAuthorizationBase?> loginBot(String botToken) async {
    if (!isConnected) connect();
    final c = client;
    if(c==null) throw Exception("Client is not started yet");
    final auth = await c.auth.importBotAuthorization(
      flags: 0,
      apiId: apiId,
      apiHash: apiHash,
      botAuthToken: botToken,
    );

    if (auth.error != null) {
      final error = auth.error!;
      if (error.errorCode == 303) {
        await _handleDcMigration(error.errorMessage);
        return await loginBot(botToken);
      } else if (error.errorCode == 420) {
        await _handleFloodWait(error.errorMessage);
        return await loginBot(botToken);
      }
      throw Exception("Unhandled Error: $error");
    }

    return auth.result;
  }

  Future<void> _handleDcMigration(String message) async {
    final dcId = int.parse(RegExp(r'\d+').firstMatch(message)!.group(0)!);
    final dc = dcList.firstWhere((d) => d.id == dcId && !d.ipv6);
    await connect(dc.ipAddress, dc.port, dc.id);
  }

  Future<void> _handleFloodWait(String message) async {
    final seconds = int.parse(RegExp(r'\d+').firstMatch(message)!.group(0)!);
    await Future.delayed(Duration(seconds: seconds));
  }
}
