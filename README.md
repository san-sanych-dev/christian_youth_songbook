# Сборник песен (PWA)

Прогрессивное веб-приложение (PWA) со сборником христианских песен: поиск по
номеру и тексту, отображение аккордов с транспонированием, регулировка размера
шрифта и светлая/тёмная тема.

Приложение собрано на Flutter Web и работает офлайн после первого открытия,
устанавливается на домашний экран телефона и рабочий стол.

## Требования

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable)
- Включённая поддержка web: `flutter config --enable-web`

## Запуск в режиме разработки

```bash
flutter pub get
flutter run -d chrome
```

## Сборка PWA

```bash
flutter build web --release
```

Готовые файлы появятся в `build/web/`. Эту папку нужно раздавать любым статическим
сервером (Nginx, GitHub Pages, Netlify, Vercel и т.п.).

Если приложение размещается не в корне домена, укажите базовый путь:

```bash
flutter build web --release --base-href /sbornik/
```

## Локальная проверка собранной версии

```bash
cd build/web
python3 -m http.server 8080
```

Затем открыть `http://localhost:8080`. Service worker и манифест уже настроены,
поэтому Chrome предложит установить приложение.

## Данные песен

Тексты песен хранятся в `assets/songs.json`. Скрипты `docx_to_json.py` и
`parse_sbornik.py` помогают конвертировать исходный `.docx` в этот JSON.
