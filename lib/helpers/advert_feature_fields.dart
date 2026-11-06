import '../connector/meshcore_protocol.dart';

/// Feature 1 and 2 occupy two bytes each after GPS and before the advert name.
/// BufferReader checks the whole skip: a truncated declared field must not be
/// mistaken for a name by either the RX parser or manual raw-frame import.
void skipAdvertFeatureFields(BufferReader reader, int flags) {
  final bytes = ((flags & 0x20) != 0 ? 2 : 0) +
      ((flags & 0x40) != 0 ? 2 : 0);
  reader.skipBytes(bytes);
}

/// An omitted/blank name carries no replacement; a real new name still wins.
/// Do not special-case literal names such as "Unknown".
String retainedAdvertName(String existing, String incoming) =>
    incoming.trim().isEmpty ? existing : incoming;
