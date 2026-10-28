import 'companion_cli_list_layout.dart';
import 'companion_cli_protocol.dart';

/// Папки уже хранят ключи peer: вместе с именами каналов. Для консоли используем
/// её служебный ключ, а не отображаемое имя и не фиктивный Channel.
bool hasCompanionCliGroupMember(Iterable<String> members) => members.any(
  (key) => key.trim().toLowerCase() == companionCliOrderKey,
);

/// Редактирование состава сохраняет позицию CLI, даже когда прошивка или
/// переключатель временно скрыли консоль. Снятая галочка удаляет только её ключ.
List<String> withCompanionCliGroupMember(
  List<String> members, {
  required bool selected,
  List<String> previousOrder = const [],
}) {
  final normal = members.where(
    (key) => key.trim().toLowerCase() != companionCliOrderKey,
  ).toList();
  if (!selected) return normal;
  final layout = CompanionCliListLayout<String>(
    items: normal,
    keyOf: (key) => key.trim().toLowerCase(),
    previousOrder: previousOrder.map((key) => key.trim().toLowerCase()).toList(),
    visible: true,
  );
  return [for (final key in layout.entries) key ?? companionCliOrderKey];
}
