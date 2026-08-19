'use strict';

// Cursor de polling persistido en un JSON simple (sin dependencias nativas).
// Guarda hasta dónde se procesó para no reprocesar ni duplicar ventas en Kommo.
//
//   {
//     "lastFecha": "2026-07-07T12:00:00",  // marca temporal del último comprobante procesado
//     "processedIds": ["FAC-0001-00012345"] // ventana reciente de IDs ya enviados (anti-duplicado)
//   }

const fs = require('fs');
const path = require('path');

const FILE = path.join(__dirname, '..', 'data', 'cursor.json');
const MAX_PROCESSED = 500; // ventana de dedupe

function load() {
  try {
    return JSON.parse(fs.readFileSync(FILE, 'utf8'));
  } catch {
    return { lastFecha: null, processedIds: [] };
  }
}

function save(state) {
  fs.mkdirSync(path.dirname(FILE), { recursive: true });
  fs.writeFileSync(FILE, JSON.stringify(state, null, 2), 'utf8');
}

class Cursor {
  constructor() {
    this.state = load();
  }

  get lastFecha() {
    return this.state.lastFecha;
  }

  seen(id) {
    return this.state.processedIds.includes(id);
  }

  markProcessed(id, fecha) {
    if (!this.state.processedIds.includes(id)) {
      this.state.processedIds.push(id);
      if (this.state.processedIds.length > MAX_PROCESSED) {
        this.state.processedIds = this.state.processedIds.slice(-MAX_PROCESSED);
      }
    }
    if (fecha && (!this.state.lastFecha || fecha > this.state.lastFecha)) {
      this.state.lastFecha = fecha;
    }
    save(this.state);
  }
}

module.exports = { Cursor };
