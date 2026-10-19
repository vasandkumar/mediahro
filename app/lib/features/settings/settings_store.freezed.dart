// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'settings_store.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$SettingsDocument implements DiagnosticableTreeMixin {

 int get schema; Map<String, Object?> get values; DateTime? get exportedAt;
/// Create a copy of SettingsDocument
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SettingsDocumentCopyWith<SettingsDocument> get copyWith => _$SettingsDocumentCopyWithImpl<SettingsDocument>(this as SettingsDocument, _$identity);

  /// Serializes this SettingsDocument to a JSON map.
  Map<String, dynamic> toJson();

@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  final _this = this as SettingsDocument;
  properties
    ..add(DiagnosticsProperty('type', 'SettingsDocument'))
    ..add(DiagnosticsProperty('schema', _this.schema))..add(DiagnosticsProperty('values', _this.values))..add(DiagnosticsProperty('exportedAt', _this.exportedAt));
}

@override
bool operator ==(Object other) {
  final _this = this as SettingsDocument;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SettingsDocument&&(identical(other.schema, _this.schema) || other.schema == _this.schema)&&const DeepCollectionEquality().equals(other.values, _this.values)&&(identical(other.exportedAt, _this.exportedAt) || other.exportedAt == _this.exportedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as SettingsDocument;
  return Object.hash(runtimeType,_this.schema,const DeepCollectionEquality().hash(_this.values),_this.exportedAt);
}

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  final _this = this as SettingsDocument;
  return 'SettingsDocument(schema: ${_this.schema}, values: ${_this.values}, exportedAt: ${_this.exportedAt})';
}


}

/// @nodoc
abstract mixin class $SettingsDocumentCopyWith<$Res>  {
  factory $SettingsDocumentCopyWith(SettingsDocument value, $Res Function(SettingsDocument) _then) = _$SettingsDocumentCopyWithImpl;
@useResult
$Res call({
 int schema, Map<String, Object?> values, DateTime? exportedAt
});




}
/// @nodoc
class _$SettingsDocumentCopyWithImpl<$Res>
    implements $SettingsDocumentCopyWith<$Res> {
  _$SettingsDocumentCopyWithImpl(this._self, this._then);

  final SettingsDocument _self;
  final $Res Function(SettingsDocument) _then;

/// Create a copy of SettingsDocument
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? schema = null,Object? values = null,Object? exportedAt = freezed,}) {
  return _then(SettingsDocument(
schema: null == schema ? _self.schema : schema // ignore: cast_nullable_to_non_nullable
as int,values: null == values ? _self.values : values // ignore: cast_nullable_to_non_nullable
as Map<String, Object?>,exportedAt: freezed == exportedAt ? _self.exportedAt : exportedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [SettingsDocument].
extension SettingsDocumentPatterns on SettingsDocument {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SettingsDocument value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SettingsDocument() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SettingsDocument value)  $default,){
final _that = this;
switch (_that) {
case _SettingsDocument():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SettingsDocument value)?  $default,){
final _that = this;
switch (_that) {
case _SettingsDocument() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int schema,  Map<String, Object?> values,  DateTime? exportedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SettingsDocument() when $default != null:
return $default(_that.schema,_that.values,_that.exportedAt);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int schema,  Map<String, Object?> values,  DateTime? exportedAt)  $default,) {final _that = this;
switch (_that) {
case _SettingsDocument():
return $default(_that.schema,_that.values,_that.exportedAt);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int schema,  Map<String, Object?> values,  DateTime? exportedAt)?  $default,) {final _that = this;
switch (_that) {
case _SettingsDocument() when $default != null:
return $default(_that.schema,_that.values,_that.exportedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _SettingsDocument with DiagnosticableTreeMixin implements SettingsDocument {
  const _SettingsDocument({this.schema = SettingsDocument.currentSchema,  Map<String, Object?> values = const <String, Object?>{}, this.exportedAt}): _values = values;
  factory _SettingsDocument.fromJson(Map<String, dynamic> json) => _$SettingsDocumentFromJson(json);

@override@JsonKey() final  int schema;
 final  Map<String, Object?> _values;
@override@JsonKey() Map<String, Object?> get values {
  if (_values is EqualUnmodifiableMapView) return _values;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_values);
}

@override final  DateTime? exportedAt;

/// Create a copy of SettingsDocument
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SettingsDocumentCopyWith<_SettingsDocument> get copyWith => __$SettingsDocumentCopyWithImpl<_SettingsDocument>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SettingsDocumentToJson(this, );
}
@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    properties
    ..add(DiagnosticsProperty('type', 'SettingsDocument'))
    ..add(DiagnosticsProperty('schema', schema))..add(DiagnosticsProperty('values', values))..add(DiagnosticsProperty('exportedAt', exportedAt));
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SettingsDocument&&(identical(other.schema, schema) || other.schema == schema)&&const DeepCollectionEquality().equals(other.values, _values)&&(identical(other.exportedAt, exportedAt) || other.exportedAt == exportedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,schema,const DeepCollectionEquality().hash(_values),exportedAt);
}

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
    return 'SettingsDocument(schema: $schema, values: $values, exportedAt: $exportedAt)';
}


}

/// @nodoc
abstract mixin class _$SettingsDocumentCopyWith<$Res> implements $SettingsDocumentCopyWith<$Res> {
  factory _$SettingsDocumentCopyWith(_SettingsDocument value, $Res Function(_SettingsDocument) _then) = __$SettingsDocumentCopyWithImpl;
@override @useResult
$Res call({
 int schema, Map<String, Object?> values, DateTime? exportedAt
});




}
/// @nodoc
class __$SettingsDocumentCopyWithImpl<$Res>
    implements _$SettingsDocumentCopyWith<$Res> {
  __$SettingsDocumentCopyWithImpl(this._self, this._then);

  final _SettingsDocument _self;
  final $Res Function(_SettingsDocument) _then;

/// Create a copy of SettingsDocument
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? schema = null,Object? values = null,Object? exportedAt = freezed,}) {
  return _then(_SettingsDocument(
schema: null == schema ? _self.schema : schema // ignore: cast_nullable_to_non_nullable
as int,values: null == values ? _self._values : values // ignore: cast_nullable_to_non_nullable
as Map<String, Object?>,exportedAt: freezed == exportedAt ? _self.exportedAt : exportedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
