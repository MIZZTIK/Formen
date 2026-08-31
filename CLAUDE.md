# CLAUDE.md — Formen

> Archivo de contexto para Claude Code. Leé esto antes de tocar nada.

## Qué hay en este repo

Todo lo de **Formen** (sastrería de autor en Corrientes, marca de Classic SRL). Es un proyecto de
**Boomerang**: no comparte servidores, cuentas ni credenciales con Consultoría Digital.

> ⛔ **El n8n de Formen es `n8n-06ir.srv1605341.hstgr.cloud`** (`187.77.12.160`, alias ssh
> `vps-boomerang`). El `~/.claude/n8n.json` **global apunta a otro**: el de Consultoría Digital
> (`n8n.srv1224751.hstgr.cloud`, `72.60.15.125`). Antes de publicar un workflow, mirá cuál estás
> tocando. El detalle y cómo se despliega acá, en `bot/CLAUDE.md` → *Despliegue*.

| Dónde | Qué es |
|---|---|
| raíz (`index.html`, `styles.css`, `assets/`) | **La landing** `formen.ar`. Estática, en Vercel. Existe para sostener la verificación del WABA ante Meta — los requisitos de más abajo son el motivo de existir del sitio. |
| `pausar.html` + `api/` | **La página interna** donde el local silencia al bot para un número por 24 h, y sus funciones serverless. Es lo único del sitio con backend (Neon). |
| `bot/` | **El asistente de WhatsApp** sobre Kommo + n8n + OpenAI. Empezá por `bot/CLAUDE.md`. |
| `dragonfish-kommo/` | **El conector** que lleva las ventas del local al CRM, con sus parches en `parches/`. Corre en la PC del local, no acá. |

Hasta el 2026-08-28 el bot vivía en un repo aparte (`asistentes-kommo`), junto con el asistente de
AVC. Cuando AVC se mudó a su propio repo quedaron dos repos que eran los dos de Formen, y el
conector partido al medio: el código de un lado y sus parches del otro. Se unificaron ese día.

## La pausa del bot — el orden para ponerla viva (al 2026-08-30)

La rama `pausar-bot` (`pausar.html` + `api/`) está pusheada **y sin mergear**, y el workflow del
repo ya tiene los 5 nodos de la consulta a la lista. Falta la infraestructura. **Los pasos no son
intercambiables:** cada uno necesita el anterior.

| # | Paso | Quién |
|---|---|---|
| 1 | **Vercel:** crear la base Neon (inyecta `DATABASE_URL` sola) y la variable `PAUSA_CLAVE` en **Production Y Preview**. | Martín |
| 2 | Probar `<preview>/pausar.html`: cargar un número y verlo aparecer en la lista. | |
| 3 | **Mergear `pausar-bot` a `main`** y confirmar que `www.formen.ar` sigue cargando igual. | |
| 4 | **n8n:** crear la credencial Header Auth "Formen pausas" → después actualizar el workflow en el lugar (ver `bot/CLAUDE.md` → *Despliegue*). | |
| 5 | **End-to-end:** número en `formen.ar/pausar.html` → mensaje al WhatsApp de Formen → el lead queda en "Lead pausado" y el bot mudo. | |

**El paso 3 es el momento de riesgo del proyecto entero.** Al mergear, el sitio pasa a tener
`package.json` y build donde hoy es 100 % estático — y de ese sitio depende la verificación del
WABA ante Meta. Por eso se prueba en preview antes, y ante cualquier cosa se usa el rollback
instantáneo de Vercel.

**El paso 5 no se puede adelantar al 3.** El nodo `Silenciado en la lista?` apunta a
`https://www.formen.ar/api/silenciado`, que es **producción**: contra el preview no engancha.

⛔ **Nada de esto se puede automatizar desde una sesión.** Ninguna sesión tiene acceso a la cuenta
de Vercel de Boomerang ni SSH al VPS de Boomerang — no hay workaround que buscar. Y la clave la
genera Martín y la carga a mano en los dos lados (`PAUSA_CLAVE` en Vercel y la credencial en n8n):
**el valor no pasa por el chat, ni por el repo, ni por Obsidian.** De la credencial de n8n solo se
necesita el **id**, para escribirlo en el JSON en lugar de `REEMPLAZAR-EN-N8N`.

## Objetivo de la landing

Construir una **landing institucional de UNA sola página** para la marca **Formen** (sastrería de autor para hombre, Corrientes, Argentina), que se publica en el dominio **formen.ar**.

**El objetivo real NO es vender online.** Es cumplir los requisitos que Meta/Facebook exige para **verificar el negocio y la cuenta de WhatsApp Business (WABA)**. Por eso hay datos que son OBLIGATORIOS y no negociables (ver sección "Requisitos Meta — CRÍTICO").

Es una web de presencia/credibilidad, no un e-commerce. Simple, profesional, elegante.

## Sobre la marca

- **Nombre comercial:** Formen (en el logo se ve "FORMEN").
- **Razón social (nombre legal):** Classic SRL.
- **CUIT:** 33-71478866-9.
- **Condición fiscal:** Responsable Inscripto.
- **Rubro:** Sastrería de autor / indumentaria formal masculina. Trajes, sacos, camisas, trajes de novio/ceremonia.
- **Slogan / posicionamiento:** "Sastrería de autor desde 1998."
- **Dirección física (local):** Mendoza 758, Corrientes, Argentina (CP 3400).
- **Instagram:** @formen.ctes (~7.500 seguidores).
- **Email de contacto:** info@formen.ar (o el que corresponda del dominio).
- **Estética:** elegante, masculina, premium. Paleta oscura (negro/grafito) con un acento dorado/champagne. Tipografía con serif para títulos (aire sastrería clásica) + sans-serif legible para texto. Mucho aire, fotos grandes de prendas/trajes.

## Requisitos Meta — CRÍTICO (no omitir ninguno)

La web DEBE cumplir esto, porque sin esto la verificación de WhatsApp no pasa:

1. **HTTPS obligatorio.** El sitio tiene que servirse por HTTPS (SSL). Sin candado, Meta lo rechaza. (El deploy/hosting debe forzar HTTPS.)
2. **Nombre del negocio visible:** "Formen" tiene que aparecer claramente (header, footer, título).
3. **Dirección física visible:** "Mendoza 758, Corrientes, Argentina" tiene que figurar en el sitio (ideal: en el footer y en una sección de contacto).
4. **Sin links rotos.** Ningún enlace puede llevar a un error 404. Si un link no apunta a nada real, que no exista o sea un ancla interna válida.
5. **Coherencia de nombre:** el nombre que se muestra en la web ("Formen") debe coincidir con el nombre del negocio en Meta. Como la **razón social legal es "Classic SRL"** (distinta del nombre comercial "Formen"), HAY que relacionarlos explícitamente en el footer para que Meta no rechace por discrepancia. Footer obligatorio: **"Formen es una marca de Classic SRL — CUIT 33-71478866-9 — Responsable Inscripto"**.
6. **Email del mismo dominio:** mostrar un email `@formen.ar` como contacto (refuerza la señal de propiedad del dominio).
7. **Footer completo** con: nombre comercial (Formen), razón social (Classic SRL), CUIT (33-71478866-9), condición fiscal (Responsable Inscripto), dirección (Mendoza 758, Corrientes) y email del dominio.

> Estos 7 puntos son el motivo de existir de la web. Antes de dar por terminado, revisá uno por uno que estén.

## Secciones de la página (orden sugerido)

1. **Hero:** logo/nombre "FORMEN", slogan "Sastrería de autor desde 1998", una foto fuerte (traje), y un botón de WhatsApp / contacto.
2. **Nosotros:** 1-2 párrafos sobre la marca (sastrería de autor, trayectoria desde 1998, atención personalizada). [Texto placeholder, marcar para completar.]
3. **Qué hacemos / Servicios:** Trajes a medida, Sacos, Camisería, Trajes de novio y ceremonia, Accesorios (corbatas, moños). Tarjetas simples, sin precios.
4. **Galería:** grilla de imágenes (placeholders por ahora; después se reemplazan por fotos reales del Instagram @formen.ctes).
5. **Contacto / Ubicación:** dirección Mendoza 758 + Corrientes, email `@formen.ar`, link a Instagram, botón de WhatsApp, e idealmente un mapa embebido de Google Maps de la dirección.
6. **Footer:** nombre, dirección completa, email, redes, © año. (Cumple varios requisitos de Meta de una.)

## Stack y restricciones técnicas

- **HTML + CSS + JS vanilla** (sin framework pesado) O un sitio estático simple. Que sea fácil de subir a cualquier hosting (DonWeb, Netlify, Vercel) y servir por HTTPS.
- **Responsive** (mobile-first; la mayoría va a entrar desde el celular).
- **Liviano y rápido.** Optimizar imágenes (WebP). Nada de dependencias innecesarias.
- **Sin backend.** Es estática. El formulario de contacto (si se agrega) puede ser un `mailto:` o un link directo a WhatsApp, no un backend.
- **Accesible y con buen SEO básico:** title, meta description, Open Graph (para que se vea bien al compartir), favicon.

## Datos a CONFIRMAR con el cliente (dejar como placeholder y marcar con TODO)

- Horarios de atención.
- Teléfono / número de WhatsApp a enlazar (botón "Escribinos").
- Texto definitivo de "Nosotros".
- Fotos reales (por ahora placeholders).

## Definición de "terminado"

- [ ] La página carga por HTTPS sin errores.
- [ ] "Formen" + "Mendoza 758, Corrientes, Argentina" + email `@formen.ar` visibles (mínimo en el footer).
- [ ] Footer relaciona marca y razón social: "Formen es una marca de Classic SRL — CUIT 33-71478866-9 — Responsable Inscripto".
- [ ] Ningún link roto.
- [ ] Responsive en mobile y desktop.
- [ ] Meta tags (title, description, OG) y favicon presentes.
- [ ] Lista para subir a hosting y apuntar a formen.ar.

---

**Contexto del por qué:** esta landing es el paso que destraba la verificación de la cuenta de WhatsApp Business de Formen en Meta (estaba en "Revisión en curso" en parte por falta de sitio web). Mantené el foco en cumplir los requisitos de Meta de la sección crítica.
