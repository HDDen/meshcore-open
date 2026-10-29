import 'dart:convert';

import '../models/app_settings.dart';

enum ContactOptionType { flag, integer, text, textList }

/// The persisted name is independent of its old preferences prefix. One SQL row
/// holds one option; only the inherently list-valued quick replies use JSON.
class ContactOptionDefinition {
  const ContactOptionDefinition(this.prefix, this.type, {this.infix = ''});

  final String prefix;
  final String infix;
  final ContactOptionType type;

  String legacyKey(String scope, String contact) => '$prefix$scope$infix$contact';

  RegExp get legacyPattern => RegExp(
    '^${RegExp.escape(prefix)}([0-9a-fA-F]{10})'
    '${RegExp.escape(infix)}([0-9a-fA-F]{64})' r'$',
  );

  String? encode(Object? value) {
    switch (type) {
      case ContactOptionType.flag:
        return value is bool ? (value ? '1' : '0') : null;
      case ContactOptionType.integer:
        return value is int ? value.toString() : null;
      case ContactOptionType.text:
        return value is String ? value : null;
      case ContactOptionType.textList:
        return value is List && value.every((entry) => entry is String)
            ? jsonEncode(AppSettings.normalizeQuickAnswerIds(value))
            : null;
    }
  }

  Object? decode(String? value) {
    if (value == null) {
      return null;
    }
    switch (type) {
      case ContactOptionType.flag:
        return value == '1' ? true : (value == '0' ? false : null);
      case ContactOptionType.integer:
        return int.tryParse(value);
      case ContactOptionType.text:
        return value;
      case ContactOptionType.textList:
        try {
          final decoded = jsonDecode(value);
          if (decoded is! List || decoded.any((entry) => entry is! String)) {
            return null;
          }
          return AppSettings.normalizeQuickAnswerIds(decoded);
        } on FormatException {
          return null;
        }
    }
  }
}

const contactOptionDefinitions = <String, ContactOptionDefinition>{
  'smaz_enabled': ContactOptionDefinition('contact_smaz_', ContactOptionType.flag),
  'mcmp_enabled': ContactOptionDefinition('contact_mcmp_', ContactOptionType.flag),
  'mcmp_version': ContactOptionDefinition('contact_mcmp_version_', ContactOptionType.integer),
  'mcmp_use_sign': ContactOptionDefinition('contact_mcmp_use_sign_', ContactOptionType.flag),
  'mcotxt_enabled': ContactOptionDefinition('contact_mcotxt_', ContactOptionType.flag),
  'mcotxt_plain_when_smaller': ContactOptionDefinition('contact_mcotxt_plain_when_smaller_', ContactOptionType.flag),
  'cyr2lat_enabled': ContactOptionDefinition('contact_cyr2lat_', ContactOptionType.flag),
  'cyr2lat_profile': ContactOptionDefinition('contact_cyr2lat_', ContactOptionType.text, infix: 'profile_'),
  'sending_delay_enabled': ContactOptionDefinition('contact_sending_delay_', ContactOptionType.flag),
  'quick_answer_ids': ContactOptionDefinition('contact_quick_answer_ids_', ContactOptionType.textList),
  'url_images_enabled': ContactOptionDefinition('contact_url_images_', ContactOptionType.flag),
};

class ContactOptionRow {
  const ContactOptionRow({
    required this.nodeKey,
    required this.contactKey,
    required this.name,
    required this.value,
  });

  final String nodeKey;
  final String contactKey;
  final String name;
  final String value;
}

/// Only valid, scoped legacy keys are eligible for startup migration. Unknown,
/// malformed and old unscoped keys stay untouched until they can be interpreted.
Map<String, ContactOptionRow> contactOptionsFromPreferences(
  Map<String, Object?> values,
) {
  final rows = <String, ContactOptionRow>{};
  final patterns = {
    for (final option in contactOptionDefinitions.entries)
      option.key: option.value.legacyPattern,
  };
  for (final entry in values.entries) {
    for (final option in contactOptionDefinitions.entries) {
      final match = patterns[option.key]!.firstMatch(entry.key);
      if (match == null) {
        continue;
      }
      final encoded = option.value.encode(entry.value);
      if (encoded != null) {
        rows[entry.key] = ContactOptionRow(
          nodeKey: match[1]!.toLowerCase(),
          contactKey: match[2]!.toLowerCase(),
          name: option.key,
          value: encoded,
        );
      }
      break;
    }
  }
  return rows;
}
