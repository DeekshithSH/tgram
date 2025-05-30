A wrapper around [tg](https://github.com/telegramflutter/tg)

It is a part of [this repo](https://github.com/DeekshithSH/tg-dart-demo)

example:
```
import 'package:tgram/tgram.dart';
import 'package:t/t.dart' as t;

const API_ID=your_api_id;
const API_HASH='your_api_hash';
const BOT_TOKEN='your_bot_token';

final TelegramClient tgclient = TelegramClient(
    apiId: API_ID,
    apiHash: API_HASH,
    onUpdate: handleUpdates,
  );

Future<void> main() async {

  await tgclient.connect();
  await Future.delayed(Duration(seconds: 1));
  print("Authenticating");
  await tgclient.loginBot(BOT_TOKEN);
  print("Account authorized");

  final result = await tgclient.client!.users.getFullUser(id: t.InputUserSelf());
  final user = result.result as t.UsersUserFull;
  final me = user.users[0] as t.User;
  print("Hello, I'm ${me.firstName}");
  print("You can find me using: @${me.username}");
}

void handleUpdates(t.UpdatesBase update) async{
  print("New Message: $update");
}

```