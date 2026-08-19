'use strict';

require('dotenv').config();

function req(name) {
  const v = process.env[name];
  if (v === undefined || v === '') {
    throw new Error(`Falta la variable de entorno ${name} (ver .env.example)`);
  }
  return v;
}

function opt(name, def = '') {
  const v = process.env[name];
  return v === undefined || v === '' ? def : v;
}

function list(name) {
  return opt(name)
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
}

const config = {
  dragonfish: {
    baseUrl: opt('DF_BASE_URL', 'http://localhost:8009').replace(/\/$/, ''),
    idCliente: opt('DF_ID_CLIENTE'),
    token: opt('DF_TOKEN'),
    baseDeDatos: opt('DF_BASE_DE_DATOS'),
    tiposVenta: list('DF_TIPOS_VENTA').length ? list('DF_TIPOS_VENTA') : ['FAC'],
  },
  kommo: {
    subdomain: opt('KOMMO_SUBDOMAIN'),
    clientId: opt('KOMMO_CLIENT_ID'),
    clientSecret: opt('KOMMO_CLIENT_SECRET'),
    redirectUri: opt('KOMMO_REDIRECT_URI'),
    accessToken: opt('KOMMO_ACCESS_TOKEN'),
    refreshToken: opt('KOMMO_REFRESH_TOKEN'),
    fieldIdDni: opt('KOMMO_FIELD_ID_DNI'),
    fieldIdTelefono: opt('KOMMO_FIELD_ID_TELEFONO'),
    fieldIdEmail: opt('KOMMO_FIELD_ID_EMAIL'),
    get baseUrl() {
      return `https://${this.subdomain}.kommo.com`;
    },
  },
  poll: {
    intervalMs: Number(opt('POLL_INTERVAL_MS', '60000')),
  },
  logLevel: opt('LOG_LEVEL', 'info'),
  dryRun: opt('DRY_RUN', 'true').toLowerCase() !== 'false',
};

module.exports = { config, req, opt, list };
