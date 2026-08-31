# Credenciales — dónde vive cada secreto

> ⚠️ **Este archivo NO contiene ningún secreto y no debe contenerlo nunca.**
> Solo dice qué credenciales existen, dónde viven y cómo se obtienen si hay que rehacerlas.

---

## En n8n (ya configuradas, se referencian por id desde el workflow)

| Credencial | Tipo | id en n8n |
|---|---|---|
| `Kommo ForMen` | Header Auth | `XFOpX4xAM95NWBU6` |
| `Telegram account` | Telegram API | `iHWlHjVPTlIb72xG` |
| `OpenAI account` | OpenAI | `tNtJ2bbWHUG4lYiX` |

El JSON del workflow trae estos ids hardcodeados → al importar, los nodos vienen enganchados.

## Fuera de n8n

| Dónde | Qué | Ubicación |
|---|---|---|
| PC del local | Token de Kommo que usa el conector | `C:\FormenConector\conector.config.json` |
| PC del local | SQL Server Dragonfish | autenticación **integrada de Windows**, sin usuario ni clave |
| Máquina de Martín | Token de Kommo de Formen | `~/.claude/kommo.json`, cuenta `Formen` |

El token de Kommo está **duplicado** entre el config del conector y `kommo.json`: al rotarlo hay que
actualizar los dos, más la credencial de n8n.

---

## Cómo se obtiene cada una

### Token de Kommo (Header Auth)
1. `adminformenar.kommo.com` → Ajustes → **Integraciones** → abrir la integración privada del bot.
2. Pestaña **"Llaves y ámbitos"** → copiar el **Token de larga duración**.
3. En n8n, la credencial Header Auth va así:
   - **Name**: `Authorization`
   - **Value**: `Bearer <token>` ← **con el prefijo `Bearer `**, si no da error 110.

> Para **rotar**: botón "Generar nueva clave secreta" en esa misma pantalla. Eso invalida el token
> anterior → hay que actualizar la credencial en n8n, el `conector.config.json` de la PC del local y
> `~/.claude/kommo.json` **en el mismo momento**, o el bot y el conector quedan caídos.

### Telegram
- Bot **@FormenAYBot** ("Formen Avisos"), creado con **@BotFather**.
- Token: BotFather → `/mybots` → el bot → *API Token*. Para rotar: `/revoke`.
- El destino es el **chat_id** de Agustín (`8665518446`), que se obtiene con `getUpdates` después de que
  la persona le escriba una vez al bot.

---

## 🔐 Pendiente de rotación

Estos secretos se pegaron en texto plano en algún chat y **conviene regenerarlos**:

- [ ] Token de larga duración de **Kommo Formen** (+ su clave secreta) — volvió a quedar expuesto
      el 2026-08-28, esta vez el del conector.
- [ ] Token del bot de **Telegram** (`/revoke` en BotFather)

Al rotar cualquiera: actualizar la credencial en n8n inmediatamente, y en el caso de Kommo también
los dos archivos de la tabla de arriba.
