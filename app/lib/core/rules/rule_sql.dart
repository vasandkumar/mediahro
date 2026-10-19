import 'package:drift/drift.dart';
import 'package:mediahro/core/rules/smart_rule.dart';
import 'package:meta/meta.dart';

/// What an item query may see (LIB-013: hidden and PIN-gated items never
/// appear in search or rows unless the gate is open).
@immutable
final class Visibility {
  const Visibility({
    this.includeHidden = false,
    this.unlocked = false,
    this.includeMissing = false,
    this.includeVault = false,
  });

  static const standard = Visibility();

  final bool includeHidden;

  /// The parental gate is open for this session.
  final bool unlocked;
  final bool includeMissing;
  final bool includeVault;

  String get sql {
    final sourceOk = unlocked
        ? 's.enabled = 1'
        : 's.enabled = 1 AND s.locked = 0';
    return [
      if (!includeHidden) 'i.hidden = 0',
      if (!includeMissing) 'i.missing = 0',
      if (!includeVault) 'i.vault = 0',
      'EXISTS (SELECT 1 FROM source s WHERE s.id = i.source_id AND $sourceOk)',
      if (!unlocked) _lockedFolderFilter,
    ].join(' AND ');
  }

  static const _lockedFolderFilter =
      'NOT EXISTS (SELECT 1 FROM locked_folder lf WHERE lf.source_id = i.source_id '
      'AND (i.rel_path = lf.rel_path OR '
      "substr(i.rel_path, 1, length(lf.rel_path) + 1) = lf.rel_path || '/'))";
}

/// SQL text plus bound variables (never interpolated values).
@immutable
final class CompiledQuery {
  const CompiledQuery(this.sql, this.variables);

  final String sql;
  final List<Variable<Object>> variables;
}

/// Joins every rule field may need; all LEFT so items without metadata stay.
const itemJoins =
    'FROM item i '
    'LEFT JOIN audio_meta a ON a.item_id = i.id '
    'LEFT JOIN video_meta v ON v.item_id = i.id '
    'LEFT JOIN image_meta im ON im.item_id = i.id '
    'LEFT JOIN rating r ON r.item_id = i.id '
    'LEFT JOIN progress pr ON pr.item_id = i.id';

/// Compiles rule trees to SQLite over [itemJoins] (LIB-007).
final class RuleCompiler {
  RuleCompiler({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  /// `SELECT i.*` for [rule] with its sort and limit.
  CompiledQuery select(
    SmartRule rule, {
    Visibility visibility = Visibility.standard,
    String? extraWhere,
    List<Variable<Object>> extraVariables = const [],
  }) {
    final vars = <Variable<Object>>[];
    final where = <String>[
      visibility.sql,
      if (rule.kinds.isNotEmpty)
        'i.kind IN (${[for (final k in rule.kinds) _bind(vars, Variable.withString(k))].join(', ')})',
      ?_nonEmpty(condition(rule.root, vars)),
      ?extraWhere,
    ];
    vars.addAll(extraVariables);
    final order = orderBy(rule.sort);
    final limit = rule.limit;
    final base = 'SELECT i.* $itemJoins WHERE ${where.join(' AND ')}';
    if (limit == null) {
      return CompiledQuery('$base ORDER BY $order', vars);
    }
    switch (rule.limitUnit) {
      case RuleLimitUnit.items:
        return CompiledQuery('$base ORDER BY $order LIMIT $limit', vars);
      case RuleLimitUnit.minutes || RuleLimitUnit.megabytes:
        final measure = rule.limitUnit == RuleLimitUnit.minutes
            ? 'coalesce(i.duration_ms, 0)'
            : 'i.size';
        final cap = rule.limitUnit == RuleLimitUnit.minutes
            ? limit * 60000
            : limit * 1048576;
        final windowed = base.replaceFirst(
          'SELECT i.* ',
          'SELECT i.*, sum($measure) OVER (ORDER BY $order ROWS UNBOUNDED PRECEDING) AS _running ',
        );
        // A random sort must be fixed before the running sum.
        return CompiledQuery(
          'SELECT * FROM ($windowed) WHERE _running <= $cap ORDER BY _running',
          vars,
        );
    }
  }

  /// WHERE fragment for [node], or `''` when it matches everything.
  String condition(RuleNode node, List<Variable<Object>> vars) =>
      switch (node) {
        RuleGroup(:final children) when children.isEmpty => '',
        RuleGroup(:final matchAll, :final children) => () {
          final parts = [
            for (final c in children) ?_nonEmpty(condition(c, vars)),
          ];
          if (parts.isEmpty) return '';
          return '(${parts.join(matchAll ? ' AND ' : ' OR ')})';
        }(),
        final RuleCondition c => _condition(c, vars),
      };

  String orderBy(RuleSort sort) {
    final f = sort.field;
    if (f == null) return 'random()';
    final dir = sort.descending ? 'DESC' : 'ASC';
    final expr = switch (f) {
      RuleField.title => 'i.sort_title',
      RuleField.tag ||
      RuleField.label ||
      RuleField.person ||
      RuleField.place => 'i.sort_title',
      _ => _column(f),
    };
    return '$expr $dir NULLS LAST, i.sort_title ASC, i.id ASC';
  }

  String _condition(RuleCondition c, List<Variable<Object>> vars) {
    switch (c.field) {
      case RuleField.tag:
        return _setField(
          c,
          vars,
          'SELECT 1 FROM item_tag it JOIN tag t ON t.id = it.tag_id WHERE it.item_id = i.id',
          't.name',
        );
      case RuleField.label:
        return _setField(
          c,
          vars,
          'SELECT 1 FROM label l WHERE l.item_id = i.id',
          'l.color',
        );
      case RuleField.person:
        return _setField(
          c,
          vars,
          'SELECT 1 FROM item_person ip JOIN person p ON p.id = ip.person_id WHERE ip.item_id = i.id',
          'p.name',
        );
      case RuleField.place:
        return _setField(
          c,
          vars,
          'SELECT 1 FROM place pl WHERE pl.id = im.place_id',
          'pl.name',
        );
      case _:
        return _scalar(c, _column(c.field), c.field.type, vars);
    }
  }

  String _setField(
    RuleCondition c,
    List<Variable<Object>> vars,
    String exists,
    String col,
  ) {
    String sub(String test) => 'EXISTS ($exists AND $test)';
    return switch (c.op) {
      RuleOp.isSet => 'EXISTS ($exists)',
      RuleOp.isNotSet => 'NOT EXISTS ($exists)',
      RuleOp.notEquals =>
        'NOT ${sub(_text(RuleOp.equals, col, c.value, vars))}',
      RuleOp.notContains =>
        'NOT ${sub(_text(RuleOp.contains, col, c.value, vars))}',
      _ => sub(_text(c.op, col, c.value, vars)),
    };
  }

  String _scalar(
    RuleCondition c,
    String col,
    RuleType type,
    List<Variable<Object>> vars,
  ) {
    if (c.op == RuleOp.isSet) return '$col IS NOT NULL';
    if (c.op == RuleOp.isNotSet) return '$col IS NULL';
    switch (type) {
      case RuleType.text || RuleType.enumeration:
        return _text(c.op, col, c.value, vars);
      case RuleType.boolean:
        return switch (c.op) {
          RuleOp.isFalse => 'coalesce($col, 0) = 0',
          _ => 'coalesce($col, 0) != 0',
        };
      case RuleType.number:
        return _compare(c, col, vars, _num);
      case RuleType.date:
        final now = _clock().millisecondsSinceEpoch ~/ 1000;
        switch (c.op) {
          case RuleOp.inLastDays:
            return '$col >= ${_bind(vars, Variable.withInt(now - _num(c.value).toInt() * 86400))}';
          case RuleOp.notInLastDays:
            return '($col IS NULL OR $col < ${_bind(vars, Variable.withInt(now - _num(c.value).toInt() * 86400))})';
          case _:
            return _compare(c, col, vars, _epochSeconds);
        }
    }
  }

  String _compare(
    RuleCondition c,
    String col,
    List<Variable<Object>> vars,
    num Function(Object?) conv,
  ) {
    String b(Object? v) {
      final n = conv(v);
      return _bind(
        vars,
        n is int ? Variable.withInt(n) : Variable.withReal(n.toDouble()),
      );
    }

    return switch (c.op) {
      RuleOp.equals => '$col = ${b(c.value)}',
      RuleOp.notEquals => '($col IS NULL OR $col != ${b(c.value)})',
      RuleOp.greaterThan => '$col > ${b(c.value)}',
      RuleOp.atLeast => '$col >= ${b(c.value)}',
      RuleOp.lessThan => '$col < ${b(c.value)}',
      RuleOp.atMost => '$col <= ${b(c.value)}',
      RuleOp.between => '$col BETWEEN ${b(c.value)} AND ${b(c.value2)}',
      RuleOp.anyOf =>
        '$col IN (${[for (final v in _list(c.value)) b(v)].join(', ')})',
      _ => throw ArgumentError('${c.op} is not valid for ${c.field}'),
    };
  }

  String _text(
    RuleOp op,
    String col,
    Object? value,
    List<Variable<Object>> vars,
  ) {
    String b(Object? v) =>
        _bind(vars, Variable.withString('${v ?? ''}'.toLowerCase()));
    final lc = 'lower($col)';
    return switch (op) {
      RuleOp.equals => '$lc = ${b(value)}',
      RuleOp.notEquals => "lower(coalesce($col, '')) != ${b(value)}",
      RuleOp.contains => 'instr($lc, ${b(value)}) > 0',
      RuleOp.notContains => "instr(lower(coalesce($col, '')), ${b(value)}) = 0",
      // Each placeholder binds its own copy of the value.
      RuleOp.startsWith => 'substr($lc, 1, length(${b(value)})) = ${b(value)}',
      RuleOp.endsWith => 'substr($lc, -length(${b(value)})) = ${b(value)}',
      RuleOp.anyOf =>
        '$lc IN (${[for (final v in _list(value)) b(v)].join(', ')})',
      _ => throw ArgumentError('$op is not valid for text'),
    };
  }

  static String _column(RuleField f) => switch (f) {
    RuleField.title => 'i.title',
    RuleField.fileName => 'i.name',
    RuleField.path => 'i.rel_path',
    RuleField.folder => 'i.parent_path',
    RuleField.extension => 'i.ext',
    RuleField.kind => 'i.kind',
    RuleField.source => 'i.source_id',
    RuleField.size => 'i.size',
    RuleField.durationMs => 'i.duration_ms',
    RuleField.width => 'i.width',
    RuleField.height => 'i.height',
    RuleField.videoCodec => 'i.video_codec',
    RuleField.audioCodec => 'i.audio_codec',
    RuleField.hdrType => 'i.hdr_type',
    RuleField.audioLayout => 'i.audio_layout',
    RuleField.audioTracks => 'i.audio_tracks',
    RuleField.subtitleTracks => 'i.subtitle_tracks',
    RuleField.playCount => 'i.play_count',
    RuleField.lastPlayed => 'i.last_played_at',
    RuleField.dateAdded => 'i.added_at',
    RuleField.dateModified => 'i.mtime',
    RuleField.dateTaken => 'i.taken_at',
    RuleField.rating => 'r.value',
    RuleField.watched => 'pr.watched',
    RuleField.inProgress => '(CASE WHEN pr.position_ms > 0 AND coalesce(pr.watched, 0) = 0 THEN 1 ELSE 0 END)',
    RuleField.artist => 'a.artist',
    RuleField.albumArtist => 'a.album_artist',
    RuleField.album => 'a.album',
    RuleField.genre => 'a.genre',
    RuleField.composer => 'a.composer',
    RuleField.year => 'coalesce(a.year, v.year)',
    RuleField.trackNumber => 'a.track_number',
    RuleField.discNumber => 'a.disc_number',
    RuleField.season => 'v.season_number',
    RuleField.episode => 'v.episode_number',
    RuleField.camera => 'im.camera',
    RuleField.favourite => 'im.favourite',
    RuleField.tag ||
    RuleField.label ||
    RuleField.person ||
    RuleField.place => throw ArgumentError('$f is set-valued'),
  };

  static String _bind(List<Variable<Object>> vars, Variable<Object> v) {
    vars.add(v);
    return '?';
  }

  static num _num(Object? v) => switch (v) {
    final num n => n,
    final String s => num.parse(s),
    final bool b => b ? 1 : 0,
    _ => throw ArgumentError('number expected, got $v'),
  };

  static int _epochSeconds(Object? v) => switch (v) {
    final DateTime d => d.millisecondsSinceEpoch ~/ 1000,
    final String s => DateTime.parse(s).millisecondsSinceEpoch ~/ 1000,
    final int n => n,
    _ => throw ArgumentError('date expected, got $v'),
  };

  static List<Object?> _list(Object? v) => v is List<Object?> ? v : [v];
}

String? _nonEmpty(String s) => s.isEmpty ? null : s;
