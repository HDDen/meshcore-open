import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/connector/pending_command_replies.dart';
import 'package:meshcore_open/helpers/direct_echo_recovery.dart';

void main() {
  group('meansRawPacketUnsupported', () {
    bool unsupported(Object error) =>
        DirectEchoRecovery.meansRawPacketUnsupported(error);

    test('a node that does not know the command', () {
      expect(
        unsupported(const CommandFailedException(errCodeUnsupportedCmd)),
        isTrue,
      );
      // Firmware from before error codes answers with a bare ERR.
      expect(unsupported(const CommandFailedException(-1)), isTrue);
    });

    test('a refusal of one packet leaves the ACK on', () {
      expect(
        unsupported(const CommandFailedException(errCodeTableFull)),
        isFalse,
      );
      // ERR_CODE_ILLEGAL_ARG: the node could not parse this packet.
      expect(unsupported(const CommandFailedException(6)), isFalse);
    });

    test('anything but an ERR leaves the ACK on', () {
      expect(unsupported(TimeoutException('no answer')), isFalse);
      expect(unsupported(StateError('not connected')), isFalse);
    });
  });
}
