# MCO Image Codec for Vanilla JS

This folder contains a dependency-free vanilla JS port of the Flutter
`MCOImageCodec`.

- `mcoimg-codec.global.js` is the browser-global build for plain `<script>` usage.
- `demo.html` is a small browser demo with drawing tools, image import,
  encoding, decoding, and rendering.

## Usage

```html
<script src="./mcoimg-codec.global.js"></script>
<script>
const {
  MCOImageCodec,
  PaletteProfile,
  drawMCOImage,
} = window.MCOImg;

const codec = new MCOImageCodec();

const encoded = codec.encode({
  width: 11,
  height: 11,
  paletteProfile: PaletteProfile.master8,
  pixels: new Array(11 * 11).fill(0), // palette indexes
});

console.log(encoded.text); // im:...

const decoded = codec.decode(encoded.text);
drawMCOImage(document.querySelector('canvas'), decoded, { scale: 12 });
</script>
```

The image payload uses palette indexes. For example, with `PaletteProfile.master8`,
each pixel must be an integer from `0` to `7`.

The JS port matches the current Flutter codec format: version 1 encoding,
version 0/1 decoding, bounds-cropped payloads, multi-region payloads, and
candidate diagnostics through `codec.debugEncode(image)`.

## Demo

Open `demo.html` in a browser. The demo uses the browser-global build, so it can
be opened directly from `file://` without ES module import restrictions.
