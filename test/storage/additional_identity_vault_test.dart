import 'dart:convert';

import 'package:convert/convert.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/services/additional_identity_vault.dart';
import 'package:meshcore_open/storage/data_root_core.dart';
import 'package:meshcore_open/storage/message_history_storage.dart';
import 'package:meshcore_open/utils/keys.dart';

import '../support/history_test_environment.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final environment = HistoryTestEnvironment();
  final storage = MessageHistoryStorage.instance;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await environment.setUp();
  });
  tearDown(environment.tearDown);

  test('keys stay encrypted in SQLite and can be reopened and edited', () async {
    MCKeyPair pair;
    do {
      pair = await generateKeyPair();
    } while (pair.public.first == 0 || pair.public.first == 0xff);
    final privateKey = hex.encode(pair.private);
    final entry = await AdditionalIdentityEntry.parse('Separate identity', privateKey);
    final vault = await AdditionalIdentityVault.open(
      password: 'example vault password',
      saved: await storage.readAdditionalIdentityVault(),
    );
    await vault.save(entry);
    final saved = (await storage.readAdditionalIdentityVault())!;
    final envelope = jsonDecode(saved) as Map<String, dynamic>;
    expect(envelope.keys, containsAll(['salt', 'verifier', 'nonce', 'tag', 'ciphertext']));
    expect(saved, isNot(contains('example vault password')));
    expect(saved, isNot(contains('Separate identity')));
    expect(saved, isNot(contains(privateKey)));

    expect(await AdditionalIdentityVault.openRemembered(), isNull);
    await vault.setUnlockRemembered(true);
    expect(await vault.isUnlockRemembered(), isTrue);
    final remembered = (await AdditionalIdentityVault.openRemembered())!;
    expect(remembered.entries.single.identity.privateKeyHex, privateKey);
    expect(await storage.readAdditionalIdentityVault(), saved);

    final profile = DataRoot.path;
    try {
      DataRoot.path = 'another-data-folder';
      expect(await AdditionalIdentityVault.openRemembered(), isNull);
    } finally {
      DataRoot.path = profile;
    }

    await expectLater(
      AdditionalIdentityVault.open(password: 'wrong', saved: saved),
      throwsFormatException,
    );
    final reopened = await AdditionalIdentityVault.open(
      password: 'example vault password',
      saved: saved,
    );
    final restored = reopened.entries.single;
    expect(restored.name, entry.name);
    expect(restored.identity.publicKeyHex, hex.encode(pair.public));
    expect(restored.identity.privateKeyHex, privateKey);
    await expectLater(reopened.save(entry), throwsFormatException);

    final updated = await AdditionalIdentityEntry.parse('Renamed', privateKey);
    await reopened.save(updated, replacing: restored.identity.publicKeyHex);
    final afterEdit = jsonDecode((await storage.readAdditionalIdentityVault())!)
        as Map<String, dynamic>;
    expect(afterEdit['nonce'], isNot(envelope['nonce']));
    expect(reopened.entries.single.name, 'Renamed');

    await reopened.changePassword('new vault password');
    final rotated = (await storage.readAdditionalIdentityVault())!;
    final afterRotation = await AdditionalIdentityVault.open(
      password: 'new vault password',
      saved: rotated,
    );
    expect(afterRotation.entries.single.identity.privateKeyHex, privateKey);
    expect(await afterRotation.isUnlockRemembered(), isTrue);
    expect(
      (await AdditionalIdentityVault.openRemembered())!
          .entries.single.identity.privateKeyHex,
      privateKey,
    );
    await afterRotation.setUnlockRemembered(false);
    expect(await AdditionalIdentityVault.openRemembered(), isNull);
    await afterRotation.remove(restored.identity.publicKeyHex);
    expect(afterRotation.entries, isEmpty);
  });
}
