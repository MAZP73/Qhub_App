import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum QhLogoKind {
  horizontal('qhub-horizontal'),
  horizontalNegative('qhub-horizontal-negativo'),
  appIcon('qhub-icono'),
  symbol('qhub-simbolo');

  const QhLogoKind(this.file);
  final String file;
}

/// Logo oficial. Fondo claro → horizontal; Ink → negativo; ícono de app y símbolo (favicon).
class QhLogo extends StatelessWidget {
  const QhLogo(this.kind, {super.key, this.height = 24});
  final QhLogoKind kind;
  final double height;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
        'assets/logos/${kind.file}.svg',
        package: 'qhub_ui',
        height: height,
        semanticsLabel: 'Qhub',
      );
}
