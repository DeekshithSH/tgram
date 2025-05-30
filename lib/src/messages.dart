// src/messages.dart
import 'client.dart';
import 'package:t/t.dart' as t;

extension Messages on TelegramClient {
  Future<t.Result<t.UpdatesBase>> sendMessage({
    required String message,
    required t.InputPeerBase peer,
    bool disableWebPagePreview = false,
    bool disableNotification = false,
    bool noforwards = false,
    bool invertMedia = false,
    bool allowPaidFloodskip = false,

    }) async {
    final response = await invoke(t.MessagesSendMessage(
      noWebpage: disableWebPagePreview,
      silent: disableNotification,
      background: false,
      clearDraft: false,
      noforwards: noforwards,
      updateStickersetsOrder: false,
      invertMedia: invertMedia,
      allowPaidFloodskip: allowPaidFloodskip,
      peer: peer,
      message: message,
      randomId: randomId
    ));
    return convertResult<t.UpdatesBase>(response);
  }

  Future<t.Result<t.UpdatesBase>> forwardMessage({
    required t.InputPeerBase fromPeer,
    required t.InputPeerBase toPeer,
    required List<int> msgIds,
    bool disableWebPagePreview = false,
    bool disableNotification = false,
    bool noforwards = false,
    bool allowPaidFloodskip = false,
    bool hideSender = false,
    bool hideCaption = false,
    }) async {
    final response = await invoke(t.MessagesForwardMessages(
      silent: disableNotification,
      background: false,
      withMyScore: false,
      dropAuthor: hideSender,
      dropMediaCaptions: hideCaption,
      noforwards: noforwards,
      allowPaidFloodskip: allowPaidFloodskip,
      fromPeer: fromPeer,
      id: msgIds,
      randomId: msgIds.map((_) => randomId).toList(),
      toPeer: toPeer
    ));
    return convertResult<t.UpdatesBase>(response);
  }
}