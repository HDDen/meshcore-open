import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/ios_presentation_guard.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/power_saving_settings.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/gif_image_provider.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/utils/app_route_observer.dart';
import 'package:meshcore_open/widgets/gif_message.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

const _first = 'https://example.invalid/gif-baseline-first.gif';
const _second = 'https://example.invalid/gif-baseline-second.gif';
const _onlyGifs = PowerSavingSettings(
  profile: PowerSavingProfile.custom,
  custom: PowerSavingOptions(pauseHiddenGifs: true),
);

class _GifBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  ImageCache createImageCache() => _GifCache();

  _GifCache get gifCache => imageCache as _GifCache;
}

/// Реальный ImageCache, но его загрузчики дают управляемые синтетические кадры.
/// Настоящий GifMessage/provider проходят обычный resolve; сеть и диск запрещены.
class _GifCache extends ImageCache {
  final sources = <Object, _Frames Function()>{};
  final created = <Object, List<_Frames>>{};
  final evicted = <Object>[];

  List<_Frames> streams(String url) => created[gifImageProvider(url)]!;

  @override
  ImageStreamCompleter? putIfAbsent(
    Object key,
    ImageStreamCompleter Function() loader, {
    ImageErrorListener? onError,
  }) {
    final source = sources[key];
    if (source == null) {
      throw StateError('Unexpected image lookup in GIF baseline: $key');
    }
    return super.putIfAbsent(key, () {
      final stream = source();
      created.putIfAbsent(key, () => <_Frames>[]).add(stream);
      return stream;
    }, onError: onError);
  }

  @override
  bool evict(Object key, {bool includeLive = true}) {
    evicted.add(key);
    return super.evict(key, includeLive: includeLive);
  }
}

class _Frames extends ImageStreamCompleter {
  final listeners = <ImageStreamListener>[];
  bool disposed = false;

  @override
  void onDisposed() {
    disposed = true;
    super.onDisposed();
  }

  @override
  void addListener(ImageStreamListener listener) {
    listeners.add(listener);
    super.addListener(listener);
  }

  @override
  void removeListener(ImageStreamListener listener) {
    listeners.remove(listener);
    super.removeListener(listener);
  }

  void emit(int width, int height) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..color = const ui.Color(0xff336699),
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(width, height);
    picture.dispose();
    setImage(ImageInfo(image: image));
  }

  void fail() => reportError(exception: StateError('Synthetic GIF load failure'));
}

class _Host extends StatefulWidget {
  const _Host({super.key, required this.settings, this.initialTicker = true});

  final AppSettingsService settings;
  final bool initialTicker;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  AppSettingsService get settings => widget.settings;
  final navigator = GlobalKey<NavigatorState>();
  late final display = ValueNotifier<(String, bool, double)>(
    (_first, widget.initialTicker, 0),
  );

  void changeUrl(String value) =>
      display.value = (value, display.value.$2, display.value.$3);
  void changeTicker(bool value) =>
      display.value = (display.value.$1, value, display.value.$3);
  void changeOffset(double value) =>
      display.value = (display.value.$1, display.value.$2, value);

  @override
  void dispose() {
    display.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider<AppSettingsService>.value(
    value: settings,
    child: MaterialApp(
      navigatorKey: navigator,
      navigatorObservers: [appRouteObserver],
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        // Как viewport списка чата: Transform сам по себе не обрезает рисунок.
        body: ClipRect(
          key: const ValueKey('gif-viewport'),
          child: ValueListenableBuilder<(String, bool, double)>(
            valueListenable: display,
            builder: (_, value, _) => TickerMode(
              enabled: value.$2,
              child: Transform.translate(
                offset: Offset(0, value.$3),
                child: Center(
                  child: GifMessage(
                    key: const ValueKey('gif-baseline'),
                    url: value.$1,
                    backgroundColor: Colors.black,
                    fallbackTextColor: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _withGif(
  WidgetTester tester,
  _GifCache cache,
  Future<void> Function(_HostState) check, {
  PowerSavingSettings powerSaving = const PowerSavingSettings(),
  bool initialTicker = true,
}) async {
  final key = GlobalKey<_HostState>();
  final settings = AppSettingsService();
  try {
    await settings.updateSettings(settings.settings.copyWith(powerSaving: powerSaving));
    await tester.pumpWidget(_Host(key: key, settings: settings, initialTicker: initialTicker));
    await tester.pump();
    await check(key.currentState!);
  } finally {
    // Завершаем подписки/индикатор загрузки до проверки инвариантов testWidgets.
    await tester.pumpWidget(const SizedBox.shrink());
    cache.clear();
    cache.clearLiveImages();
    await tester.pump();
    settings.dispose();
  }
}

RawImage _displayed(WidgetTester tester) => tester.widget<RawImage>(find.byType(RawImage));

void main() {
  final binding = _GifBinding();
  final cache = binding.gifCache;
  final previousInterval = VisibilityDetectorController.instance.updateInterval;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    // Платформенная подготовка завершается до FakeAsync тела widget test.
    await PrefsManager.initialize();
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    cache.sources.clear();
    cache.created.clear();
    cache.evicted.clear();
    cache.sources[gifImageProvider(_first)] = () => _Frames()..emit(4, 2);
    cache.sources[gifImageProvider(_second)] = () => _Frames()..emit(3, 6);
  });
  tearDown(() {
    VisibilityDetectorController.instance.updateInterval = previousInterval;
    PrefsManager.reset();
  });

  for (final profile in [
    PowerSavingProfile.balanced,
    PowerSavingProfile.economical,
    PowerSavingProfile.maximum,
    PowerSavingProfile.custom,
  ]) {
    testWidgets('${profile.name}: hidden GIF releases and restores one listener',
        (tester) async {
      await _withGif(tester, cache, (host) async {
        final frames = cache.streams(_first).single;
        expect(frames.listeners, hasLength(1));
        host.changeTicker(false);
        await tester.pump();
        expect(frames.listeners, isEmpty);
        expect(find.byIcon(Icons.pause), findsNothing);
        frames.emit(8, 4);
        host.changeTicker(true);
        await tester.pump();
        await tester.pump();
        expect(frames.listeners, hasLength(1));
        expect(_displayed(tester).image!.width, 8);
        expect(cache.streams(_first), hasLength(1));
      }, powerSaving: _onlyGifs.copyWith(profile: profile));
    });
  }

  testWidgets('automatic visibility and profile changes preserve manual pause',
      (tester) async {
    await _withGif(tester, cache, (host) async {
      final frames = cache.streams(_first).single;
      await tester.tap(find.byType(GifMessage));
      await tester.pump();
      expect(frames.listeners, isEmpty);
      host.changeTicker(false);
      await tester.pump();
      host.changeTicker(true);
      await tester.pump();
      await tester.pump();
      expect(frames.listeners, isEmpty);
      expect(find.byIcon(Icons.pause), findsOneWidget);
      await host.settings.setPowerSavingProfile(PowerSavingProfile.disabled);
      await tester.pump();
      expect(frames.listeners, isEmpty);
      expect(find.byIcon(Icons.pause), findsOneWidget);
      await host.settings.setPowerSavingProfile(PowerSavingProfile.custom);
      await tester.pump();
      await tester.pump();
      expect(frames.listeners, isEmpty);
      await tester.tap(find.byType(GifMessage));
      await tester.pump();
      expect(frames.listeners, hasLength(1));
    }, powerSaving: _onlyGifs);
  });

  testWidgets('the GIF flag can be changed live without changing its custom siblings',
      (tester) async {
    await _withGif(tester, cache, (host) async {
      final frames = cache.streams(_first).single;
      host.changeTicker(false);
      await tester.pump();
      expect(frames.listeners, isEmpty);
      await host.settings.setPauseHiddenGifs(false);
      await tester.pump();
      expect(frames.listeners, hasLength(1));
      await host.settings.setPauseHiddenGifs(true);
      await tester.pump();
      await tester.pump();
      expect(frames.listeners, isEmpty);
      expect(host.settings.settings.powerSaving.custom.pauseIdleImageCleanup, isFalse);
      expect(host.settings.settings.powerSaving.custom.pauseHiddenRadioIndicator, isFalse);
      expect(host.settings.settings.powerSaving.custom.batteryIntervalSeconds, 120);
      expect(host.settings.settings.powerSaving.custom.gpsIntervalSeconds, 60);
    }, powerSaving: _onlyGifs);
  });

  testWidgets('offscreen GIF stops frames and resumes without another source',
      (tester) async {
    await _withGif(tester, cache, (host) async {
      final frames = cache.streams(_first).single;
      host.changeOffset(1200);
      await tester.pump();
      await tester.pump();
      final viewport = tester.getRect(find.byKey(const ValueKey('gif-viewport')));
      expect(tester.getRect(find.byType(GifMessage)).overlaps(viewport), isFalse);
      expect(frames.listeners, isEmpty);
      expect(find.byType(GifMessage), findsOneWidget);
      expect(find.byIcon(Icons.pause), findsNothing);
      frames.emit(8, 4);
      await tester.pump();
      expect(_displayed(tester).image!.width, 4);
      host.changeOffset(0);
      await tester.pump();
      await tester.pump();
      expect(tester.getRect(find.byType(GifMessage)).overlaps(viewport), isTrue);
      expect(frames.listeners, hasLength(1));
      expect(_displayed(tester).image!.width, 8);
      expect(cache.streams(_first), hasLength(1));
    }, powerSaving: _onlyGifs);
  });

  testWidgets('covered GIF survives cache eviction and releases its handle on dispose',
      (tester) async {
    late _Frames frames;
    await _withGif(tester, cache, (host) async {
      frames = cache.streams(_first).single;
      final pushed = host.navigator.currentState!.push<void>(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('cover')),
      ));
      await tester.pump();
      expect(frames.listeners, isEmpty);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(GifMessage, skipOffstage: false), findsOneWidget);
      cache.evict(gifImageProvider(_first));
      await tester.pump();
      expect(frames.disposed, isFalse);
      host.navigator.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      await pushed;
      expect(frames.listeners, hasLength(1));
      expect(cache.streams(_first), hasLength(1));
      host.changeTicker(false);
      await tester.pump();
      expect(frames.listeners, isEmpty);
    }, powerSaving: _onlyGifs);
    expect(frames.listeners, isEmpty);
    expect(frames.disposed, isTrue);
  });

  testWidgets('inactive and paused GIF releases its listener and resumes',
      (tester) async {
    await _withGif(tester, cache, (_) async {
      final previous = binding.lifecycleState ?? AppLifecycleState.resumed;
      final frames = cache.streams(_first).single;
      try {
        binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        expect(frames.listeners, isEmpty);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        expect(frames.listeners, isEmpty);
        frames.emit(8, 4);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();
        await tester.pump();
        expect(frames.listeners, hasLength(1));
        expect(_displayed(tester).image!.width, 8);
      } finally {
        binding.handleAppLifecycleStateChanged(previous);
        await tester.pump();
      }
    }, powerSaving: _onlyGifs);
  });

  testWidgets('native inactivity pauses GIF even when Flutter remains resumed',
      (tester) async {
    final previous = binding.lifecycleState ?? AppLifecycleState.resumed;
    final messenger = binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(IosPresentationBridge.platformChannel,
        (call) async => call.method == 'watch' ? {
          'schema': 1, 'enabled': false, 'active': false, 'revision': 0,
        } : null);
    final bridge = IosPresentationBridge(onPresentationChanged: (_) {});
    try {
      // Test binding начинает сценарий с null; проверяем именно native-only паузу.
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _withGif(tester, cache, (_) async {
        final frames = cache.streams(_first).single;
        await bridge.start();
        expect(binding.lifecycleState, AppLifecycleState.resumed);
        expect(frames.listeners, isEmpty);
        frames.emit(8, 4);
        await bridge.dispose();
        await tester.pump();
        expect(binding.lifecycleState, AppLifecycleState.resumed);
        expect(frames.listeners, hasLength(1));
        expect(_displayed(tester).image!.width, 8);
      }, powerSaving: _onlyGifs);
    } finally {
      await bridge.dispose();
      messenger.setMockMethodCallHandler(IosPresentationBridge.platformChannel, null);
      binding.handleAppLifecycleStateChanged(previous);
      await tester.pump();
    }
  });

  testWidgets('hidden initial load and URL change wait for visibility',
      (tester) async {
    await _withGif(tester, cache, (host) async {
      expect(cache.created, isEmpty);
      host.changeUrl(_second);
      await tester.pump();
      expect(cache.created, isEmpty);
      host.changeTicker(true);
      await tester.pump();
      await tester.pump();
      expect(cache.created.containsKey(gifImageProvider(_first)), isFalse);
      expect(cache.streams(_second), hasLength(1));
      expect(_displayed(tester).image!.width, 3);
      final oldListener = cache.streams(_second).single.listeners.single;
      host.changeUrl(_first);
      await tester.pump();
      oldListener.onError!(StateError('Stale synthetic GIF error'), StackTrace.empty);
      oldListener.onImage(ImageInfo(image: _displayed(tester).image!.clone()), false);
      await tester.pump();
      expect(_displayed(tester).image!.width, 4);
      expect(find.text("Can't load GIF\nTap to retry"), findsNothing);
    }, powerSaving: _onlyGifs, initialTicker: false);
  });

  testWidgets('retry remains available with GIF power saving enabled',
      (tester) async {
    await _withGif(tester, cache, (_) async {
      cache.streams(_first).single.fail();
      await tester.pump();
      expect(find.text("Can't load GIF\nTap to retry"), findsOneWidget);
      cache.sources[gifImageProvider(_first)] = () => _Frames()..emit(8, 4);
      await tester.tap(find.byType(GifMessage));
      await tester.pump();
      expect(cache.streams(_first), hasLength(2));
      expect(cache.streams(_first).last.listeners, hasLength(1));
      expect(_displayed(tester).image!.width, 8);
    }, powerSaving: _onlyGifs);
  });

  testWidgets('baseline: GIF loading becomes a frame and later frames update',
      (tester) async {
    cache.sources[gifImageProvider(_first)] = _Frames.new;
    await _withGif(tester, cache, (_) async {
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final frames = cache.streams(_first).single;
      frames.emit(4, 2);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(_displayed(tester).image!.width, 4);
      expect(_displayed(tester).image!.height, 2);
      expect(frames.listeners, hasLength(1));
      frames.emit(8, 4);
      await tester.pump();
      expect(_displayed(tester).image!.width, 8);
      expect(cache.streams(_first), hasLength(1));
    });
  });

  testWidgets('baseline: manual pause keeps its frame and resume catches up',
      (tester) async {
    late _Frames frames;
    await _withGif(tester, cache, (_) async {
      frames = cache.streams(_first).single;
      await tester.tap(find.byType(GifMessage));
      await tester.pump();
      expect(frames.listeners, isEmpty);
      expect(find.byIcon(Icons.pause), findsOneWidget);
      frames.emit(8, 4);
      await tester.pump();
      expect(_displayed(tester).image!.width, 4);
      await tester.tap(find.byType(GifMessage));
      await tester.pump();
      expect(frames.listeners, hasLength(1));
      expect(find.byIcon(Icons.pause), findsNothing);
      expect(_displayed(tester).image!.width, 8);
      expect(cache.streams(_first), hasLength(1));
    });
    expect(frames.listeners, isEmpty);
  });

  testWidgets('baseline: changing URL replaces the stream and resets manual pause',
      (tester) async {
    await _withGif(tester, cache, (host) async {
      final old = cache.streams(_first).single;
      host.changeUrl(_first);
      await tester.pump();
      expect(cache.streams(_first), hasLength(1));
      expect(old.listeners, hasLength(1));
      await tester.tap(find.byType(GifMessage));
      await tester.pump();
      host.changeUrl(_second);
      await tester.pump();
      expect(old.listeners, isEmpty);
      expect(cache.streams(_second).single.listeners, hasLength(1));
      expect(find.byIcon(Icons.pause), findsNothing);
      expect(_displayed(tester).image!.width, 3);
      expect(_displayed(tester).image!.height, 6);
    });
  });

  testWidgets('baseline: failed GIF retries through cache eviction', (tester) async {
    await _withGif(tester, cache, (_) async {
      final old = cache.streams(_first).single;
      old.fail();
      await tester.pump();
      expect(find.text("Can't load GIF\nTap to retry"), findsOneWidget);
      expect(cache.evicted, isEmpty);
      cache.sources[gifImageProvider(_first)] = () => _Frames()..emit(8, 4);
      await tester.tap(find.byType(GifMessage));
      await tester.pump();
      expect(cache.evicted, [gifImageProvider(_first)]);
      expect(cache.streams(_first), hasLength(2));
      expect(old.listeners, isEmpty);
      expect(cache.streams(_first).last.listeners, hasLength(1));
      expect(_displayed(tester).image!.width, 8);
      expect(find.text("Can't load GIF\nTap to retry"), findsNothing);
    });
  });

  testWidgets('baseline: GIF keeps its listener when TickerMode is disabled',
      (tester) async {
    await _withGif(tester, cache, (host) async {
      final frames = cache.streams(_first).single;
      host.changeTicker(false);
      await tester.pump();
      expect(frames.listeners, hasLength(1));
      frames.emit(8, 4);
      await tester.pump();
      expect(_displayed(tester).image!.width, 8);
      host.changeTicker(true);
      await tester.pump();
      expect(frames.listeners, hasLength(1));
      expect(cache.streams(_first), hasLength(1));
    });
  });

  testWidgets('baseline: covered GIF keeps its listener until widget disposal',
      (tester) async {
    late _Frames frames;
    await _withGif(tester, cache, (host) async {
      frames = cache.streams(_first).single;
      final pushed = host.navigator.currentState!.push<void>(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('cover')),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('cover'), findsOneWidget);
      expect(find.byType(GifMessage, skipOffstage: false), findsOneWidget);
      expect(frames.listeners, hasLength(1));
      frames.emit(8, 4);
      await tester.pump();
      host.navigator.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await pushed;
      expect(_displayed(tester).image!.width, 8);
      expect(frames.listeners, hasLength(1));
    });
    expect(frames.listeners, isEmpty);
  });

  testWidgets('baseline: offscreen GIF keeps its listener while mounted',
      (tester) async {
    await _withGif(tester, cache, (host) async {
      final frames = cache.streams(_first).single;
      host.changeOffset(1200);
      await tester.pump();
      final screenHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
      expect(tester.getRect(find.byType(GifMessage)).top, greaterThan(screenHeight));
      expect(frames.listeners, hasLength(1));
      frames.emit(8, 4);
      await tester.pump();
      host.changeOffset(0);
      await tester.pump();
      expect(_displayed(tester).image!.width, 8);
      expect(cache.streams(_first), hasLength(1));
    });
  });

  testWidgets('baseline: inactive GIF keeps its listener until widget disposal',
      (tester) async {
    final previous = binding.lifecycleState ?? AppLifecycleState.resumed;
    late _Frames frames;
    try {
      await _withGif(tester, cache, (_) async {
        frames = cache.streams(_first).single;
        binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        expect(frames.listeners, hasLength(1));
        binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        expect(frames.listeners, hasLength(1));
        frames.emit(8, 4);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();
        expect(_displayed(tester).image!.width, 8);
        expect(cache.streams(_first), hasLength(1));
      });
      expect(frames.listeners, isEmpty);
    } finally {
      binding.handleAppLifecycleStateChanged(previous);
      await tester.pump();
    }
  });
}
