// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$EngineError {

 EngineErrorCode get code;/// Technical detail for the info sheet ("Copy details"), never primary copy.
 String? get detail;
/// Create a copy of EngineError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EngineErrorCopyWith<EngineError> get copyWith => _$EngineErrorCopyWithImpl<EngineError>(this as EngineError, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as EngineError;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EngineError&&(identical(other.code, _this.code) || other.code == _this.code)&&(identical(other.detail, _this.detail) || other.detail == _this.detail));
}


@override
int get hashCode {
  final _this = this as EngineError;
  return Object.hash(runtimeType,_this.code,_this.detail);
}

@override
String toString() {
  final _this = this as EngineError;
  return 'EngineError(code: ${_this.code}, detail: ${_this.detail})';
}


}

/// @nodoc
abstract mixin class $EngineErrorCopyWith<$Res>  {
  factory $EngineErrorCopyWith(EngineError value, $Res Function(EngineError) _then) = _$EngineErrorCopyWithImpl;
@useResult
$Res call({
 EngineErrorCode code, String? detail
});




}
/// @nodoc
class _$EngineErrorCopyWithImpl<$Res>
    implements $EngineErrorCopyWith<$Res> {
  _$EngineErrorCopyWithImpl(this._self, this._then);

  final EngineError _self;
  final $Res Function(EngineError) _then;

/// Create a copy of EngineError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? code = null,Object? detail = freezed,}) {
  return _then(EngineError(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as EngineErrorCode,detail: freezed == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [EngineError].
extension EngineErrorPatterns on EngineError {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _EngineError value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _EngineError() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _EngineError value)  $default,){
final _that = this;
switch (_that) {
case _EngineError():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _EngineError value)?  $default,){
final _that = this;
switch (_that) {
case _EngineError() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( EngineErrorCode code,  String? detail)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _EngineError() when $default != null:
return $default(_that.code,_that.detail);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( EngineErrorCode code,  String? detail)  $default,) {final _that = this;
switch (_that) {
case _EngineError():
return $default(_that.code,_that.detail);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( EngineErrorCode code,  String? detail)?  $default,) {final _that = this;
switch (_that) {
case _EngineError() when $default != null:
return $default(_that.code,_that.detail);case _:
  return null;

}
}

}

/// @nodoc


class _EngineError implements EngineError {
  const _EngineError({required this.code, this.detail});
  

@override final  EngineErrorCode code;
/// Technical detail for the info sheet ("Copy details"), never primary copy.
@override final  String? detail;

/// Create a copy of EngineError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$EngineErrorCopyWith<_EngineError> get copyWith => __$EngineErrorCopyWithImpl<_EngineError>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _EngineError&&(identical(other.code, code) || other.code == code)&&(identical(other.detail, detail) || other.detail == detail));
}


@override
int get hashCode {
    return Object.hash(runtimeType,code,detail);
}

@override
String toString() {
    return 'EngineError(code: $code, detail: $detail)';
}


}

/// @nodoc
abstract mixin class _$EngineErrorCopyWith<$Res> implements $EngineErrorCopyWith<$Res> {
  factory _$EngineErrorCopyWith(_EngineError value, $Res Function(_EngineError) _then) = __$EngineErrorCopyWithImpl;
@override @useResult
$Res call({
 EngineErrorCode code, String? detail
});




}
/// @nodoc
class __$EngineErrorCopyWithImpl<$Res>
    implements _$EngineErrorCopyWith<$Res> {
  __$EngineErrorCopyWithImpl(this._self, this._then);

  final _EngineError _self;
  final $Res Function(_EngineError) _then;

/// Create a copy of EngineError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? code = null,Object? detail = freezed,}) {
  return _then(_EngineError(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as EngineErrorCode,detail: freezed == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$Track {

 int get id; TrackType get type; String? get title;/// BCP 47 language tag when known.
 String? get language; String? get codec; int? get channels; int? get sampleRate; int? get width; int? get height; double? get fps; bool get isDefault; bool get isForced; bool get isExternal; bool get isAudioDescription; bool get isHearingImpaired;/// Technical Dolby Vision profile of a video track (5, 7, 8); UI copy
/// never uses the trademark (docs/09 §4).
 int? get dolbyVisionProfile;/// ReplayGain tags read by the demuxer (AUD-004).
 double? get replayGainTrackDb; double? get replayGainAlbumDb;
/// Create a copy of Track
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TrackCopyWith<Track> get copyWith => _$TrackCopyWithImpl<Track>(this as Track, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as Track;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Track&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.type, _this.type) || other.type == _this.type)&&(identical(other.title, _this.title) || other.title == _this.title)&&(identical(other.language, _this.language) || other.language == _this.language)&&(identical(other.codec, _this.codec) || other.codec == _this.codec)&&(identical(other.channels, _this.channels) || other.channels == _this.channels)&&(identical(other.sampleRate, _this.sampleRate) || other.sampleRate == _this.sampleRate)&&(identical(other.width, _this.width) || other.width == _this.width)&&(identical(other.height, _this.height) || other.height == _this.height)&&(identical(other.fps, _this.fps) || other.fps == _this.fps)&&(identical(other.isDefault, _this.isDefault) || other.isDefault == _this.isDefault)&&(identical(other.isForced, _this.isForced) || other.isForced == _this.isForced)&&(identical(other.isExternal, _this.isExternal) || other.isExternal == _this.isExternal)&&(identical(other.isAudioDescription, _this.isAudioDescription) || other.isAudioDescription == _this.isAudioDescription)&&(identical(other.isHearingImpaired, _this.isHearingImpaired) || other.isHearingImpaired == _this.isHearingImpaired)&&(identical(other.dolbyVisionProfile, _this.dolbyVisionProfile) || other.dolbyVisionProfile == _this.dolbyVisionProfile)&&(identical(other.replayGainTrackDb, _this.replayGainTrackDb) || other.replayGainTrackDb == _this.replayGainTrackDb)&&(identical(other.replayGainAlbumDb, _this.replayGainAlbumDb) || other.replayGainAlbumDb == _this.replayGainAlbumDb));
}


@override
int get hashCode {
  final _this = this as Track;
  return Object.hash(runtimeType,_this.id,_this.type,_this.title,_this.language,_this.codec,_this.channels,_this.sampleRate,_this.width,_this.height,_this.fps,_this.isDefault,_this.isForced,_this.isExternal,_this.isAudioDescription,_this.isHearingImpaired,_this.dolbyVisionProfile,_this.replayGainTrackDb,_this.replayGainAlbumDb);
}

@override
String toString() {
  final _this = this as Track;
  return 'Track(id: ${_this.id}, type: ${_this.type}, title: ${_this.title}, language: ${_this.language}, codec: ${_this.codec}, channels: ${_this.channels}, sampleRate: ${_this.sampleRate}, width: ${_this.width}, height: ${_this.height}, fps: ${_this.fps}, isDefault: ${_this.isDefault}, isForced: ${_this.isForced}, isExternal: ${_this.isExternal}, isAudioDescription: ${_this.isAudioDescription}, isHearingImpaired: ${_this.isHearingImpaired}, dolbyVisionProfile: ${_this.dolbyVisionProfile}, replayGainTrackDb: ${_this.replayGainTrackDb}, replayGainAlbumDb: ${_this.replayGainAlbumDb})';
}


}

/// @nodoc
abstract mixin class $TrackCopyWith<$Res>  {
  factory $TrackCopyWith(Track value, $Res Function(Track) _then) = _$TrackCopyWithImpl;
@useResult
$Res call({
 int id, TrackType type, String? title, String? language, String? codec, int? channels, int? sampleRate, int? width, int? height, double? fps, bool isDefault, bool isForced, bool isExternal, bool isAudioDescription, bool isHearingImpaired, int? dolbyVisionProfile, double? replayGainTrackDb, double? replayGainAlbumDb
});




}
/// @nodoc
class _$TrackCopyWithImpl<$Res>
    implements $TrackCopyWith<$Res> {
  _$TrackCopyWithImpl(this._self, this._then);

  final Track _self;
  final $Res Function(Track) _then;

/// Create a copy of Track
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? type = null,Object? title = freezed,Object? language = freezed,Object? codec = freezed,Object? channels = freezed,Object? sampleRate = freezed,Object? width = freezed,Object? height = freezed,Object? fps = freezed,Object? isDefault = null,Object? isForced = null,Object? isExternal = null,Object? isAudioDescription = null,Object? isHearingImpaired = null,Object? dolbyVisionProfile = freezed,Object? replayGainTrackDb = freezed,Object? replayGainAlbumDb = freezed,}) {
  return _then(Track(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as TrackType,title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,language: freezed == language ? _self.language : language // ignore: cast_nullable_to_non_nullable
as String?,codec: freezed == codec ? _self.codec : codec // ignore: cast_nullable_to_non_nullable
as String?,channels: freezed == channels ? _self.channels : channels // ignore: cast_nullable_to_non_nullable
as int?,sampleRate: freezed == sampleRate ? _self.sampleRate : sampleRate // ignore: cast_nullable_to_non_nullable
as int?,width: freezed == width ? _self.width : width // ignore: cast_nullable_to_non_nullable
as int?,height: freezed == height ? _self.height : height // ignore: cast_nullable_to_non_nullable
as int?,fps: freezed == fps ? _self.fps : fps // ignore: cast_nullable_to_non_nullable
as double?,isDefault: null == isDefault ? _self.isDefault : isDefault // ignore: cast_nullable_to_non_nullable
as bool,isForced: null == isForced ? _self.isForced : isForced // ignore: cast_nullable_to_non_nullable
as bool,isExternal: null == isExternal ? _self.isExternal : isExternal // ignore: cast_nullable_to_non_nullable
as bool,isAudioDescription: null == isAudioDescription ? _self.isAudioDescription : isAudioDescription // ignore: cast_nullable_to_non_nullable
as bool,isHearingImpaired: null == isHearingImpaired ? _self.isHearingImpaired : isHearingImpaired // ignore: cast_nullable_to_non_nullable
as bool,dolbyVisionProfile: freezed == dolbyVisionProfile ? _self.dolbyVisionProfile : dolbyVisionProfile // ignore: cast_nullable_to_non_nullable
as int?,replayGainTrackDb: freezed == replayGainTrackDb ? _self.replayGainTrackDb : replayGainTrackDb // ignore: cast_nullable_to_non_nullable
as double?,replayGainAlbumDb: freezed == replayGainAlbumDb ? _self.replayGainAlbumDb : replayGainAlbumDb // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}

}


/// Adds pattern-matching-related methods to [Track].
extension TrackPatterns on Track {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Track value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Track() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Track value)  $default,){
final _that = this;
switch (_that) {
case _Track():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Track value)?  $default,){
final _that = this;
switch (_that) {
case _Track() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int id,  TrackType type,  String? title,  String? language,  String? codec,  int? channels,  int? sampleRate,  int? width,  int? height,  double? fps,  bool isDefault,  bool isForced,  bool isExternal,  bool isAudioDescription,  bool isHearingImpaired,  int? dolbyVisionProfile,  double? replayGainTrackDb,  double? replayGainAlbumDb)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Track() when $default != null:
return $default(_that.id,_that.type,_that.title,_that.language,_that.codec,_that.channels,_that.sampleRate,_that.width,_that.height,_that.fps,_that.isDefault,_that.isForced,_that.isExternal,_that.isAudioDescription,_that.isHearingImpaired,_that.dolbyVisionProfile,_that.replayGainTrackDb,_that.replayGainAlbumDb);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int id,  TrackType type,  String? title,  String? language,  String? codec,  int? channels,  int? sampleRate,  int? width,  int? height,  double? fps,  bool isDefault,  bool isForced,  bool isExternal,  bool isAudioDescription,  bool isHearingImpaired,  int? dolbyVisionProfile,  double? replayGainTrackDb,  double? replayGainAlbumDb)  $default,) {final _that = this;
switch (_that) {
case _Track():
return $default(_that.id,_that.type,_that.title,_that.language,_that.codec,_that.channels,_that.sampleRate,_that.width,_that.height,_that.fps,_that.isDefault,_that.isForced,_that.isExternal,_that.isAudioDescription,_that.isHearingImpaired,_that.dolbyVisionProfile,_that.replayGainTrackDb,_that.replayGainAlbumDb);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int id,  TrackType type,  String? title,  String? language,  String? codec,  int? channels,  int? sampleRate,  int? width,  int? height,  double? fps,  bool isDefault,  bool isForced,  bool isExternal,  bool isAudioDescription,  bool isHearingImpaired,  int? dolbyVisionProfile,  double? replayGainTrackDb,  double? replayGainAlbumDb)?  $default,) {final _that = this;
switch (_that) {
case _Track() when $default != null:
return $default(_that.id,_that.type,_that.title,_that.language,_that.codec,_that.channels,_that.sampleRate,_that.width,_that.height,_that.fps,_that.isDefault,_that.isForced,_that.isExternal,_that.isAudioDescription,_that.isHearingImpaired,_that.dolbyVisionProfile,_that.replayGainTrackDb,_that.replayGainAlbumDb);case _:
  return null;

}
}

}

/// @nodoc


class _Track implements Track {
  const _Track({required this.id, required this.type, this.title, this.language, this.codec, this.channels, this.sampleRate, this.width, this.height, this.fps, this.isDefault = false, this.isForced = false, this.isExternal = false, this.isAudioDescription = false, this.isHearingImpaired = false, this.dolbyVisionProfile, this.replayGainTrackDb, this.replayGainAlbumDb});
  

@override final  int id;
@override final  TrackType type;
@override final  String? title;
/// BCP 47 language tag when known.
@override final  String? language;
@override final  String? codec;
@override final  int? channels;
@override final  int? sampleRate;
@override final  int? width;
@override final  int? height;
@override final  double? fps;
@override@JsonKey() final  bool isDefault;
@override@JsonKey() final  bool isForced;
@override@JsonKey() final  bool isExternal;
@override@JsonKey() final  bool isAudioDescription;
@override@JsonKey() final  bool isHearingImpaired;
/// Technical Dolby Vision profile of a video track (5, 7, 8); UI copy
/// never uses the trademark (docs/09 §4).
@override final  int? dolbyVisionProfile;
/// ReplayGain tags read by the demuxer (AUD-004).
@override final  double? replayGainTrackDb;
@override final  double? replayGainAlbumDb;

/// Create a copy of Track
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TrackCopyWith<_Track> get copyWith => __$TrackCopyWithImpl<_Track>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Track&&(identical(other.id, id) || other.id == id)&&(identical(other.type, type) || other.type == type)&&(identical(other.title, title) || other.title == title)&&(identical(other.language, language) || other.language == language)&&(identical(other.codec, codec) || other.codec == codec)&&(identical(other.channels, channels) || other.channels == channels)&&(identical(other.sampleRate, sampleRate) || other.sampleRate == sampleRate)&&(identical(other.width, width) || other.width == width)&&(identical(other.height, height) || other.height == height)&&(identical(other.fps, fps) || other.fps == fps)&&(identical(other.isDefault, isDefault) || other.isDefault == isDefault)&&(identical(other.isForced, isForced) || other.isForced == isForced)&&(identical(other.isExternal, isExternal) || other.isExternal == isExternal)&&(identical(other.isAudioDescription, isAudioDescription) || other.isAudioDescription == isAudioDescription)&&(identical(other.isHearingImpaired, isHearingImpaired) || other.isHearingImpaired == isHearingImpaired)&&(identical(other.dolbyVisionProfile, dolbyVisionProfile) || other.dolbyVisionProfile == dolbyVisionProfile)&&(identical(other.replayGainTrackDb, replayGainTrackDb) || other.replayGainTrackDb == replayGainTrackDb)&&(identical(other.replayGainAlbumDb, replayGainAlbumDb) || other.replayGainAlbumDb == replayGainAlbumDb));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,type,title,language,codec,channels,sampleRate,width,height,fps,isDefault,isForced,isExternal,isAudioDescription,isHearingImpaired,dolbyVisionProfile,replayGainTrackDb,replayGainAlbumDb);
}

@override
String toString() {
    return 'Track(id: $id, type: $type, title: $title, language: $language, codec: $codec, channels: $channels, sampleRate: $sampleRate, width: $width, height: $height, fps: $fps, isDefault: $isDefault, isForced: $isForced, isExternal: $isExternal, isAudioDescription: $isAudioDescription, isHearingImpaired: $isHearingImpaired, dolbyVisionProfile: $dolbyVisionProfile, replayGainTrackDb: $replayGainTrackDb, replayGainAlbumDb: $replayGainAlbumDb)';
}


}

/// @nodoc
abstract mixin class _$TrackCopyWith<$Res> implements $TrackCopyWith<$Res> {
  factory _$TrackCopyWith(_Track value, $Res Function(_Track) _then) = __$TrackCopyWithImpl;
@override @useResult
$Res call({
 int id, TrackType type, String? title, String? language, String? codec, int? channels, int? sampleRate, int? width, int? height, double? fps, bool isDefault, bool isForced, bool isExternal, bool isAudioDescription, bool isHearingImpaired, int? dolbyVisionProfile, double? replayGainTrackDb, double? replayGainAlbumDb
});




}
/// @nodoc
class __$TrackCopyWithImpl<$Res>
    implements _$TrackCopyWith<$Res> {
  __$TrackCopyWithImpl(this._self, this._then);

  final _Track _self;
  final $Res Function(_Track) _then;

/// Create a copy of Track
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? type = null,Object? title = freezed,Object? language = freezed,Object? codec = freezed,Object? channels = freezed,Object? sampleRate = freezed,Object? width = freezed,Object? height = freezed,Object? fps = freezed,Object? isDefault = null,Object? isForced = null,Object? isExternal = null,Object? isAudioDescription = null,Object? isHearingImpaired = null,Object? dolbyVisionProfile = freezed,Object? replayGainTrackDb = freezed,Object? replayGainAlbumDb = freezed,}) {
  return _then(_Track(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as TrackType,title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,language: freezed == language ? _self.language : language // ignore: cast_nullable_to_non_nullable
as String?,codec: freezed == codec ? _self.codec : codec // ignore: cast_nullable_to_non_nullable
as String?,channels: freezed == channels ? _self.channels : channels // ignore: cast_nullable_to_non_nullable
as int?,sampleRate: freezed == sampleRate ? _self.sampleRate : sampleRate // ignore: cast_nullable_to_non_nullable
as int?,width: freezed == width ? _self.width : width // ignore: cast_nullable_to_non_nullable
as int?,height: freezed == height ? _self.height : height // ignore: cast_nullable_to_non_nullable
as int?,fps: freezed == fps ? _self.fps : fps // ignore: cast_nullable_to_non_nullable
as double?,isDefault: null == isDefault ? _self.isDefault : isDefault // ignore: cast_nullable_to_non_nullable
as bool,isForced: null == isForced ? _self.isForced : isForced // ignore: cast_nullable_to_non_nullable
as bool,isExternal: null == isExternal ? _self.isExternal : isExternal // ignore: cast_nullable_to_non_nullable
as bool,isAudioDescription: null == isAudioDescription ? _self.isAudioDescription : isAudioDescription // ignore: cast_nullable_to_non_nullable
as bool,isHearingImpaired: null == isHearingImpaired ? _self.isHearingImpaired : isHearingImpaired // ignore: cast_nullable_to_non_nullable
as bool,dolbyVisionProfile: freezed == dolbyVisionProfile ? _self.dolbyVisionProfile : dolbyVisionProfile // ignore: cast_nullable_to_non_nullable
as int?,replayGainTrackDb: freezed == replayGainTrackDb ? _self.replayGainTrackDb : replayGainTrackDb // ignore: cast_nullable_to_non_nullable
as double?,replayGainAlbumDb: freezed == replayGainAlbumDb ? _self.replayGainAlbumDb : replayGainAlbumDb // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}


}

/// @nodoc
mixin _$Chapter {

 Duration get start; String? get title;
/// Create a copy of Chapter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChapterCopyWith<Chapter> get copyWith => _$ChapterCopyWithImpl<Chapter>(this as Chapter, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as Chapter;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Chapter&&(identical(other.start, _this.start) || other.start == _this.start)&&(identical(other.title, _this.title) || other.title == _this.title));
}


@override
int get hashCode {
  final _this = this as Chapter;
  return Object.hash(runtimeType,_this.start,_this.title);
}

@override
String toString() {
  final _this = this as Chapter;
  return 'Chapter(start: ${_this.start}, title: ${_this.title})';
}


}

/// @nodoc
abstract mixin class $ChapterCopyWith<$Res>  {
  factory $ChapterCopyWith(Chapter value, $Res Function(Chapter) _then) = _$ChapterCopyWithImpl;
@useResult
$Res call({
 Duration start, String? title
});




}
/// @nodoc
class _$ChapterCopyWithImpl<$Res>
    implements $ChapterCopyWith<$Res> {
  _$ChapterCopyWithImpl(this._self, this._then);

  final Chapter _self;
  final $Res Function(Chapter) _then;

/// Create a copy of Chapter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? start = null,Object? title = freezed,}) {
  return _then(Chapter(
start: null == start ? _self.start : start // ignore: cast_nullable_to_non_nullable
as Duration,title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [Chapter].
extension ChapterPatterns on Chapter {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Chapter value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Chapter() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Chapter value)  $default,){
final _that = this;
switch (_that) {
case _Chapter():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Chapter value)?  $default,){
final _that = this;
switch (_that) {
case _Chapter() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( Duration start,  String? title)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Chapter() when $default != null:
return $default(_that.start,_that.title);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( Duration start,  String? title)  $default,) {final _that = this;
switch (_that) {
case _Chapter():
return $default(_that.start,_that.title);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( Duration start,  String? title)?  $default,) {final _that = this;
switch (_that) {
case _Chapter() when $default != null:
return $default(_that.start,_that.title);case _:
  return null;

}
}

}

/// @nodoc


class _Chapter implements Chapter {
  const _Chapter({required this.start, this.title});
  

@override final  Duration start;
@override final  String? title;

/// Create a copy of Chapter
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ChapterCopyWith<_Chapter> get copyWith => __$ChapterCopyWithImpl<_Chapter>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Chapter&&(identical(other.start, start) || other.start == start)&&(identical(other.title, title) || other.title == title));
}


@override
int get hashCode {
    return Object.hash(runtimeType,start,title);
}

@override
String toString() {
    return 'Chapter(start: $start, title: $title)';
}


}

/// @nodoc
abstract mixin class _$ChapterCopyWith<$Res> implements $ChapterCopyWith<$Res> {
  factory _$ChapterCopyWith(_Chapter value, $Res Function(_Chapter) _then) = __$ChapterCopyWithImpl;
@override @useResult
$Res call({
 Duration start, String? title
});




}
/// @nodoc
class __$ChapterCopyWithImpl<$Res>
    implements _$ChapterCopyWith<$Res> {
  __$ChapterCopyWithImpl(this._self, this._then);

  final _Chapter _self;
  final $Res Function(_Chapter) _then;

/// Create a copy of Chapter
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? start = null,Object? title = freezed,}) {
  return _then(_Chapter(
start: null == start ? _self.start : start // ignore: cast_nullable_to_non_nullable
as Duration,title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$VideoStats {

 String? get container; String? get videoCodec; HwdecPath get hwdec; int? get width; int? get height; double? get fps; int get droppedFrames; int? get bitrate; HdrType get hdr;/// e.g. 5, 7, 8 — profile string only, shown as "HDR (dynamic metadata, profile 8)".
 int? get dolbyVisionProfile; String? get subtitleRenderer;/// Render path of the video surface (VID-030, VID-072 info overlay):
/// "d3d11" and "opengl-iosurface" (zero-copy), "d3d11-copy",
/// "opengl-readback" (iOS Simulator only), "android-surface", "software";
/// null without a surface.
 String? get renderBackend;/// Mastering display peak (cd/m²) and MaxCLL from HDR10 metadata.
 double? get peakNits; double? get maxCll;
/// Create a copy of VideoStats
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VideoStatsCopyWith<VideoStats> get copyWith => _$VideoStatsCopyWithImpl<VideoStats>(this as VideoStats, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as VideoStats;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VideoStats&&(identical(other.container, _this.container) || other.container == _this.container)&&(identical(other.videoCodec, _this.videoCodec) || other.videoCodec == _this.videoCodec)&&(identical(other.hwdec, _this.hwdec) || other.hwdec == _this.hwdec)&&(identical(other.width, _this.width) || other.width == _this.width)&&(identical(other.height, _this.height) || other.height == _this.height)&&(identical(other.fps, _this.fps) || other.fps == _this.fps)&&(identical(other.droppedFrames, _this.droppedFrames) || other.droppedFrames == _this.droppedFrames)&&(identical(other.bitrate, _this.bitrate) || other.bitrate == _this.bitrate)&&(identical(other.hdr, _this.hdr) || other.hdr == _this.hdr)&&(identical(other.dolbyVisionProfile, _this.dolbyVisionProfile) || other.dolbyVisionProfile == _this.dolbyVisionProfile)&&(identical(other.subtitleRenderer, _this.subtitleRenderer) || other.subtitleRenderer == _this.subtitleRenderer)&&(identical(other.renderBackend, _this.renderBackend) || other.renderBackend == _this.renderBackend)&&(identical(other.peakNits, _this.peakNits) || other.peakNits == _this.peakNits)&&(identical(other.maxCll, _this.maxCll) || other.maxCll == _this.maxCll));
}


@override
int get hashCode {
  final _this = this as VideoStats;
  return Object.hash(runtimeType,_this.container,_this.videoCodec,_this.hwdec,_this.width,_this.height,_this.fps,_this.droppedFrames,_this.bitrate,_this.hdr,_this.dolbyVisionProfile,_this.subtitleRenderer,_this.renderBackend,_this.peakNits,_this.maxCll);
}

@override
String toString() {
  final _this = this as VideoStats;
  return 'VideoStats(container: ${_this.container}, videoCodec: ${_this.videoCodec}, hwdec: ${_this.hwdec}, width: ${_this.width}, height: ${_this.height}, fps: ${_this.fps}, droppedFrames: ${_this.droppedFrames}, bitrate: ${_this.bitrate}, hdr: ${_this.hdr}, dolbyVisionProfile: ${_this.dolbyVisionProfile}, subtitleRenderer: ${_this.subtitleRenderer}, renderBackend: ${_this.renderBackend}, peakNits: ${_this.peakNits}, maxCll: ${_this.maxCll})';
}


}

/// @nodoc
abstract mixin class $VideoStatsCopyWith<$Res>  {
  factory $VideoStatsCopyWith(VideoStats value, $Res Function(VideoStats) _then) = _$VideoStatsCopyWithImpl;
@useResult
$Res call({
 String? container, String? videoCodec, HwdecPath hwdec, int? width, int? height, double? fps, int droppedFrames, int? bitrate, HdrType hdr, int? dolbyVisionProfile, String? subtitleRenderer, String? renderBackend, double? peakNits, double? maxCll
});




}
/// @nodoc
class _$VideoStatsCopyWithImpl<$Res>
    implements $VideoStatsCopyWith<$Res> {
  _$VideoStatsCopyWithImpl(this._self, this._then);

  final VideoStats _self;
  final $Res Function(VideoStats) _then;

/// Create a copy of VideoStats
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? container = freezed,Object? videoCodec = freezed,Object? hwdec = null,Object? width = freezed,Object? height = freezed,Object? fps = freezed,Object? droppedFrames = null,Object? bitrate = freezed,Object? hdr = null,Object? dolbyVisionProfile = freezed,Object? subtitleRenderer = freezed,Object? renderBackend = freezed,Object? peakNits = freezed,Object? maxCll = freezed,}) {
  return _then(VideoStats(
container: freezed == container ? _self.container : container // ignore: cast_nullable_to_non_nullable
as String?,videoCodec: freezed == videoCodec ? _self.videoCodec : videoCodec // ignore: cast_nullable_to_non_nullable
as String?,hwdec: null == hwdec ? _self.hwdec : hwdec // ignore: cast_nullable_to_non_nullable
as HwdecPath,width: freezed == width ? _self.width : width // ignore: cast_nullable_to_non_nullable
as int?,height: freezed == height ? _self.height : height // ignore: cast_nullable_to_non_nullable
as int?,fps: freezed == fps ? _self.fps : fps // ignore: cast_nullable_to_non_nullable
as double?,droppedFrames: null == droppedFrames ? _self.droppedFrames : droppedFrames // ignore: cast_nullable_to_non_nullable
as int,bitrate: freezed == bitrate ? _self.bitrate : bitrate // ignore: cast_nullable_to_non_nullable
as int?,hdr: null == hdr ? _self.hdr : hdr // ignore: cast_nullable_to_non_nullable
as HdrType,dolbyVisionProfile: freezed == dolbyVisionProfile ? _self.dolbyVisionProfile : dolbyVisionProfile // ignore: cast_nullable_to_non_nullable
as int?,subtitleRenderer: freezed == subtitleRenderer ? _self.subtitleRenderer : subtitleRenderer // ignore: cast_nullable_to_non_nullable
as String?,renderBackend: freezed == renderBackend ? _self.renderBackend : renderBackend // ignore: cast_nullable_to_non_nullable
as String?,peakNits: freezed == peakNits ? _self.peakNits : peakNits // ignore: cast_nullable_to_non_nullable
as double?,maxCll: freezed == maxCll ? _self.maxCll : maxCll // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}

}


/// Adds pattern-matching-related methods to [VideoStats].
extension VideoStatsPatterns on VideoStats {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _VideoStats value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _VideoStats() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _VideoStats value)  $default,){
final _that = this;
switch (_that) {
case _VideoStats():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _VideoStats value)?  $default,){
final _that = this;
switch (_that) {
case _VideoStats() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? container,  String? videoCodec,  HwdecPath hwdec,  int? width,  int? height,  double? fps,  int droppedFrames,  int? bitrate,  HdrType hdr,  int? dolbyVisionProfile,  String? subtitleRenderer,  String? renderBackend,  double? peakNits,  double? maxCll)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _VideoStats() when $default != null:
return $default(_that.container,_that.videoCodec,_that.hwdec,_that.width,_that.height,_that.fps,_that.droppedFrames,_that.bitrate,_that.hdr,_that.dolbyVisionProfile,_that.subtitleRenderer,_that.renderBackend,_that.peakNits,_that.maxCll);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? container,  String? videoCodec,  HwdecPath hwdec,  int? width,  int? height,  double? fps,  int droppedFrames,  int? bitrate,  HdrType hdr,  int? dolbyVisionProfile,  String? subtitleRenderer,  String? renderBackend,  double? peakNits,  double? maxCll)  $default,) {final _that = this;
switch (_that) {
case _VideoStats():
return $default(_that.container,_that.videoCodec,_that.hwdec,_that.width,_that.height,_that.fps,_that.droppedFrames,_that.bitrate,_that.hdr,_that.dolbyVisionProfile,_that.subtitleRenderer,_that.renderBackend,_that.peakNits,_that.maxCll);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? container,  String? videoCodec,  HwdecPath hwdec,  int? width,  int? height,  double? fps,  int droppedFrames,  int? bitrate,  HdrType hdr,  int? dolbyVisionProfile,  String? subtitleRenderer,  String? renderBackend,  double? peakNits,  double? maxCll)?  $default,) {final _that = this;
switch (_that) {
case _VideoStats() when $default != null:
return $default(_that.container,_that.videoCodec,_that.hwdec,_that.width,_that.height,_that.fps,_that.droppedFrames,_that.bitrate,_that.hdr,_that.dolbyVisionProfile,_that.subtitleRenderer,_that.renderBackend,_that.peakNits,_that.maxCll);case _:
  return null;

}
}

}

/// @nodoc


class _VideoStats implements VideoStats {
  const _VideoStats({this.container, this.videoCodec, this.hwdec = HwdecPath.none, this.width, this.height, this.fps, this.droppedFrames = 0, this.bitrate, this.hdr = HdrType.sdr, this.dolbyVisionProfile, this.subtitleRenderer, this.renderBackend, this.peakNits, this.maxCll});
  

@override final  String? container;
@override final  String? videoCodec;
@override@JsonKey() final  HwdecPath hwdec;
@override final  int? width;
@override final  int? height;
@override final  double? fps;
@override@JsonKey() final  int droppedFrames;
@override final  int? bitrate;
@override@JsonKey() final  HdrType hdr;
/// e.g. 5, 7, 8 — profile string only, shown as "HDR (dynamic metadata, profile 8)".
@override final  int? dolbyVisionProfile;
@override final  String? subtitleRenderer;
/// Render path of the video surface (VID-030, VID-072 info overlay):
/// "d3d11" and "opengl-iosurface" (zero-copy), "d3d11-copy",
/// "opengl-readback" (iOS Simulator only), "android-surface", "software";
/// null without a surface.
@override final  String? renderBackend;
/// Mastering display peak (cd/m²) and MaxCLL from HDR10 metadata.
@override final  double? peakNits;
@override final  double? maxCll;

/// Create a copy of VideoStats
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$VideoStatsCopyWith<_VideoStats> get copyWith => __$VideoStatsCopyWithImpl<_VideoStats>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _VideoStats&&(identical(other.container, container) || other.container == container)&&(identical(other.videoCodec, videoCodec) || other.videoCodec == videoCodec)&&(identical(other.hwdec, hwdec) || other.hwdec == hwdec)&&(identical(other.width, width) || other.width == width)&&(identical(other.height, height) || other.height == height)&&(identical(other.fps, fps) || other.fps == fps)&&(identical(other.droppedFrames, droppedFrames) || other.droppedFrames == droppedFrames)&&(identical(other.bitrate, bitrate) || other.bitrate == bitrate)&&(identical(other.hdr, hdr) || other.hdr == hdr)&&(identical(other.dolbyVisionProfile, dolbyVisionProfile) || other.dolbyVisionProfile == dolbyVisionProfile)&&(identical(other.subtitleRenderer, subtitleRenderer) || other.subtitleRenderer == subtitleRenderer)&&(identical(other.renderBackend, renderBackend) || other.renderBackend == renderBackend)&&(identical(other.peakNits, peakNits) || other.peakNits == peakNits)&&(identical(other.maxCll, maxCll) || other.maxCll == maxCll));
}


@override
int get hashCode {
    return Object.hash(runtimeType,container,videoCodec,hwdec,width,height,fps,droppedFrames,bitrate,hdr,dolbyVisionProfile,subtitleRenderer,renderBackend,peakNits,maxCll);
}

@override
String toString() {
    return 'VideoStats(container: $container, videoCodec: $videoCodec, hwdec: $hwdec, width: $width, height: $height, fps: $fps, droppedFrames: $droppedFrames, bitrate: $bitrate, hdr: $hdr, dolbyVisionProfile: $dolbyVisionProfile, subtitleRenderer: $subtitleRenderer, renderBackend: $renderBackend, peakNits: $peakNits, maxCll: $maxCll)';
}


}

/// @nodoc
abstract mixin class _$VideoStatsCopyWith<$Res> implements $VideoStatsCopyWith<$Res> {
  factory _$VideoStatsCopyWith(_VideoStats value, $Res Function(_VideoStats) _then) = __$VideoStatsCopyWithImpl;
@override @useResult
$Res call({
 String? container, String? videoCodec, HwdecPath hwdec, int? width, int? height, double? fps, int droppedFrames, int? bitrate, HdrType hdr, int? dolbyVisionProfile, String? subtitleRenderer, String? renderBackend, double? peakNits, double? maxCll
});




}
/// @nodoc
class __$VideoStatsCopyWithImpl<$Res>
    implements _$VideoStatsCopyWith<$Res> {
  __$VideoStatsCopyWithImpl(this._self, this._then);

  final _VideoStats _self;
  final $Res Function(_VideoStats) _then;

/// Create a copy of VideoStats
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? container = freezed,Object? videoCodec = freezed,Object? hwdec = null,Object? width = freezed,Object? height = freezed,Object? fps = freezed,Object? droppedFrames = null,Object? bitrate = freezed,Object? hdr = null,Object? dolbyVisionProfile = freezed,Object? subtitleRenderer = freezed,Object? renderBackend = freezed,Object? peakNits = freezed,Object? maxCll = freezed,}) {
  return _then(_VideoStats(
container: freezed == container ? _self.container : container // ignore: cast_nullable_to_non_nullable
as String?,videoCodec: freezed == videoCodec ? _self.videoCodec : videoCodec // ignore: cast_nullable_to_non_nullable
as String?,hwdec: null == hwdec ? _self.hwdec : hwdec // ignore: cast_nullable_to_non_nullable
as HwdecPath,width: freezed == width ? _self.width : width // ignore: cast_nullable_to_non_nullable
as int?,height: freezed == height ? _self.height : height // ignore: cast_nullable_to_non_nullable
as int?,fps: freezed == fps ? _self.fps : fps // ignore: cast_nullable_to_non_nullable
as double?,droppedFrames: null == droppedFrames ? _self.droppedFrames : droppedFrames // ignore: cast_nullable_to_non_nullable
as int,bitrate: freezed == bitrate ? _self.bitrate : bitrate // ignore: cast_nullable_to_non_nullable
as int?,hdr: null == hdr ? _self.hdr : hdr // ignore: cast_nullable_to_non_nullable
as HdrType,dolbyVisionProfile: freezed == dolbyVisionProfile ? _self.dolbyVisionProfile : dolbyVisionProfile // ignore: cast_nullable_to_non_nullable
as int?,subtitleRenderer: freezed == subtitleRenderer ? _self.subtitleRenderer : subtitleRenderer // ignore: cast_nullable_to_non_nullable
as String?,renderBackend: freezed == renderBackend ? _self.renderBackend : renderBackend // ignore: cast_nullable_to_non_nullable
as String?,peakNits: freezed == peakNits ? _self.peakNits : peakNits // ignore: cast_nullable_to_non_nullable
as double?,maxCll: freezed == maxCll ? _self.maxCll : maxCll // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}


}

/// @nodoc
mixin _$AudioOutputInfo {

 String? get device; String? get format; int? get sampleRate; int? get bitDepth; int? get channels; AudioOutputPath get path;/// Engine audio output in use (`wasapi`, `aaudio`, `coreaudio`, …).
 String? get output;
/// Create a copy of AudioOutputInfo
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AudioOutputInfoCopyWith<AudioOutputInfo> get copyWith => _$AudioOutputInfoCopyWithImpl<AudioOutputInfo>(this as AudioOutputInfo, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AudioOutputInfo;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AudioOutputInfo&&(identical(other.device, _this.device) || other.device == _this.device)&&(identical(other.format, _this.format) || other.format == _this.format)&&(identical(other.sampleRate, _this.sampleRate) || other.sampleRate == _this.sampleRate)&&(identical(other.bitDepth, _this.bitDepth) || other.bitDepth == _this.bitDepth)&&(identical(other.channels, _this.channels) || other.channels == _this.channels)&&(identical(other.path, _this.path) || other.path == _this.path)&&(identical(other.output, _this.output) || other.output == _this.output));
}


@override
int get hashCode {
  final _this = this as AudioOutputInfo;
  return Object.hash(runtimeType,_this.device,_this.format,_this.sampleRate,_this.bitDepth,_this.channels,_this.path,_this.output);
}

@override
String toString() {
  final _this = this as AudioOutputInfo;
  return 'AudioOutputInfo(device: ${_this.device}, format: ${_this.format}, sampleRate: ${_this.sampleRate}, bitDepth: ${_this.bitDepth}, channels: ${_this.channels}, path: ${_this.path}, output: ${_this.output})';
}


}

/// @nodoc
abstract mixin class $AudioOutputInfoCopyWith<$Res>  {
  factory $AudioOutputInfoCopyWith(AudioOutputInfo value, $Res Function(AudioOutputInfo) _then) = _$AudioOutputInfoCopyWithImpl;
@useResult
$Res call({
 String? device, String? format, int? sampleRate, int? bitDepth, int? channels, AudioOutputPath path, String? output
});




}
/// @nodoc
class _$AudioOutputInfoCopyWithImpl<$Res>
    implements $AudioOutputInfoCopyWith<$Res> {
  _$AudioOutputInfoCopyWithImpl(this._self, this._then);

  final AudioOutputInfo _self;
  final $Res Function(AudioOutputInfo) _then;

/// Create a copy of AudioOutputInfo
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? device = freezed,Object? format = freezed,Object? sampleRate = freezed,Object? bitDepth = freezed,Object? channels = freezed,Object? path = null,Object? output = freezed,}) {
  return _then(AudioOutputInfo(
device: freezed == device ? _self.device : device // ignore: cast_nullable_to_non_nullable
as String?,format: freezed == format ? _self.format : format // ignore: cast_nullable_to_non_nullable
as String?,sampleRate: freezed == sampleRate ? _self.sampleRate : sampleRate // ignore: cast_nullable_to_non_nullable
as int?,bitDepth: freezed == bitDepth ? _self.bitDepth : bitDepth // ignore: cast_nullable_to_non_nullable
as int?,channels: freezed == channels ? _self.channels : channels // ignore: cast_nullable_to_non_nullable
as int?,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as AudioOutputPath,output: freezed == output ? _self.output : output // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [AudioOutputInfo].
extension AudioOutputInfoPatterns on AudioOutputInfo {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AudioOutputInfo value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AudioOutputInfo() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AudioOutputInfo value)  $default,){
final _that = this;
switch (_that) {
case _AudioOutputInfo():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AudioOutputInfo value)?  $default,){
final _that = this;
switch (_that) {
case _AudioOutputInfo() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? device,  String? format,  int? sampleRate,  int? bitDepth,  int? channels,  AudioOutputPath path,  String? output)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AudioOutputInfo() when $default != null:
return $default(_that.device,_that.format,_that.sampleRate,_that.bitDepth,_that.channels,_that.path,_that.output);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? device,  String? format,  int? sampleRate,  int? bitDepth,  int? channels,  AudioOutputPath path,  String? output)  $default,) {final _that = this;
switch (_that) {
case _AudioOutputInfo():
return $default(_that.device,_that.format,_that.sampleRate,_that.bitDepth,_that.channels,_that.path,_that.output);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? device,  String? format,  int? sampleRate,  int? bitDepth,  int? channels,  AudioOutputPath path,  String? output)?  $default,) {final _that = this;
switch (_that) {
case _AudioOutputInfo() when $default != null:
return $default(_that.device,_that.format,_that.sampleRate,_that.bitDepth,_that.channels,_that.path,_that.output);case _:
  return null;

}
}

}

/// @nodoc


class _AudioOutputInfo implements AudioOutputInfo {
  const _AudioOutputInfo({this.device, this.format, this.sampleRate, this.bitDepth, this.channels, this.path = AudioOutputPath.unknown, this.output});
  

@override final  String? device;
@override final  String? format;
@override final  int? sampleRate;
@override final  int? bitDepth;
@override final  int? channels;
@override@JsonKey() final  AudioOutputPath path;
/// Engine audio output in use (`wasapi`, `aaudio`, `coreaudio`, …).
@override final  String? output;

/// Create a copy of AudioOutputInfo
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AudioOutputInfoCopyWith<_AudioOutputInfo> get copyWith => __$AudioOutputInfoCopyWithImpl<_AudioOutputInfo>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AudioOutputInfo&&(identical(other.device, device) || other.device == device)&&(identical(other.format, format) || other.format == format)&&(identical(other.sampleRate, sampleRate) || other.sampleRate == sampleRate)&&(identical(other.bitDepth, bitDepth) || other.bitDepth == bitDepth)&&(identical(other.channels, channels) || other.channels == channels)&&(identical(other.path, path) || other.path == path)&&(identical(other.output, output) || other.output == output));
}


@override
int get hashCode {
    return Object.hash(runtimeType,device,format,sampleRate,bitDepth,channels,path,output);
}

@override
String toString() {
    return 'AudioOutputInfo(device: $device, format: $format, sampleRate: $sampleRate, bitDepth: $bitDepth, channels: $channels, path: $path, output: $output)';
}


}

/// @nodoc
abstract mixin class _$AudioOutputInfoCopyWith<$Res> implements $AudioOutputInfoCopyWith<$Res> {
  factory _$AudioOutputInfoCopyWith(_AudioOutputInfo value, $Res Function(_AudioOutputInfo) _then) = __$AudioOutputInfoCopyWithImpl;
@override @useResult
$Res call({
 String? device, String? format, int? sampleRate, int? bitDepth, int? channels, AudioOutputPath path, String? output
});




}
/// @nodoc
class __$AudioOutputInfoCopyWithImpl<$Res>
    implements _$AudioOutputInfoCopyWith<$Res> {
  __$AudioOutputInfoCopyWithImpl(this._self, this._then);

  final _AudioOutputInfo _self;
  final $Res Function(_AudioOutputInfo) _then;

/// Create a copy of AudioOutputInfo
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? device = freezed,Object? format = freezed,Object? sampleRate = freezed,Object? bitDepth = freezed,Object? channels = freezed,Object? path = null,Object? output = freezed,}) {
  return _then(_AudioOutputInfo(
device: freezed == device ? _self.device : device // ignore: cast_nullable_to_non_nullable
as String?,format: freezed == format ? _self.format : format // ignore: cast_nullable_to_non_nullable
as String?,sampleRate: freezed == sampleRate ? _self.sampleRate : sampleRate // ignore: cast_nullable_to_non_nullable
as int?,bitDepth: freezed == bitDepth ? _self.bitDepth : bitDepth // ignore: cast_nullable_to_non_nullable
as int?,channels: freezed == channels ? _self.channels : channels // ignore: cast_nullable_to_non_nullable
as int?,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as AudioOutputPath,output: freezed == output ? _self.output : output // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$PlaybackState {

 PlaybackStatus get status; Duration get position; Duration? get duration; Duration get bufferedUntil; double get rate;/// 0.0–3.0 (300 % boost with limiter, VID-066).
 double get volume; bool get muted; List<Track> get tracks; int? get videoTrackId; int? get audioTrackId; int? get subtitleTrackId; int? get secondarySubtitleTrackId; List<Chapter> get chapters; Duration get audioDelay; Duration get subtitleDelay; Duration get secondarySubtitleDelay;/// Current secondary subtitle line (SUB-016). The UI draws it with its own
/// size and position; the engine does not burn it in.
 String? get secondarySubtitleText; VideoStats get video; AudioOutputInfo get audio; EngineError? get error;/// One-time informational notes for the current item (e.g. VID-035).
 Set<EngineNotice> get notices;/// True when the next item is preloaded for gapless or crossfade
/// (AUD-002, AUD-003).
 bool get nextPrepared;/// Increments each time an item starts, including gapless and crossfade
/// advances, so queues can follow transitions.
 int get item;
/// Create a copy of PlaybackState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlaybackStateCopyWith<PlaybackState> get copyWith => _$PlaybackStateCopyWithImpl<PlaybackState>(this as PlaybackState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PlaybackState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlaybackState&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.position, _this.position) || other.position == _this.position)&&(identical(other.duration, _this.duration) || other.duration == _this.duration)&&(identical(other.bufferedUntil, _this.bufferedUntil) || other.bufferedUntil == _this.bufferedUntil)&&(identical(other.rate, _this.rate) || other.rate == _this.rate)&&(identical(other.volume, _this.volume) || other.volume == _this.volume)&&(identical(other.muted, _this.muted) || other.muted == _this.muted)&&const DeepCollectionEquality().equals(other.tracks, _this.tracks)&&(identical(other.videoTrackId, _this.videoTrackId) || other.videoTrackId == _this.videoTrackId)&&(identical(other.audioTrackId, _this.audioTrackId) || other.audioTrackId == _this.audioTrackId)&&(identical(other.subtitleTrackId, _this.subtitleTrackId) || other.subtitleTrackId == _this.subtitleTrackId)&&(identical(other.secondarySubtitleTrackId, _this.secondarySubtitleTrackId) || other.secondarySubtitleTrackId == _this.secondarySubtitleTrackId)&&const DeepCollectionEquality().equals(other.chapters, _this.chapters)&&(identical(other.audioDelay, _this.audioDelay) || other.audioDelay == _this.audioDelay)&&(identical(other.subtitleDelay, _this.subtitleDelay) || other.subtitleDelay == _this.subtitleDelay)&&(identical(other.secondarySubtitleDelay, _this.secondarySubtitleDelay) || other.secondarySubtitleDelay == _this.secondarySubtitleDelay)&&(identical(other.secondarySubtitleText, _this.secondarySubtitleText) || other.secondarySubtitleText == _this.secondarySubtitleText)&&(identical(other.video, _this.video) || other.video == _this.video)&&(identical(other.audio, _this.audio) || other.audio == _this.audio)&&(identical(other.error, _this.error) || other.error == _this.error)&&const DeepCollectionEquality().equals(other.notices, _this.notices)&&(identical(other.nextPrepared, _this.nextPrepared) || other.nextPrepared == _this.nextPrepared)&&(identical(other.item, _this.item) || other.item == _this.item));
}


@override
int get hashCode {
  final _this = this as PlaybackState;
  return Object.hashAll([runtimeType,_this.status,_this.position,_this.duration,_this.bufferedUntil,_this.rate,_this.volume,_this.muted,const DeepCollectionEquality().hash(_this.tracks),_this.videoTrackId,_this.audioTrackId,_this.subtitleTrackId,_this.secondarySubtitleTrackId,const DeepCollectionEquality().hash(_this.chapters),_this.audioDelay,_this.subtitleDelay,_this.secondarySubtitleDelay,_this.secondarySubtitleText,_this.video,_this.audio,_this.error,const DeepCollectionEquality().hash(_this.notices),_this.nextPrepared,_this.item]);
}

@override
String toString() {
  final _this = this as PlaybackState;
  return 'PlaybackState(status: ${_this.status}, position: ${_this.position}, duration: ${_this.duration}, bufferedUntil: ${_this.bufferedUntil}, rate: ${_this.rate}, volume: ${_this.volume}, muted: ${_this.muted}, tracks: ${_this.tracks}, videoTrackId: ${_this.videoTrackId}, audioTrackId: ${_this.audioTrackId}, subtitleTrackId: ${_this.subtitleTrackId}, secondarySubtitleTrackId: ${_this.secondarySubtitleTrackId}, chapters: ${_this.chapters}, audioDelay: ${_this.audioDelay}, subtitleDelay: ${_this.subtitleDelay}, secondarySubtitleDelay: ${_this.secondarySubtitleDelay}, secondarySubtitleText: ${_this.secondarySubtitleText}, video: ${_this.video}, audio: ${_this.audio}, error: ${_this.error}, notices: ${_this.notices}, nextPrepared: ${_this.nextPrepared}, item: ${_this.item})';
}


}

/// @nodoc
abstract mixin class $PlaybackStateCopyWith<$Res>  {
  factory $PlaybackStateCopyWith(PlaybackState value, $Res Function(PlaybackState) _then) = _$PlaybackStateCopyWithImpl;
@useResult
$Res call({
 PlaybackStatus status, Duration position, Duration? duration, Duration bufferedUntil, double rate, double volume, bool muted, List<Track> tracks, int? videoTrackId, int? audioTrackId, int? subtitleTrackId, int? secondarySubtitleTrackId, List<Chapter> chapters, Duration audioDelay, Duration subtitleDelay, Duration secondarySubtitleDelay, String? secondarySubtitleText, VideoStats video, AudioOutputInfo audio, EngineError? error, Set<EngineNotice> notices, bool nextPrepared, int item
});


$VideoStatsCopyWith<$Res> get video;$AudioOutputInfoCopyWith<$Res> get audio;$EngineErrorCopyWith<$Res>? get error;

}
/// @nodoc
class _$PlaybackStateCopyWithImpl<$Res>
    implements $PlaybackStateCopyWith<$Res> {
  _$PlaybackStateCopyWithImpl(this._self, this._then);

  final PlaybackState _self;
  final $Res Function(PlaybackState) _then;

/// Create a copy of PlaybackState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? status = null,Object? position = null,Object? duration = freezed,Object? bufferedUntil = null,Object? rate = null,Object? volume = null,Object? muted = null,Object? tracks = null,Object? videoTrackId = freezed,Object? audioTrackId = freezed,Object? subtitleTrackId = freezed,Object? secondarySubtitleTrackId = freezed,Object? chapters = null,Object? audioDelay = null,Object? subtitleDelay = null,Object? secondarySubtitleDelay = null,Object? secondarySubtitleText = freezed,Object? video = null,Object? audio = null,Object? error = freezed,Object? notices = null,Object? nextPrepared = null,Object? item = null,}) {
  return _then(PlaybackState(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as PlaybackStatus,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as Duration,duration: freezed == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as Duration?,bufferedUntil: null == bufferedUntil ? _self.bufferedUntil : bufferedUntil // ignore: cast_nullable_to_non_nullable
as Duration,rate: null == rate ? _self.rate : rate // ignore: cast_nullable_to_non_nullable
as double,volume: null == volume ? _self.volume : volume // ignore: cast_nullable_to_non_nullable
as double,muted: null == muted ? _self.muted : muted // ignore: cast_nullable_to_non_nullable
as bool,tracks: null == tracks ? _self.tracks : tracks // ignore: cast_nullable_to_non_nullable
as List<Track>,videoTrackId: freezed == videoTrackId ? _self.videoTrackId : videoTrackId // ignore: cast_nullable_to_non_nullable
as int?,audioTrackId: freezed == audioTrackId ? _self.audioTrackId : audioTrackId // ignore: cast_nullable_to_non_nullable
as int?,subtitleTrackId: freezed == subtitleTrackId ? _self.subtitleTrackId : subtitleTrackId // ignore: cast_nullable_to_non_nullable
as int?,secondarySubtitleTrackId: freezed == secondarySubtitleTrackId ? _self.secondarySubtitleTrackId : secondarySubtitleTrackId // ignore: cast_nullable_to_non_nullable
as int?,chapters: null == chapters ? _self.chapters : chapters // ignore: cast_nullable_to_non_nullable
as List<Chapter>,audioDelay: null == audioDelay ? _self.audioDelay : audioDelay // ignore: cast_nullable_to_non_nullable
as Duration,subtitleDelay: null == subtitleDelay ? _self.subtitleDelay : subtitleDelay // ignore: cast_nullable_to_non_nullable
as Duration,secondarySubtitleDelay: null == secondarySubtitleDelay ? _self.secondarySubtitleDelay : secondarySubtitleDelay // ignore: cast_nullable_to_non_nullable
as Duration,secondarySubtitleText: freezed == secondarySubtitleText ? _self.secondarySubtitleText : secondarySubtitleText // ignore: cast_nullable_to_non_nullable
as String?,video: null == video ? _self.video : video // ignore: cast_nullable_to_non_nullable
as VideoStats,audio: null == audio ? _self.audio : audio // ignore: cast_nullable_to_non_nullable
as AudioOutputInfo,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as EngineError?,notices: null == notices ? _self.notices : notices // ignore: cast_nullable_to_non_nullable
as Set<EngineNotice>,nextPrepared: null == nextPrepared ? _self.nextPrepared : nextPrepared // ignore: cast_nullable_to_non_nullable
as bool,item: null == item ? _self.item : item // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of PlaybackState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$VideoStatsCopyWith<$Res> get video {
  
  return $VideoStatsCopyWith<$Res>(_self.video, (value) {
    return _then(_self.copyWith(video: value));
  });
}/// Create a copy of PlaybackState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AudioOutputInfoCopyWith<$Res> get audio {
  
  return $AudioOutputInfoCopyWith<$Res>(_self.audio, (value) {
    return _then(_self.copyWith(audio: value));
  });
}/// Create a copy of PlaybackState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$EngineErrorCopyWith<$Res>? get error {
    if (_self.error == null) {
    return null;
  }

  return $EngineErrorCopyWith<$Res>(_self.error!, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}


/// Adds pattern-matching-related methods to [PlaybackState].
extension PlaybackStatePatterns on PlaybackState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PlaybackState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PlaybackState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PlaybackState value)  $default,){
final _that = this;
switch (_that) {
case _PlaybackState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PlaybackState value)?  $default,){
final _that = this;
switch (_that) {
case _PlaybackState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( PlaybackStatus status,  Duration position,  Duration? duration,  Duration bufferedUntil,  double rate,  double volume,  bool muted,  List<Track> tracks,  int? videoTrackId,  int? audioTrackId,  int? subtitleTrackId,  int? secondarySubtitleTrackId,  List<Chapter> chapters,  Duration audioDelay,  Duration subtitleDelay,  Duration secondarySubtitleDelay,  String? secondarySubtitleText,  VideoStats video,  AudioOutputInfo audio,  EngineError? error,  Set<EngineNotice> notices,  bool nextPrepared,  int item)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PlaybackState() when $default != null:
return $default(_that.status,_that.position,_that.duration,_that.bufferedUntil,_that.rate,_that.volume,_that.muted,_that.tracks,_that.videoTrackId,_that.audioTrackId,_that.subtitleTrackId,_that.secondarySubtitleTrackId,_that.chapters,_that.audioDelay,_that.subtitleDelay,_that.secondarySubtitleDelay,_that.secondarySubtitleText,_that.video,_that.audio,_that.error,_that.notices,_that.nextPrepared,_that.item);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( PlaybackStatus status,  Duration position,  Duration? duration,  Duration bufferedUntil,  double rate,  double volume,  bool muted,  List<Track> tracks,  int? videoTrackId,  int? audioTrackId,  int? subtitleTrackId,  int? secondarySubtitleTrackId,  List<Chapter> chapters,  Duration audioDelay,  Duration subtitleDelay,  Duration secondarySubtitleDelay,  String? secondarySubtitleText,  VideoStats video,  AudioOutputInfo audio,  EngineError? error,  Set<EngineNotice> notices,  bool nextPrepared,  int item)  $default,) {final _that = this;
switch (_that) {
case _PlaybackState():
return $default(_that.status,_that.position,_that.duration,_that.bufferedUntil,_that.rate,_that.volume,_that.muted,_that.tracks,_that.videoTrackId,_that.audioTrackId,_that.subtitleTrackId,_that.secondarySubtitleTrackId,_that.chapters,_that.audioDelay,_that.subtitleDelay,_that.secondarySubtitleDelay,_that.secondarySubtitleText,_that.video,_that.audio,_that.error,_that.notices,_that.nextPrepared,_that.item);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( PlaybackStatus status,  Duration position,  Duration? duration,  Duration bufferedUntil,  double rate,  double volume,  bool muted,  List<Track> tracks,  int? videoTrackId,  int? audioTrackId,  int? subtitleTrackId,  int? secondarySubtitleTrackId,  List<Chapter> chapters,  Duration audioDelay,  Duration subtitleDelay,  Duration secondarySubtitleDelay,  String? secondarySubtitleText,  VideoStats video,  AudioOutputInfo audio,  EngineError? error,  Set<EngineNotice> notices,  bool nextPrepared,  int item)?  $default,) {final _that = this;
switch (_that) {
case _PlaybackState() when $default != null:
return $default(_that.status,_that.position,_that.duration,_that.bufferedUntil,_that.rate,_that.volume,_that.muted,_that.tracks,_that.videoTrackId,_that.audioTrackId,_that.subtitleTrackId,_that.secondarySubtitleTrackId,_that.chapters,_that.audioDelay,_that.subtitleDelay,_that.secondarySubtitleDelay,_that.secondarySubtitleText,_that.video,_that.audio,_that.error,_that.notices,_that.nextPrepared,_that.item);case _:
  return null;

}
}

}

/// @nodoc


class _PlaybackState implements PlaybackState {
  const _PlaybackState({this.status = PlaybackStatus.idle, this.position = Duration.zero, this.duration, this.bufferedUntil = Duration.zero, this.rate = 1.0, this.volume = 1.0, this.muted = false,  List<Track> tracks = const <Track>[], this.videoTrackId, this.audioTrackId, this.subtitleTrackId, this.secondarySubtitleTrackId,  List<Chapter> chapters = const <Chapter>[], this.audioDelay = Duration.zero, this.subtitleDelay = Duration.zero, this.secondarySubtitleDelay = Duration.zero, this.secondarySubtitleText, this.video = const VideoStats(), this.audio = const AudioOutputInfo(), this.error,  Set<EngineNotice> notices = const <EngineNotice>{}, this.nextPrepared = false, this.item = 0}): _tracks = tracks,_chapters = chapters,_notices = notices;
  

@override@JsonKey() final  PlaybackStatus status;
@override@JsonKey() final  Duration position;
@override final  Duration? duration;
@override@JsonKey() final  Duration bufferedUntil;
@override@JsonKey() final  double rate;
/// 0.0–3.0 (300 % boost with limiter, VID-066).
@override@JsonKey() final  double volume;
@override@JsonKey() final  bool muted;
 final  List<Track> _tracks;
@override@JsonKey() List<Track> get tracks {
  if (_tracks is EqualUnmodifiableListView) return _tracks;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_tracks);
}

@override final  int? videoTrackId;
@override final  int? audioTrackId;
@override final  int? subtitleTrackId;
@override final  int? secondarySubtitleTrackId;
 final  List<Chapter> _chapters;
@override@JsonKey() List<Chapter> get chapters {
  if (_chapters is EqualUnmodifiableListView) return _chapters;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_chapters);
}

@override@JsonKey() final  Duration audioDelay;
@override@JsonKey() final  Duration subtitleDelay;
@override@JsonKey() final  Duration secondarySubtitleDelay;
/// Current secondary subtitle line (SUB-016). The UI draws it with its own
/// size and position; the engine does not burn it in.
@override final  String? secondarySubtitleText;
@override@JsonKey() final  VideoStats video;
@override@JsonKey() final  AudioOutputInfo audio;
@override final  EngineError? error;
/// One-time informational notes for the current item (e.g. VID-035).
 final  Set<EngineNotice> _notices;
/// One-time informational notes for the current item (e.g. VID-035).
@override@JsonKey() Set<EngineNotice> get notices {
  if (_notices is EqualUnmodifiableSetView) return _notices;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_notices);
}

/// True when the next item is preloaded for gapless or crossfade
/// (AUD-002, AUD-003).
@override@JsonKey() final  bool nextPrepared;
/// Increments each time an item starts, including gapless and crossfade
/// advances, so queues can follow transitions.
@override@JsonKey() final  int item;

/// Create a copy of PlaybackState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PlaybackStateCopyWith<_PlaybackState> get copyWith => __$PlaybackStateCopyWithImpl<_PlaybackState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PlaybackState&&(identical(other.status, status) || other.status == status)&&(identical(other.position, position) || other.position == position)&&(identical(other.duration, duration) || other.duration == duration)&&(identical(other.bufferedUntil, bufferedUntil) || other.bufferedUntil == bufferedUntil)&&(identical(other.rate, rate) || other.rate == rate)&&(identical(other.volume, volume) || other.volume == volume)&&(identical(other.muted, muted) || other.muted == muted)&&const DeepCollectionEquality().equals(other.tracks, _tracks)&&(identical(other.videoTrackId, videoTrackId) || other.videoTrackId == videoTrackId)&&(identical(other.audioTrackId, audioTrackId) || other.audioTrackId == audioTrackId)&&(identical(other.subtitleTrackId, subtitleTrackId) || other.subtitleTrackId == subtitleTrackId)&&(identical(other.secondarySubtitleTrackId, secondarySubtitleTrackId) || other.secondarySubtitleTrackId == secondarySubtitleTrackId)&&const DeepCollectionEquality().equals(other.chapters, _chapters)&&(identical(other.audioDelay, audioDelay) || other.audioDelay == audioDelay)&&(identical(other.subtitleDelay, subtitleDelay) || other.subtitleDelay == subtitleDelay)&&(identical(other.secondarySubtitleDelay, secondarySubtitleDelay) || other.secondarySubtitleDelay == secondarySubtitleDelay)&&(identical(other.secondarySubtitleText, secondarySubtitleText) || other.secondarySubtitleText == secondarySubtitleText)&&(identical(other.video, video) || other.video == video)&&(identical(other.audio, audio) || other.audio == audio)&&(identical(other.error, error) || other.error == error)&&const DeepCollectionEquality().equals(other.notices, _notices)&&(identical(other.nextPrepared, nextPrepared) || other.nextPrepared == nextPrepared)&&(identical(other.item, item) || other.item == item));
}


@override
int get hashCode {
    return Object.hashAll([runtimeType,status,position,duration,bufferedUntil,rate,volume,muted,const DeepCollectionEquality().hash(_tracks),videoTrackId,audioTrackId,subtitleTrackId,secondarySubtitleTrackId,const DeepCollectionEquality().hash(_chapters),audioDelay,subtitleDelay,secondarySubtitleDelay,secondarySubtitleText,video,audio,error,const DeepCollectionEquality().hash(_notices),nextPrepared,item]);
}

@override
String toString() {
    return 'PlaybackState(status: $status, position: $position, duration: $duration, bufferedUntil: $bufferedUntil, rate: $rate, volume: $volume, muted: $muted, tracks: $tracks, videoTrackId: $videoTrackId, audioTrackId: $audioTrackId, subtitleTrackId: $subtitleTrackId, secondarySubtitleTrackId: $secondarySubtitleTrackId, chapters: $chapters, audioDelay: $audioDelay, subtitleDelay: $subtitleDelay, secondarySubtitleDelay: $secondarySubtitleDelay, secondarySubtitleText: $secondarySubtitleText, video: $video, audio: $audio, error: $error, notices: $notices, nextPrepared: $nextPrepared, item: $item)';
}


}

/// @nodoc
abstract mixin class _$PlaybackStateCopyWith<$Res> implements $PlaybackStateCopyWith<$Res> {
  factory _$PlaybackStateCopyWith(_PlaybackState value, $Res Function(_PlaybackState) _then) = __$PlaybackStateCopyWithImpl;
@override @useResult
$Res call({
 PlaybackStatus status, Duration position, Duration? duration, Duration bufferedUntil, double rate, double volume, bool muted, List<Track> tracks, int? videoTrackId, int? audioTrackId, int? subtitleTrackId, int? secondarySubtitleTrackId, List<Chapter> chapters, Duration audioDelay, Duration subtitleDelay, Duration secondarySubtitleDelay, String? secondarySubtitleText, VideoStats video, AudioOutputInfo audio, EngineError? error, Set<EngineNotice> notices, bool nextPrepared, int item
});


@override $VideoStatsCopyWith<$Res> get video;@override $AudioOutputInfoCopyWith<$Res> get audio;@override $EngineErrorCopyWith<$Res>? get error;

}
/// @nodoc
class __$PlaybackStateCopyWithImpl<$Res>
    implements _$PlaybackStateCopyWith<$Res> {
  __$PlaybackStateCopyWithImpl(this._self, this._then);

  final _PlaybackState _self;
  final $Res Function(_PlaybackState) _then;

/// Create a copy of PlaybackState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? status = null,Object? position = null,Object? duration = freezed,Object? bufferedUntil = null,Object? rate = null,Object? volume = null,Object? muted = null,Object? tracks = null,Object? videoTrackId = freezed,Object? audioTrackId = freezed,Object? subtitleTrackId = freezed,Object? secondarySubtitleTrackId = freezed,Object? chapters = null,Object? audioDelay = null,Object? subtitleDelay = null,Object? secondarySubtitleDelay = null,Object? secondarySubtitleText = freezed,Object? video = null,Object? audio = null,Object? error = freezed,Object? notices = null,Object? nextPrepared = null,Object? item = null,}) {
  return _then(_PlaybackState(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as PlaybackStatus,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as Duration,duration: freezed == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as Duration?,bufferedUntil: null == bufferedUntil ? _self.bufferedUntil : bufferedUntil // ignore: cast_nullable_to_non_nullable
as Duration,rate: null == rate ? _self.rate : rate // ignore: cast_nullable_to_non_nullable
as double,volume: null == volume ? _self.volume : volume // ignore: cast_nullable_to_non_nullable
as double,muted: null == muted ? _self.muted : muted // ignore: cast_nullable_to_non_nullable
as bool,tracks: null == tracks ? _self._tracks : tracks // ignore: cast_nullable_to_non_nullable
as List<Track>,videoTrackId: freezed == videoTrackId ? _self.videoTrackId : videoTrackId // ignore: cast_nullable_to_non_nullable
as int?,audioTrackId: freezed == audioTrackId ? _self.audioTrackId : audioTrackId // ignore: cast_nullable_to_non_nullable
as int?,subtitleTrackId: freezed == subtitleTrackId ? _self.subtitleTrackId : subtitleTrackId // ignore: cast_nullable_to_non_nullable
as int?,secondarySubtitleTrackId: freezed == secondarySubtitleTrackId ? _self.secondarySubtitleTrackId : secondarySubtitleTrackId // ignore: cast_nullable_to_non_nullable
as int?,chapters: null == chapters ? _self._chapters : chapters // ignore: cast_nullable_to_non_nullable
as List<Chapter>,audioDelay: null == audioDelay ? _self.audioDelay : audioDelay // ignore: cast_nullable_to_non_nullable
as Duration,subtitleDelay: null == subtitleDelay ? _self.subtitleDelay : subtitleDelay // ignore: cast_nullable_to_non_nullable
as Duration,secondarySubtitleDelay: null == secondarySubtitleDelay ? _self.secondarySubtitleDelay : secondarySubtitleDelay // ignore: cast_nullable_to_non_nullable
as Duration,secondarySubtitleText: freezed == secondarySubtitleText ? _self.secondarySubtitleText : secondarySubtitleText // ignore: cast_nullable_to_non_nullable
as String?,video: null == video ? _self.video : video // ignore: cast_nullable_to_non_nullable
as VideoStats,audio: null == audio ? _self.audio : audio // ignore: cast_nullable_to_non_nullable
as AudioOutputInfo,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as EngineError?,notices: null == notices ? _self._notices : notices // ignore: cast_nullable_to_non_nullable
as Set<EngineNotice>,nextPrepared: null == nextPrepared ? _self.nextPrepared : nextPrepared // ignore: cast_nullable_to_non_nullable
as bool,item: null == item ? _self.item : item // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of PlaybackState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$VideoStatsCopyWith<$Res> get video {
  
  return $VideoStatsCopyWith<$Res>(_self.video, (value) {
    return _then(_self.copyWith(video: value));
  });
}/// Create a copy of PlaybackState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AudioOutputInfoCopyWith<$Res> get audio {
  
  return $AudioOutputInfoCopyWith<$Res>(_self.audio, (value) {
    return _then(_self.copyWith(audio: value));
  });
}/// Create a copy of PlaybackState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$EngineErrorCopyWith<$Res>? get error {
    if (_self.error == null) {
    return null;
  }

  return $EngineErrorCopyWith<$Res>(_self.error!, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

/// @nodoc
mixin _$OpenOptions {

 Duration? get start; bool get autoplay;/// Music role and video audio-only mode (VID-068): `vid=no`.
 bool get audioOnly; List<String> get preferredAudioLanguages; List<String> get preferredSubtitleLanguages;/// Read-ahead cache budget; null lets the engine size it by bitrate (VID-006).
 int? get cacheBytes;/// Chapters known from outside the container (disc IFO/MPLS, VID-007);
/// used when the stream itself has none.
 List<Chapter> get chapters;/// Gain from the library's background EBU R128 scan for items without
/// ReplayGain tags (AUD-004, `LoudnessScanner`); applied when loudness
/// normalisation is on.
 double? get loudnessGainDb;
/// Create a copy of OpenOptions
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OpenOptionsCopyWith<OpenOptions> get copyWith => _$OpenOptionsCopyWithImpl<OpenOptions>(this as OpenOptions, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as OpenOptions;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OpenOptions&&(identical(other.start, _this.start) || other.start == _this.start)&&(identical(other.autoplay, _this.autoplay) || other.autoplay == _this.autoplay)&&(identical(other.audioOnly, _this.audioOnly) || other.audioOnly == _this.audioOnly)&&const DeepCollectionEquality().equals(other.preferredAudioLanguages, _this.preferredAudioLanguages)&&const DeepCollectionEquality().equals(other.preferredSubtitleLanguages, _this.preferredSubtitleLanguages)&&(identical(other.cacheBytes, _this.cacheBytes) || other.cacheBytes == _this.cacheBytes)&&const DeepCollectionEquality().equals(other.chapters, _this.chapters)&&(identical(other.loudnessGainDb, _this.loudnessGainDb) || other.loudnessGainDb == _this.loudnessGainDb));
}


@override
int get hashCode {
  final _this = this as OpenOptions;
  return Object.hash(runtimeType,_this.start,_this.autoplay,_this.audioOnly,const DeepCollectionEquality().hash(_this.preferredAudioLanguages),const DeepCollectionEquality().hash(_this.preferredSubtitleLanguages),_this.cacheBytes,const DeepCollectionEquality().hash(_this.chapters),_this.loudnessGainDb);
}

@override
String toString() {
  final _this = this as OpenOptions;
  return 'OpenOptions(start: ${_this.start}, autoplay: ${_this.autoplay}, audioOnly: ${_this.audioOnly}, preferredAudioLanguages: ${_this.preferredAudioLanguages}, preferredSubtitleLanguages: ${_this.preferredSubtitleLanguages}, cacheBytes: ${_this.cacheBytes}, chapters: ${_this.chapters}, loudnessGainDb: ${_this.loudnessGainDb})';
}


}

/// @nodoc
abstract mixin class $OpenOptionsCopyWith<$Res>  {
  factory $OpenOptionsCopyWith(OpenOptions value, $Res Function(OpenOptions) _then) = _$OpenOptionsCopyWithImpl;
@useResult
$Res call({
 Duration? start, bool autoplay, bool audioOnly, List<String> preferredAudioLanguages, List<String> preferredSubtitleLanguages, int? cacheBytes, List<Chapter> chapters, double? loudnessGainDb
});




}
/// @nodoc
class _$OpenOptionsCopyWithImpl<$Res>
    implements $OpenOptionsCopyWith<$Res> {
  _$OpenOptionsCopyWithImpl(this._self, this._then);

  final OpenOptions _self;
  final $Res Function(OpenOptions) _then;

/// Create a copy of OpenOptions
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? start = freezed,Object? autoplay = null,Object? audioOnly = null,Object? preferredAudioLanguages = null,Object? preferredSubtitleLanguages = null,Object? cacheBytes = freezed,Object? chapters = null,Object? loudnessGainDb = freezed,}) {
  return _then(OpenOptions(
start: freezed == start ? _self.start : start // ignore: cast_nullable_to_non_nullable
as Duration?,autoplay: null == autoplay ? _self.autoplay : autoplay // ignore: cast_nullable_to_non_nullable
as bool,audioOnly: null == audioOnly ? _self.audioOnly : audioOnly // ignore: cast_nullable_to_non_nullable
as bool,preferredAudioLanguages: null == preferredAudioLanguages ? _self.preferredAudioLanguages : preferredAudioLanguages // ignore: cast_nullable_to_non_nullable
as List<String>,preferredSubtitleLanguages: null == preferredSubtitleLanguages ? _self.preferredSubtitleLanguages : preferredSubtitleLanguages // ignore: cast_nullable_to_non_nullable
as List<String>,cacheBytes: freezed == cacheBytes ? _self.cacheBytes : cacheBytes // ignore: cast_nullable_to_non_nullable
as int?,chapters: null == chapters ? _self.chapters : chapters // ignore: cast_nullable_to_non_nullable
as List<Chapter>,loudnessGainDb: freezed == loudnessGainDb ? _self.loudnessGainDb : loudnessGainDb // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}

}


/// Adds pattern-matching-related methods to [OpenOptions].
extension OpenOptionsPatterns on OpenOptions {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _OpenOptions value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _OpenOptions() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _OpenOptions value)  $default,){
final _that = this;
switch (_that) {
case _OpenOptions():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _OpenOptions value)?  $default,){
final _that = this;
switch (_that) {
case _OpenOptions() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( Duration? start,  bool autoplay,  bool audioOnly,  List<String> preferredAudioLanguages,  List<String> preferredSubtitleLanguages,  int? cacheBytes,  List<Chapter> chapters,  double? loudnessGainDb)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _OpenOptions() when $default != null:
return $default(_that.start,_that.autoplay,_that.audioOnly,_that.preferredAudioLanguages,_that.preferredSubtitleLanguages,_that.cacheBytes,_that.chapters,_that.loudnessGainDb);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( Duration? start,  bool autoplay,  bool audioOnly,  List<String> preferredAudioLanguages,  List<String> preferredSubtitleLanguages,  int? cacheBytes,  List<Chapter> chapters,  double? loudnessGainDb)  $default,) {final _that = this;
switch (_that) {
case _OpenOptions():
return $default(_that.start,_that.autoplay,_that.audioOnly,_that.preferredAudioLanguages,_that.preferredSubtitleLanguages,_that.cacheBytes,_that.chapters,_that.loudnessGainDb);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( Duration? start,  bool autoplay,  bool audioOnly,  List<String> preferredAudioLanguages,  List<String> preferredSubtitleLanguages,  int? cacheBytes,  List<Chapter> chapters,  double? loudnessGainDb)?  $default,) {final _that = this;
switch (_that) {
case _OpenOptions() when $default != null:
return $default(_that.start,_that.autoplay,_that.audioOnly,_that.preferredAudioLanguages,_that.preferredSubtitleLanguages,_that.cacheBytes,_that.chapters,_that.loudnessGainDb);case _:
  return null;

}
}

}

/// @nodoc


class _OpenOptions implements OpenOptions {
  const _OpenOptions({this.start, this.autoplay = true, this.audioOnly = false,  List<String> preferredAudioLanguages = const <String>[],  List<String> preferredSubtitleLanguages = const <String>[], this.cacheBytes,  List<Chapter> chapters = const <Chapter>[], this.loudnessGainDb}): _preferredAudioLanguages = preferredAudioLanguages,_preferredSubtitleLanguages = preferredSubtitleLanguages,_chapters = chapters;
  

@override final  Duration? start;
@override@JsonKey() final  bool autoplay;
/// Music role and video audio-only mode (VID-068): `vid=no`.
@override@JsonKey() final  bool audioOnly;
 final  List<String> _preferredAudioLanguages;
@override@JsonKey() List<String> get preferredAudioLanguages {
  if (_preferredAudioLanguages is EqualUnmodifiableListView) return _preferredAudioLanguages;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_preferredAudioLanguages);
}

 final  List<String> _preferredSubtitleLanguages;
@override@JsonKey() List<String> get preferredSubtitleLanguages {
  if (_preferredSubtitleLanguages is EqualUnmodifiableListView) return _preferredSubtitleLanguages;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_preferredSubtitleLanguages);
}

/// Read-ahead cache budget; null lets the engine size it by bitrate (VID-006).
@override final  int? cacheBytes;
/// Chapters known from outside the container (disc IFO/MPLS, VID-007);
/// used when the stream itself has none.
 final  List<Chapter> _chapters;
/// Chapters known from outside the container (disc IFO/MPLS, VID-007);
/// used when the stream itself has none.
@override@JsonKey() List<Chapter> get chapters {
  if (_chapters is EqualUnmodifiableListView) return _chapters;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_chapters);
}

/// Gain from the library's background EBU R128 scan for items without
/// ReplayGain tags (AUD-004, `LoudnessScanner`); applied when loudness
/// normalisation is on.
@override final  double? loudnessGainDb;

/// Create a copy of OpenOptions
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$OpenOptionsCopyWith<_OpenOptions> get copyWith => __$OpenOptionsCopyWithImpl<_OpenOptions>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _OpenOptions&&(identical(other.start, start) || other.start == start)&&(identical(other.autoplay, autoplay) || other.autoplay == autoplay)&&(identical(other.audioOnly, audioOnly) || other.audioOnly == audioOnly)&&const DeepCollectionEquality().equals(other.preferredAudioLanguages, _preferredAudioLanguages)&&const DeepCollectionEquality().equals(other.preferredSubtitleLanguages, _preferredSubtitleLanguages)&&(identical(other.cacheBytes, cacheBytes) || other.cacheBytes == cacheBytes)&&const DeepCollectionEquality().equals(other.chapters, _chapters)&&(identical(other.loudnessGainDb, loudnessGainDb) || other.loudnessGainDb == loudnessGainDb));
}


@override
int get hashCode {
    return Object.hash(runtimeType,start,autoplay,audioOnly,const DeepCollectionEquality().hash(_preferredAudioLanguages),const DeepCollectionEquality().hash(_preferredSubtitleLanguages),cacheBytes,const DeepCollectionEquality().hash(_chapters),loudnessGainDb);
}

@override
String toString() {
    return 'OpenOptions(start: $start, autoplay: $autoplay, audioOnly: $audioOnly, preferredAudioLanguages: $preferredAudioLanguages, preferredSubtitleLanguages: $preferredSubtitleLanguages, cacheBytes: $cacheBytes, chapters: $chapters, loudnessGainDb: $loudnessGainDb)';
}


}

/// @nodoc
abstract mixin class _$OpenOptionsCopyWith<$Res> implements $OpenOptionsCopyWith<$Res> {
  factory _$OpenOptionsCopyWith(_OpenOptions value, $Res Function(_OpenOptions) _then) = __$OpenOptionsCopyWithImpl;
@override @useResult
$Res call({
 Duration? start, bool autoplay, bool audioOnly, List<String> preferredAudioLanguages, List<String> preferredSubtitleLanguages, int? cacheBytes, List<Chapter> chapters, double? loudnessGainDb
});




}
/// @nodoc
class __$OpenOptionsCopyWithImpl<$Res>
    implements _$OpenOptionsCopyWith<$Res> {
  __$OpenOptionsCopyWithImpl(this._self, this._then);

  final _OpenOptions _self;
  final $Res Function(_OpenOptions) _then;

/// Create a copy of OpenOptions
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? start = freezed,Object? autoplay = null,Object? audioOnly = null,Object? preferredAudioLanguages = null,Object? preferredSubtitleLanguages = null,Object? cacheBytes = freezed,Object? chapters = null,Object? loudnessGainDb = freezed,}) {
  return _then(_OpenOptions(
start: freezed == start ? _self.start : start // ignore: cast_nullable_to_non_nullable
as Duration?,autoplay: null == autoplay ? _self.autoplay : autoplay // ignore: cast_nullable_to_non_nullable
as bool,audioOnly: null == audioOnly ? _self.audioOnly : audioOnly // ignore: cast_nullable_to_non_nullable
as bool,preferredAudioLanguages: null == preferredAudioLanguages ? _self._preferredAudioLanguages : preferredAudioLanguages // ignore: cast_nullable_to_non_nullable
as List<String>,preferredSubtitleLanguages: null == preferredSubtitleLanguages ? _self._preferredSubtitleLanguages : preferredSubtitleLanguages // ignore: cast_nullable_to_non_nullable
as List<String>,cacheBytes: freezed == cacheBytes ? _self.cacheBytes : cacheBytes // ignore: cast_nullable_to_non_nullable
as int?,chapters: null == chapters ? _self._chapters : chapters // ignore: cast_nullable_to_non_nullable
as List<Chapter>,loudnessGainDb: freezed == loudnessGainDb ? _self.loudnessGainDb : loudnessGainDb // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}


}

/// @nodoc
mixin _$VideoFilterChain {

 ToneMapping get toneMapping; Scaler get scaler; bool get deband; Deinterlace get deinterlace; double get sharpen; double get brightness; double get contrast; double get saturation; double get gamma; double get hue;/// Clockwise degrees: 0, 90, 180, 270.
 int get rotate; bool get flipHorizontal; bool get flipVertical;/// e.g. 16/9; null keeps the container aspect.
 double? get aspectOverride; double get zoom; double get panX; double get panY; bool get interpolation;
/// Create a copy of VideoFilterChain
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VideoFilterChainCopyWith<VideoFilterChain> get copyWith => _$VideoFilterChainCopyWithImpl<VideoFilterChain>(this as VideoFilterChain, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as VideoFilterChain;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VideoFilterChain&&(identical(other.toneMapping, _this.toneMapping) || other.toneMapping == _this.toneMapping)&&(identical(other.scaler, _this.scaler) || other.scaler == _this.scaler)&&(identical(other.deband, _this.deband) || other.deband == _this.deband)&&(identical(other.deinterlace, _this.deinterlace) || other.deinterlace == _this.deinterlace)&&(identical(other.sharpen, _this.sharpen) || other.sharpen == _this.sharpen)&&(identical(other.brightness, _this.brightness) || other.brightness == _this.brightness)&&(identical(other.contrast, _this.contrast) || other.contrast == _this.contrast)&&(identical(other.saturation, _this.saturation) || other.saturation == _this.saturation)&&(identical(other.gamma, _this.gamma) || other.gamma == _this.gamma)&&(identical(other.hue, _this.hue) || other.hue == _this.hue)&&(identical(other.rotate, _this.rotate) || other.rotate == _this.rotate)&&(identical(other.flipHorizontal, _this.flipHorizontal) || other.flipHorizontal == _this.flipHorizontal)&&(identical(other.flipVertical, _this.flipVertical) || other.flipVertical == _this.flipVertical)&&(identical(other.aspectOverride, _this.aspectOverride) || other.aspectOverride == _this.aspectOverride)&&(identical(other.zoom, _this.zoom) || other.zoom == _this.zoom)&&(identical(other.panX, _this.panX) || other.panX == _this.panX)&&(identical(other.panY, _this.panY) || other.panY == _this.panY)&&(identical(other.interpolation, _this.interpolation) || other.interpolation == _this.interpolation));
}


@override
int get hashCode {
  final _this = this as VideoFilterChain;
  return Object.hash(runtimeType,_this.toneMapping,_this.scaler,_this.deband,_this.deinterlace,_this.sharpen,_this.brightness,_this.contrast,_this.saturation,_this.gamma,_this.hue,_this.rotate,_this.flipHorizontal,_this.flipVertical,_this.aspectOverride,_this.zoom,_this.panX,_this.panY,_this.interpolation);
}

@override
String toString() {
  final _this = this as VideoFilterChain;
  return 'VideoFilterChain(toneMapping: ${_this.toneMapping}, scaler: ${_this.scaler}, deband: ${_this.deband}, deinterlace: ${_this.deinterlace}, sharpen: ${_this.sharpen}, brightness: ${_this.brightness}, contrast: ${_this.contrast}, saturation: ${_this.saturation}, gamma: ${_this.gamma}, hue: ${_this.hue}, rotate: ${_this.rotate}, flipHorizontal: ${_this.flipHorizontal}, flipVertical: ${_this.flipVertical}, aspectOverride: ${_this.aspectOverride}, zoom: ${_this.zoom}, panX: ${_this.panX}, panY: ${_this.panY}, interpolation: ${_this.interpolation})';
}


}

/// @nodoc
abstract mixin class $VideoFilterChainCopyWith<$Res>  {
  factory $VideoFilterChainCopyWith(VideoFilterChain value, $Res Function(VideoFilterChain) _then) = _$VideoFilterChainCopyWithImpl;
@useResult
$Res call({
 ToneMapping toneMapping, Scaler scaler, bool deband, Deinterlace deinterlace, double sharpen, double brightness, double contrast, double saturation, double gamma, double hue, int rotate, bool flipHorizontal, bool flipVertical, double? aspectOverride, double zoom, double panX, double panY, bool interpolation
});




}
/// @nodoc
class _$VideoFilterChainCopyWithImpl<$Res>
    implements $VideoFilterChainCopyWith<$Res> {
  _$VideoFilterChainCopyWithImpl(this._self, this._then);

  final VideoFilterChain _self;
  final $Res Function(VideoFilterChain) _then;

/// Create a copy of VideoFilterChain
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? toneMapping = null,Object? scaler = null,Object? deband = null,Object? deinterlace = null,Object? sharpen = null,Object? brightness = null,Object? contrast = null,Object? saturation = null,Object? gamma = null,Object? hue = null,Object? rotate = null,Object? flipHorizontal = null,Object? flipVertical = null,Object? aspectOverride = freezed,Object? zoom = null,Object? panX = null,Object? panY = null,Object? interpolation = null,}) {
  return _then(VideoFilterChain(
toneMapping: null == toneMapping ? _self.toneMapping : toneMapping // ignore: cast_nullable_to_non_nullable
as ToneMapping,scaler: null == scaler ? _self.scaler : scaler // ignore: cast_nullable_to_non_nullable
as Scaler,deband: null == deband ? _self.deband : deband // ignore: cast_nullable_to_non_nullable
as bool,deinterlace: null == deinterlace ? _self.deinterlace : deinterlace // ignore: cast_nullable_to_non_nullable
as Deinterlace,sharpen: null == sharpen ? _self.sharpen : sharpen // ignore: cast_nullable_to_non_nullable
as double,brightness: null == brightness ? _self.brightness : brightness // ignore: cast_nullable_to_non_nullable
as double,contrast: null == contrast ? _self.contrast : contrast // ignore: cast_nullable_to_non_nullable
as double,saturation: null == saturation ? _self.saturation : saturation // ignore: cast_nullable_to_non_nullable
as double,gamma: null == gamma ? _self.gamma : gamma // ignore: cast_nullable_to_non_nullable
as double,hue: null == hue ? _self.hue : hue // ignore: cast_nullable_to_non_nullable
as double,rotate: null == rotate ? _self.rotate : rotate // ignore: cast_nullable_to_non_nullable
as int,flipHorizontal: null == flipHorizontal ? _self.flipHorizontal : flipHorizontal // ignore: cast_nullable_to_non_nullable
as bool,flipVertical: null == flipVertical ? _self.flipVertical : flipVertical // ignore: cast_nullable_to_non_nullable
as bool,aspectOverride: freezed == aspectOverride ? _self.aspectOverride : aspectOverride // ignore: cast_nullable_to_non_nullable
as double?,zoom: null == zoom ? _self.zoom : zoom // ignore: cast_nullable_to_non_nullable
as double,panX: null == panX ? _self.panX : panX // ignore: cast_nullable_to_non_nullable
as double,panY: null == panY ? _self.panY : panY // ignore: cast_nullable_to_non_nullable
as double,interpolation: null == interpolation ? _self.interpolation : interpolation // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [VideoFilterChain].
extension VideoFilterChainPatterns on VideoFilterChain {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _VideoFilterChain value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _VideoFilterChain() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _VideoFilterChain value)  $default,){
final _that = this;
switch (_that) {
case _VideoFilterChain():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _VideoFilterChain value)?  $default,){
final _that = this;
switch (_that) {
case _VideoFilterChain() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ToneMapping toneMapping,  Scaler scaler,  bool deband,  Deinterlace deinterlace,  double sharpen,  double brightness,  double contrast,  double saturation,  double gamma,  double hue,  int rotate,  bool flipHorizontal,  bool flipVertical,  double? aspectOverride,  double zoom,  double panX,  double panY,  bool interpolation)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _VideoFilterChain() when $default != null:
return $default(_that.toneMapping,_that.scaler,_that.deband,_that.deinterlace,_that.sharpen,_that.brightness,_that.contrast,_that.saturation,_that.gamma,_that.hue,_that.rotate,_that.flipHorizontal,_that.flipVertical,_that.aspectOverride,_that.zoom,_that.panX,_that.panY,_that.interpolation);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ToneMapping toneMapping,  Scaler scaler,  bool deband,  Deinterlace deinterlace,  double sharpen,  double brightness,  double contrast,  double saturation,  double gamma,  double hue,  int rotate,  bool flipHorizontal,  bool flipVertical,  double? aspectOverride,  double zoom,  double panX,  double panY,  bool interpolation)  $default,) {final _that = this;
switch (_that) {
case _VideoFilterChain():
return $default(_that.toneMapping,_that.scaler,_that.deband,_that.deinterlace,_that.sharpen,_that.brightness,_that.contrast,_that.saturation,_that.gamma,_that.hue,_that.rotate,_that.flipHorizontal,_that.flipVertical,_that.aspectOverride,_that.zoom,_that.panX,_that.panY,_that.interpolation);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ToneMapping toneMapping,  Scaler scaler,  bool deband,  Deinterlace deinterlace,  double sharpen,  double brightness,  double contrast,  double saturation,  double gamma,  double hue,  int rotate,  bool flipHorizontal,  bool flipVertical,  double? aspectOverride,  double zoom,  double panX,  double panY,  bool interpolation)?  $default,) {final _that = this;
switch (_that) {
case _VideoFilterChain() when $default != null:
return $default(_that.toneMapping,_that.scaler,_that.deband,_that.deinterlace,_that.sharpen,_that.brightness,_that.contrast,_that.saturation,_that.gamma,_that.hue,_that.rotate,_that.flipHorizontal,_that.flipVertical,_that.aspectOverride,_that.zoom,_that.panX,_that.panY,_that.interpolation);case _:
  return null;

}
}

}

/// @nodoc


class _VideoFilterChain implements VideoFilterChain {
  const _VideoFilterChain({this.toneMapping = ToneMapping.bt2390, this.scaler = Scaler.spline36, this.deband = false, this.deinterlace = Deinterlace.auto, this.sharpen = 0, this.brightness = 0, this.contrast = 0, this.saturation = 0, this.gamma = 0, this.hue = 0, this.rotate = 0, this.flipHorizontal = false, this.flipVertical = false, this.aspectOverride, this.zoom = 0, this.panX = 0, this.panY = 0, this.interpolation = false});
  

@override@JsonKey() final  ToneMapping toneMapping;
@override@JsonKey() final  Scaler scaler;
@override@JsonKey() final  bool deband;
@override@JsonKey() final  Deinterlace deinterlace;
@override@JsonKey() final  double sharpen;
@override@JsonKey() final  double brightness;
@override@JsonKey() final  double contrast;
@override@JsonKey() final  double saturation;
@override@JsonKey() final  double gamma;
@override@JsonKey() final  double hue;
/// Clockwise degrees: 0, 90, 180, 270.
@override@JsonKey() final  int rotate;
@override@JsonKey() final  bool flipHorizontal;
@override@JsonKey() final  bool flipVertical;
/// e.g. 16/9; null keeps the container aspect.
@override final  double? aspectOverride;
@override@JsonKey() final  double zoom;
@override@JsonKey() final  double panX;
@override@JsonKey() final  double panY;
@override@JsonKey() final  bool interpolation;

/// Create a copy of VideoFilterChain
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$VideoFilterChainCopyWith<_VideoFilterChain> get copyWith => __$VideoFilterChainCopyWithImpl<_VideoFilterChain>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _VideoFilterChain&&(identical(other.toneMapping, toneMapping) || other.toneMapping == toneMapping)&&(identical(other.scaler, scaler) || other.scaler == scaler)&&(identical(other.deband, deband) || other.deband == deband)&&(identical(other.deinterlace, deinterlace) || other.deinterlace == deinterlace)&&(identical(other.sharpen, sharpen) || other.sharpen == sharpen)&&(identical(other.brightness, brightness) || other.brightness == brightness)&&(identical(other.contrast, contrast) || other.contrast == contrast)&&(identical(other.saturation, saturation) || other.saturation == saturation)&&(identical(other.gamma, gamma) || other.gamma == gamma)&&(identical(other.hue, hue) || other.hue == hue)&&(identical(other.rotate, rotate) || other.rotate == rotate)&&(identical(other.flipHorizontal, flipHorizontal) || other.flipHorizontal == flipHorizontal)&&(identical(other.flipVertical, flipVertical) || other.flipVertical == flipVertical)&&(identical(other.aspectOverride, aspectOverride) || other.aspectOverride == aspectOverride)&&(identical(other.zoom, zoom) || other.zoom == zoom)&&(identical(other.panX, panX) || other.panX == panX)&&(identical(other.panY, panY) || other.panY == panY)&&(identical(other.interpolation, interpolation) || other.interpolation == interpolation));
}


@override
int get hashCode {
    return Object.hash(runtimeType,toneMapping,scaler,deband,deinterlace,sharpen,brightness,contrast,saturation,gamma,hue,rotate,flipHorizontal,flipVertical,aspectOverride,zoom,panX,panY,interpolation);
}

@override
String toString() {
    return 'VideoFilterChain(toneMapping: $toneMapping, scaler: $scaler, deband: $deband, deinterlace: $deinterlace, sharpen: $sharpen, brightness: $brightness, contrast: $contrast, saturation: $saturation, gamma: $gamma, hue: $hue, rotate: $rotate, flipHorizontal: $flipHorizontal, flipVertical: $flipVertical, aspectOverride: $aspectOverride, zoom: $zoom, panX: $panX, panY: $panY, interpolation: $interpolation)';
}


}

/// @nodoc
abstract mixin class _$VideoFilterChainCopyWith<$Res> implements $VideoFilterChainCopyWith<$Res> {
  factory _$VideoFilterChainCopyWith(_VideoFilterChain value, $Res Function(_VideoFilterChain) _then) = __$VideoFilterChainCopyWithImpl;
@override @useResult
$Res call({
 ToneMapping toneMapping, Scaler scaler, bool deband, Deinterlace deinterlace, double sharpen, double brightness, double contrast, double saturation, double gamma, double hue, int rotate, bool flipHorizontal, bool flipVertical, double? aspectOverride, double zoom, double panX, double panY, bool interpolation
});




}
/// @nodoc
class __$VideoFilterChainCopyWithImpl<$Res>
    implements _$VideoFilterChainCopyWith<$Res> {
  __$VideoFilterChainCopyWithImpl(this._self, this._then);

  final _VideoFilterChain _self;
  final $Res Function(_VideoFilterChain) _then;

/// Create a copy of VideoFilterChain
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? toneMapping = null,Object? scaler = null,Object? deband = null,Object? deinterlace = null,Object? sharpen = null,Object? brightness = null,Object? contrast = null,Object? saturation = null,Object? gamma = null,Object? hue = null,Object? rotate = null,Object? flipHorizontal = null,Object? flipVertical = null,Object? aspectOverride = freezed,Object? zoom = null,Object? panX = null,Object? panY = null,Object? interpolation = null,}) {
  return _then(_VideoFilterChain(
toneMapping: null == toneMapping ? _self.toneMapping : toneMapping // ignore: cast_nullable_to_non_nullable
as ToneMapping,scaler: null == scaler ? _self.scaler : scaler // ignore: cast_nullable_to_non_nullable
as Scaler,deband: null == deband ? _self.deband : deband // ignore: cast_nullable_to_non_nullable
as bool,deinterlace: null == deinterlace ? _self.deinterlace : deinterlace // ignore: cast_nullable_to_non_nullable
as Deinterlace,sharpen: null == sharpen ? _self.sharpen : sharpen // ignore: cast_nullable_to_non_nullable
as double,brightness: null == brightness ? _self.brightness : brightness // ignore: cast_nullable_to_non_nullable
as double,contrast: null == contrast ? _self.contrast : contrast // ignore: cast_nullable_to_non_nullable
as double,saturation: null == saturation ? _self.saturation : saturation // ignore: cast_nullable_to_non_nullable
as double,gamma: null == gamma ? _self.gamma : gamma // ignore: cast_nullable_to_non_nullable
as double,hue: null == hue ? _self.hue : hue // ignore: cast_nullable_to_non_nullable
as double,rotate: null == rotate ? _self.rotate : rotate // ignore: cast_nullable_to_non_nullable
as int,flipHorizontal: null == flipHorizontal ? _self.flipHorizontal : flipHorizontal // ignore: cast_nullable_to_non_nullable
as bool,flipVertical: null == flipVertical ? _self.flipVertical : flipVertical // ignore: cast_nullable_to_non_nullable
as bool,aspectOverride: freezed == aspectOverride ? _self.aspectOverride : aspectOverride // ignore: cast_nullable_to_non_nullable
as double?,zoom: null == zoom ? _self.zoom : zoom // ignore: cast_nullable_to_non_nullable
as double,panX: null == panX ? _self.panX : panX // ignore: cast_nullable_to_non_nullable
as double,panY: null == panY ? _self.panY : panY // ignore: cast_nullable_to_non_nullable
as double,interpolation: null == interpolation ? _self.interpolation : interpolation // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$ShaderPreset {

 String get id; List<Uri> get shaders;
/// Create a copy of ShaderPreset
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShaderPresetCopyWith<ShaderPreset> get copyWith => _$ShaderPresetCopyWithImpl<ShaderPreset>(this as ShaderPreset, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ShaderPreset;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ShaderPreset&&(identical(other.id, _this.id) || other.id == _this.id)&&const DeepCollectionEquality().equals(other.shaders, _this.shaders));
}


@override
int get hashCode {
  final _this = this as ShaderPreset;
  return Object.hash(runtimeType,_this.id,const DeepCollectionEquality().hash(_this.shaders));
}

@override
String toString() {
  final _this = this as ShaderPreset;
  return 'ShaderPreset(id: ${_this.id}, shaders: ${_this.shaders})';
}


}

/// @nodoc
abstract mixin class $ShaderPresetCopyWith<$Res>  {
  factory $ShaderPresetCopyWith(ShaderPreset value, $Res Function(ShaderPreset) _then) = _$ShaderPresetCopyWithImpl;
@useResult
$Res call({
 String id, List<Uri> shaders
});




}
/// @nodoc
class _$ShaderPresetCopyWithImpl<$Res>
    implements $ShaderPresetCopyWith<$Res> {
  _$ShaderPresetCopyWithImpl(this._self, this._then);

  final ShaderPreset _self;
  final $Res Function(ShaderPreset) _then;

/// Create a copy of ShaderPreset
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? shaders = null,}) {
  return _then(ShaderPreset(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,shaders: null == shaders ? _self.shaders : shaders // ignore: cast_nullable_to_non_nullable
as List<Uri>,
  ));
}

}


/// Adds pattern-matching-related methods to [ShaderPreset].
extension ShaderPresetPatterns on ShaderPreset {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ShaderPreset value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ShaderPreset() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ShaderPreset value)  $default,){
final _that = this;
switch (_that) {
case _ShaderPreset():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ShaderPreset value)?  $default,){
final _that = this;
switch (_that) {
case _ShaderPreset() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  List<Uri> shaders)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ShaderPreset() when $default != null:
return $default(_that.id,_that.shaders);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  List<Uri> shaders)  $default,) {final _that = this;
switch (_that) {
case _ShaderPreset():
return $default(_that.id,_that.shaders);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  List<Uri> shaders)?  $default,) {final _that = this;
switch (_that) {
case _ShaderPreset() when $default != null:
return $default(_that.id,_that.shaders);case _:
  return null;

}
}

}

/// @nodoc


class _ShaderPreset implements ShaderPreset {
  const _ShaderPreset({required this.id,  List<Uri> shaders = const <Uri>[]}): _shaders = shaders;
  

@override final  String id;
 final  List<Uri> _shaders;
@override@JsonKey() List<Uri> get shaders {
  if (_shaders is EqualUnmodifiableListView) return _shaders;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_shaders);
}


/// Create a copy of ShaderPreset
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ShaderPresetCopyWith<_ShaderPreset> get copyWith => __$ShaderPresetCopyWithImpl<_ShaderPreset>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ShaderPreset&&(identical(other.id, id) || other.id == id)&&const DeepCollectionEquality().equals(other.shaders, _shaders));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,const DeepCollectionEquality().hash(_shaders));
}

@override
String toString() {
    return 'ShaderPreset(id: $id, shaders: $shaders)';
}


}

/// @nodoc
abstract mixin class _$ShaderPresetCopyWith<$Res> implements $ShaderPresetCopyWith<$Res> {
  factory _$ShaderPresetCopyWith(_ShaderPreset value, $Res Function(_ShaderPreset) _then) = __$ShaderPresetCopyWithImpl;
@override @useResult
$Res call({
 String id, List<Uri> shaders
});




}
/// @nodoc
class __$ShaderPresetCopyWithImpl<$Res>
    implements _$ShaderPresetCopyWith<$Res> {
  __$ShaderPresetCopyWithImpl(this._self, this._then);

  final _ShaderPreset _self;
  final $Res Function(_ShaderPreset) _then;

/// Create a copy of ShaderPreset
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? shaders = null,}) {
  return _then(_ShaderPreset(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,shaders: null == shaders ? _self._shaders : shaders // ignore: cast_nullable_to_non_nullable
as List<Uri>,
  ));
}


}

/// @nodoc
mixin _$EqBand {

 EqBandType get type; double get frequencyHz; double get gainDb; double get q;
/// Create a copy of EqBand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EqBandCopyWith<EqBand> get copyWith => _$EqBandCopyWithImpl<EqBand>(this as EqBand, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as EqBand;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EqBand&&(identical(other.type, _this.type) || other.type == _this.type)&&(identical(other.frequencyHz, _this.frequencyHz) || other.frequencyHz == _this.frequencyHz)&&(identical(other.gainDb, _this.gainDb) || other.gainDb == _this.gainDb)&&(identical(other.q, _this.q) || other.q == _this.q));
}


@override
int get hashCode {
  final _this = this as EqBand;
  return Object.hash(runtimeType,_this.type,_this.frequencyHz,_this.gainDb,_this.q);
}

@override
String toString() {
  final _this = this as EqBand;
  return 'EqBand(type: ${_this.type}, frequencyHz: ${_this.frequencyHz}, gainDb: ${_this.gainDb}, q: ${_this.q})';
}


}

/// @nodoc
abstract mixin class $EqBandCopyWith<$Res>  {
  factory $EqBandCopyWith(EqBand value, $Res Function(EqBand) _then) = _$EqBandCopyWithImpl;
@useResult
$Res call({
 EqBandType type, double frequencyHz, double gainDb, double q
});




}
/// @nodoc
class _$EqBandCopyWithImpl<$Res>
    implements $EqBandCopyWith<$Res> {
  _$EqBandCopyWithImpl(this._self, this._then);

  final EqBand _self;
  final $Res Function(EqBand) _then;

/// Create a copy of EqBand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? type = null,Object? frequencyHz = null,Object? gainDb = null,Object? q = null,}) {
  return _then(EqBand(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as EqBandType,frequencyHz: null == frequencyHz ? _self.frequencyHz : frequencyHz // ignore: cast_nullable_to_non_nullable
as double,gainDb: null == gainDb ? _self.gainDb : gainDb // ignore: cast_nullable_to_non_nullable
as double,q: null == q ? _self.q : q // ignore: cast_nullable_to_non_nullable
as double,
  ));
}

}


/// Adds pattern-matching-related methods to [EqBand].
extension EqBandPatterns on EqBand {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _EqBand value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _EqBand() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _EqBand value)  $default,){
final _that = this;
switch (_that) {
case _EqBand():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _EqBand value)?  $default,){
final _that = this;
switch (_that) {
case _EqBand() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( EqBandType type,  double frequencyHz,  double gainDb,  double q)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _EqBand() when $default != null:
return $default(_that.type,_that.frequencyHz,_that.gainDb,_that.q);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( EqBandType type,  double frequencyHz,  double gainDb,  double q)  $default,) {final _that = this;
switch (_that) {
case _EqBand():
return $default(_that.type,_that.frequencyHz,_that.gainDb,_that.q);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( EqBandType type,  double frequencyHz,  double gainDb,  double q)?  $default,) {final _that = this;
switch (_that) {
case _EqBand() when $default != null:
return $default(_that.type,_that.frequencyHz,_that.gainDb,_that.q);case _:
  return null;

}
}

}

/// @nodoc


class _EqBand implements EqBand {
  const _EqBand({required this.type, required this.frequencyHz, required this.gainDb, this.q = 0.707});
  

@override final  EqBandType type;
@override final  double frequencyHz;
@override final  double gainDb;
@override@JsonKey() final  double q;

/// Create a copy of EqBand
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$EqBandCopyWith<_EqBand> get copyWith => __$EqBandCopyWithImpl<_EqBand>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _EqBand&&(identical(other.type, type) || other.type == type)&&(identical(other.frequencyHz, frequencyHz) || other.frequencyHz == frequencyHz)&&(identical(other.gainDb, gainDb) || other.gainDb == gainDb)&&(identical(other.q, q) || other.q == q));
}


@override
int get hashCode {
    return Object.hash(runtimeType,type,frequencyHz,gainDb,q);
}

@override
String toString() {
    return 'EqBand(type: $type, frequencyHz: $frequencyHz, gainDb: $gainDb, q: $q)';
}


}

/// @nodoc
abstract mixin class _$EqBandCopyWith<$Res> implements $EqBandCopyWith<$Res> {
  factory _$EqBandCopyWith(_EqBand value, $Res Function(_EqBand) _then) = __$EqBandCopyWithImpl;
@override @useResult
$Res call({
 EqBandType type, double frequencyHz, double gainDb, double q
});




}
/// @nodoc
class __$EqBandCopyWithImpl<$Res>
    implements _$EqBandCopyWith<$Res> {
  __$EqBandCopyWithImpl(this._self, this._then);

  final _EqBand _self;
  final $Res Function(_EqBand) _then;

/// Create a copy of EqBand
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? type = null,Object? frequencyHz = null,Object? gainDb = null,Object? q = null,}) {
  return _then(_EqBand(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as EqBandType,frequencyHz: null == frequencyHz ? _self.frequencyHz : frequencyHz // ignore: cast_nullable_to_non_nullable
as double,gainDb: null == gainDb ? _self.gainDb : gainDb // ignore: cast_nullable_to_non_nullable
as double,q: null == q ? _self.q : q // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc
mixin _$AudioDspChain {

/// 10-band graphic EQ gains in dB (31 Hz … 16 kHz), empty when off.
 List<double> get graphicEq;/// Up to 32 parametric biquads.
 List<EqBand> get parametricEq; double get preampDb; LoudnessMode get loudness; double get r128TargetLufs; bool get clippingPrevention; bool get limiter; double get balance; bool get mono; bool get crossfeed; double get bassDb; double get trebleDb; double get pitch; bool get skipSilence;/// Channel mixer: one row per output channel, one gain per input channel
/// (AUD-005). Empty keeps the layout.
 List<List<double>> get channelMatrix;
/// Create a copy of AudioDspChain
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AudioDspChainCopyWith<AudioDspChain> get copyWith => _$AudioDspChainCopyWithImpl<AudioDspChain>(this as AudioDspChain, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AudioDspChain;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AudioDspChain&&const DeepCollectionEquality().equals(other.graphicEq, _this.graphicEq)&&const DeepCollectionEquality().equals(other.parametricEq, _this.parametricEq)&&(identical(other.preampDb, _this.preampDb) || other.preampDb == _this.preampDb)&&(identical(other.loudness, _this.loudness) || other.loudness == _this.loudness)&&(identical(other.r128TargetLufs, _this.r128TargetLufs) || other.r128TargetLufs == _this.r128TargetLufs)&&(identical(other.clippingPrevention, _this.clippingPrevention) || other.clippingPrevention == _this.clippingPrevention)&&(identical(other.limiter, _this.limiter) || other.limiter == _this.limiter)&&(identical(other.balance, _this.balance) || other.balance == _this.balance)&&(identical(other.mono, _this.mono) || other.mono == _this.mono)&&(identical(other.crossfeed, _this.crossfeed) || other.crossfeed == _this.crossfeed)&&(identical(other.bassDb, _this.bassDb) || other.bassDb == _this.bassDb)&&(identical(other.trebleDb, _this.trebleDb) || other.trebleDb == _this.trebleDb)&&(identical(other.pitch, _this.pitch) || other.pitch == _this.pitch)&&(identical(other.skipSilence, _this.skipSilence) || other.skipSilence == _this.skipSilence)&&const DeepCollectionEquality().equals(other.channelMatrix, _this.channelMatrix));
}


@override
int get hashCode {
  final _this = this as AudioDspChain;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.graphicEq),const DeepCollectionEquality().hash(_this.parametricEq),_this.preampDb,_this.loudness,_this.r128TargetLufs,_this.clippingPrevention,_this.limiter,_this.balance,_this.mono,_this.crossfeed,_this.bassDb,_this.trebleDb,_this.pitch,_this.skipSilence,const DeepCollectionEquality().hash(_this.channelMatrix));
}

@override
String toString() {
  final _this = this as AudioDspChain;
  return 'AudioDspChain(graphicEq: ${_this.graphicEq}, parametricEq: ${_this.parametricEq}, preampDb: ${_this.preampDb}, loudness: ${_this.loudness}, r128TargetLufs: ${_this.r128TargetLufs}, clippingPrevention: ${_this.clippingPrevention}, limiter: ${_this.limiter}, balance: ${_this.balance}, mono: ${_this.mono}, crossfeed: ${_this.crossfeed}, bassDb: ${_this.bassDb}, trebleDb: ${_this.trebleDb}, pitch: ${_this.pitch}, skipSilence: ${_this.skipSilence}, channelMatrix: ${_this.channelMatrix})';
}


}

/// @nodoc
abstract mixin class $AudioDspChainCopyWith<$Res>  {
  factory $AudioDspChainCopyWith(AudioDspChain value, $Res Function(AudioDspChain) _then) = _$AudioDspChainCopyWithImpl;
@useResult
$Res call({
 List<double> graphicEq, List<EqBand> parametricEq, double preampDb, LoudnessMode loudness, double r128TargetLufs, bool clippingPrevention, bool limiter, double balance, bool mono, bool crossfeed, double bassDb, double trebleDb, double pitch, bool skipSilence, List<List<double>> channelMatrix
});




}
/// @nodoc
class _$AudioDspChainCopyWithImpl<$Res>
    implements $AudioDspChainCopyWith<$Res> {
  _$AudioDspChainCopyWithImpl(this._self, this._then);

  final AudioDspChain _self;
  final $Res Function(AudioDspChain) _then;

/// Create a copy of AudioDspChain
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? graphicEq = null,Object? parametricEq = null,Object? preampDb = null,Object? loudness = null,Object? r128TargetLufs = null,Object? clippingPrevention = null,Object? limiter = null,Object? balance = null,Object? mono = null,Object? crossfeed = null,Object? bassDb = null,Object? trebleDb = null,Object? pitch = null,Object? skipSilence = null,Object? channelMatrix = null,}) {
  return _then(AudioDspChain(
graphicEq: null == graphicEq ? _self.graphicEq : graphicEq // ignore: cast_nullable_to_non_nullable
as List<double>,parametricEq: null == parametricEq ? _self.parametricEq : parametricEq // ignore: cast_nullable_to_non_nullable
as List<EqBand>,preampDb: null == preampDb ? _self.preampDb : preampDb // ignore: cast_nullable_to_non_nullable
as double,loudness: null == loudness ? _self.loudness : loudness // ignore: cast_nullable_to_non_nullable
as LoudnessMode,r128TargetLufs: null == r128TargetLufs ? _self.r128TargetLufs : r128TargetLufs // ignore: cast_nullable_to_non_nullable
as double,clippingPrevention: null == clippingPrevention ? _self.clippingPrevention : clippingPrevention // ignore: cast_nullable_to_non_nullable
as bool,limiter: null == limiter ? _self.limiter : limiter // ignore: cast_nullable_to_non_nullable
as bool,balance: null == balance ? _self.balance : balance // ignore: cast_nullable_to_non_nullable
as double,mono: null == mono ? _self.mono : mono // ignore: cast_nullable_to_non_nullable
as bool,crossfeed: null == crossfeed ? _self.crossfeed : crossfeed // ignore: cast_nullable_to_non_nullable
as bool,bassDb: null == bassDb ? _self.bassDb : bassDb // ignore: cast_nullable_to_non_nullable
as double,trebleDb: null == trebleDb ? _self.trebleDb : trebleDb // ignore: cast_nullable_to_non_nullable
as double,pitch: null == pitch ? _self.pitch : pitch // ignore: cast_nullable_to_non_nullable
as double,skipSilence: null == skipSilence ? _self.skipSilence : skipSilence // ignore: cast_nullable_to_non_nullable
as bool,channelMatrix: null == channelMatrix ? _self.channelMatrix : channelMatrix // ignore: cast_nullable_to_non_nullable
as List<List<double>>,
  ));
}

}


/// Adds pattern-matching-related methods to [AudioDspChain].
extension AudioDspChainPatterns on AudioDspChain {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AudioDspChain value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AudioDspChain() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AudioDspChain value)  $default,){
final _that = this;
switch (_that) {
case _AudioDspChain():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AudioDspChain value)?  $default,){
final _that = this;
switch (_that) {
case _AudioDspChain() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<double> graphicEq,  List<EqBand> parametricEq,  double preampDb,  LoudnessMode loudness,  double r128TargetLufs,  bool clippingPrevention,  bool limiter,  double balance,  bool mono,  bool crossfeed,  double bassDb,  double trebleDb,  double pitch,  bool skipSilence,  List<List<double>> channelMatrix)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AudioDspChain() when $default != null:
return $default(_that.graphicEq,_that.parametricEq,_that.preampDb,_that.loudness,_that.r128TargetLufs,_that.clippingPrevention,_that.limiter,_that.balance,_that.mono,_that.crossfeed,_that.bassDb,_that.trebleDb,_that.pitch,_that.skipSilence,_that.channelMatrix);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<double> graphicEq,  List<EqBand> parametricEq,  double preampDb,  LoudnessMode loudness,  double r128TargetLufs,  bool clippingPrevention,  bool limiter,  double balance,  bool mono,  bool crossfeed,  double bassDb,  double trebleDb,  double pitch,  bool skipSilence,  List<List<double>> channelMatrix)  $default,) {final _that = this;
switch (_that) {
case _AudioDspChain():
return $default(_that.graphicEq,_that.parametricEq,_that.preampDb,_that.loudness,_that.r128TargetLufs,_that.clippingPrevention,_that.limiter,_that.balance,_that.mono,_that.crossfeed,_that.bassDb,_that.trebleDb,_that.pitch,_that.skipSilence,_that.channelMatrix);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<double> graphicEq,  List<EqBand> parametricEq,  double preampDb,  LoudnessMode loudness,  double r128TargetLufs,  bool clippingPrevention,  bool limiter,  double balance,  bool mono,  bool crossfeed,  double bassDb,  double trebleDb,  double pitch,  bool skipSilence,  List<List<double>> channelMatrix)?  $default,) {final _that = this;
switch (_that) {
case _AudioDspChain() when $default != null:
return $default(_that.graphicEq,_that.parametricEq,_that.preampDb,_that.loudness,_that.r128TargetLufs,_that.clippingPrevention,_that.limiter,_that.balance,_that.mono,_that.crossfeed,_that.bassDb,_that.trebleDb,_that.pitch,_that.skipSilence,_that.channelMatrix);case _:
  return null;

}
}

}

/// @nodoc


class _AudioDspChain implements AudioDspChain {
  const _AudioDspChain({ List<double> graphicEq = const <double>[],  List<EqBand> parametricEq = const <EqBand>[], this.preampDb = 0, this.loudness = LoudnessMode.off, this.r128TargetLufs = -18, this.clippingPrevention = true, this.limiter = false, this.balance = 0, this.mono = false, this.crossfeed = false, this.bassDb = 0, this.trebleDb = 0, this.pitch = 1, this.skipSilence = false,  List<List<double>> channelMatrix = const <List<double>>[]}): _graphicEq = graphicEq,_parametricEq = parametricEq,_channelMatrix = channelMatrix;
  

/// 10-band graphic EQ gains in dB (31 Hz … 16 kHz), empty when off.
 final  List<double> _graphicEq;
/// 10-band graphic EQ gains in dB (31 Hz … 16 kHz), empty when off.
@override@JsonKey() List<double> get graphicEq {
  if (_graphicEq is EqualUnmodifiableListView) return _graphicEq;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_graphicEq);
}

/// Up to 32 parametric biquads.
 final  List<EqBand> _parametricEq;
/// Up to 32 parametric biquads.
@override@JsonKey() List<EqBand> get parametricEq {
  if (_parametricEq is EqualUnmodifiableListView) return _parametricEq;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_parametricEq);
}

@override@JsonKey() final  double preampDb;
@override@JsonKey() final  LoudnessMode loudness;
@override@JsonKey() final  double r128TargetLufs;
@override@JsonKey() final  bool clippingPrevention;
@override@JsonKey() final  bool limiter;
@override@JsonKey() final  double balance;
@override@JsonKey() final  bool mono;
@override@JsonKey() final  bool crossfeed;
@override@JsonKey() final  double bassDb;
@override@JsonKey() final  double trebleDb;
@override@JsonKey() final  double pitch;
@override@JsonKey() final  bool skipSilence;
/// Channel mixer: one row per output channel, one gain per input channel
/// (AUD-005). Empty keeps the layout.
 final  List<List<double>> _channelMatrix;
/// Channel mixer: one row per output channel, one gain per input channel
/// (AUD-005). Empty keeps the layout.
@override@JsonKey() List<List<double>> get channelMatrix {
  if (_channelMatrix is EqualUnmodifiableListView) return _channelMatrix;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_channelMatrix);
}


/// Create a copy of AudioDspChain
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AudioDspChainCopyWith<_AudioDspChain> get copyWith => __$AudioDspChainCopyWithImpl<_AudioDspChain>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AudioDspChain&&const DeepCollectionEquality().equals(other.graphicEq, _graphicEq)&&const DeepCollectionEquality().equals(other.parametricEq, _parametricEq)&&(identical(other.preampDb, preampDb) || other.preampDb == preampDb)&&(identical(other.loudness, loudness) || other.loudness == loudness)&&(identical(other.r128TargetLufs, r128TargetLufs) || other.r128TargetLufs == r128TargetLufs)&&(identical(other.clippingPrevention, clippingPrevention) || other.clippingPrevention == clippingPrevention)&&(identical(other.limiter, limiter) || other.limiter == limiter)&&(identical(other.balance, balance) || other.balance == balance)&&(identical(other.mono, mono) || other.mono == mono)&&(identical(other.crossfeed, crossfeed) || other.crossfeed == crossfeed)&&(identical(other.bassDb, bassDb) || other.bassDb == bassDb)&&(identical(other.trebleDb, trebleDb) || other.trebleDb == trebleDb)&&(identical(other.pitch, pitch) || other.pitch == pitch)&&(identical(other.skipSilence, skipSilence) || other.skipSilence == skipSilence)&&const DeepCollectionEquality().equals(other.channelMatrix, _channelMatrix));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_graphicEq),const DeepCollectionEquality().hash(_parametricEq),preampDb,loudness,r128TargetLufs,clippingPrevention,limiter,balance,mono,crossfeed,bassDb,trebleDb,pitch,skipSilence,const DeepCollectionEquality().hash(_channelMatrix));
}

@override
String toString() {
    return 'AudioDspChain(graphicEq: $graphicEq, parametricEq: $parametricEq, preampDb: $preampDb, loudness: $loudness, r128TargetLufs: $r128TargetLufs, clippingPrevention: $clippingPrevention, limiter: $limiter, balance: $balance, mono: $mono, crossfeed: $crossfeed, bassDb: $bassDb, trebleDb: $trebleDb, pitch: $pitch, skipSilence: $skipSilence, channelMatrix: $channelMatrix)';
}


}

/// @nodoc
abstract mixin class _$AudioDspChainCopyWith<$Res> implements $AudioDspChainCopyWith<$Res> {
  factory _$AudioDspChainCopyWith(_AudioDspChain value, $Res Function(_AudioDspChain) _then) = __$AudioDspChainCopyWithImpl;
@override @useResult
$Res call({
 List<double> graphicEq, List<EqBand> parametricEq, double preampDb, LoudnessMode loudness, double r128TargetLufs, bool clippingPrevention, bool limiter, double balance, bool mono, bool crossfeed, double bassDb, double trebleDb, double pitch, bool skipSilence, List<List<double>> channelMatrix
});




}
/// @nodoc
class __$AudioDspChainCopyWithImpl<$Res>
    implements _$AudioDspChainCopyWith<$Res> {
  __$AudioDspChainCopyWithImpl(this._self, this._then);

  final _AudioDspChain _self;
  final $Res Function(_AudioDspChain) _then;

/// Create a copy of AudioDspChain
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? graphicEq = null,Object? parametricEq = null,Object? preampDb = null,Object? loudness = null,Object? r128TargetLufs = null,Object? clippingPrevention = null,Object? limiter = null,Object? balance = null,Object? mono = null,Object? crossfeed = null,Object? bassDb = null,Object? trebleDb = null,Object? pitch = null,Object? skipSilence = null,Object? channelMatrix = null,}) {
  return _then(_AudioDspChain(
graphicEq: null == graphicEq ? _self._graphicEq : graphicEq // ignore: cast_nullable_to_non_nullable
as List<double>,parametricEq: null == parametricEq ? _self._parametricEq : parametricEq // ignore: cast_nullable_to_non_nullable
as List<EqBand>,preampDb: null == preampDb ? _self.preampDb : preampDb // ignore: cast_nullable_to_non_nullable
as double,loudness: null == loudness ? _self.loudness : loudness // ignore: cast_nullable_to_non_nullable
as LoudnessMode,r128TargetLufs: null == r128TargetLufs ? _self.r128TargetLufs : r128TargetLufs // ignore: cast_nullable_to_non_nullable
as double,clippingPrevention: null == clippingPrevention ? _self.clippingPrevention : clippingPrevention // ignore: cast_nullable_to_non_nullable
as bool,limiter: null == limiter ? _self.limiter : limiter // ignore: cast_nullable_to_non_nullable
as bool,balance: null == balance ? _self.balance : balance // ignore: cast_nullable_to_non_nullable
as double,mono: null == mono ? _self.mono : mono // ignore: cast_nullable_to_non_nullable
as bool,crossfeed: null == crossfeed ? _self.crossfeed : crossfeed // ignore: cast_nullable_to_non_nullable
as bool,bassDb: null == bassDb ? _self.bassDb : bassDb // ignore: cast_nullable_to_non_nullable
as double,trebleDb: null == trebleDb ? _self.trebleDb : trebleDb // ignore: cast_nullable_to_non_nullable
as double,pitch: null == pitch ? _self.pitch : pitch // ignore: cast_nullable_to_non_nullable
as double,skipSilence: null == skipSilence ? _self.skipSilence : skipSilence // ignore: cast_nullable_to_non_nullable
as bool,channelMatrix: null == channelMatrix ? _self._channelMatrix : channelMatrix // ignore: cast_nullable_to_non_nullable
as List<List<double>>,
  ));
}


}

/// @nodoc
mixin _$AudioOutputConfig {

/// Engine device id; null = system default.
 String? get deviceId; bool get exclusive; List<String> get passthroughCodecs; bool get nativeDsd;/// Low-pass applied after DSD→PCM conversion (AUD-043).
 DsdFilter get dsdFilter;/// Switch the device to the source sample rate when exclusive
/// (AUD-040…042).
 bool get matchSampleRate;/// Extra output latency compensation, e.g. Bluetooth A/V sync (AUD-044).
 Duration get latencyOffset;
/// Create a copy of AudioOutputConfig
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AudioOutputConfigCopyWith<AudioOutputConfig> get copyWith => _$AudioOutputConfigCopyWithImpl<AudioOutputConfig>(this as AudioOutputConfig, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AudioOutputConfig;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AudioOutputConfig&&(identical(other.deviceId, _this.deviceId) || other.deviceId == _this.deviceId)&&(identical(other.exclusive, _this.exclusive) || other.exclusive == _this.exclusive)&&const DeepCollectionEquality().equals(other.passthroughCodecs, _this.passthroughCodecs)&&(identical(other.nativeDsd, _this.nativeDsd) || other.nativeDsd == _this.nativeDsd)&&(identical(other.dsdFilter, _this.dsdFilter) || other.dsdFilter == _this.dsdFilter)&&(identical(other.matchSampleRate, _this.matchSampleRate) || other.matchSampleRate == _this.matchSampleRate)&&(identical(other.latencyOffset, _this.latencyOffset) || other.latencyOffset == _this.latencyOffset));
}


@override
int get hashCode {
  final _this = this as AudioOutputConfig;
  return Object.hash(runtimeType,_this.deviceId,_this.exclusive,const DeepCollectionEquality().hash(_this.passthroughCodecs),_this.nativeDsd,_this.dsdFilter,_this.matchSampleRate,_this.latencyOffset);
}

@override
String toString() {
  final _this = this as AudioOutputConfig;
  return 'AudioOutputConfig(deviceId: ${_this.deviceId}, exclusive: ${_this.exclusive}, passthroughCodecs: ${_this.passthroughCodecs}, nativeDsd: ${_this.nativeDsd}, dsdFilter: ${_this.dsdFilter}, matchSampleRate: ${_this.matchSampleRate}, latencyOffset: ${_this.latencyOffset})';
}


}

/// @nodoc
abstract mixin class $AudioOutputConfigCopyWith<$Res>  {
  factory $AudioOutputConfigCopyWith(AudioOutputConfig value, $Res Function(AudioOutputConfig) _then) = _$AudioOutputConfigCopyWithImpl;
@useResult
$Res call({
 String? deviceId, bool exclusive, List<String> passthroughCodecs, bool nativeDsd, DsdFilter dsdFilter, bool matchSampleRate, Duration latencyOffset
});




}
/// @nodoc
class _$AudioOutputConfigCopyWithImpl<$Res>
    implements $AudioOutputConfigCopyWith<$Res> {
  _$AudioOutputConfigCopyWithImpl(this._self, this._then);

  final AudioOutputConfig _self;
  final $Res Function(AudioOutputConfig) _then;

/// Create a copy of AudioOutputConfig
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? deviceId = freezed,Object? exclusive = null,Object? passthroughCodecs = null,Object? nativeDsd = null,Object? dsdFilter = null,Object? matchSampleRate = null,Object? latencyOffset = null,}) {
  return _then(AudioOutputConfig(
deviceId: freezed == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String?,exclusive: null == exclusive ? _self.exclusive : exclusive // ignore: cast_nullable_to_non_nullable
as bool,passthroughCodecs: null == passthroughCodecs ? _self.passthroughCodecs : passthroughCodecs // ignore: cast_nullable_to_non_nullable
as List<String>,nativeDsd: null == nativeDsd ? _self.nativeDsd : nativeDsd // ignore: cast_nullable_to_non_nullable
as bool,dsdFilter: null == dsdFilter ? _self.dsdFilter : dsdFilter // ignore: cast_nullable_to_non_nullable
as DsdFilter,matchSampleRate: null == matchSampleRate ? _self.matchSampleRate : matchSampleRate // ignore: cast_nullable_to_non_nullable
as bool,latencyOffset: null == latencyOffset ? _self.latencyOffset : latencyOffset // ignore: cast_nullable_to_non_nullable
as Duration,
  ));
}

}


/// Adds pattern-matching-related methods to [AudioOutputConfig].
extension AudioOutputConfigPatterns on AudioOutputConfig {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AudioOutputConfig value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AudioOutputConfig() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AudioOutputConfig value)  $default,){
final _that = this;
switch (_that) {
case _AudioOutputConfig():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AudioOutputConfig value)?  $default,){
final _that = this;
switch (_that) {
case _AudioOutputConfig() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? deviceId,  bool exclusive,  List<String> passthroughCodecs,  bool nativeDsd,  DsdFilter dsdFilter,  bool matchSampleRate,  Duration latencyOffset)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AudioOutputConfig() when $default != null:
return $default(_that.deviceId,_that.exclusive,_that.passthroughCodecs,_that.nativeDsd,_that.dsdFilter,_that.matchSampleRate,_that.latencyOffset);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? deviceId,  bool exclusive,  List<String> passthroughCodecs,  bool nativeDsd,  DsdFilter dsdFilter,  bool matchSampleRate,  Duration latencyOffset)  $default,) {final _that = this;
switch (_that) {
case _AudioOutputConfig():
return $default(_that.deviceId,_that.exclusive,_that.passthroughCodecs,_that.nativeDsd,_that.dsdFilter,_that.matchSampleRate,_that.latencyOffset);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? deviceId,  bool exclusive,  List<String> passthroughCodecs,  bool nativeDsd,  DsdFilter dsdFilter,  bool matchSampleRate,  Duration latencyOffset)?  $default,) {final _that = this;
switch (_that) {
case _AudioOutputConfig() when $default != null:
return $default(_that.deviceId,_that.exclusive,_that.passthroughCodecs,_that.nativeDsd,_that.dsdFilter,_that.matchSampleRate,_that.latencyOffset);case _:
  return null;

}
}

}

/// @nodoc


class _AudioOutputConfig implements AudioOutputConfig {
  const _AudioOutputConfig({this.deviceId, this.exclusive = false,  List<String> passthroughCodecs = const <String>[], this.nativeDsd = false, this.dsdFilter = DsdFilter.standard, this.matchSampleRate = true, this.latencyOffset = Duration.zero}): _passthroughCodecs = passthroughCodecs;
  

/// Engine device id; null = system default.
@override final  String? deviceId;
@override@JsonKey() final  bool exclusive;
 final  List<String> _passthroughCodecs;
@override@JsonKey() List<String> get passthroughCodecs {
  if (_passthroughCodecs is EqualUnmodifiableListView) return _passthroughCodecs;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_passthroughCodecs);
}

@override@JsonKey() final  bool nativeDsd;
/// Low-pass applied after DSD→PCM conversion (AUD-043).
@override@JsonKey() final  DsdFilter dsdFilter;
/// Switch the device to the source sample rate when exclusive
/// (AUD-040…042).
@override@JsonKey() final  bool matchSampleRate;
/// Extra output latency compensation, e.g. Bluetooth A/V sync (AUD-044).
@override@JsonKey() final  Duration latencyOffset;

/// Create a copy of AudioOutputConfig
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AudioOutputConfigCopyWith<_AudioOutputConfig> get copyWith => __$AudioOutputConfigCopyWithImpl<_AudioOutputConfig>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AudioOutputConfig&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.exclusive, exclusive) || other.exclusive == exclusive)&&const DeepCollectionEquality().equals(other.passthroughCodecs, _passthroughCodecs)&&(identical(other.nativeDsd, nativeDsd) || other.nativeDsd == nativeDsd)&&(identical(other.dsdFilter, dsdFilter) || other.dsdFilter == dsdFilter)&&(identical(other.matchSampleRate, matchSampleRate) || other.matchSampleRate == matchSampleRate)&&(identical(other.latencyOffset, latencyOffset) || other.latencyOffset == latencyOffset));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deviceId,exclusive,const DeepCollectionEquality().hash(_passthroughCodecs),nativeDsd,dsdFilter,matchSampleRate,latencyOffset);
}

@override
String toString() {
    return 'AudioOutputConfig(deviceId: $deviceId, exclusive: $exclusive, passthroughCodecs: $passthroughCodecs, nativeDsd: $nativeDsd, dsdFilter: $dsdFilter, matchSampleRate: $matchSampleRate, latencyOffset: $latencyOffset)';
}


}

/// @nodoc
abstract mixin class _$AudioOutputConfigCopyWith<$Res> implements $AudioOutputConfigCopyWith<$Res> {
  factory _$AudioOutputConfigCopyWith(_AudioOutputConfig value, $Res Function(_AudioOutputConfig) _then) = __$AudioOutputConfigCopyWithImpl;
@override @useResult
$Res call({
 String? deviceId, bool exclusive, List<String> passthroughCodecs, bool nativeDsd, DsdFilter dsdFilter, bool matchSampleRate, Duration latencyOffset
});




}
/// @nodoc
class __$AudioOutputConfigCopyWithImpl<$Res>
    implements _$AudioOutputConfigCopyWith<$Res> {
  __$AudioOutputConfigCopyWithImpl(this._self, this._then);

  final _AudioOutputConfig _self;
  final $Res Function(_AudioOutputConfig) _then;

/// Create a copy of AudioOutputConfig
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? deviceId = freezed,Object? exclusive = null,Object? passthroughCodecs = null,Object? nativeDsd = null,Object? dsdFilter = null,Object? matchSampleRate = null,Object? latencyOffset = null,}) {
  return _then(_AudioOutputConfig(
deviceId: freezed == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String?,exclusive: null == exclusive ? _self.exclusive : exclusive // ignore: cast_nullable_to_non_nullable
as bool,passthroughCodecs: null == passthroughCodecs ? _self._passthroughCodecs : passthroughCodecs // ignore: cast_nullable_to_non_nullable
as List<String>,nativeDsd: null == nativeDsd ? _self.nativeDsd : nativeDsd // ignore: cast_nullable_to_non_nullable
as bool,dsdFilter: null == dsdFilter ? _self.dsdFilter : dsdFilter // ignore: cast_nullable_to_non_nullable
as DsdFilter,matchSampleRate: null == matchSampleRate ? _self.matchSampleRate : matchSampleRate // ignore: cast_nullable_to_non_nullable
as bool,latencyOffset: null == latencyOffset ? _self.latencyOffset : latencyOffset // ignore: cast_nullable_to_non_nullable
as Duration,
  ));
}


}

/// @nodoc
mixin _$SubtitleStyle {

 String? get font; double? get scale; int? get colorArgb; int? get outlineColorArgb; double? get outlineWidth; double? get shadowOffset; int? get backgroundArgb;/// 0 = bottom, 100 = top.
 double? get verticalPosition; bool get overrideAssStyles;/// Horizontal alignment and margins (SUB-014).
 SubtitleAlignX? get alignX; double? get marginX; double? get marginY; SubtitleBorderStyle get borderStyle;
/// Create a copy of SubtitleStyle
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SubtitleStyleCopyWith<SubtitleStyle> get copyWith => _$SubtitleStyleCopyWithImpl<SubtitleStyle>(this as SubtitleStyle, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SubtitleStyle;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SubtitleStyle&&(identical(other.font, _this.font) || other.font == _this.font)&&(identical(other.scale, _this.scale) || other.scale == _this.scale)&&(identical(other.colorArgb, _this.colorArgb) || other.colorArgb == _this.colorArgb)&&(identical(other.outlineColorArgb, _this.outlineColorArgb) || other.outlineColorArgb == _this.outlineColorArgb)&&(identical(other.outlineWidth, _this.outlineWidth) || other.outlineWidth == _this.outlineWidth)&&(identical(other.shadowOffset, _this.shadowOffset) || other.shadowOffset == _this.shadowOffset)&&(identical(other.backgroundArgb, _this.backgroundArgb) || other.backgroundArgb == _this.backgroundArgb)&&(identical(other.verticalPosition, _this.verticalPosition) || other.verticalPosition == _this.verticalPosition)&&(identical(other.overrideAssStyles, _this.overrideAssStyles) || other.overrideAssStyles == _this.overrideAssStyles)&&(identical(other.alignX, _this.alignX) || other.alignX == _this.alignX)&&(identical(other.marginX, _this.marginX) || other.marginX == _this.marginX)&&(identical(other.marginY, _this.marginY) || other.marginY == _this.marginY)&&(identical(other.borderStyle, _this.borderStyle) || other.borderStyle == _this.borderStyle));
}


@override
int get hashCode {
  final _this = this as SubtitleStyle;
  return Object.hash(runtimeType,_this.font,_this.scale,_this.colorArgb,_this.outlineColorArgb,_this.outlineWidth,_this.shadowOffset,_this.backgroundArgb,_this.verticalPosition,_this.overrideAssStyles,_this.alignX,_this.marginX,_this.marginY,_this.borderStyle);
}

@override
String toString() {
  final _this = this as SubtitleStyle;
  return 'SubtitleStyle(font: ${_this.font}, scale: ${_this.scale}, colorArgb: ${_this.colorArgb}, outlineColorArgb: ${_this.outlineColorArgb}, outlineWidth: ${_this.outlineWidth}, shadowOffset: ${_this.shadowOffset}, backgroundArgb: ${_this.backgroundArgb}, verticalPosition: ${_this.verticalPosition}, overrideAssStyles: ${_this.overrideAssStyles}, alignX: ${_this.alignX}, marginX: ${_this.marginX}, marginY: ${_this.marginY}, borderStyle: ${_this.borderStyle})';
}


}

/// @nodoc
abstract mixin class $SubtitleStyleCopyWith<$Res>  {
  factory $SubtitleStyleCopyWith(SubtitleStyle value, $Res Function(SubtitleStyle) _then) = _$SubtitleStyleCopyWithImpl;
@useResult
$Res call({
 String? font, double? scale, int? colorArgb, int? outlineColorArgb, double? outlineWidth, double? shadowOffset, int? backgroundArgb, double? verticalPosition, bool overrideAssStyles, SubtitleAlignX? alignX, double? marginX, double? marginY, SubtitleBorderStyle borderStyle
});




}
/// @nodoc
class _$SubtitleStyleCopyWithImpl<$Res>
    implements $SubtitleStyleCopyWith<$Res> {
  _$SubtitleStyleCopyWithImpl(this._self, this._then);

  final SubtitleStyle _self;
  final $Res Function(SubtitleStyle) _then;

/// Create a copy of SubtitleStyle
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? font = freezed,Object? scale = freezed,Object? colorArgb = freezed,Object? outlineColorArgb = freezed,Object? outlineWidth = freezed,Object? shadowOffset = freezed,Object? backgroundArgb = freezed,Object? verticalPosition = freezed,Object? overrideAssStyles = null,Object? alignX = freezed,Object? marginX = freezed,Object? marginY = freezed,Object? borderStyle = null,}) {
  return _then(SubtitleStyle(
font: freezed == font ? _self.font : font // ignore: cast_nullable_to_non_nullable
as String?,scale: freezed == scale ? _self.scale : scale // ignore: cast_nullable_to_non_nullable
as double?,colorArgb: freezed == colorArgb ? _self.colorArgb : colorArgb // ignore: cast_nullable_to_non_nullable
as int?,outlineColorArgb: freezed == outlineColorArgb ? _self.outlineColorArgb : outlineColorArgb // ignore: cast_nullable_to_non_nullable
as int?,outlineWidth: freezed == outlineWidth ? _self.outlineWidth : outlineWidth // ignore: cast_nullable_to_non_nullable
as double?,shadowOffset: freezed == shadowOffset ? _self.shadowOffset : shadowOffset // ignore: cast_nullable_to_non_nullable
as double?,backgroundArgb: freezed == backgroundArgb ? _self.backgroundArgb : backgroundArgb // ignore: cast_nullable_to_non_nullable
as int?,verticalPosition: freezed == verticalPosition ? _self.verticalPosition : verticalPosition // ignore: cast_nullable_to_non_nullable
as double?,overrideAssStyles: null == overrideAssStyles ? _self.overrideAssStyles : overrideAssStyles // ignore: cast_nullable_to_non_nullable
as bool,alignX: freezed == alignX ? _self.alignX : alignX // ignore: cast_nullable_to_non_nullable
as SubtitleAlignX?,marginX: freezed == marginX ? _self.marginX : marginX // ignore: cast_nullable_to_non_nullable
as double?,marginY: freezed == marginY ? _self.marginY : marginY // ignore: cast_nullable_to_non_nullable
as double?,borderStyle: null == borderStyle ? _self.borderStyle : borderStyle // ignore: cast_nullable_to_non_nullable
as SubtitleBorderStyle,
  ));
}

}


/// Adds pattern-matching-related methods to [SubtitleStyle].
extension SubtitleStylePatterns on SubtitleStyle {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SubtitleStyle value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SubtitleStyle() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SubtitleStyle value)  $default,){
final _that = this;
switch (_that) {
case _SubtitleStyle():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SubtitleStyle value)?  $default,){
final _that = this;
switch (_that) {
case _SubtitleStyle() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? font,  double? scale,  int? colorArgb,  int? outlineColorArgb,  double? outlineWidth,  double? shadowOffset,  int? backgroundArgb,  double? verticalPosition,  bool overrideAssStyles,  SubtitleAlignX? alignX,  double? marginX,  double? marginY,  SubtitleBorderStyle borderStyle)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SubtitleStyle() when $default != null:
return $default(_that.font,_that.scale,_that.colorArgb,_that.outlineColorArgb,_that.outlineWidth,_that.shadowOffset,_that.backgroundArgb,_that.verticalPosition,_that.overrideAssStyles,_that.alignX,_that.marginX,_that.marginY,_that.borderStyle);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? font,  double? scale,  int? colorArgb,  int? outlineColorArgb,  double? outlineWidth,  double? shadowOffset,  int? backgroundArgb,  double? verticalPosition,  bool overrideAssStyles,  SubtitleAlignX? alignX,  double? marginX,  double? marginY,  SubtitleBorderStyle borderStyle)  $default,) {final _that = this;
switch (_that) {
case _SubtitleStyle():
return $default(_that.font,_that.scale,_that.colorArgb,_that.outlineColorArgb,_that.outlineWidth,_that.shadowOffset,_that.backgroundArgb,_that.verticalPosition,_that.overrideAssStyles,_that.alignX,_that.marginX,_that.marginY,_that.borderStyle);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? font,  double? scale,  int? colorArgb,  int? outlineColorArgb,  double? outlineWidth,  double? shadowOffset,  int? backgroundArgb,  double? verticalPosition,  bool overrideAssStyles,  SubtitleAlignX? alignX,  double? marginX,  double? marginY,  SubtitleBorderStyle borderStyle)?  $default,) {final _that = this;
switch (_that) {
case _SubtitleStyle() when $default != null:
return $default(_that.font,_that.scale,_that.colorArgb,_that.outlineColorArgb,_that.outlineWidth,_that.shadowOffset,_that.backgroundArgb,_that.verticalPosition,_that.overrideAssStyles,_that.alignX,_that.marginX,_that.marginY,_that.borderStyle);case _:
  return null;

}
}

}

/// @nodoc


class _SubtitleStyle implements SubtitleStyle {
  const _SubtitleStyle({this.font, this.scale, this.colorArgb, this.outlineColorArgb, this.outlineWidth, this.shadowOffset, this.backgroundArgb, this.verticalPosition, this.overrideAssStyles = false, this.alignX, this.marginX, this.marginY, this.borderStyle = SubtitleBorderStyle.outlineAndShadow});
  

@override final  String? font;
@override final  double? scale;
@override final  int? colorArgb;
@override final  int? outlineColorArgb;
@override final  double? outlineWidth;
@override final  double? shadowOffset;
@override final  int? backgroundArgb;
/// 0 = bottom, 100 = top.
@override final  double? verticalPosition;
@override@JsonKey() final  bool overrideAssStyles;
/// Horizontal alignment and margins (SUB-014).
@override final  SubtitleAlignX? alignX;
@override final  double? marginX;
@override final  double? marginY;
@override@JsonKey() final  SubtitleBorderStyle borderStyle;

/// Create a copy of SubtitleStyle
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SubtitleStyleCopyWith<_SubtitleStyle> get copyWith => __$SubtitleStyleCopyWithImpl<_SubtitleStyle>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SubtitleStyle&&(identical(other.font, font) || other.font == font)&&(identical(other.scale, scale) || other.scale == scale)&&(identical(other.colorArgb, colorArgb) || other.colorArgb == colorArgb)&&(identical(other.outlineColorArgb, outlineColorArgb) || other.outlineColorArgb == outlineColorArgb)&&(identical(other.outlineWidth, outlineWidth) || other.outlineWidth == outlineWidth)&&(identical(other.shadowOffset, shadowOffset) || other.shadowOffset == shadowOffset)&&(identical(other.backgroundArgb, backgroundArgb) || other.backgroundArgb == backgroundArgb)&&(identical(other.verticalPosition, verticalPosition) || other.verticalPosition == verticalPosition)&&(identical(other.overrideAssStyles, overrideAssStyles) || other.overrideAssStyles == overrideAssStyles)&&(identical(other.alignX, alignX) || other.alignX == alignX)&&(identical(other.marginX, marginX) || other.marginX == marginX)&&(identical(other.marginY, marginY) || other.marginY == marginY)&&(identical(other.borderStyle, borderStyle) || other.borderStyle == borderStyle));
}


@override
int get hashCode {
    return Object.hash(runtimeType,font,scale,colorArgb,outlineColorArgb,outlineWidth,shadowOffset,backgroundArgb,verticalPosition,overrideAssStyles,alignX,marginX,marginY,borderStyle);
}

@override
String toString() {
    return 'SubtitleStyle(font: $font, scale: $scale, colorArgb: $colorArgb, outlineColorArgb: $outlineColorArgb, outlineWidth: $outlineWidth, shadowOffset: $shadowOffset, backgroundArgb: $backgroundArgb, verticalPosition: $verticalPosition, overrideAssStyles: $overrideAssStyles, alignX: $alignX, marginX: $marginX, marginY: $marginY, borderStyle: $borderStyle)';
}


}

/// @nodoc
abstract mixin class _$SubtitleStyleCopyWith<$Res> implements $SubtitleStyleCopyWith<$Res> {
  factory _$SubtitleStyleCopyWith(_SubtitleStyle value, $Res Function(_SubtitleStyle) _then) = __$SubtitleStyleCopyWithImpl;
@override @useResult
$Res call({
 String? font, double? scale, int? colorArgb, int? outlineColorArgb, double? outlineWidth, double? shadowOffset, int? backgroundArgb, double? verticalPosition, bool overrideAssStyles, SubtitleAlignX? alignX, double? marginX, double? marginY, SubtitleBorderStyle borderStyle
});




}
/// @nodoc
class __$SubtitleStyleCopyWithImpl<$Res>
    implements _$SubtitleStyleCopyWith<$Res> {
  __$SubtitleStyleCopyWithImpl(this._self, this._then);

  final _SubtitleStyle _self;
  final $Res Function(_SubtitleStyle) _then;

/// Create a copy of SubtitleStyle
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? font = freezed,Object? scale = freezed,Object? colorArgb = freezed,Object? outlineColorArgb = freezed,Object? outlineWidth = freezed,Object? shadowOffset = freezed,Object? backgroundArgb = freezed,Object? verticalPosition = freezed,Object? overrideAssStyles = null,Object? alignX = freezed,Object? marginX = freezed,Object? marginY = freezed,Object? borderStyle = null,}) {
  return _then(_SubtitleStyle(
font: freezed == font ? _self.font : font // ignore: cast_nullable_to_non_nullable
as String?,scale: freezed == scale ? _self.scale : scale // ignore: cast_nullable_to_non_nullable
as double?,colorArgb: freezed == colorArgb ? _self.colorArgb : colorArgb // ignore: cast_nullable_to_non_nullable
as int?,outlineColorArgb: freezed == outlineColorArgb ? _self.outlineColorArgb : outlineColorArgb // ignore: cast_nullable_to_non_nullable
as int?,outlineWidth: freezed == outlineWidth ? _self.outlineWidth : outlineWidth // ignore: cast_nullable_to_non_nullable
as double?,shadowOffset: freezed == shadowOffset ? _self.shadowOffset : shadowOffset // ignore: cast_nullable_to_non_nullable
as double?,backgroundArgb: freezed == backgroundArgb ? _self.backgroundArgb : backgroundArgb // ignore: cast_nullable_to_non_nullable
as int?,verticalPosition: freezed == verticalPosition ? _self.verticalPosition : verticalPosition // ignore: cast_nullable_to_non_nullable
as double?,overrideAssStyles: null == overrideAssStyles ? _self.overrideAssStyles : overrideAssStyles // ignore: cast_nullable_to_non_nullable
as bool,alignX: freezed == alignX ? _self.alignX : alignX // ignore: cast_nullable_to_non_nullable
as SubtitleAlignX?,marginX: freezed == marginX ? _self.marginX : marginX // ignore: cast_nullable_to_non_nullable
as double?,marginY: freezed == marginY ? _self.marginY : marginY // ignore: cast_nullable_to_non_nullable
as double?,borderStyle: null == borderStyle ? _self.borderStyle : borderStyle // ignore: cast_nullable_to_non_nullable
as SubtitleBorderStyle,
  ));
}


}

/// @nodoc
mixin _$TransitionConfig {

/// Crossfade on natural track end, 0–12 s; zero means gapless.
 Duration get naturalEnd;/// Crossfade on a manual skip, 0–12 s.
 Duration get manualSkip;/// Crossfade even between consecutive tracks of a gapless album (opt-in).
 bool get crossfadeGaplessAlbums;
/// Create a copy of TransitionConfig
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TransitionConfigCopyWith<TransitionConfig> get copyWith => _$TransitionConfigCopyWithImpl<TransitionConfig>(this as TransitionConfig, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as TransitionConfig;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TransitionConfig&&(identical(other.naturalEnd, _this.naturalEnd) || other.naturalEnd == _this.naturalEnd)&&(identical(other.manualSkip, _this.manualSkip) || other.manualSkip == _this.manualSkip)&&(identical(other.crossfadeGaplessAlbums, _this.crossfadeGaplessAlbums) || other.crossfadeGaplessAlbums == _this.crossfadeGaplessAlbums));
}


@override
int get hashCode {
  final _this = this as TransitionConfig;
  return Object.hash(runtimeType,_this.naturalEnd,_this.manualSkip,_this.crossfadeGaplessAlbums);
}

@override
String toString() {
  final _this = this as TransitionConfig;
  return 'TransitionConfig(naturalEnd: ${_this.naturalEnd}, manualSkip: ${_this.manualSkip}, crossfadeGaplessAlbums: ${_this.crossfadeGaplessAlbums})';
}


}

/// @nodoc
abstract mixin class $TransitionConfigCopyWith<$Res>  {
  factory $TransitionConfigCopyWith(TransitionConfig value, $Res Function(TransitionConfig) _then) = _$TransitionConfigCopyWithImpl;
@useResult
$Res call({
 Duration naturalEnd, Duration manualSkip, bool crossfadeGaplessAlbums
});




}
/// @nodoc
class _$TransitionConfigCopyWithImpl<$Res>
    implements $TransitionConfigCopyWith<$Res> {
  _$TransitionConfigCopyWithImpl(this._self, this._then);

  final TransitionConfig _self;
  final $Res Function(TransitionConfig) _then;

/// Create a copy of TransitionConfig
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? naturalEnd = null,Object? manualSkip = null,Object? crossfadeGaplessAlbums = null,}) {
  return _then(TransitionConfig(
naturalEnd: null == naturalEnd ? _self.naturalEnd : naturalEnd // ignore: cast_nullable_to_non_nullable
as Duration,manualSkip: null == manualSkip ? _self.manualSkip : manualSkip // ignore: cast_nullable_to_non_nullable
as Duration,crossfadeGaplessAlbums: null == crossfadeGaplessAlbums ? _self.crossfadeGaplessAlbums : crossfadeGaplessAlbums // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [TransitionConfig].
extension TransitionConfigPatterns on TransitionConfig {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TransitionConfig value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TransitionConfig() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TransitionConfig value)  $default,){
final _that = this;
switch (_that) {
case _TransitionConfig():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TransitionConfig value)?  $default,){
final _that = this;
switch (_that) {
case _TransitionConfig() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( Duration naturalEnd,  Duration manualSkip,  bool crossfadeGaplessAlbums)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TransitionConfig() when $default != null:
return $default(_that.naturalEnd,_that.manualSkip,_that.crossfadeGaplessAlbums);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( Duration naturalEnd,  Duration manualSkip,  bool crossfadeGaplessAlbums)  $default,) {final _that = this;
switch (_that) {
case _TransitionConfig():
return $default(_that.naturalEnd,_that.manualSkip,_that.crossfadeGaplessAlbums);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( Duration naturalEnd,  Duration manualSkip,  bool crossfadeGaplessAlbums)?  $default,) {final _that = this;
switch (_that) {
case _TransitionConfig() when $default != null:
return $default(_that.naturalEnd,_that.manualSkip,_that.crossfadeGaplessAlbums);case _:
  return null;

}
}

}

/// @nodoc


class _TransitionConfig implements TransitionConfig {
  const _TransitionConfig({this.naturalEnd = Duration.zero, this.manualSkip = Duration.zero, this.crossfadeGaplessAlbums = false});
  

/// Crossfade on natural track end, 0–12 s; zero means gapless.
@override@JsonKey() final  Duration naturalEnd;
/// Crossfade on a manual skip, 0–12 s.
@override@JsonKey() final  Duration manualSkip;
/// Crossfade even between consecutive tracks of a gapless album (opt-in).
@override@JsonKey() final  bool crossfadeGaplessAlbums;

/// Create a copy of TransitionConfig
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TransitionConfigCopyWith<_TransitionConfig> get copyWith => __$TransitionConfigCopyWithImpl<_TransitionConfig>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TransitionConfig&&(identical(other.naturalEnd, naturalEnd) || other.naturalEnd == naturalEnd)&&(identical(other.manualSkip, manualSkip) || other.manualSkip == manualSkip)&&(identical(other.crossfadeGaplessAlbums, crossfadeGaplessAlbums) || other.crossfadeGaplessAlbums == crossfadeGaplessAlbums));
}


@override
int get hashCode {
    return Object.hash(runtimeType,naturalEnd,manualSkip,crossfadeGaplessAlbums);
}

@override
String toString() {
    return 'TransitionConfig(naturalEnd: $naturalEnd, manualSkip: $manualSkip, crossfadeGaplessAlbums: $crossfadeGaplessAlbums)';
}


}

/// @nodoc
abstract mixin class _$TransitionConfigCopyWith<$Res> implements $TransitionConfigCopyWith<$Res> {
  factory _$TransitionConfigCopyWith(_TransitionConfig value, $Res Function(_TransitionConfig) _then) = __$TransitionConfigCopyWithImpl;
@override @useResult
$Res call({
 Duration naturalEnd, Duration manualSkip, bool crossfadeGaplessAlbums
});




}
/// @nodoc
class __$TransitionConfigCopyWithImpl<$Res>
    implements _$TransitionConfigCopyWith<$Res> {
  __$TransitionConfigCopyWithImpl(this._self, this._then);

  final _TransitionConfig _self;
  final $Res Function(_TransitionConfig) _then;

/// Create a copy of TransitionConfig
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? naturalEnd = null,Object? manualSkip = null,Object? crossfadeGaplessAlbums = null,}) {
  return _then(_TransitionConfig(
naturalEnd: null == naturalEnd ? _self.naturalEnd : naturalEnd // ignore: cast_nullable_to_non_nullable
as Duration,manualSkip: null == manualSkip ? _self.manualSkip : manualSkip // ignore: cast_nullable_to_non_nullable
as Duration,crossfadeGaplessAlbums: null == crossfadeGaplessAlbums ? _self.crossfadeGaplessAlbums : crossfadeGaplessAlbums // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
