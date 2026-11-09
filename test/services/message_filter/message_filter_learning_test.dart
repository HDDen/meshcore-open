import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/message_filter.dart';
import 'package:meshcore_open/services/message_filter/message_filter_service.dart';
import 'package:meshcore_open/services/message_filter/ngram_spam_classifier.dart';
import 'package:meshcore_open/storage/message_filter_store.dart';

const _spamA = FilterExample(sender: 'alice', text: 'buy cheap radios today', spam: true);
const _spamB = FilterExample(sender: 'alice', text: 'claim your free prize', spam: true);
const _clean = FilterExample(sender: 'bob', text: 'the weather is nice', spam: false);
const _readyModel = SpamModel({}, 8);

class _Store extends MessageFilterStore {
  _Store({this.labels = const []});

  List<FilterExample> labels;
  final recentClean = <FilterExample>[];
  MessageFilterSettings settings = const MessageFilterSettings();
  int loads = 0;
  int writes = 0;
  int cleanWrites = 0;

  @override
  MessageFilterSettings loadSettings() => settings;

  @override
  List<FilterRule> loadRules() => const [];

  @override
  Future<void> saveSettings(MessageFilterSettings value) async {
    settings = value;
  }

  @override
  Future<void> saveRules(List<FilterRule> rules) async {}

  @override
  Future<({int spam, int notSpam})> loadTrainingLabelCounts() async {
    final spam = labels.where((example) => example.spam).length;
    return (spam: spam, notSpam: labels.length - spam);
  }

  @override
  Future<List<FilterExample>> loadTrainingExamples() async {
    loads++;
    return [...labels, ...recentClean];
  }

  @override
  Future<void> saveTrainingExamples(
    Iterable<FilterExample> examples, {
    required bool manual,
  }) async {
    if (manual) {
      writes++;
      for (final example in examples) {
        labels = [
          for (final label in labels)
            if (label.text != example.text ||
                (label.spam == example.spam && label.sender != example.sender))
              label,
          example,
        ];
      }
      recentClean.removeWhere(
        (row) => labels.any((label) => label.text == row.text),
      );
    } else {
      cleanWrites++;
      recentClean.addAll(
        examples.where((row) => !labels.any((label) => label.text == row.text)),
      );
      if (recentClean.length > 300) {
        recentClean.removeRange(0, recentClean.length - 300);
      }
    }
  }

  @override
  Future<void> clearTrainingExamples() async {
    labels = [];
    recentClean.clear();
  }
}

FilterReason? _score(MessageFilterService service, {String channel = 'test'}) =>
    service.evaluate(
      channelId: channel,
      sender: 'Alice',
      text: 'a synthetic post',
    )?.reason;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('U27d: learning off skips loading, scoring, writes and jobs', (
    tester,
  ) async {
    final store = _Store(labels: const [_spamA, _spamB, _clean]);
    var jobs = 0;
    final service = MessageFilterService(
      store: store,
      trainer: (_) async {
        jobs++;
        return _readyModel;
      },
    )..load();
    addTearDown(service.dispose);

    await service.recordFeedback('test', 'Alice', 'manual label', spam: true);
    service.recordClean('test', 'Bob', 'ordinary post');
    await service.updateSettings(service.settings.copyWith(learning: true));
    await tester.pump(const Duration(seconds: 1));
    expect(store.loads, 0);
    expect(store.writes, 0);
    expect(jobs, 0);
    expect(_score(service), isNull);

    await service.updateSettings(service.settings.copyWith(enabled: true));
    await tester.pump(const Duration(milliseconds: 300));
    expect(store.loads, 1);
    expect(jobs, 1);
    expect(_score(service), FilterReason.learned);

    await service.updateSettings(service.settings.copyWith(learning: false));
    await service.recordFeedback('test', 'Alice', 'another label', spam: true);
    await tester.pump(const Duration(seconds: 1));
    expect(store.writes, 0);
    expect(jobs, 1);
    expect(_score(service), isNull);
  });

  testWidgets('U27d: ordinary examples persist in batches and feedback coalesces fits', (
    tester,
  ) async {
    final store = _Store();
    final jobs = <SpamTrainingJob>[];
    final service = MessageFilterService(
      store: store,
      trainer: (job) async {
        jobs.add(job);
        return _readyModel;
      },
    );
    addTearDown(service.dispose);
    await service.updateSettings(
      const MessageFilterSettings(
        enabled: true,
        learning: true,
        excludedChannelIds: {'excluded'},
      ),
    );
    service.recordClean('excluded', 'Other', 'excluded text');
    await service.recordFeedback(
      'excluded',
      'Other',
      'excluded spam',
      spam: true,
    );
    await service.recordFeedback('test', 'Alice', _spamA.text, spam: true);
    await service.recordFeedback('test', 'Alice', _spamB.text, spam: true);
    await tester.pump(const Duration(seconds: 1));
    expect(jobs, isEmpty);

    for (var i = 0; i < 310; i++) {
      service.recordClean('test', 'Bob', 'clean post number $i');
      if (i % 10 == 9) await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 300));
    expect(jobs, hasLength(1));
    expect(jobs.single.spam.map((example) => example.text), [_spamA.text, _spamB.text]);
    expect(jobs.single.ham, hasLength(300));
    expect(jobs.single.ham.first.text, 'clean post number 10');
    expect(store.labels.map((example) => example.text), [_spamA.text, _spamB.text]);
    expect(store.writes, 2);
    expect(store.cleanWrites, 31);
    expect(_score(service, channel: 'excluded'), isNull);
    expect(_score(service), FilterReason.learned);
    service.allowRestoredText('test', 'a synthetic post');
    expect(_score(service), isNull);

    await service.replaceRules(const [FilterRule(id: 'keep', pattern: 'word')]);
    await service.resetLearning();
    expect(store.labels, isEmpty);
    expect(store.recentClean, isEmpty);
    expect(service.rules.single.id, 'keep');
    expect(service.spamExampleCount, 0);
    expect(_score(service), isNull);
  });

  testWidgets('U27d: a short batch can train after reopening', (tester) async {
    final store = _Store();
    final first = MessageFilterService(store: store);
    await first.updateSettings(
      const MessageFilterSettings(enabled: true, learning: true),
    );
    first.recordClean('channel-a', 'Bob', _clean.text);
    await tester.pump(const Duration(seconds: 4));
    expect(store.cleanWrites, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(store.cleanWrites, 1);
    expect(store.loads, 0);
    first.dispose();

    final jobs = <SpamTrainingJob>[];
    final reopened = MessageFilterService(
      store: store,
      trainer: (job) async {
        jobs.add(job);
        return _readyModel;
      },
    )..load();
    addTearDown(reopened.dispose);
    await reopened.recordFeedback('channel-b', 'Alice', _spamA.text, spam: true);
    await reopened.recordFeedback('channel-b', 'Alice', _spamB.text, spam: true);
    await tester.pump(const Duration(milliseconds: 300));
    expect(jobs, hasLength(1));
    expect(jobs.single.ham.map((example) => example.text), [_clean.text]);
    expect(_score(reopened), FilterReason.learned);
  });

  testWidgets('ordinary samples preserve receive order in the write buffer', (
    tester,
  ) async {
    final store = _Store();
    final service = MessageFilterService(store: store);
    addTearDown(service.dispose);
    await service.updateSettings(
      const MessageFilterSettings(enabled: true, learning: true),
    );

    for (final (sender, text) in [
      ('Alice', 'thanks'),
      ('Alice', 'thanks'),
      ('Bob', 'thanks'),
      ('Alice', 'thanks'),
      ('Alice', 'THANKS'),
    ]) {
      service.recordClean('test', sender, text);
    }
    await tester.pump(const Duration(seconds: 5));

    expect(store.cleanWrites, 1);
    expect(
      store.recentClean.map((example) => example.sender),
      ['alice', 'bob', 'alice', 'alice'],
    );
    expect(store.recentClean.map((example) => example.text), List.filled(4, 'thanks'));
  });

  testWidgets('U27d: the same spam text from two senders can train', (
    tester,
  ) async {
    final store = _Store(labels: const [_clean]);
    final jobs = <SpamTrainingJob>[];
    final service = MessageFilterService(
      store: store,
      trainer: (job) async {
        jobs.add(job);
        return _readyModel;
      },
    );
    addTearDown(service.dispose);
    await service.updateSettings(
      const MessageFilterSettings(enabled: true, learning: true),
    );

    await service.recordFeedback('test', 'Alice', _spamA.text, spam: true);
    await service.recordFeedback('test', 'ＡＬＩＣＥ', _spamA.text, spam: true);
    expect(service.spamExampleCount, 1);
    await service.recordFeedback('test', 'Bob', _spamA.text, spam: true);
    await tester.pump(const Duration(milliseconds: 300));

    expect(service.spamExampleCount, 2);
    expect(jobs, hasLength(1));
    expect(jobs.single.spam.map((example) => example.sender), ['alice', 'bob']);
    expect(jobs.single.spam.map((example) => example.text), [_spamA.text, _spamA.text]);
    expect(_score(service), FilterReason.learned);
  });

  testWidgets('U27d: a fit already running cannot publish after disabling', (
    tester,
  ) async {
    final store = _Store(labels: const [_spamA, _spamB, _clean]);
    final fit = Completer<SpamModel?>();
    var jobs = 0;
    final service = MessageFilterService(
      store: store,
      trainer: (_) {
        jobs++;
        return fit.future;
      },
    );
    addTearDown(service.dispose);
    await service.updateSettings(
      const MessageFilterSettings(enabled: true, learning: true),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(jobs, 1);
    await service.updateSettings(service.settings.copyWith(learning: false));
    fit.complete(_readyModel);
    await tester.pump();
    expect(_score(service), isNull);

    await service.updateSettings(service.settings.copyWith(learning: true));
    expect(_score(service), isNull);
    await service.updateSettings(service.settings.copyWith(enabled: false));
    await tester.pump(const Duration(seconds: 1));
    expect(jobs, 1);
  });

  test('U27d: the upstream statistical model separates labelled examples', () {
    final classifier = NgramSpamClassifier();
    classifier.train(const [_spamA, _spamB], const [_clean]);
    expect(classifier.isTrained, isTrue);
    expect(classifier.probability(_spamA.sender, _spamA.text), greaterThan(0.80));
    expect(classifier.probability(_clean.sender, _clean.text), lessThan(0.20));
  });
}
