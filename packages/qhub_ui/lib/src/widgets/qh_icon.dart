import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/qh_theme.dart';

/// Set propio de íconos del design system (trazo 1.5 px, cuadrícula 16).
enum QhIcons {
  arrowRight('arrow-right'),
  bell('bell'),
  building('building'),
  calendar('calendar'),
  call('call'),
  chart('chart'),
  check('check'),
  chevronDown('chevron-down'),
  chevronLeft('chevron-left'),
  chevronRight('chevron-right'),
  clock('clock'),
  close('close'),
  code('code'),
  copy('copy'),
  dashboard('dashboard'),
  edit('edit'),
  error('error'),
  filter('filter'),
  history('history'),
  info('info'),
  live('live'),
  location('location'),
  logout('logout'),
  menu('menu'),
  noshow('noshow'),
  overflow('overflow'),
  play('play'),
  plus('plus'),
  queue('queue'),
  search('search'),
  settings('settings'),
  ticket('ticket'),
  trash('trash'),
  user('user'),
  warning('warning');

  const QhIcons(this.file);
  final String file;
  String get asset => 'assets/icons/$file.svg';
}

/// Ícono tintado por máscara. Tamaños del sistema: 16, 20 (móvil), 24, 32.
class QhIcon extends StatelessWidget {
  const QhIcon(this.icon, {super.key, this.size = 16, this.color, this.semanticLabel});
  final QhIcons icon;
  final double size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? DefaultTextStyle.of(context).style.color ?? context.qh.textPrimary;
    return SvgPicture.asset(
      icon.asset,
      package: 'qhub_ui',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
      semanticsLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
    );
  }
}
