import 'package:flutter/material.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';

/// A number pad for the vault's PIN. The PIN is typed on the pad rather than
/// in a text field, so no keyboard learns it or suggests it (IMG-011).
class PinPad extends StatefulWidget {
  const PinPad({
    required this.onSubmit,
    this.enabled = true,
    this.minLength = 4,
    this.maxLength = 12,
    super.key,
  });

  /// Called with the digits when the user presses Unlock.
  final ValueChanged<String> onSubmit;
  final bool enabled;
  final int minLength;
  final int maxLength;

  @override
  State<PinPad> createState() => PinPadState();
}

class PinPadState extends State<PinPad> {
  String _digits = '';

  /// Digits typed so far.
  String get digits => _digits;

  /// Wipes what was typed (after a wrong PIN, and when the screen goes).
  void clear() => setState(() => _digits = '');

  void _add(String d) {
    if (!widget.enabled || _digits.length >= widget.maxLength) return;
    setState(() => _digits += d);
  }

  void _back() {
    if (!widget.enabled || _digits.isEmpty) return;
    setState(() => _digits = _digits.substring(0, _digits.length - 1));
  }

  void _submit() {
    if (!widget.enabled || _digits.length < widget.minLength) return;
    final entered = _digits;
    setState(() => _digits = '');
    widget.onSubmit(entered);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    Widget key(String d) => _Key(
      label: d,
      semantics: l10n.photosVaultDigit(d),
      onTap: widget.enabled ? () => _add(d) : null,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          liveRegion: true,
          label: l10n.photosVaultDigitsEntered(_digits.length),
          excludeSemantics: true,
          child: SizedBox(
            height: 32,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _digits.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: Icon(
                      Icons.circle,
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [for (final d in row) key(d)],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Key(
              icon: Icons.backspace_outlined,
              semantics: l10n.photosVaultBackspace,
              onTap: widget.enabled && _digits.isNotEmpty ? _back : null,
            ),
            key('0'),
            _Key(
              icon: Icons.check,
              semantics: l10n.photosVaultUnlock,
              onTap: widget.enabled && _digits.length >= widget.minLength
                  ? _submit
                  : null,
              filled: true,
            ),
          ],
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    required this.semantics,
    required this.onTap,
    this.label,
    this.icon,
    this.filled = false,
  });

  final String? label;
  final IconData? icon;
  final String semantics;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(6),
      child: SizedBox.square(
        dimension: 64,
        child: Semantics(
          button: true,
          enabled: onTap != null,
          label: semantics,
          excludeSemantics: true,
          onTap: onTap,
          child: Material(
            shape: const CircleBorder(),
            color: filled && onTap != null
                ? scheme.primary
                : scheme.surfaceContainerHighest,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Center(
                child: label != null
                    ? Text(
                        label!,
                        style: Theme.of(context).textTheme.headlineSmall,
                      )
                    : Icon(
                        icon,
                        color: filled && onTap != null
                            ? scheme.onPrimary
                            : scheme.onSurface,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
