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
