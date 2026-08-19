'use strict';

// Intercambia el `authorization_code` de Kommo por access/refresh token y los
// deja guardados en data/kommo-tokens.json.
//
// Uso:
//   node scripts/kommo-auth.js <AUTHORIZATION_CODE>
//
// El authorization_code se obtiene al instalar/autorizar la integración privada
// en Kommo (Ajustes > Integraciones). ¡Dura solo 20 minutos!

const { config } = require('../src/config');
const tokenStore = require('../src/kommo/tokenStore');

async function main() {
  const code = process.argv[2];
  if (!code) {
    console.error('Falta el authorization_code.\nUso: node scripts/kommo-auth.js <CODE>');
    process.exit(1);
  }
  if (!config.kommo.clientId || !config.kommo.clientSecret || !config.kommo.subdomain) {
    console.error('Faltan KOMMO_SUBDOMAIN / KOMMO_CLIENT_ID / KOMMO_CLIENT_SECRET en .env');
    process.exit(1);
  }

  const res = await fetch(`${config.kommo.baseUrl}/oauth2/access_token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      client_id: config.kommo.clientId,
      client_secret: config.kommo.clientSecret,
      grant_type: 'authorization_code',
      code,
      redirect_uri: config.kommo.redirectUri,
    }),
  });

  const text = await res.text();
  if (!res.ok) {
    console.error(`Kommo devolvió ${res.status}: ${text}`);
    process.exit(1);
  }

  const saved = tokenStore.save(JSON.parse(text));
  console.log('✅ Tokens de Kommo guardados en data/kommo-tokens.json');
  console.log(`   access_token vence: ${new Date(saved.expires_at).toLocaleString('es-AR')}`);
}

main().catch((e) => {
  console.error('Error:', e.message);
  process.exit(1);
});
