import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/message_filter.dart';
import 'package:meshcore_open/storage/message_history_database.dart';

FilterTrainingRow _row(String sender, String text, FilterTrainingKind kind) => (
  sender: sender, text: text, kind: kind,
  sourceKey: kind == FilterTrainingKind.ordinary
      ? FilterExample.sourceKeyFor(sender, text)
      : null,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SQL keeps recent examples after reopening and respects manual labels', () async {
    final directory = await Directory.systemTemp.createTemp('mcoa-filter-sql-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File.fromUri(directory.uri.resolve('history.sqlite'));

    MessageHistoryDatabase open() =>
        MessageHistoryDatabase.withExecutor(NativeDatabase(file));

    var database = open();
    addTearDown(() => database.close());
    await database.customStatement('DROP TABLE filter_training_corpus');
    await database.close();
    database = open();

    final ordinary = [
      for (var i = 0; i < 301; i++)
        FilterExample(sender: 'Bob', text: 'ordinary $i', spam: false),
    ];
    await database.writeFilterTrainingExamples(ordinary, manual: false);
    await database.writeFilterTrainingExamples(
      const [FilterExample(sender: 'Bob', text: 'ordinary 50', spam: true)],
      manual: true,
    );
    await database.writeFilterTrainingExamples([ordinary[50]], manual: false);
    await database.close();
    database = open();

    final corpus = await database.readFilterTrainingExamples();
    expect(corpus, hasLength(300));
    expect(corpus.first.text, 'ordinary 1');
    expect(corpus.last.text, 'ordinary 50');
    expect(corpus.last.spam, isTrue);
    expect(await database.filterTrainingLabelCounts(), (spam: 1, notSpam: 0));

    await database.clearFilterTrainingExamples();
    expect(await database.readFilterTrainingExamples(), isEmpty);
  });

  test('corpus merge preserves local labels, authors and ordinary multiplicity', () async {
    final directory = await Directory.systemTemp.createTemp('mcoa-filter-backup-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File.fromUri(directory.uri.resolve('history.sqlite'));
    MessageHistoryDatabase open() => MessageHistoryDatabase.withExecutor(NativeDatabase(file));
    var database = open();
    addTearDown(() => database.close());
    const ordinary = FilterTrainingKind.ordinary;
    const spam = FilterTrainingKind.spam;
    const notSpam = FilterTrainingKind.notSpam;

    final first = _row('alice', 'hello', ordinary);
    final second = _row('bob', 'hello', ordinary);
    final localLabel = _row('alice', 'local label', notSpam);
    await database.restoreFilterTrainingCorpus([
      first, _row('alice', 'classify this', ordinary), localLabel,
    ]);
    final incoming = [
      first,
      _row('carol', 'local label', spam),
      _row('bob', 'local label', notSpam),
      second,
      first,
      _row('alice', 'classify this', spam),
      _row('carol', 'classify this', ordinary),
    ];
    expect(await database.restoreFilterTrainingCorpus(incoming), 4);
    await database.close();
    database = open();
    final saved = await database.readFilterTrainingCorpus();
    expect(saved, [first, localLabel, incoming[2], second, first, incoming[5]]);
    expect(await database.filterTrainingLabelCounts(), (spam: 1, notSpam: 2));
    expect(await database.restoreFilterTrainingCorpus(incoming), 0);
    expect(await database.readFilterTrainingCorpus(), saved);
  });

  test('corpus merge fills free capacity without evicting local rows', () async {
    final database = MessageHistoryDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(database.close);
    const spam = FilterTrainingKind.spam;
    final local = [for (var index = 0; index < spam.capacity - 1; index++)
      _row('alice', 'local $index', spam),
    ];
    await database.restoreFilterTrainingCorpus(local);
    final newest = _row('bob', 'newer backup entry', spam);
    expect(await database.restoreFilterTrainingCorpus([
      _row('bob', 'older backup entry', spam), newest,
    ]), 1);
    expect(await database.readFilterTrainingCorpus(), [...local, newest]);
  });

  test('ordinary examples skip only adjacent copies across batches', () async {
    final directory = await Directory.systemTemp.createTemp('mcoa-filter-clean-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File.fromUri(directory.uri.resolve('history.sqlite'));
    MessageHistoryDatabase open() =>
        MessageHistoryDatabase.withExecutor(NativeDatabase(file));

    var database = open();
    addTearDown(() => database.close());
    const alice = FilterExample(sender: 'alice', text: 'thanks', spam: false);
    const bob = FilterExample(sender: 'bob', text: 'thanks', spam: false);
    final upper = FilterExample(
      sender: 'alice',
      text: 'thanks',
      spam: false,
      sourceKey: FilterExample.sourceKeyFor('alice', 'THANKS'),
    );
    await database.writeFilterTrainingExamples([alice, alice, bob], manual: false);
    await database.close();
    database = open();
    await database.writeFilterTrainingExamples(
      [bob, alice, upper, upper],
      manual: false,
    );

    final examples = await database.readFilterTrainingExamples();
    expect(examples.map((example) => example.sender), ['alice', 'bob', 'alice', 'alice']);
    expect(examples.map((example) => example.text), List.filled(4, 'thanks'));
  });

  test('manual labels retain each sender and respect a changed label', () async {
    final directory = await Directory.systemTemp.createTemp('mcoa-filter-keys-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File.fromUri(directory.uri.resolve('history.sqlite'));

    MessageHistoryDatabase open() =>
        MessageHistoryDatabase.withExecutor(NativeDatabase(file));

    var database = open();
    addTearDown(() => database.close());

    const text = 'claim your free prize';
    const alice = FilterExample(sender: 'alice', text: text, spam: true);
    const bob = FilterExample(sender: 'bob', text: text, spam: true);
    await database.writeFilterTrainingExamples([alice, bob, alice], manual: true);
    await database.writeFilterTrainingExamples(
      const [FilterExample(sender: 'carol', text: text, spam: false)],
      manual: false,
    );
    await database.close();
    database = open();

    final examples = await database.readFilterTrainingExamples();
    expect(examples.map((example) => example.sender), ['bob', 'alice']);
    expect(examples.every((example) => example.spam), isTrue);
    expect(await database.filterTrainingLabelCounts(), (spam: 2, notSpam: 0));

    await database.writeFilterTrainingExamples(
      const [FilterExample(sender: 'alice', text: text, spam: false)],
      manual: true,
    );
    final relabelled = (await database.readFilterTrainingExamples()).single;
    expect(relabelled.sender, 'alice');
    expect(relabelled.spam, isFalse);
    expect(await database.filterTrainingLabelCounts(), (spam: 0, notSpam: 1));
  });
}
