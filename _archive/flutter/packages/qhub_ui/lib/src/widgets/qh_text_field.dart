import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/qh_theme.dart';
import '../tokens/qh_tokens.g.dart';
import 'qh_icon.dart';

/// Campo con label arriba, fondo `field` y borde inferior. Error: contorno 2 px + ícono + mensaje.
class QhTextField extends StatefulWidget {
  const QhTextField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.helper,
    this.errorText,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.autofillHints,
    this.enabled = true,
    this.inputFormatters,
    this.autofocus = false,
    this.maxLines = 1,
    this.maxLength,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final String? helper;
  final String? errorText;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;
  final bool enabled;
  final List<TextInputFormatter>? inputFormatters;
  final bool autofocus;
  final int maxLines;
  final int? maxLength;

  @override
  State<QhTextField> createState() => _QhTextFieldState();
}

class _QhTextFieldState extends State<QhTextField> {
  late bool _hidden = widget.obscure;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.qh;
    final hasError = widget.errorText != null;
    final border = hasError
        ? Border.all(color: c.supportError, width: 2)
        : _focus.hasFocus
            ? Border.all(color: c.focus, width: 2)
            : Border(bottom: BorderSide(color: c.borderStrong));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.label, style: QhText.label.copyWith(color: c.textSecondary)),
        const SizedBox(height: QhSpacing.s02),
        Container(
          constraints: const BoxConstraints(minHeight: QhSize.controlMd),
          decoration: BoxDecoration(color: c.field, border: border),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  textField: true,
                  label: widget.label,
                  child: TextField(
                    focusNode: _focus,
                    controller: widget.controller,
                    enabled: widget.enabled,
                    obscureText: _hidden,
                    keyboardType: widget.keyboardType,
                    textInputAction: widget.textInputAction,
                    onChanged: widget.onChanged,
                    onSubmitted: widget.onSubmitted,
                    autofillHints: widget.autofillHints,
                    inputFormatters: widget.inputFormatters,
                    autofocus: widget.autofocus,
                    maxLines: widget.maxLines,
                    maxLength: widget.maxLength,
                    buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                    style: QhText.body.copyWith(color: widget.enabled ? c.textPrimary : c.textDisabled),
                    cursorColor: c.interactive,
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: widget.hint,
                      hintStyle: QhText.body.copyWith(color: c.textPlaceholder),
                      contentPadding: const EdgeInsets.symmetric(horizontal: QhSpacing.s05, vertical: QhSpacing.s04),
                    ),
                  ),
                ),
              ),
              if (widget.obscure)
                TextButton(
                  onPressed: () => setState(() => _hidden = !_hidden),
                  child: Text(_hidden ? 'Mostrar' : 'Ocultar', style: QhText.label.copyWith(color: c.link)),
                ),
              if (hasError)
                Padding(
                  padding: const EdgeInsets.only(right: QhSpacing.s04),
                  child: QhIcon(QhIcons.warning, color: c.supportError),
                ),
            ],
          ),
        ),
        if (hasError || widget.helper != null) ...[
          const SizedBox(height: QhSpacing.s02),
          Text(
            widget.errorText ?? widget.helper!,
            style: QhText.caption.copyWith(color: hasError ? c.supportError : c.textSecondary),
          ),
        ],
      ],
    );
  }
}

/// Lista desplegable simple con el estilo de campo.
class QhSelect<T> extends StatelessWidget {
  const QhSelect({super.key, required this.label, required this.value, required this.items, required this.onChanged});
  final String label;
  final T? value;
  final Map<T, String> items;
  final ValueChanged<T?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.qh;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: QhText.label.copyWith(color: c.textSecondary)),
        const SizedBox(height: QhSpacing.s02),
        Container(
          height: QhSize.controlMd,
          padding: const EdgeInsets.symmetric(horizontal: QhSpacing.s05),
          decoration: BoxDecoration(color: c.field, border: Border(bottom: BorderSide(color: c.borderStrong))),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              dropdownColor: c.layer01,
              style: QhText.body.copyWith(color: c.textPrimary),
              icon: QhIcon(QhIcons.chevronDown, color: c.textSecondary),
              items: [for (final e in items.entries) DropdownMenuItem<T>(value: e.key, child: Text(e.value))],
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}
