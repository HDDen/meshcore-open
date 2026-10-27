/* Демо использует только публичный API MCOtxt; весь пользовательский вывод — textContent/value. */
(function () {
  'use strict';
  const codec = window.MCOtxt;
  const byId = id => document.getElementById(id);
  const languageNames = {en: 'English', ru: 'Russian', fr: 'French', de: 'German',
    it: 'Italian', uk: 'Ukrainian', be: 'Belarusian'};
  let lastEncoding = null;
  let displayed = null;

  codec.getLanguages().forEach(language => {
    const label = document.createElement('label'), checkbox = document.createElement('input');
    checkbox.type = 'checkbox'; checkbox.value = language.code;
    checkbox.checked = language.code === 'ru' || language.code === 'en';
    checkbox.title = languageNames[language.code] || language.code;
    label.appendChild(checkbox); label.appendChild(document.createTextNode(language.code.toUpperCase()));
    byId('languageChoices').appendChild(label);
  });
  function report(id, message) { byId(id).textContent = message; byId(id).hidden = !message; }
  function requireOk(result) {
    if (!result.ok) { throw new Error(result.error.code + ': ' + result.error.message); }
    return result;
  }
  function json(result) {
    return JSON.stringify(result, (key, value) => value instanceof Uint8Array
      ? {type: 'Uint8Array', hex: codec.toHex(value), byteLength: value.byteLength} : value, 2);
  }
  function percent(value) { return value === null ? '—' : value.toFixed(1) + '%'; }
  function numeric(id, options, key) {
    const value = byId(id).value.trim();
    if (value !== '') { options[key] = Number(value); }
  }
  function displayData(result) {
    displayed = result;
    byId('encodedData').value = typeof result.data === 'string' ? result.data : codec.toHex(result.data);
  }

  byId('encodeForm').addEventListener('submit', event => {
    event.preventDefault(); report('encodeError', ''); report('transportStatus', '');
    try {
      const options = {
        languages: Array.from(byId('languageChoices').querySelectorAll('input:checked'), input => input.value),
        base91: byId('useBase91').checked
      };
      const frameOnly = byId('encodeFormat').value === 'frame';
      if (!frameOnly) {
        options.senderName = byId('senderName').value;
        numeric('timestamp', options, 'timestamp');
        const author = byId('replyAuthor').value;
        // Пустой автор с заданным timestamp тоже допустим по протоколу.
        if (author !== '' || byId('replyTimestamp').value !== '') { options.replyAuthorName = author; }
        numeric('replyTimestamp', options, 'replyTimestamp');
      }
      const text = byId('sourceText').value;
      const result = requireOk(frameOnly ? codec.encodeFrame(text, options) : codec.encode(text, options));
      lastEncoding = result; displayData(result);
      byId('originalSize').textContent = result.originalBytes;
      byId('encodedSize').textContent = result.encodedBytes;
      byId('encodedType').textContent = result.type === 'base91' ? 'Base91 bytes' : 'binary bytes';
      byId('saving').textContent = percent(result.compressionPercent);
      const frameSize = frameOnly ? result.binaryBytes : result.textEncodedBytes;
      const framePercent = frameOnly && result.originalBytes
        ? 100 * (1 - frameSize / result.originalBytes) : result.textCompressionPercent;
      byId('textOnlyStats').textContent = 'Text frame only: ' + frameSize + ' bytes; space saved: ' +
        percent(framePercent === undefined ? null : framePercent) + '. Text languages: ' + (result.textLanguages || result.languages).join(', ');
      byId('encodeObject').textContent = json(result);
      byId('showMct').disabled = frameOnly; byId('showEnvelope').disabled = frameOnly;
      byId('encodedResult').hidden = false;
    } catch (error) {
      lastEncoding = null; displayed = null; byId('encodedResult').hidden = true;
      report('encodeError', error.message);
    }
  });

  byId('toDecoder').addEventListener('click', () => {
    if (!displayed) { return; }
    byId('decodeData').value = typeof displayed.data === 'string' ? displayed.data : codec.toHex(displayed.data);
    byId('decodeType').value = displayed.type === 'base91' ? 'base91' : 'hex';
    byId('decodeFormat').value = displayed.format;
    byId('decodeForm').dispatchEvent(new Event('submit', {cancelable: true}));
  });
  byId('showMct').addEventListener('click', () => {
    if (!lastEncoding) { return; }
    try {
      const data = codec.toTextTransport(lastEncoding);
      displayData({data: data, type: 'base91', format: 'mct'});
      report('transportStatus', 'mct: contains 0x31 + body in Base91. String size: ' + data.length + ' bytes. The metrics above refer to the original encode response.');
    } catch (error) { report('transportStatus', error.message); }
  });
  byId('showEnvelope').addEventListener('click', () => {
    if (!lastEncoding) { return; }
    try {
      const envelope = codec.wrapEnvelope(lastEncoding);
      displayData(envelope);
      report('transportStatus', 'Envelope with an empty outer name: ' + envelope.encodedBytes + ' bytes. dataType 0x0120 is set separately. The metrics above refer to the encode response.');
    } catch (error) { report('transportStatus', error.message); }
  });
  byId('copyData').addEventListener('click', () => {
    const text = byId('encodedData').value;
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(() => report('transportStatus', 'Data copied.'), () => {
        byId('encodedData').focus(); byId('encodedData').select(); report('transportStatus', 'Press Ctrl+C / ⌘C to copy.');
      });
    } else {
      byId('encodedData').focus(); byId('encodedData').select(); report('transportStatus', 'Press Ctrl+C / ⌘C to copy.');
    }
  });
  byId('decodeForm').addEventListener('submit', event => {
    event.preventDefault(); report('decodeError', '');
    try {
      const text = byId('decodeData').value.trim();
      const mct = text.indexOf('mct:') === 0;
      const input = {data: mct || byId('decodeType').value === 'base91' ? text : codec.fromHex(text),
        format: byId('decodeFormat').value};
      if (!mct) { input.type = byId('decodeType').value === 'base91' ? 'base91' : 'binary'; }
      numeric('inheritedTimestamp', input, 'inheritedTimestamp');
      const result = requireOk(codec.decode(input));
      byId('decodedText').value = result.text;
      byId('decodedLanguages').textContent = 'Format: ' + result.format + '; languages: ' + (result.languages.join(', ') || 'no language tables');
      byId('decodeObject').textContent = json(result); byId('decodedResult').hidden = false;
    } catch (error) { byId('decodedResult').hidden = true; report('decodeError', error.message); }
  });
}());
