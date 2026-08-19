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

function bool(name, def = false) {
  const v = opt(name);
  if (v === '') return def;
  return v.toLowerCase() === 'true';
}

const config = {
  dragonfish: {
    sql: {
      server: opt('DF_SQL_SERVER', 'localhost'),
      instance: opt('DF_SQL_INSTANCE', 'ZOOLOGIC'),
      port: Number(opt('DF_SQL_PORT', '')) || null,
      database: opt('DF_SQL_DATABASE', 'DRAGONFISH_FORMEN'),
      schema: opt('DF_SQL_SCHEMA', 'ZooLogic'),
      user: opt('DF_SQL_USER'),
      password: opt('DF_SQL_PASSWORD'),
      encrypt: bool('DF_SQL_ENCRYPT', false),
      trustServerCertificate: bool('DF_SQL_TRUST_CERT', true),
    },
    // FACTTIPO que cuentan como venta. 2 = el grueso (10.883 de ~11.800).
    tiposVenta: list('DF_TIPOS_VENTA').length ? list('DF_TIPOS_VENTA') : ['2'],
  },

  kommo: {
    subdomain: opt('KOMMO_SUBDOMAIN'),
    // Token de larga duración (integración privada). Si está, se usa directo y
    // no hace falta el flujo OAuth.
    accessToken: opt('KOMMO_ACCESS_TOKEN'),
    clientId: opt('KOMMO_CLIENT_ID'),
    clientSecret: opt('KOMMO_CLIENT_SECRET'),
    redirectUri: opt('KOMMO_REDIRECT_URI'),
    refreshToken: opt('KOMMO_REFRESH_TOKEN'),
    fieldIdDni: opt('KOMMO_FIELD_ID_DNI'),
    fieldIdTelefono: opt('KOMMO_FIELD_ID_TELEFONO', '326778'),
    fieldIdEmail: opt('KOMMO_FIELD_ID_EMAIL', '326780'),
    get baseUrl() {
      return `https://${this.subdomain}.kommo.com`;
    },
  },

  // ── Apareo venta <-> contacto del iPad ──
  // El vendedor pasa el iPad DESPUÉS de cobrar, así que la ventana es
  // asimétrica: se buscan contactos creados entre la venta y N minutos después.
  match: {
    ventanaMin: Number(opt('MATCH_VENTANA_MIN', '10')),
    // Cuánto esperar antes de evaluar una venta, para darle tiempo al vendedor
    // a cargar el contacto. Tiene que ser > ventanaMin.
    esperaMin: Number(opt('MATCH_ESPERA_MIN', '15')),
    // Usuario de Kommo con el que está logueado el iPad. Los contactos que crea
    // aparecen como created_by = este id.
    ipadUserId: Number(opt('KOMMO_IPAD_USER_ID', '15483335')),
  },

  poll: {
    intervalMs: Number(opt('POLL_INTERVAL_MS', '60000')),
  },
  logLevel: opt('LOG_LEVEL', 'info'),
  dryRun: opt('DRY_RUN', 'true').toLowerCase() !== 'false',
};

module.exports = { config, req, opt, list, bool };
