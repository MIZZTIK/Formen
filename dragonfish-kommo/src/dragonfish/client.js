'use strict';

// ⚠️  A CONFIRMAR CONTRA LA INSTALACIÓN DE FORMEN  ⚠️
// La documentación del servicio REST de Dragonfish (Zoo Logic) NO es pública
// (se pide a soporteapi@zoologic.com.ar / Campus). Este cliente usa la FORMA
// TÍPICA del servicio; los nombres exactos de headers, rutas y campos pueden
// variar según la versión instalada. Los puntos a verificar están marcados
// con TODO(df). Una vez confirmados, ajustar acá y borrar los avisos.

const { config } = require('../config');
const log = require('../logger');

class DragonfishClient {
  constructor() {
    this.base = config.dragonfish.baseUrl;
  }

  _headers() {
    // TODO(df): confirmar los nombres exactos de estos headers.
    return {
      'Content-Type': 'application/json',
      Authorization: config.dragonfish.token,
      IdCliente: config.dragonfish.idCliente,
      BaseDeDatos: config.dragonfish.baseDeDatos,
    };
  }

  async _get(pathname, query = {}) {
    const qs = new URLSearchParams(query).toString();
    const url = `${this.base}${pathname}${qs ? `?${qs}` : ''}`;
    log.debug('Dragonfish GET', url);
    const res = await fetch(url, { headers: this._headers() });
    const text = await res.text();
    if (!res.ok) {
      throw new Error(`Dragonfish GET ${pathname} -> ${res.status}: ${text}`);
    }
    return text ? JSON.parse(text) : null;
  }

  // Trae comprobantes de venta desde una fecha (o todos los recientes).
  // TODO(df): confirmar ruta real (p.ej. /api.Dragonfish/Comprobante), el
  // parámetro de filtro por fecha y por tipo, y la forma de la respuesta.
  async getVentasDesde({ desde, tipos }) {
    const results = [];
    for (const tipo of tipos) {
      const data = await this._get('/api.Dragonfish/Comprobante', {
        Tipo: tipo,
        ...(desde ? { FechaDesde: desde } : {}),
      });
      const items = data?.Resultados || data?.Items || data || [];
      for (const raw of items) results.push(this._normalizeVenta(raw, tipo));
    }
    // Orden ascendente por fecha para procesar en orden cronológico.
    return results.sort((a, b) => String(a.fecha).localeCompare(String(b.fecha)));
  }

  // Datos completos del cliente asociado a la venta (si el comprobante solo
  // trae el código). TODO(df): confirmar ruta y campos.
  async getCliente(codigoCliente) {
    if (!codigoCliente) return null;
    const data = await this._get('/api.Dragonfish/Cliente', { Codigo: codigoCliente });
    const raw = data?.Resultados?.[0] || data?.Items?.[0] || data || null;
    return raw ? this._normalizeCliente(raw) : null;
  }

  // ── Normalizadores: aíslan el resto del código de los nombres crudos de DF ──
  // TODO(df): mapear a los nombres de campo REALES que devuelva el servicio.
  _normalizeVenta(raw, tipo) {
    return {
      tipo,
      numero: raw.Numero ?? raw.NroComprobante ?? raw.Comprobante ?? null,
      // ID estable para dedupe en el cursor:
      id: `${tipo}-${raw.Numero ?? raw.NroComprobante ?? raw.Comprobante ?? 'S/N'}`,
      fecha: raw.Fecha ?? raw.FechaComprobante ?? null,
      total: raw.Total ?? raw.ImporteTotal ?? null,
      codigoCliente: raw.CodigoCliente ?? raw.Cliente ?? null,
      // Datos de cliente si vienen embebidos en el comprobante:
      cliente: {
        nombre: raw.RazonSocial ?? raw.NombreCliente ?? null,
        documento: raw.NroDocumento ?? raw.CUIT ?? raw.DNI ?? null,
        telefono: raw.Telefono ?? raw.Celular ?? null,
        email: raw.Email ?? raw.Mail ?? null,
      },
      raw,
    };
  }

  _normalizeCliente(raw) {
    return {
      codigo: raw.Codigo ?? null,
      nombre: raw.RazonSocial ?? raw.Nombre ?? null,
      documento: raw.NroDocumento ?? raw.CUIT ?? raw.DNI ?? null,
      telefono: raw.Telefono ?? raw.Celular ?? null,
      email: raw.Email ?? raw.Mail ?? null,
      raw,
    };
  }
}

module.exports = { DragonfishClient };
