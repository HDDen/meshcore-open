'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');

function loadMcoImg() {
  const context = {
    console,
    Uint8Array,
    ArrayBuffer,
    DataView,
    TextEncoder,
    TextDecoder,
    setTimeout,
    clearTimeout,
  };
  context.globalThis = context;
  context.window = context;
  vm.createContext(context);
  const source = fs.readFileSync(
    path.join(__dirname, '..', 'mcoimg-codec.global.js'),
    'utf8',
  );
  vm.runInContext(source, context, {
    filename: 'mcoimg-codec.global.js',
  });
  return context.MCOImg;
}

module.exports = { loadMcoImg };
