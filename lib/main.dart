import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Управляем системными панелями вручную, чтобы задавать цвет плашки навигации.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
      overlays: SystemUiOverlay.values);
  await Settings.instance.init();
  runApp(const SbornikApp());
}

/// Хранилище пользовательских настроек поверх [SharedPreferences].
///
/// Сохраняет тему, размер шрифта, свёрнутость аккордов и транспонирование
/// (для каждой песни своё), чтобы настройки переживали перезапуск приложения.
class Settings {
  Settings._();

  static final Settings instance = Settings._();

  static const _kThemeMode = 'theme_mode';
  static const _kFontSize = 'font_size';
  static const _kChordsCollapsed = 'chords_collapsed';
  static const _kTransposePrefix = 'transpose_';

  late final SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  ThemeMode get themeMode {
    switch (_prefs.getString(_kThemeMode)) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs.setString(_kThemeMode, mode.name);
  }

  double? get fontSize => _prefs.getDouble(_kFontSize);

  Future<void> setFontSize(double value) async {
    await _prefs.setDouble(_kFontSize, value);
  }

  bool get chordsCollapsed => _prefs.getBool(_kChordsCollapsed) ?? false;

  Future<void> setChordsCollapsed(bool value) async {
    await _prefs.setBool(_kChordsCollapsed, value);
  }

  int transposeFor(int songNumber) =>
      _prefs.getInt('$_kTransposePrefix$songNumber') ?? 0;

  Future<void> setTransposeFor(int songNumber, int value) async {
    final key = '$_kTransposePrefix$songNumber';
    if (value == 0) {
      await _prefs.remove(key);
    } else {
      await _prefs.setInt(key, value);
    }
  }
}

/// Стиль системной панели навигации в зависимости от яркости темы.
SystemUiOverlayStyle _navBarStyle(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final color = isDark ? Colors.black : Colors.white;
  return SystemUiOverlayStyle(
    systemNavigationBarColor: color,
    systemNavigationBarDividerColor: color,
    systemNavigationBarIconBrightness:
        isDark ? Brightness.light : Brightness.dark,
  );
}

class Song {
  final int number;
  final String name;
  final String accords;
  final String content;

  const Song({
    required this.number,
    required this.name,
    required this.accords,
    required this.content,
  });

  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      number: json['number'] as int,
      name: (json['name'] as String?)?.trim() ?? '',
      accords: (json['accords'] as String?)?.trim() ?? '',
      content: (json['content'] as String?)?.trim() ?? '',
    );
  }

  /// Заголовок песни: поле `name`, иначе первая непустая строка текста.
  String get title {
    if (name.isNotEmpty) return name;
    for (final line in content.split('\n')) {
      final trimmed = stripMarkers(line).trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return 'Песня №$number';
  }
}

/// Убирает Markdown-маркеры выделения (`*`, `**`, `***`).
String stripMarkers(String text) => text.replaceAll('*', '');

/// Названия нот для вывода (немецкая нотация: `B` = си-бемоль, `H` = си).
const List<String> _noteNames = [
  'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'B', 'H',
];

/// Сопоставление обозначения ноты с её индексом в хроматической гамме.
const Map<String, int> _noteToIndex = {
  'C': 0, 'C#': 1, 'Cb': 11,
  'D': 2, 'D#': 3, 'Db': 1,
  'E': 4, 'E#': 5, 'Eb': 3,
  'F': 5, 'F#': 6, 'Fb': 4,
  'G': 7, 'G#': 8, 'Gb': 6,
  'A': 9, 'A#': 10, 'Ab': 8,
  'B': 10, 'Bb': 10,
  'H': 11, 'Hb': 10,
};

/// Распознаёт корни аккордов и транспонирует их на [semitones] полутонов.
///
/// Заглавные ноты (`A`–`H`) считаются корнями всегда, строчные (`a`–`h`) —
/// только если стоят отдельным токеном, чтобы не задеть суффиксы
/// вроде `aug`, `dim`, `add`, `maj`. Суффиксы и разделители сохраняются.
String transposeAccords(String text, int semitones) {
  final shift = semitones % 12;
  if (shift == 0) return text;

  final pattern = RegExp(r'[A-H](?:#|b|♭)?|(?<![A-Za-z])[a-h](?:#|b|♭)?');
  return text.replaceAllMapped(pattern, (match) {
    final token = match.group(0)!;
    final isLower = token[0].toLowerCase() == token[0];
    final key = (token[0].toUpperCase() + token.substring(1))
        .replaceAll('♭', 'b');

    final index = _noteToIndex[key];
    if (index == null) return token;

    final newIndex = (index + shift + 12) % 12;
    final name = _noteNames[newIndex];
    return isLower ? name.toLowerCase() : name;
  });
}

/// Разбирает строку с Markdown-маркерами выделения на спаны TextSpan.
///
/// Поддерживаются `***жирный курсив***`, `**жирный**` и `*курсив*`.
List<TextSpan> buildBoldSpans(String text) {
  final spans = <TextSpan>[];
  final pattern = RegExp(r'\*\*\*(.+?)\*\*\*|\*\*(.+?)\*\*|\*(.+?)\*');
  var index = 0;
  for (final match in pattern.allMatches(text)) {
    if (match.start > index) {
      spans.add(TextSpan(text: text.substring(index, match.start)));
    }
    if (match.group(1) != null) {
      spans.add(
        TextSpan(
          text: match.group(1),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    } else if (match.group(2) != null) {
      spans.add(
        TextSpan(
          text: match.group(2),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      );
    } else {
      spans.add(
        TextSpan(
          text: match.group(3),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ),
      );
    }
    index = match.end;
  }
  if (index < text.length) {
    spans.add(TextSpan(text: text.substring(index)));
  }
  return spans;
}

Future<List<Song>> loadSongs() async {
  final raw = await rootBundle.loadString('assets/songs.json');
  final data = json.decode(raw) as List<dynamic>;
  final songs = data
      .map((item) => Song.fromJson(item as Map<String, dynamic>))
      .toList();
  songs.sort((a, b) => a.number.compareTo(b.number));
  return songs;
}

class SbornikApp extends StatefulWidget {
  const SbornikApp({super.key});

  @override
  State<SbornikApp> createState() => _SbornikAppState();
}

class _SbornikAppState extends State<SbornikApp> {
  ThemeMode _themeMode = Settings.instance.themeMode;

  void _toggleTheme() {
    setState(() {
      _themeMode =
          _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
    Settings.instance.setThemeMode(_themeMode);
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF5B4BB5);
    return MaterialApp(
      title: 'Сборник песен',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
      ),
      builder: (context, child) {
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: _navBarStyle(Theme.of(context).brightness),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: HomePage(onToggleTheme: _toggleTheme),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.onToggleTheme});

  final VoidCallback onToggleTheme;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List<Song>> _songsFuture;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _songsFuture = loadSongs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Song> _filter(List<Song> songs) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return songs;
    return songs.where((song) {
      if (song.number.toString() == query) return true;
      if (song.number.toString().startsWith(query)) return true;
      return stripMarkers(song.content).toLowerCase().contains(query) ||
          song.title.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Сборник песен'),
        actions: [
          IconButton(
            tooltip: 'Сменить тему',
            icon: const Icon(Icons.brightness_6_outlined),
            onPressed: widget.onToggleTheme,
          ),
        ],
      ),
      body: FutureBuilder<List<Song>>(
        future: _songsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Не удалось загрузить песни:\n${snapshot.error}'),
              ),
            );
          }

          final songs = snapshot.data ?? const <Song>[];
          final filtered = _filter(songs);

          return SafeArea(
            top: false,
            child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _query = value),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Поиск по номеру или тексту',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                          ),
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              if (filtered.isEmpty)
                const Expanded(
                  child: Center(child: Text('Ничего не найдено')),
                )
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final song = filtered[index];
                      return SongListTile(
                        song: song,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => SongPage(
                                songs: filtered,
                                initialIndex: index,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
            ],
            ),
          );
        },
      ),
    );
  }
}

class SongListTile extends StatelessWidget {
  const SongListTile({super.key, required this.song, required this.onTap});

  final Song song;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        child: Text(
          '${song.number}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      title: Text(
        song.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

class SongPage extends StatefulWidget {
  const SongPage({
    super.key,
    required this.songs,
    required this.initialIndex,
  });

  final List<Song> songs;
  final int initialIndex;

  @override
  State<SongPage> createState() => _SongPageState();
}

class _SongPageState extends State<SongPage> {
  static const double _minFontSize = 14;
  static const double _maxFontSize = 34;
  double _fontSize = Settings.instance.fontSize ?? 18;
  bool _chordsCollapsed = Settings.instance.chordsCollapsed;
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _changeFontSize(double delta) {
    setState(() {
      _fontSize = (_fontSize + delta).clamp(_minFontSize, _maxFontSize);
    });
    Settings.instance.setFontSize(_fontSize);
  }

  void _toggleChords() {
    setState(() => _chordsCollapsed = !_chordsCollapsed);
    Settings.instance.setChordsCollapsed(_chordsCollapsed);
  }

  @override
  Widget build(BuildContext context) {
    final song = widget.songs[_index];

    return Scaffold(
      appBar: AppBar(
        title: Text('Песня №${song.number}'),
        actions: [
          IconButton(
            tooltip: 'Уменьшить шрифт',
            icon: const Icon(Icons.text_decrease),
            onPressed: _fontSize <= _minFontSize
                ? null
                : () => _changeFontSize(-2),
          ),
          IconButton(
            tooltip: 'Увеличить шрифт',
            icon: const Icon(Icons.text_increase),
            onPressed: _fontSize >= _maxFontSize
                ? null
                : () => _changeFontSize(2),
          ),
        ],
      ),
      body: SafeArea(
        child: PageView.builder(
          controller: _controller,
          itemCount: widget.songs.length,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (context, i) {
            return _SongView(
              song: widget.songs[i],
              fontSize: _fontSize,
              chordsCollapsed: _chordsCollapsed,
              onToggleChords: _toggleChords,
            );
          },
        ),
      ),
    );
  }
}

class _SongView extends StatefulWidget {
  const _SongView({
    required this.song,
    required this.fontSize,
    required this.chordsCollapsed,
    required this.onToggleChords,
  });

  final Song song;
  final double fontSize;
  final bool chordsCollapsed;
  final VoidCallback onToggleChords;

  @override
  State<_SongView> createState() => _SongViewState();
}

class _SongViewState extends State<_SongView> {
  late int _transpose = Settings.instance.transposeFor(widget.song.number);

  void _changeTranspose(int delta) {
    setState(() {
      _transpose = (_transpose + delta).clamp(-11, 11);
    });
    Settings.instance.setTransposeFor(widget.song.number, _transpose);
  }

  void _resetTranspose() {
    if (_transpose != 0) {
      setState(() => _transpose = 0);
      Settings.instance.setTransposeFor(widget.song.number, 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final song = widget.song;
    final fontSize = widget.fontSize;
    final scheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
                child: Text(
                  '${song.number}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  song.title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (song.accords.isNotEmpty) ...[
            Row(
              children: [
                _ChordsToggle(
                  collapsed: widget.chordsCollapsed,
                  color: scheme.secondary,
                  onTap: widget.onToggleChords,
                ),
                const Spacer(),
                if (!widget.chordsCollapsed)
                  _TransposeControls(
                    value: _transpose,
                    onChange: _changeTranspose,
                    onReset: _resetTranspose,
                  ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: widget.chordsCollapsed
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 20),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: scheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: SelectableText(
                          transposeAccords(song.accords, _transpose),
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: fontSize,
                            height: 1.5,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 16),
          ],
          SelectableText.rich(
            TextSpan(
              style: TextStyle(
                fontSize: fontSize,
                height: 1.6,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
              children: buildBoldSpans(song.content),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransposeControls extends StatelessWidget {
  const _TransposeControls({
    required this.value,
    required this.onChange,
    required this.onReset,
  });

  final int value;
  final ValueChanged<int> onChange;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = value == 0
        ? '0'
        : (value > 0 ? '+$value' : '$value');

    return Container(
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Понизить на полтона',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove),
            color: scheme.onSecondaryContainer,
            onPressed: value <= -11 ? null : () => onChange(-1),
          ),
          Tooltip(
            message: 'Сбросить тональность',
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onReset,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 28),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: scheme.onSecondaryContainer,
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Повысить на полтона',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add),
            color: scheme.onSecondaryContainer,
            onPressed: value >= 11 ? null : () => onChange(1),
          ),
        ],
      ),
    );
  }
}

/// Кнопка-переключатель видимости блока аккордов.
class _ChordsToggle extends StatelessWidget {
  const _ChordsToggle({
    required this.collapsed,
    required this.color,
    required this.onTap,
  });

  final bool collapsed;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Tooltip(
        message: collapsed ? 'Показать аккорды' : 'Скрыть аккорды',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.music_note, size: 18, color: color),
              const SizedBox(width: 6),
              Text(
                'АККОРДЫ',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                collapsed ? Icons.expand_more : Icons.expand_less,
                size: 18,
                color: color,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
