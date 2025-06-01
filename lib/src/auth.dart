// src/auth.dart
import 'dart:async';
import 'dart:io';

import 'client.dart';
import 'package:t/t.dart' as t;
import 'package:tg/tg.dart' as tg;

extension AuthMethods on TelegramClient {
  Future<t.AuthAuthorizationBase?> login({
    String? botToken,
    String? phone,
    String? password,
    FutureOr<String> Function(t.TlConstructor) inputCallback = input
  }) async {
    if (!isConnected) connect();
    final c = client;
    if(c==null) throw Exception("Client is not started yet");

    t.Result<t.AuthAuthorizationBase> auth;
    if (botToken != null){
      auth = await c.auth.importBotAuthorization(
        flags: 0,
        apiId: apiId,
        apiHash: apiHash,
        botAuthToken: botToken,
      );
    } else if (phone != null){
      final sendCodeResponse = await c.auth.sendCode(
        apiId: apiId,
        apiHash: apiHash,
        phoneNumber: phone,
        settings: const t.CodeSettings(
          allowFlashcall: false,
          currentNumber: true,
          allowAppHash: false,
          allowMissedCall: false,
          allowFirebase: false,
          unknownNumber: false,
        ),
      );
      if (sendCodeResponse.error != null){
        throw Exception(sendCodeResponse.error);
      }
      final sendCodeResult = sendCodeResponse.result as t.AuthSentCode;

      final phoneCode = await Future.value(inputCallback(sendCodeResult));
      final signInResponse = await c.auth.signIn(
        phoneCodeHash: sendCodeResult.phoneCodeHash,
        phoneNumber: phone,
        phoneCode: phoneCode,
      );
      if (signInResponse is t.AuthAuthorizationSignUpRequired) throw Exception("Phone number is not registered with telegram");
      auth = signInResponse;

      final accountPasswordResponse = await c.account.getPassword();
      final accountPasswordResult = accountPasswordResponse.result as t.AccountPassword;
      if (accountPasswordResult.hasPassword){
        final password = await Future.value(inputCallback(accountPasswordResult));
        final passwordSRP = tg.check2FA(accountPasswordResult, password);
        final checkPasswordResponse = await c.auth.checkPassword(password: passwordSRP);
        auth = checkPasswordResponse;
      }
    } else {
      stdout.write("Enter Bot Token or Phone Number (international format):");
      final phoneNo = stdin.readLineSync() as String;
      if (phoneNo.contains(':')){
        return login(botToken: phoneNo);
      }
      return login(phone: phoneNo);
    }

    if (auth.error != null) {
      final error = auth.error!;
      if (error.errorCode == 303) {
        await _handleDcMigration(error.errorMessage);
        return await login(botToken: botToken, phone: phone, password: password);
      } else if (error.errorCode == 420) {
        await _handleFloodWait(error.errorMessage);
        return await login(botToken: botToken, phone: phone, password: password);
      }
      throw Exception("Unhandled Error: $error");
    }
    dcManager!.authKeys[dcId]=c.authKey!;
    isAuthorized=true;
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

String input(t.TlConstructor obj){
  if(obj is t.AuthSentCode){
    stdout.write("Enter OTP:");
  } else if (obj is t.AccountPassword){
    stdout.write("Enter Password:");
  } else{
    stdout.write("Enter: ");
  }
  return stdin.readLineSync() as String;
}