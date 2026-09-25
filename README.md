# RadioTrade — мобильная торговля радиокомпонентами

Кроссплатформенное приложение (Android / iOS / Windows .exe / Linux / macOS) для торговых
представителей и продавцов электронных компонентов. Аналог «Моби-С»: pre-selling (сбор
заказов) и van-selling (торговля с мобильного склада).

## Возможности
- Электронный мобильный склад: остатки по сериям/ячейкам, поиск по артикулу/номиналу/корпусу/производителю, сканер штрихкодов, резервирование, инвентаризация.
- Продажи: заказы и реализации, прайс-листы, скидки клиентов, наличные/карта/перевод/отсрочка, печать чека/накладной на Bluetooth ESC/POS-принтер.
- Клиенты и маршруты: база с долгами и лимитами, визиты по дням недели, GPS-чек-ин, фотоотчёты.
- Offline-first SQLite + двусторонняя синхронизация с 1С (УТ/УНФ/ERP) через HTTP-шлюз; очередь `outbox`, курсор `sync_cursor`.
- Отчёты: продажи дня, дебиторка, выполнение плана.
- Роли: агент / супервайзер / администратор. Material 3, тёмная/светлая тема, русский язык.

## Структура
```
lib/
  main.dart               — вход, DI (provider), выбор реализации sqlite
  core/                   — тема, сессия (роли, режимы работы)
  models/                 — Product, Stock, Client, Order, Payment, Visit
  data/db/app_db.dart     — SQLite (schema + запросы + демо-данные)
  data/sync/sync_engine.dart — push/pull c 1С, триггеры сеть/таймер
  services/devices.dart   — Bluetooth-принтер (ESC/POS), GPS, сканер
  features/               — экраны: вход, день, склад, заказы, клиенты, отчёты, настройки
```

## Сборка
```bash
flutter pub get
flutter run -d windows        # десктоп
flutter run -d android        # Android
flutter build windows         # -> build/windows/x64/runner/Release/*.exe
flutter build apk --release   # Android APK
flutter build ipa             # iOS (на macOS)
```
На Windows/Linux база SQLite работает через `sqflite_common_ffi` (уже настроено в `main.dart`).

## Демо-доступ
Пользователь «Иванов И.» (агент), PIN `1111`. Режимы: pre-selling / van-selling.

## Шлюз 1С
`POST /push` — пачка изменений из outbox, ответ `{accepted: [id], stocks: [...]}`.
`GET /pull?cursor_products=&cursor_clients=&cursor_stocks=` — изменённые справочники.
Адрес задаётся в настройках приложения. Пример HTTP-сервиса 1С — см. `docs/1c_gateway.md`.

## История версий / Version history (полная версия, без демо/ограничений | full version, no demo/limits)
| Версия / Version | Что внутри / What's inside |
|---|---|
| 0.1.0 | Архивный бинарник без исходников (ранний билд) / Archived binary, no sources (early build) |
| 1.0.0 | Стабильный релиз, подпись своим ключом, иконка, пакет com.telemaster.teleport / Stable release, own signing key, icon, applicationId |
| 1.1.0 | Накладные поставщиков: Excel-импорт, матчинг дублей, проведение / Supplier invoices: Excel import, duplicate matching, posting |
| 1.1.1 | Описание товара в поиске и на карточке / Product description in search and on card |
| 1.1.2 | Номер коробки на карточке вместо артикула / Box number on card instead of SKU |
| 1.1.3 | Архивные бинарники без исходников / Archived binaries, no sources |
| 1.2.0 | Возвраты товаров: из заказа построчно, из карточки / Product returns: per order line, from product card |
| 1.2.1 | Диета APK 75→26 МБ: сплиты по ABI + обфускация / APK diet 75→26 MB: ABI splits + obfuscation |
| 1.2.2 | OCR накладных с фото, офлайн (MLKit) / Photo invoice OCR, offline (MLKit) |
| 1.2.3 | Выбор фото через системный picker, фикс галереи / System file picker, gallery fix |
| 1.2.4 | Проверка работы Gemini: тесты парсера, keep-правила R8 / Gemini check: parser tests, R8 keep rules |
| 1.2.5 | Онлайн-распознавание через Gemini (удалено в 1.2.6) / Online Gemini OCR (removed in 1.2.6) |
| 1.2.6 | Офлайн-парсер усилен: штрихкоды, мусорные строки, матчинг по транслиту / Offline parser hardened: barcodes, junk lines, translit matching |
| 1.2.7 | Архивация dist, удалён GPS (вес не изменился) / dist archiving, GPS removed (size unchanged) |
| 1.3.0 | Пороги остатков, касса дня, маржа, голосовой поиск / Low-stock thresholds, cash register, margins, voice search |

Каждый новый релиз: коммит + тег `vX.Y.Z` + GitHub Release с
`TelePort_X_Windows_x64.zip` и `TelePort_X_Android_arm64-v8a.apk`.
Each new release: commit + tag `vX.Y.Z` + GitHub Release with
`TelePort_X_Windows_x64.zip` and `TelePort_X_Android_arm64-v8a.apk`.
