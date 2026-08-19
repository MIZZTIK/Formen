'use strict';

// Lectura de ventas desde la base de Dragonfish (SQL Server local).
//
// Reemplaza al cliente REST (`client.js`): el servicio REST de Zoo Logic NO está
// instalado en Formen — ver README > "PROYECTO FRENADO". Acá solo hacemos SELECT;
// el conector nunca escribe en Dragonfish.
//
// Mapeo relevado el 19/8/2026 sobre ZooLogic.COMPROBANTEV:
//   CODIGO             id estable del comprobante (dedupe)
//   FALTAFW + HALTAFW  fecha y hora de ALTA en el sistema -> el cursor y el apareo
//   FFCH               fecha del comprobante
//   FTOTAL             total
//   FLETRA/FPTOVEN/FNUMCOMP  numeración
//   ANULADO            hay que filtrar los anulados

const sql = require('mssql');
const { config } = require('../config');
const log = require('../logger');

// El timestamp real de la venta se arma concatenando la fecha (datetime a las
// 00:00) con la hora (varchar 'HH:mm:ss'). Se usa en el WHERE y en el ORDER BY.
const TS = "CAST(CONVERT(varchar(10),FALTAFW,120)+' '+HALTAFW AS datetime)";

class DragonfishSqlClient {
  constructor() {
    const c = config.dragonfish.sql;
    // El esquema va interpolado (no admite parámetro), así que lo validamos.
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(c.schema)) {
      throw new Error(`Nombre de esquema inválido: ${c.schema}`);
    }
    this.schema = c.schema;
    this.cfg = {
      server: c.server,
      database: c.database,
      user: c.user,
      password: c.password,
      port: c.port || undefined,
      options: {
        instanceName: c.instance || undefined,
        encrypt: c.encrypt,
        trustServerCertificate: c.trustServerCertificate,
      },
      requestTimeout: 30000,
    };
  }

  async connect() {
    if (!this.pool) {
      this.pool = await new sql.ConnectionPool(this.cfg).connect();
      log.debug(`Dragonfish SQL: conectado a ${this.cfg.server}/${this.cfg.database}`);
    }
    return this.pool;
  }

  async close() {
    if (this.pool) {
      await this.pool.close();
      this.pool = null;
    }
  }

  // Ventas dadas de alta DESPUÉS de `desde` (Date), en orden cronológico.
  // `desde` null = solo las de hoy, para no arrastrar años de historia en el
  // primer arranque.
  async getVentasDesde(desde, limite = 200) {
    const pool = await this.connect();
    const req = pool.request();
    req.input('desde', sql.DateTime, desde || startOfToday());
    req.input('limite', sql.Int, limite);

    const tipos = config.dragonfish.tiposVenta;
    let filtroTipo = '';
    if (tipos.length) {
      const params = tipos.map((t, i) => {
        req.input(`tipo${i}`, sql.Int, Number(t));
        return `@tipo${i}`;
      });
      filtroTipo = ` AND FACTTIPO IN (${params.join(',')})`;
    }

    const q = `
      SELECT TOP (@limite)
        CODIGO, FFCH, FALTAFW, HALTAFW, FTOTAL,
        FACTTIPO, FLETRA, FPTOVEN, FNUMCOMP,
        FPERSON, FCLIENTE, FCUIT, EMAIL,
        ${TS} AS TS
      FROM [${this.schema}].[COMPROBANTEV]
      WHERE ANULADO = 0 ${filtroTipo}
        AND ${TS} > @desde
      ORDER BY ${TS} ASC`;

    const res = await req.query(q);
    return res.recordset.map(normalizarVenta);
  }
}

function startOfToday() {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  return d;
}

// Aísla al resto del código de los nombres crudos de Dragonfish.
function normalizarVenta(r) {
  const letra = (r.FLETRA || '').trim();
  const pto = r.FPTOVEN != null ? String(r.FPTOVEN).padStart(4, '0') : '????';
  const nro = r.FNUMCOMP != null ? String(r.FNUMCOMP).padStart(8, '0') : '????????';
  return {
    // CODIGO es char(38): viene con padding de espacios.
    id: String(r.CODIGO || '').trim(),
    comprobante: `${letra} ${pto}-${nro}`.trim(),
    tipo: r.FACTTIPO,
    // Momento del alta: es el que se compara contra la creación del contacto.
    ts: r.TS instanceof Date ? r.TS : new Date(r.TS),
    fecha: r.FFCH,
    total: r.FTOTAL != null ? Number(r.FTOTAL) : null,
    // Casi siempre 0000000001 (consumidor final); se guarda por si algún día sirve.
    codigoCliente: String(r.FPERSON || '').trim() || null,
    cliente: {
      nombre: (r.FCLIENTE || '').trim() || null,
      documento: (r.FCUIT || '').trim() || null,
      email: (r.EMAIL || '').trim() || null,
    },
  };
}

module.exports = { DragonfishSqlClient };
