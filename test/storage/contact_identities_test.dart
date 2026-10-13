import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/storage/contact_identity_store.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

// What the contact identity table promises, pinned on its preference form:
// a key with no row is a group of itself, a link makes two keys one contact
// and chains, keys are compared without case, the rows survive a reload and
// a forget removes the whole group.

final _a = 'aa' * 32;
final _b = 'bb' * 32;
final _c = 'cc' * 32;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final identities = ContactIdentities.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
    identities.resetForTesting();
    await identities.load();
  });

  tearDown(() {
    identities.resetForTesting();
    PrefsManager.reset();
  });

  test('a key without a row is a group of itself', () {
    expect(identities.keysOf(_a), [_a]);
    expect(identities.groupIdOf(_a), isNull);
    expect(identities.sameContact(_a, _b), isFalse);
    expect(identities.sameContact(_a, _a.toUpperCase()), isTrue);
  });

  test('a link makes two keys one contact and chains', () async {
    final revision = identities.revision;
    expect(await identities.link(_a, _b), isTrue);
    expect(identities.revision, greaterThan(revision));
    expect(await identities.link(_b, _a), isFalse);
    expect(await identities.link(_b, _c), isTrue);

    expect(identities.keysOf(_a).first, _a);
    expect(identities.keysOf(_a).toSet(), {_a, _b, _c});
    expect(identities.keysOf(_c.toUpperCase()).first, _c);
    expect(identities.sameContact(_a, _c), isTrue);
    expect(await identities.link(_a, _a), isFalse);
    expect(await identities.link('', _a), isFalse);
  });

  test('the rows survive a reload and a forget removes the group', () async {
    await identities.link(_a, _b);
    identities.resetForTesting();
    expect(identities.keysOf(_a), [_a]);
    await identities.load();
    expect(identities.keysOf(_a), [_a, _b]);

    await identities.forget(_b);
    expect(identities.keysOf(_a), [_a]);
    identities.resetForTesting();
    await identities.load();
    expect(identities.keysOf(_b), [_b]);
    expect(identities.isEmpty, isTrue);
  });
}
