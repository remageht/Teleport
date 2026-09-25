import 'package:http/http.dart' as http;

/// Отправка копии базы в Telegram через бота.
/// Настройка (один раз): BotFather -> /newbot -> токен; создать группу,
/// добавить бота админом, узнать chat_id (бот @getmyid_bot или
/// https://api.telegram.org/bot<token>/getUpdates).
class TelegramBackup {
  /// Отправить файл БД как документ. Бросает текст ошибки.
  static Future<void> sendDb({
    required String botToken,
    required String chatId,
    required String dbPath,
    String? caption,
  }) async {
    final uri =
        Uri.parse('https://api.telegram.org/bot$botToken/sendDocument');
    final req = http.MultipartRequest('POST', uri)
      ..fields['chat_id'] = chatId
      ..fields['caption'] = caption ??
          'Копия базы ТелеПорт · ${DateTime.now().toString().substring(0, 16)}'
      ..files.add(await http.MultipartFile.fromPath('document', dbPath));
    final resp =
        await req.send().timeout(const Duration(seconds: 120));
    if (resp.statusCode != 200) {
      throw 'Telegram вернул ${resp.statusCode}: проверь токен и chat_id';
    }
  }
}
