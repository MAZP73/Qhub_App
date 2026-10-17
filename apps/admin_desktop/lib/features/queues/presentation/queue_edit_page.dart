import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qhub_api_client/qhub_api_client.dart' hide Queue;
import 'package:qhub_core/qhub_core.dart';
import 'package:qhub_ui/qhub_ui.dart';

import '../../../app/providers.dart';
import '../../../app/widgets.dart';
import '../../auth/presentation/setup_page.dart' show timeZones;
import '../domain/schedule_form.dart';
import 'queue_providers.dart';

/// Crea o edita una cola y su horario (solo admin).
class QueueEditPage extends ConsumerStatefulWidget {
  const QueueEditPage({super.key, this.queueId});
  final String? queueId;

  @override
  ConsumerState<QueueEditPage> createState() => _QueueEditPageState();
}

class _QueueEditPageState extends ConsumerState<QueueEditPage> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _prefix = TextEditingController();
  final _opens = TextEditingController(text: '08:00');
  final _closes = TextEditingController(text: '17:00');
  final _turn = TextEditingController(text: '10');
  final _stations = TextEditingController(text: '1');
  final _daily = TextEditingController(text: '0');
  final _ahead = TextEditingController(text: '7');
  var _slot = 30;
  var _days = <int>{1, 2, 3, 4, 5};
  var _zone = 'America/Guayaquil';
  var _active = true;
  var _loading = false;
  var _saving = false;
  var _dirty = false;
  Failure? _error;
  final _errs = <String, String>{};
  String? _loadedName;

  bool get _editing => widget.queueId != null;

  @override
  void initState() {
    super.initState();
    _zone = ref.read(activeMembershipProvider)?.organization.timeZone ?? _zone;
    if (!timeZones.containsKey(_zone)) _zone = 'UTC';
    if (_editing) _load();
    for (final c in [_name, _desc, _prefix, _opens, _closes, _turn, _stations, _daily, _ahead]) {
      c.addListener(() => setState(() => _dirty = true));
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final repo = ref.read(queueRepositoryProvider);
    final id = widget.queueId!;
    final q = await repo.get(id);
    final s = await repo.schedule(id);
    final prefixes = await ref.read(queuePrefixesProvider.future);
    if (!mounted) return;
    q.when(
      ok: (queue) {
        _name.text = queue.name;
        _desc.text = queue.description ?? '';
        _active = queue.active;
        _loadedName = queue.name;
        _prefix.text = prefixes[id] ?? defaultQueuePrefix(queue.name);
      },
      err: (f) => _error = f,
    );
    s.when(
      ok: (sch) {
        _opens.text = trimSeconds(sch.opens);
        _closes.text = trimSeconds(sch.closes);
        _slot = const [10, 15, 20, 30, 45, 60, 90, 120].contains(sch.slotMinutes) ? sch.slotMinutes : 30;
        _days = sch.days.toSet();
        _turn.text = '${sch.turnMinutes}';
        _stations.text = '${sch.stations}';
        _daily.text = '${sch.dailyCapacity}';
        _ahead.text = '${sch.maxDaysAhead}';
        _zone = timeZones.containsKey(sch.timeZone) ? sch.timeZone : 'UTC';
      },
      err: (f) => _error ??= f,
    );
    setState(() {
      _loading = false;
      _dirty = false;
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _desc, _prefix, _opens, _closes, _turn, _stations, _daily, _ahead]) {
      c.dispose();
    }
    super.dispose();
  }

  int _int(TextEditingController c, [int fallback = 0]) => int.tryParse(c.text.trim()) ?? fallback;

  ScheduleInput? _input() {
    if (!isValidHm(_opens.text) || !isValidHm(_closes.text)) return null;
    return ScheduleInput(
      opens: normalizeHm(_opens.text),
      closes: normalizeHm(_closes.text),
      slotMinutes: _slot,
      days: (_days.toList()..sort()),
      turnMinutes: _int(_turn, 1),
      stations: _int(_stations, 1),
      dailyCapacity: _int(_daily),
      maxDaysAhead: _int(_ahead),
      timeZone: _zone,
    );
  }

  bool _validate() {
    _errs.clear();
    if (_name.text.trim().isEmpty) _errs['name'] = 'Escribe el nombre de la cola.';
    if (!RegExp(r'^[A-Za-z]{1,2}$').hasMatch(_prefix.text.trim())) _errs['prefix'] = '1 o 2 letras (A–Z).';
    if (!isValidHm(_opens.text)) _errs['opens'] = 'Usa HH:mm.';
    if (!isValidHm(_closes.text)) _errs['closes'] = 'Usa HH:mm.';
    final input = _input();
    if (input != null) {
      final err = const ValidateSchedule()(input);
      if (err != null) _errs['schedule'] = err;
    }
    setState(() {});
    return _errs.isEmpty;
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (!_validate()) return;
    final input = _input()!;
    setState(() => _saving = true);
    final queues = ref.read(queueRepositoryProvider);
    final staff = ref.read(staffRepositoryProvider);
    final org = ref.read(activeMembershipProvider)!.organization.id;

    Result<String> res;
    if (_editing) {
      final id = widget.queueId!;
      final patch = await queues.update(id, name: _name.text.trim(), description: _desc.text.trim());
      if (patch.isErr) {
        res = Result.err(patch.failureOrNull!);
      } else {
        final sch = await ReplaceSchedule(queues)(id, input);
        res = sch.when(ok: (_) => Result.ok(id), err: (f) => Result.err(f));
      }
    } else {
      final created = await CreateQueue(queues)(CreateQueueInput(name: _name.text, description: _desc.text, schedule: input));
      res = created.map((q) => q.id);
    }

    if (!mounted) return;
    if (res.isErr) {
      setState(() {
        _saving = false;
        _error = res.failureOrNull;
      });
      return;
    }
    final id = res.valueOrNull!;
    await staff.setQueuePrefix(org, id, _prefix.text.trim());
    await staff.audit(org, _editing ? 'cola.editar' : 'cola.crear', entity: 'cola', entityId: id, detail: {'nombre': _name.text.trim()});
    ref.invalidate(queuesProvider);
    ref.invalidate(queueLimitProvider);
    ref.invalidate(queuePrefixesProvider);
    if (!mounted) return;
    showToast(context, _editing ? 'Cola actualizada.' : 'Cola creada.');
    context.go('/colas');
  }

  Future<void> _archive() async {
    final ok = await qhConfirm(context,
        title: 'Eliminar cola',
        message: 'Se archiva "${_loadedName ?? _name.text}": libera un lugar y su nombre, y se conserva el historial de turnos.',
        confirmLabel: 'Eliminar cola');
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    final res = await ref.read(queueRepositoryProvider).delete(widget.queueId!);
    if (!mounted) return;
    if (res.isErr) {
      setState(() { _saving = false; _error = res.failureOrNull; });
      return;
    }
    final org = ref.read(activeMembershipProvider)!.organization.id;
    await ref.read(staffRepositoryProvider).audit(org, 'cola.archivar', entity: 'cola', entityId: widget.queueId);
    ref.invalidate(queuesProvider);
    ref.invalidate(queueLimitProvider);
    if (!mounted) return;
    showToast(context, 'Cola archivada.');
    context.go('/colas');
  }

  Future<void> _reactivate() async {
    setState(() => _saving = true);
    final res = await ref.read(queueRepositoryProvider).update(widget.queueId!, active: true);
    if (!mounted) return;
    if (res.isErr) {
      setState(() { _saving = false; _error = res.failureOrNull; });
      return;
    }
    ref.invalidate(queuesProvider);
    ref.invalidate(queueLimitProvider);
    showToast(context, 'Cola reactivada.');
    context.go('/colas');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.qh;
    final input = _input();
    final summary = input == null ? null : summarize(input);
    final digits = [FilteringTextInputFormatter.digitsOnly];

    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        PageHead(
          title: _editing ? 'Editar cola' : 'Crear cola',
          breadcrumb: 'Colas${_loadedName == null ? '' : ' / $_loadedName'}',
          actions: [
            if (_dirty) Text('Cambios sin guardar', style: QhText.caption.copyWith(color: c.textSecondary)),
            QhButton(label: 'Cancelar', kind: QhButtonKind.ghost, onPressed: () => context.go('/colas')),
            QhButton(label: 'Guardar cola', icon: QhIcons.check, loading: _saving, onPressed: _loading || !_active ? null : _save),
          ],
        ),
        if (_error != null) ...[
          QhNotice(kind: QhNoticeKind.error, title: _error!.message),
          const SizedBox(height: QhSpacing.s05),
        ],
        if (_errs['schedule'] != null) ...[
          QhNotice(kind: QhNoticeKind.warning, title: _errs['schedule']!),
          const SizedBox(height: QhSpacing.s05),
        ],
        if (_editing && !_active) ...[
          QhNotice(kind: QhNoticeKind.info, title: 'Esta cola está archivada.', message: 'Reactívala para volver a editarla y recibir turnos.'),
          const SizedBox(height: QhSpacing.s05),
        ],
        if (_loading)
          const Skeleton(height: 320)
        else
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(children: [
                Panel(title: 'Información', child: Column(children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(flex: 3, child: QhTextField(label: 'Nombre de la cola', controller: _name, errorText: _errs['name'])),
                    const SizedBox(width: QhSpacing.s05),
                    Expanded(child: QhTextField(label: 'Prefijo del turno', controller: _prefix, errorText: _errs['prefix'], helper: 'Turnos ${_prefix.text.isEmpty ? 'A' : _prefix.text.toUpperCase()}-001…', maxLength: 2)),
                  ]),
                  const SizedBox(height: QhSpacing.s05),
                  QhTextField(label: 'Descripción (opcional)', controller: _desc),
                ])),
                const SizedBox(height: QhSpacing.s05),
                Panel(title: 'Horario', child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Días de atención', style: QhText.label.copyWith(color: c.textSecondary)),
                  const SizedBox(height: QhSpacing.s03),
                  Row(children: [
                    for (var i = 0; i < 7; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: QhSpacing.s03),
                        child: _DayChip(
                          label: weekdayLetters[i],
                          selected: _days.contains(i + 1),
                          onTap: () => setState(() { _dirty = true; _days.contains(i + 1) ? _days.remove(i + 1) : _days.add(i + 1); }),
                        ),
                      ),
                  ]),
                  const SizedBox(height: QhSpacing.s05),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: QhTextField(label: 'Apertura', controller: _opens, errorText: _errs['opens'], hint: '08:00')),
                    const SizedBox(width: QhSpacing.s05),
                    Expanded(child: QhTextField(label: 'Cierre', controller: _closes, errorText: _errs['closes'], hint: '17:00')),
                    const SizedBox(width: QhSpacing.s05),
                    Expanded(child: QhSelect<String>(label: 'Zona horaria', value: _zone, items: timeZones, onChanged: (v) => setState(() { _zone = v ?? _zone; _dirty = true; }))),
                  ]),
                ])),
                const SizedBox(height: QhSpacing.s05),
                Panel(title: 'Franjas y cupos', child: Column(children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: QhSelect<int>(
                      label: 'Duración de franja',
                      value: _slot,
                      items: {for (final m in const [10, 15, 20, 30, 45, 60, 90, 120]) m: '$m minutos'},
                      onChanged: (v) => setState(() { _slot = v ?? _slot; _dirty = true; }),
                    )),
                    const SizedBox(width: QhSpacing.s05),
                    Expanded(child: QhTextField(label: 'Duración del trámite (min)', controller: _turn, keyboardType: TextInputType.number, inputFormatters: digits)),
                    const SizedBox(width: QhSpacing.s05),
                    Expanded(child: QhTextField(label: 'Puestos en paralelo', controller: _stations, keyboardType: TextInputType.number, inputFormatters: digits, helper: 'Ventanillas o agentes')),
                  ]),
                  const SizedBox(height: QhSpacing.s05),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: QhTextField(label: 'Reservar con anticipación (días)', controller: _ahead, keyboardType: TextInputType.number, inputFormatters: digits)),
                    const SizedBox(width: QhSpacing.s05),
                    Expanded(child: QhTextField(label: 'Tope diario (0 = sin tope)', controller: _daily, keyboardType: TextInputType.number, inputFormatters: digits)),
                    const SizedBox(width: QhSpacing.s05),
                    const Expanded(child: SizedBox()),
                  ]),
                ])),
              ]),
            ),
            const SizedBox(width: QhSpacing.s05),
            SizedBox(
              width: 320,
              child: Column(children: [
                Panel(title: 'Resumen', child: Column(children: [
                  _Row('Franjas por día', '${summary?.slotsPerDay ?? '—'}'),
                  _Row('Cupos por franja', '${summary?.capacityPerSlot ?? '—'}'),
                  _Row('Turnos por día', '${summary?.turnsPerDay ?? '—'}'),
                  _Row('Turnos por semana', '${summary?.turnsPerWeek ?? '—'}'),
                  const SizedBox(height: QhSpacing.s03),
                  Text('Los cupos se calculan: franja ÷ trámite × puestos.', style: QhText.caption.copyWith(color: c.textSecondary)),
                ])),
                if (_editing) ...[
                  const SizedBox(height: QhSpacing.s05),
                  Panel(title: _active ? 'Zona de peligro' : 'Cola archivada', child: _active
                      ? QhButton(label: 'Eliminar cola', icon: QhIcons.trash, kind: QhButtonKind.danger, onPressed: _saving ? null : _archive)
                      : QhButton(label: 'Reactivar cola', icon: QhIcons.play, onPressed: _saving ? null : _reactivate)),
                ],
              ]),
            ),
          ]),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.k, this.v);
  final String k;
  final String v;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(child: Text(k, style: QhText.body.copyWith(color: context.qh.textSecondary))),
          Text(v, style: QhText.code.copyWith(color: context.qh.textPrimary)),
        ]),
      );
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.qh;
    return Semantics(
      button: true,
      toggled: selected,
      label: 'Día $label',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: selected ? c.interactive : c.field, border: selected ? null : Border(bottom: BorderSide(color: c.borderStrong))),
          child: Text(label, style: QhText.body.copyWith(color: selected ? c.textOnColor : c.textPrimary, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}
