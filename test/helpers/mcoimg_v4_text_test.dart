import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/mcoimg_palette.dart';
import 'package:meshcore_open/helpers/mcoimg_types.dart';
import 'package:meshcore_open/helpers/mcoimg_v4_codec.dart';
import 'package:meshcore_open/helpers/mcoimg_v4_model.dart';

const PaletteProfile _profile = PaletteProfile.master8;
const MCOImageV4Style _style = MCOImageV4Style(strokeColor: 1);

MCOImageV4Document _document(
  List<MCOImageV4Figure> figures, {
  int width = 128,
  int height = 128,
}) {
  return MCOImageV4Document(
    width: width,
    height: height,
    paletteProfile: _profile,
    palette: <int>[
      MCOImagePalette.whiteIndexFor(_profile),
      MCOImagePalette.blackIndexFor(_profile),
    ],
    backgroundColor: 0,
    initialStyle: _style,
    figures: figures,
  );
}

MCOImageV4Text _text({
  required String text,
  int x = 8,
  int y = 8,
  int? width,
  int fontSize = 15,
  MCOImageV4TextAlign align = MCOImageV4TextAlign.left,
}) {
  return MCOImageV4Text(
    origin: MCOImageV4Point(x, y),
    width: width,
    fontSize: fontSize,
    align: align,
    text: text,
    style: _style,
  );
}

({List<MCOImageV4Text> figures, int bytes}) _roundTrip(
  MCOImageV4Document document,
) {
  const codec = MCOImageV4Codec();
  final encoded = codec.encode(document, nonce: 0);
  final decoded = codec.decodeBody(encoded.body);
  return (
    figures: decoded.document.figures.cast<MCOImageV4Text>().toList(),
    bytes: encoded.body.length,
  );
}

void main() {
  group('MCOimg v4 text figure', () {
    test('round-trips a default layer', () {
      final result = _roundTrip(_document(<MCOImageV4Figure>[
        _text(text: 'Hello mesh'),
      ]));
      final figure = result.figures.single;

      expect(figure.text, 'Hello mesh');
      expect(figure.origin, const MCOImageV4Point(8, 8));
      expect(figure.align, MCOImageV4TextAlign.left);
      expect(figure.fontSize, 15);
      // The default width is not transmitted and resolves to the right edge.
      expect(figure.width, isNull);
      expect(figure.resolvedWidth(128), 120);
    });

    test('carries an explicit width, alignment and font size', () {
      final result = _roundTrip(_document(<MCOImageV4Figure>[
        _text(
          text: 'right',
          x: 4,
          y: 40,
          width: 60,
          fontSize: 24,
          align: MCOImageV4TextAlign.right,
        ),
      ]));
      final figure = result.figures.single;

      expect(figure.width, 60);
      expect(figure.fontSize, 24);
      expect(figure.align, MCOImageV4TextAlign.right);
      expect(figure.origin, const MCOImageV4Point(4, 40));
    });

    test('round-trips Cyrillic text with an explicit line break', () {
      const text = 'Привет\nсеть';
      final result = _roundTrip(_document(<MCOImageV4Figure>[
        _text(text: text),
      ]));

      expect(result.figures.single.text, text);
    });

    test('the default font size follows the canvas width', () {
      // 12% of the canvas width, so an average glyph is about 6% of it.
      expect(MCOImageV4Text.defaultFontSizeFor(128), 15);
      expect(MCOImageV4Text.defaultFontSizeFor(64), 7);
      expect(MCOImageV4Text.defaultFontSizeFor(8), 1);
    });

    test('a second layer inherits alignment and size for free', () {
      final inherited = _roundTrip(_document(<MCOImageV4Figure>[
        _text(text: 'one', y: 8, fontSize: 24, align: MCOImageV4TextAlign.center),
        _text(text: 'two', y: 48, fontSize: 24, align: MCOImageV4TextAlign.center),
      ]));
      final changed = _roundTrip(_document(<MCOImageV4Figure>[
        _text(text: 'one', y: 8, fontSize: 24, align: MCOImageV4TextAlign.center),
        _text(text: 'two', y: 48, fontSize: 20, align: MCOImageV4TextAlign.left),
      ]));

      expect(inherited.figures.map((figure) => figure.fontSize), <int>[24, 24]);
      expect(
        inherited.figures.map((figure) => figure.align),
        <MCOImageV4TextAlign>[
          MCOImageV4TextAlign.center,
          MCOImageV4TextAlign.center,
        ],
      );
      expect(changed.figures[1].fontSize, 20);
      expect(changed.figures[1].align, MCOImageV4TextAlign.left);
      // Repeating the state costs nothing; changing it costs the two fields.
      expect(inherited.bytes, lessThan(changed.bytes));
    });

    test('keeps its place in the paint order next to other figures', () {
      const codec = MCOImageV4Codec();
      final document = _document(<MCOImageV4Figure>[
        MCOImageV4Dot(point: const MCOImageV4Point(2, 2), style: _style),
        _text(text: 'label'),
        MCOImageV4Line(
          start: const MCOImageV4Point(0, 100),
          end: const MCOImageV4Point(120, 100),
          style: _style,
        ),
      ]);
      final decoded = codec.decodeBody(codec.encode(document, nonce: 0).body);

      expect(decoded.document.figures[0], isA<MCOImageV4Dot>());
      expect(decoded.document.figures[1], isA<MCOImageV4Text>());
      expect(decoded.document.figures[2], isA<MCOImageV4Line>());
    });

    test('rejects a font size and an area width the canvas cannot hold', () {
      const codec = MCOImageV4Codec();

      expect(
        () => codec.encode(
          _document(<MCOImageV4Figure>[_text(text: 'big', fontSize: 200)]),
        ),
        throwsA(isA<MCOImageInvalidInputException>()),
      );
      expect(
        () => codec.encode(
          _document(<MCOImageV4Figure>[_text(text: 'wide', width: 200)]),
        ),
        throwsA(isA<MCOImageInvalidInputException>()),
      );
    });
  });
}
