// Genera lib/src/tokens/qh_tokens.g.dart desde tokens/tokens.json (design system).
// Uso: dart run tool/gen_tokens.dart
import 'dart:convert';
import 'dart:io';

String camel(String name) {
  final parts = name.split(RegExp(r'[-_.]'));
  return parts.first + parts.skip(1).map((p) => p.isEmpty ? '' : p[0].toUpperCase() + p.substring(1)).join();
}

String hex(String v) {
  var h = v.replaceFirst('#', '');
  if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
  if (h.length == 6) return '0xFF${h.toUpperCase()}';
  if (h.length == 8) return '0x${h.substring(6).toUpperCase()}${h.substring(0, 6).toUpperCase()}'; // RGBA → ARGB
  throw FormatException('Color no soportado: $v');
}

num px(String v) => num.parse(v.replaceAll('px', '').replaceAll('%', ''));

void main() {
  final json = jsonDecode(File('tokens/tokens.json').readAsStringSync()) as Map<String, dynamic>;
  final out = StringBuffer()
    ..writeln('// GENERADO por tool/gen_tokens.dart desde tokens/tokens.json. No editar a mano.')
    ..writeln('// ignore_for_file: lines_longer_than_80_chars')
    ..writeln("import 'package:flutter/material.dart';")
    ..writeln();

  // ---- colores ----
  final color = json['color'] as Map<String, dynamic>;
  final themes = (color['themes'] as List).map((t) => (t as Map)['id'] as String).toList();
  final tokens = (color['tokens'] as List).cast<Map<String, dynamic>>();
  final byName = {for (final t in tokens) t['name'] as String: t};

  String resolve(String name, String theme, [int depth = 0]) {
    if (depth > 8) throw StateError('Alias circular: $name');
    final raw = byName[name]!['value'];
    final String v = raw is Map ? (raw[theme] ?? raw[themes.first]) as String : raw as String;
    if (v.startsWith('{')) return resolve(v.substring(1, v.length - 1), theme, depth + 1);
    return hex(v);
  }

  final names = byName.keys.toList();
  out.writeln('/// Colores del design system (ThemeExtension). Acceso: `context.qh`.');
  out.writeln('@immutable');
  out.writeln('class QhColors extends ThemeExtension<QhColors> {');
  out.writeln('  const QhColors({');
  for (final n in names) {
    out.writeln('    required this.${camel(n)},');
  }
  out.writeln('  });');
  for (final n in names) {
    final usage = (byName[n]!['usage'] as String).replaceAll('\n', ' ');
    out.writeln('  /// $usage');
    out.writeln('  final Color ${camel(n)};');
  }
  for (final theme in themes) {
    out.writeln('  static const QhColors $theme = QhColors(');
    for (final n in names) {
      out.writeln('    ${camel(n)}: Color(${resolve(n, theme)}),');
    }
    out.writeln('  );');
  }
  out.writeln('  @override');
  out.writeln('  QhColors copyWith({');
  for (final n in names) {
    out.writeln('    Color? ${camel(n)},');
  }
  out.writeln('  }) =>');
  out.writeln('      QhColors(');
  for (final n in names) {
    out.writeln('        ${camel(n)}: ${camel(n)} ?? this.${camel(n)},');
  }
  out.writeln('      );');
  out.writeln('  @override');
  out.writeln('  QhColors lerp(ThemeExtension<QhColors>? other, double t) {');
  out.writeln('    if (other is! QhColors) return this;');
  out.writeln('    return QhColors(');
  for (final n in names) {
    out.writeln('      ${camel(n)}: Color.lerp(${camel(n)}, other.${camel(n)}, t)!,');
  }
  out.writeln('    );');
  out.writeln('  }');
  out.writeln('}');
  out.writeln();

  // ---- spacing / size / radius ----
  void consts(String cls, String key, {String prefix = ''}) {
    final list = ((json[key] as Map)['tokens'] as List).cast<Map<String, dynamic>>();
    out.writeln('abstract final class $cls {');
    for (final t in list) {
      final n = camel((t['name'] as String).replaceFirst(prefix, ''));
      final v = (t['value'] as String);
      out.writeln('  /// ${t['usage']}');
      out.writeln('  static const double ${n.startsWith(RegExp(r'[0-9]')) ? 's$n' : n} = ${v.contains('%') ? 999 : px(v)};');
    }
    out.writeln('}');
    out.writeln();
  }

  consts('QhSpacing', 'spacing', prefix: 'spacing-');
  consts('QhSize', 'size');
  consts('QhRadius', 'radius', prefix: 'radius-');

  // ---- tipografía ----
  final type = json['type'] as Map<String, dynamic>;
  String famOf(String key) => key == 'mono' ? 'IBMPlexMono' : 'IBMPlexSans';
  out.writeln('/// Estilos de texto sin color (el color lo pone el tema/widget).');
  out.writeln('abstract final class QhText {');
  for (final g in (type['groups'] as List).cast<Map<String, dynamic>>()) {
    final fam = famOf(g['family'] as String);
    for (final s in (g['styles'] as List).cast<Map<String, dynamic>>()) {
      final size = px(s['fontSize'] as String);
      final lh = px(s['lineHeight'] as String);
      final w = s['fontWeight'] as int;
      final ls = s['letterSpacing'] != null ? px(s['letterSpacing'] as String) : 0;
      final variable = fam == 'IBMPlexSans';
      out.writeln('  /// ${s['usage']}');
      out.writeln('  static const TextStyle ${camel(s['name'] as String)} = TextStyle(');
      out.writeln("    fontFamily: '$fam', package: 'qhub_ui', fontSize: $size, height: ${(lh / size).toStringAsFixed(4)}, "
          'fontWeight: FontWeight.w$w, letterSpacing: $ls,');
      if (variable) out.writeln("    fontVariations: [FontVariation('wght', $w)],");
      out.writeln('  );');
    }
  }
  out.writeln('}');

  File('lib/src/tokens/qh_tokens.g.dart').writeAsStringSync(out.toString());
  stdout.writeln('OK: ${names.length} colores, ${themes.length} temas');
}
