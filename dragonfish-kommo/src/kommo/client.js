'use strict';

// Cliente Kommo (API v4). Basado en la documentación pública:
//   - OAuth 2.0:      https://developers.kommo.com/docs/oauth-20
//   - Add/patch contacts: https://developers.kommo.com/reference/add-contacts
//   - Add notes:      https://developers.kommo.com/reference/add-notes
//
// Flujo que usamos (Ventas -> Kommo): buscar contacto por teléfono/email/DNI,
// crear o actualizar el contacto, y agregar una nota con el detalle de la venta.

const { config } = require('../config');
const log = require('../logger');
const tokenStore = require('./tokenStore');

class KommoClient {
  constructor() {
    this.base = config.kommo.baseUrl;
    this.tokens = tokenStore.load();
  }

  // ── Auth ───────────────────────────────────────────────────
  async _refreshIfNeeded() {
    if (this.tokens.access_token && Date.now() < (this.tokens.expires_at || 0)) return;
    if (!this.tokens.refresh_token) {
      throw new Error(
        'No hay refresh_token de Kommo. Corré `npm run kommo:auth` con el authorization_code.'
      );
    }
    log.debug('Kommo: refrescando access_token…');
    const res = await fetch(`${this.base}/oauth2/access_token`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        client_id: config.kommo.clientId,
        client_secret: config.kommo.clientSecret,
        grant_type: 'refresh_token',
        refresh_token: this.tokens.refresh_token,
        redirect_uri: config.kommo.redirectUri,
      }),
    });
    if (!res.ok) {
      throw new Error(`Kommo refresh falló (${res.status}): ${await res.text()}`);
    }
    this.tokens = tokenStore.save(await res.json());
    log.info('Kommo: token refrescado OK.');
  }

  async _req(method, pathname, body) {
    await this._refreshIfNeeded();
    const res = await fetch(`${this.base}${pathname}`, {
      method,
      headers: {
        Authorization: `Bearer ${this.tokens.access_token}`,
        'Content-Type': 'application/json',
      },
      body: body ? JSON.stringify(body) : undefined,
    });
    if (res.status === 204) return null; // No Content
    const text = await res.text();
    const data = text ? JSON.parse(text) : null;
    if (!res.ok) {
      throw new Error(`Kommo ${method} ${pathname} -> ${res.status}: ${text}`);
    }
    return data;
  }

  // ── Contactos ──────────────────────────────────────────────
  // Busca por texto libre (Kommo matchea nombre, teléfono, email, etc.).
  async findContact(query) {
    if (!query) return null;
    const q = encodeURIComponent(query);
    const data = await this._req('GET', `/api/v4/contacts?query=${q}&limit=1`);
    return data?._embedded?.contacts?.[0] || null;
  }

  // Devuelve el primer contacto que matchee alguno de los identificadores.
  async findContactByAny({ dni, telefono, email }) {
    for (const q of [dni, telefono, email].filter(Boolean)) {
      const c = await this.findContact(q);
      if (c) return c;
    }
    return null;
  }

  async createContact(contact) {
    const data = await this._req('POST', '/api/v4/contacts', [contact]);
    return data?._embedded?.contacts?.[0] || null;
  }

  async updateContact(id, patch) {
    return this._req('PATCH', `/api/v4/contacts/${id}`, patch);
  }

  // ── Notas ──────────────────────────────────────────────────
  // entityType: 'contacts' | 'leads'
  async addNote(entityType, entityId, text) {
    const body = [
      { entity_id: entityId, note_type: 'common', params: { text } },
    ];
    return this._req('POST', `/api/v4/${entityType}/notes`, body);
  }
}

module.exports = { KommoClient };
