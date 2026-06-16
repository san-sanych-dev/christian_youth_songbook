import 'package:flutter_test/flutter_test.dart';

import 'package:sbornik/main.dart';

void main() {
  test('Song.title returns name when present', () {
    const song = Song(
      number: 1,
      name: 'Заголовок',
      accords: 'C G',
      content: '  \nПервая строка\nВторая',
    );
    expect(song.title, 'Заголовок');
  });

  test('Song.title falls back to first non-empty line', () {
    const song = Song(
      number: 1,
      name: '',
      accords: 'C G',
      content: '  \n**Первая строка**\nВторая',
    );
    expect(song.title, 'Первая строка');
  });

  test('Song.fromJson parses fields', () {
    final song = Song.fromJson({
      'number': 5,
      'accords': 'Am',
      'content': 'Текст песни',
    });
    expect(song.number, 5);
    expect(song.accords, 'Am');
    expect(song.content, 'Текст песни');
  });
}
