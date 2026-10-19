import 'dart:convert';

import 'package:meta/meta.dart';

/// Every indexed field a smart rule can test (LIB-007: "any indexed field").
/// Shared by smart playlists (LIB-007, MUS-008), smart albums (IMG) and the
/// search filters (LIB-005).
enum RuleField {
  title(RuleType.text),
  fileName(RuleType.text),
  path(RuleType.text),
  folder(RuleType.text),
  extension(RuleType.text),
  kind(RuleType.enumeration),
  source(RuleType.number),
  size(RuleType.number),
  durationMs(RuleType.number),
  width(RuleType.number),
  height(RuleType.number),
  videoCodec(RuleType.text),
  audioCodec(RuleType.text),
  hdrType(RuleType.text),
  audioLayout(RuleType.text),
  audioTracks(RuleType.number),
  subtitleTracks(RuleType.number),
  playCount(RuleType.number),
  lastPlayed(RuleType.date),
  dateAdded(RuleType.date),
  dateModified(RuleType.date),
  dateTaken(RuleType.date),
  rating(RuleType.number),
  tag(RuleType.text),
  label(RuleType.enumeration),
  watched(RuleType.boolean),
  inProgress(RuleType.boolean),
  artist(RuleType.text),
  albumArtist(RuleType.text),
  album(RuleType.text),
  genre(RuleType.text),
  composer(RuleType.text),
  year(RuleType.number),
  trackNumber(RuleType.number),
  discNumber(RuleType.number),
  season(RuleType.number),
  episode(RuleType.number),
  camera(RuleType.text),
  favourite(RuleType.boolean),
  person(RuleType.text),
  place(RuleType.text);

  const RuleField(this.type);

  final RuleType type;
}

enum RuleType { text, number, date, boolean, enumeration }

enum RuleOp {
  equals,
  notEquals,
  contains,
  notContains,
  startsWith,
  endsWith,
  greaterThan,
  atLeast,
  lessThan,
  atMost,
  between,
  inLastDays,
  notInLastDays,
  isSet,
  isNotSet,
  anyOf,
  isTrue,
  isFalse;

  /// Operators that make sense for a field type (rule-builder UI).
  static List<RuleOp> forType(RuleType t) => switch (t) {
    RuleType.text => const [
      equals,
      notEquals,
      contains,
      notContains,
      startsWith,
      endsWith,
      isSet,
      isNotSet,
      anyOf,
    ],
    RuleType.number => const [
      equals,
      notEquals,
      greaterThan,
      atLeast,
      lessThan,
      atMost,
      between,
      isSet,
      isNotSet,
    ],
    RuleType.date => const [
      greaterThan,
      lessThan,
      between,
      inLastDays,
      notInLastDays,
      isSet,
      isNotSet,
    ],
    RuleType.boolean => const [isTrue, isFalse],
    RuleType.enumeration => const [equals, notEquals, anyOf],
  };
}

/// A node of the rule tree.
@immutable
sealed class RuleNode {
  const RuleNode();

  Map<String, Object?> toJson();

  static RuleNode fromJson(Map<String, Object?> j) => switch (j['type']) {
    'group' => RuleGroup.fromJson(j),
    'condition' => RuleCondition.fromJson(j),
    final t => throw FormatException('unknown rule node $t'),
  };
}

/// AND (`all`) / OR (`any`) of child nodes.
final class RuleGroup extends RuleNode {
  const RuleGroup({this.matchAll = true, this.children = const []});

  factory RuleGroup.fromJson(Map<String, Object?> j) => RuleGroup(
    matchAll: j['all'] as bool? ?? true,
    children: [
      for (final c in (j['children'] as List<Object?>? ?? const []))
        RuleNode.fromJson(c! as Map<String, Object?>),
    ],
  );

  final bool matchAll;
  final List<RuleNode> children;

  @override
  Map<String, Object?> toJson() => {
    'type': 'group',
    'all': matchAll,
    'children': [for (final c in children) c.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is RuleGroup &&
      other.matchAll == matchAll &&
      _listEq(other.children, children);

  @override
  int get hashCode => Object.hash(matchAll, Object.hashAll(children));
}

/// `field op value(s)`. Values are strings, numbers, booleans or lists of
/// those; dates are ISO-8601 strings.
final class RuleCondition extends RuleNode {
  const RuleCondition(this.field, this.op, [this.value, this.value2]);

  factory RuleCondition.fromJson(Map<String, Object?> j) => RuleCondition(
    RuleField.values.byName(j['field']! as String),
    RuleOp.values.byName(j['op']! as String),
    j['value'],
    j['value2'],
  );

  final RuleField field;
  final RuleOp op;
  final Object? value;
  final Object? value2;

  @override
  Map<String, Object?> toJson() => {
    'type': 'condition',
    'field': field.name,
    'op': op.name,
    if (value != null) 'value': value,
    if (value2 != null) 'value2': value2,
  };

  @override
  bool operator ==(Object other) =>
      other is RuleCondition &&
      other.field == field &&
      other.op == op &&
      _valueEq(other.value, value) &&
      _valueEq(other.value2, value2);

  @override
  int get hashCode => Object.hash(field, op, '$value', '$value2');
}

/// How the result is capped (LIB-007 "limits").
enum RuleLimitUnit { items, minutes, megabytes }

@immutable
final class RuleSort {
  const RuleSort(this.field, {this.descending = false});

  factory RuleSort.fromJson(Map<String, Object?> j) => RuleSort(
    j['field'] == 'random'
        ? null
        : RuleField.values.byName(j['field']! as String),
    descending: j['desc'] as bool? ?? false,
  );

  /// `null` sorts randomly.
  final RuleField? field;
  final bool descending;

  static const random = RuleSort(null);

  Map<String, Object?> toJson() => {
    'field': field?.name ?? 'random',
    'desc': descending,
  };

  @override
  bool operator ==(Object other) =>
      other is RuleSort &&
      other.field == field &&
      other.descending == descending;

  @override
  int get hashCode => Object.hash(field, descending);
}

/// A smart playlist / smart album definition, stored as JSON in
/// `playlist.rule`.
@immutable
final class SmartRule {
  const SmartRule({
    this.root = const RuleGroup(),
    this.limit,
    this.limitUnit = RuleLimitUnit.items,
    this.sort = const RuleSort(RuleField.title),
    this.kinds = const {},
  });

  factory SmartRule.decode(String json) =>
      SmartRule.fromJson(jsonDecode(json) as Map<String, Object?>);

  factory SmartRule.fromJson(Map<String, Object?> j) => SmartRule(
    root: RuleNode.fromJson(j['root']! as Map<String, Object?>),
    limit: (j['limit'] as num?)?.toInt(),
    limitUnit: RuleLimitUnit.values.byName(
      j['limitUnit'] as String? ?? 'items',
    ),
    sort: j['sort'] == null
        ? const RuleSort(RuleField.title)
        : RuleSort.fromJson(j['sort']! as Map<String, Object?>),
    kinds: {
      for (final k in (j['kinds'] as List<Object?>? ?? const [])) k! as String,
    },
  );

  final RuleNode root;
  final int? limit;
  final RuleLimitUnit limitUnit;
  final RuleSort sort;

  /// Item kinds in scope (`ItemKind.name`); empty means all.
  final Set<String> kinds;

  Map<String, Object?> toJson() => {
    'root': root.toJson(),
    if (limit != null) 'limit': limit,
    'limitUnit': limitUnit.name,
    'sort': sort.toJson(),
    if (kinds.isNotEmpty) 'kinds': kinds.toList()..sort(),
  };

  String encode() => jsonEncode(toJson());

  @override
  bool operator ==(Object other) =>
      other is SmartRule &&
      other.root == root &&
      other.limit == limit &&
      other.limitUnit == limitUnit &&
      other.sort == sort &&
      other.kinds.length == kinds.length &&
      other.kinds.containsAll(kinds);

  @override
  int get hashCode =>
      Object.hash(root, limit, limitUnit, sort, Object.hashAllUnordered(kinds));
}

bool _listEq(List<Object?> a, List<Object?> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _valueEq(Object? a, Object? b) =>
    a is List<Object?> && b is List<Object?> ? _listEq(a, b) : a == b;
