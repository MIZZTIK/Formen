# Credenciales — dónde vive cada secreto

> ⚠️ **Este archivo NO contiene ningún secreto y no debe contenerlo nunca.**
> Solo dice qué credenciales existen, dónde viven y cómo se obtienen si hay que rehacerlas.

---

## En n8n (ya configuradas, se referencian por id desde los workflows)

| Proyecto | Credencial | Tipo | id en n8n |
|---|---|---|---|
| AVC | `Kommo AVC` | Header Auth | `BqHFVJZcWvtdH6ee` |
| AVC | `AVC Calendar` | Google Calendar OAuth2 | `9yYQShk9v3idvbD3` |
| AVC | `AVC` | OpenAI | `U8exa9B7bGjLh4cw` |
| Formen | `Kommo ForMen` | Header Auth | `XFOpX4xAM95NWBU6` |
| Formen | `Telegram account` | Telegram API | `iHWlHjVPTlIb72xG` |
| Formen | `OpenAI account` | OpenAI | `tNtJ2bbWHUG4lYiX` |

Los JSON de los workflows traen estos ids hardcodeados → al importar, los nodos vienen enganchados.

---

## Cómo se obtiene cada una

### Token de Kommo (Header Auth)
1. `<subdominio>.kommo.com` → Ajustes → **Integraciones** → abrir la integración privada del bot.
2. Pestaña **"Llaves y ámbitos"** → copiar el **Token de larga duración**.
3. En n8n, la credencial Header Auth va así:
   - **Name**: `Authorization`
   - **Value**: `Bearer <token>` ← **con el prefijo `Bearer `**, si no da error 110.

> Para **rotar**: botón "Generar nueva clave secreta" en esa misma pantalla. Eso invalida el token
> anterior → hay que actualizar la credencial en n8n **en el mismo momento** o el bot queda caído.

### Google Calendar OAuth2 (AVC)
- App propia en Google Cloud de `avcsolucionesempresariales@gmail.com`, proyecto "My First Project".
- Calendar API habilitada · pantalla de consentimiento tipo **Externo** · **PUBLICADA en Producción**.
- Cliente OAuth tipo *Aplicación web*, con redirect URI:
  `https://n8n.srv1224751.hstgr.cloud/rest/oauth2-credential/callback`
- El **Client Secret** solo se ve al crearlo (queda en el JSON que descarga Google).

### Telegram (Formen)
- Bot **@FormenAYBot** ("Formen Avisos"), creado con **@BotFather**.
- Token: BotFather → `/mybots` → el bot → *API Token*. Para rotar: `/revoke`.
- El destino es el **chat_id** de Agustín (`8665518446`), que se obtiene con `getUpdates` después de que
  la persona le escriba una vez al bot.

---

## 🔐 Pendiente de rotación

Estos secretos se pegaron en texto plano en algún chat y **conviene regenerarlos**:

- [ ] Token de larga duración de **Kommo AVC**
- [ ] Token de larga duración de **Kommo Formen** (+ su clave secreta)
- [ ] Token del bot de **Telegram** (`/revoke` en BotFather)

Al rotar cualquiera: actualizar la credencial en n8n inmediatamente.
