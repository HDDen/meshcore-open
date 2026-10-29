import '../models/contact.dart';

/// Stable partition AFTER the selected sort. Each group keeps that sort's
/// existing order, including unread priority and equal-value tie handling.
List<Contact> favoriteContactsFirst(List<Contact> sortedContacts) {
  final favorites = <Contact>[];
  final others = <Contact>[];
  for (final contact in sortedContacts) {
    (contact.isFavorite ? favorites : others).add(contact);
  }
  return [...favorites, ...others];
}
