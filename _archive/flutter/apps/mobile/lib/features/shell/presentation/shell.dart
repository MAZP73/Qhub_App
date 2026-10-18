import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:qhub_ui/qhub_ui.dart';

class _Tab {
  const _Tab(this.path, this.label, this.icon);
  final String path;
  final String label;
  final QhIcons icon;
}

const _tabs = [
  _Tab('/turno', 'Turno', QhIcons.ticket),
  _Tab('/explorar', 'Explorar', QhIcons.search),
  _Tab('/avisos', 'Avisos', QhIcons.bell),
  _Tab('/historial', 'Historial', QhIcons.history),
];

/// Barra de pestañas inferior de 4 ítems (design: móvil).
class MobileShell extends StatelessWidget {
  const MobileShell({super.key, required this.child, required this.location});
  final Widget child;
  final String location;

  @override
  Widget build(BuildContext context) {
    final c = context.qh;
    final current = _tabs.indexWhere((t) => location.startsWith(t.path));
    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(color: c.layer01, border: Border(top: BorderSide(color: c.borderSubtle))),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 56,
            child: Row(children: [
              for (var i = 0; i < _tabs.length; i++)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: i == current,
                    label: _tabs[i].label,
                    excludeSemantics: true,
                    child: InkWell(
                      onTap: () => context.go(_tabs[i].path),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        QhIcon(_tabs[i].icon, size: 20, color: i == current ? c.link : c.textSecondary),
                        const SizedBox(height: 2),
                        Text(_tabs[i].label,
                            style: QhText.caption.copyWith(color: i == current ? c.link : c.textSecondary, fontWeight: i == current ? FontWeight.w600 : FontWeight.w400)),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
