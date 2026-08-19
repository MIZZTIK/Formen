'use strict';

// Los tokens de Kommo rotan: el access_token dura ~24h y cada refresh
// devuelve un refresh_token nuevo. Persistimos el par vigente en disco
// para sobrevivir reinicios del servicio.

const fs = require('fs');
const path = require('path');
const { config } = require('../config');

const FILE = path.join(__dirname, '..', '..', 'data', 'kommo-tokens.json');

function load() {
  try {
    return JSON.parse(fs.readFileSync(FILE, 'utf8'));
  } catch {
    // Fallback: lo que haya en .env (primer arranque tras `kommo:auth`).
    return {
      access_token: config.kommo.accessToken || null,
      refresh_token: config.kommo.refreshToken || null,
      expires_at: 0,
    };
  }
}

function save(tokens) {
  fs.mkdirSync(path.dirname(FILE), { recursive: true });
  const withExpiry = {
    access_token: tokens.access_token,
    refresh_token: tokens.refresh_token,
    // expires_in viene en segundos; guardamos el instante absoluto (ms) con margen.
    expires_at: Date.now() + (tokens.expires_in ? tokens.expires_in * 1000 : 0) - 60000,
  };
  fs.writeFileSync(FILE, JSON.stringify(withExpiry, null, 2), 'utf8');
  return withExpiry;
}

module.exports = { load, save, FILE };
