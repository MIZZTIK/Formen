'use strict';

// Punto de entrada del conector.
//   node src/index.js          -> corre en loop (polling cada POLL_INTERVAL_MS)
//   node src/index.js --once   -> una sola pasada y termina (ideal para probar)
//   node src/index.js --medir  -> imprime el reporte de apareo y termina

const log = require('./logger');
const { config } = require('./config');
const { runOnce } = require('./sync/salesToKommo');
const reporte = require('./reporte');

const ONCE = process.argv.includes('--once');
const MEDIR = process.argv.includes('--medir');

async function tick() {
  try {
    await runOnce();
  } catch (err) {
    log.error('Pasada de sync falló:', err.message);
  }
}

async function main() {
  if (MEDIR) {
    reporte.imprimirResumen();
    return;
  }
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
