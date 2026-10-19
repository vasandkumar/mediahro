import 'package:flutter/material.dart';
import 'package:mediahro_design/src/foundation/accessibility.dart';
import 'package:mediahro_design/src/foundation/strings.dart';
import 'package:mediahro_design/src/icons.dart';
import 'package:mediahro_design/src/theme.dart';
import 'package:mediahro_design/src/tokens.dart';

/// One settings row (docs/06 §3.5, CORE-006): title, a one-line
/// description, and a control. Rows locked by managed configuration show a
/// lock and "Managed by your organisation" and cannot be changed.
class KSettingsRow extends StatelessWidget {
  /// A switch; tapping anywhere on the row toggles it.
  const KSettingsRow.toggle({
    required this.title,
    required this.description,
    required bool this.value,
    required ValueChanged<bool>? onChanged,
    this.icon,
    this.managed = false,
    this.highlight,
    super.key,
  }) : _onToggle = onChanged,
       onTap = null,
       valueLabel = null,
       trailing = null,
       _kind = _Kind.toggle;

  /// Shows the current value; tapping opens a picker.
  const KSettingsRow.value({
    required this.title,
    required this.description,
    required String this.valueLabel,
    required this.onTap,
    this.icon,
    this.managed = false,
    this.highlight,
    super.key,
  }) : value = null,
       _onToggle = null,
       trailing = null,
       _kind = _Kind.value;

  /// Opens a sub-page.
  const KSettingsRow.navigation({
    required this.title,
    required this.description,
    required this.onTap,
    this.icon,
    this.managed = false,
    this.highlight,
    super.key,
  }) : value = null,
       valueLabel = null,
       _onToggle = null,
       trailing = null,
       _kind = _Kind.navigation;

  /// A custom control (slider, segmented button) laid out under the text.
  const KSettingsRow.custom({
    required this.title,
    required this.description,
    required Widget this.trailing,
    this.icon,
    this.managed = false,
    this.highlight,
    super.key,
  }) : value = null,
       valueLabel = null,
       _onToggle = null,
       onTap = null,
       _kind = _Kind.custom;

  final String title;

  /// One line saying what the option does (CORE-006 AC).
  final String description;
  final KIcon? icon;
  final bool managed;

  /// Search term to emphasise in [title].
  final String? highlight;
  final bool? value;
  final String? valueLabel;
  final VoidCallback? onTap;
  final Widget? trailing;
  final ValueChanged<bool>? _onToggle;
  final _Kind _kind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final family = theme.mediahroShape.family;
    final strings = KStrings.of(context);
    final reduceMotion = KAccessibility.reduceMotion(context);
    final secondary = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    final locked = managed;
    final toggle = _onToggle;
    final tap = locked
        ? null
        : switch (_kind) {
            _Kind.toggle =>
              toggle == null ? null : () => toggle(!(value ?? false)),
            _Kind.value || _Kind.navigation => onTap,
            _Kind.custom => null,
          };

    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Highlighted(
          text: title,
          term: highlight,
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 2),
        Text(description, style: secondary),
        if (locked)
          Padding(
            padding: const EdgeInsets.only(top: KSpacing.s4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  KIcon.lock.resolve(family),
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: KSpacing.s4),
                Flexible(
                  child: Text(strings.managedByOrganisation, style: secondary),
                ),
              ],
            ),
          ),
      ],
    );

    final control = switch (_kind) {
      _Kind.toggle => ExcludeSemantics(
        child: Switch.adaptive(
          value: value ?? false,
          onChanged: locked ? null : _onToggle,
        ),
      ),
      _Kind.value => Text(
        valueLabel!,
        style: secondary,
        textAlign: TextAlign.end,
      ),
      _Kind.navigation => Icon(
        Directionality.of(context) == TextDirection.rtl
            ? Icons.chevron_left
            : Icons.chevron_right,
        color: scheme.onSurfaceVariant,
      ),
      _Kind.custom => null,
    };

    final body = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KSpacing.s16,
        vertical: KSpacing.s12,
      ),
      child: _kind == _Kind.custom
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _withIcon(context, texts),
                const SizedBox(height: KSpacing.s8),
                IgnorePointer(
                  ignoring: locked,
                  child: Opacity(opacity: locked ? 0.5 : 1, child: trailing),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(flex: 2, child: _withIcon(context, texts)),
                if (control != null) ...[
                  const SizedBox(width: KSpacing.s12),
                  // Values may be long ("Follow system") and wrap at large
                  // text sizes instead of overflowing.
                  if (_kind == _Kind.value)
                    Flexible(child: control)
                  else
                    control,
                ],
              ],
            ),
    );

    final row = ConstrainedBox(
      constraints: BoxConstraints(minHeight: theme.mediahroShape.minTarget),
      child: tap == null
          ? body
          : InkWell(
              onTap: tap,
              splashFactory: reduceMotion ? NoSplash.splashFactory : null,
              child: body,
            ),
    );

    if (_kind == _Kind.custom) return row;
    return MergeSemantics(
      child: Semantics(
        toggled: _kind == _Kind.toggle ? (value ?? false) : null,
        button: _kind != _Kind.toggle,
        enabled: !locked,
        value: valueLabel,
        child: row,
      ),
    );
  }

  Widget _withIcon(BuildContext context, Widget texts) {
    if (icon == null) return texts;
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            icon!.resolve(theme.mediahroShape.family),
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: KSpacing.s16),
        Expanded(child: texts),
      ],
    );
  }
}

enum _Kind { toggle, value, navigation, custom }

/// Section heading in a settings list.
class KSettingsHeader extends StatelessWidget {
  const KSettingsHeader({required this.title, this.trailing, super.key});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KSpacing.s16,
        KSpacing.s24,
        KSpacing.s8,
        KSpacing.s4,
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Collapsed group of advanced rows (CORE-006: "Advanced sections
/// collapsed").
class KAdvancedGroup extends StatefulWidget {
  const KAdvancedGroup({
    required this.children,
    this.initiallyExpanded = false,
    super.key,
  });

  final List<Widget> children;
  final bool initiallyExpanded;

  @override
  State<KAdvancedGroup> createState() => _KAdvancedGroupState();
}

class _KAdvancedGroupState extends State<KAdvancedGroup> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final strings = KStrings.of(context);
    final theme = Theme.of(context);
    final reduceMotion = KAccessibility.reduceMotion(context);
    final label = _expanded ? strings.hideAdvanced : strings.showAdvanced;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          expanded: _expanded,
          button: true,
          child: InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: theme.mediahroShape.minTarget,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: KSpacing.s16,
                  vertical: KSpacing.s8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    ExcludeSemantics(
                      child: Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: KMotion.resolve(KMotion.base, reduceMotion: reduceMotion),
          alignment: AlignmentDirectional.topStart,
          child: _expanded
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: widget.children,
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// Emphasises the first case-insensitive match of [term] in [text].
class _Highlighted extends StatelessWidget {
  const _Highlighted({required this.text, required this.term, this.style});

  final String text;
  final String? term;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final t = term?.trim() ?? '';
    final i = t.isEmpty ? -1 : text.toLowerCase().indexOf(t.toLowerCase());
    if (i < 0) return Text(text, style: style);
    final strong = (style ?? const TextStyle()).copyWith(
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
    );
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: text.substring(0, i)),
          TextSpan(text: text.substring(i, i + t.length), style: strong),
          TextSpan(text: text.substring(i + t.length)),
        ],
      ),
    );
  }
}
