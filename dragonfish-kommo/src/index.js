'use strict';

// Punto de entrada del conector.
//   node src/index.js         -> corre en loop (polling cada POLL_INTERVAL_MS)
//   node src/index.js --once  -> una sola pasada y termina (ideal para probar)

const log = require('./logger');
const { config } = require('./config');
const { runOnce } = require('./sync/salesToKommo');

const ONCE = process.argv.includes('--once');

async function tick() {
  try {
    await runOnce();
  } catch (err) {
    log.error('Pasada de sync falló:', err.message);
  }
}

async function main() {
  log.info(`Conector Dragonfish -> Kommo iniciado. DRY_RUN=${config.dryRun}`);
  if (ONCE) {
    await tick();
    return;
  }
  // Loop sin solapamiento: espera a que termine una pasada antes de agendar la próxima.
  // eslint-disable-next-line no-constant-condition
  while (true) {
    await tick();
    await new Promise((r) => setTimeout(r, config.poll.intervalMs));
  }
}

main().catch((err) => {
  log.error('Fatal:', err);
  process.exit(1);
});
