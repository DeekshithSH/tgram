// src/files.dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'client.dart';
import 'package:t/t.dart' as t;

extension FileMethods on TelegramClient {
  Stream<Uint8List> _iterDownload(t.InputFileLocationBase location, int dcId, int firstPart, int firstPartCut, int lastPart, int lastPartCut, int partCount, int partSize) async* {
    final sender = await borrowDcClient(dcId);
    try{
      int part = firstPart;
      int offset = part * partSize;

      while (part <= lastPart) {
        final resp = await sender.upload.getFile(
          precise: false,
          cdnSupported: false,
          location: location,
          offset: offset,
          limit: partSize,
        );

        if (resp.error != null)  throw Exception(resp.error);

        final result = resp.result as t.UploadFile;
        final bytes = result.bytes;

        if (bytes.isEmpty) break;

        if (firstPart == lastPart) {
          // Single part with cuts at both ends
          yield bytes.sublist(firstPartCut, lastPartCut);
        } else if (part == firstPart) {
          // First part: skip firstPartCut
          yield bytes.sublist(firstPartCut);
        } else if (part == lastPart) {
          // Last part: take only up to lastPartCut
          yield bytes.sublist(0, lastPartCut);
        } else {
          // Full part
          yield bytes;
        }

        offset += partSize;
        part += 1;
        // print("Part $part/$lastPart (total $partCount) downloaded");
      }
      print("Download finished");
    } catch (e) {
      print("Error: $e");
    } finally {
      returnDcClient(sender);
    }
  }

  Stream<Uint8List> iterDownload({
    required t.InputFileLocationBase location,
    required int size,
    required int dcId,
    int partSize = 512 * 1024, // 512 KB
    int fromBytes = 0, // inclusive
    int? untilBytes, // inclusive
  }){
    untilBytes ??= size - 1;
    int firstPartCut = fromBytes % partSize;
    int firstPart = (fromBytes/partSize).floor();
    int lastPartCut = (untilBytes % partSize) + 1;
    int lastPart = (untilBytes/partSize).ceil();
    int partCount = (size/partSize).ceil();
    return _iterDownload(location, dcId, firstPart, firstPartCut, lastPart, lastPartCut, partCount, partSize);
  }

  Future<String?> downloadMedia({
    required t.InputFileLocationBase location,
    required int dcId,
    required int size,
    required String path,
  }) async {
    final c = client;
    if (c == null) throw Exception("Client is not started yet");

    final file = File(path);
    final sink = file.openWrite();

    try {
      await for (Uint8List bytes in iterDownload(location: location, size: size, dcId: dcId, partSize: 1024 * 1024)) {
        sink.add(bytes);
      }
      print("Download complete: $path");
      return path;
    } catch (e) {
      print("Download error: $e");
    } finally {
      await sink.close();
    }
    return null;
  }
}