// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings_store.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_SettingsDocument _$SettingsDocumentFromJson(
  Map<String, dynamic> json,
) => _SettingsDocument(
  schema: (json['schema'] as num?)?.toInt() ?? SettingsDocument.currentSchema,
  values: json['values'] as Map<String, dynamic>? ?? const <String, Object?>{},
  exportedAt: json['exportedAt'] == null
      ? null
      : DateTime.parse(json['exportedAt'] as String),
);

Map<String, dynamic> _$SettingsDocumentToJson(_SettingsDocument instance) =>
    <String, dynamic>{
      'schema': instance.schema,
      'values': instance.values,
      'exportedAt': instance.exportedAt?.toIso8601String(),
    };
