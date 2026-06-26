# Formen — Landing institucional

Landing de una sola página para **Formen** (marca de **Classic SRL**), sastrería de autor en Corrientes, Argentina.
Sitio estático (HTML + CSS + JS vanilla), sin backend ni dependencias de build. Listo para subir a cualquier hosting y apuntar a **formen.ar**.

> El objetivo de esta web es cumplir los requisitos de Meta/Facebook para verificar el negocio y la cuenta de **WhatsApp Business (WABA)**.

## Estructura

```
index.html              → la página (todas las secciones)
styles.css              → estilos
script.js               → menú mobile + año del footer
Images/                 → fotos originales sin tocar (archivo de respaldo)
assets/
  favicon.svg           → favicon
  og-formen.jpg         → imagen para compartir (Open Graph / WhatsApp)
  img/hero.jpg          → foto de fondo del hero
  img/about-atelier.jpg → foto de la sección Nosotros
  img/galeria-*.jpg     → fotos reales de la galería
```

## Cómo probarlo localmente

Abrí `index.html` en el navegador, o serví la carpeta:

```bash
# con Python
python -m http.server 8080
# luego abrí http://localhost:8080
```

## Despliegue (IMPORTANTE: HTTPS obligatorio)

Meta **rechaza** sitios sin candado HTTPS. Subir a un hosting que sirva HTTPS y forzar la redirección http→https.

- **Netlify / Vercel:** arrastrar la carpeta o conectar el repo → HTTPS automático. Luego apuntar el dominio `formen.ar`.
- **DonWeb / hosting tradicional:** subir los archivos por FTP a `public_html/`, activar el certificado SSL (Let's Encrypt) y forzar HTTPS.

Después del deploy, confirmá que `https://formen.ar` carga con candado y sin errores.

## ✅ Checklist de requisitos Meta (verificar antes de dar por cerrado)

- [x] Nombre del negocio "Formen" visible (header, hero, footer, `<title>`).
- [x] Dirección física "Mendoza 758, Corrientes, Argentina" visible (contacto + footer).
- [x] Footer relaciona marca y razón social: *"Formen es una marca de Classic SRL — CUIT 33-71478866-9 — Responsable Inscripto"*.
- [x] Email del dominio: `info@formen.ar`.
- [x] Footer completo: nombre, razón social, CUIT, condición fiscal, dirección, email.
- [x] Sin links rotos (anclas internas válidas; externos a wa.me / Instagram / mailto / Google Maps).
- [x] Meta tags (title, description, Open Graph), favicon y datos estructurados.
- [x] Responsive mobile + desktop.
- [ ] **HTTPS** — depende del hosting (ver arriba). ⬅️ único punto pendiente, se cumple al desplegar.

## 🔧 TODO — datos a confirmar con el cliente

Buscá los comentarios `TODO` en el código. Pendientes:

1. ~~**Número de WhatsApp.**~~ ✅ Listo: `+54 9 379 456-8826` (`5493794568826`) en los 4 enlaces y en el JSON-LD.
2. ~~**Horarios de atención**~~ ✅ Listo: Lun–Vie 8.30–12.30 y 17–21, Sáb 9–13 y 17–21, Dom cerrado (en Contacto y en el JSON-LD).
3. **Texto definitivo de "Nosotros"** — a confirmar (ya se quitó la nota de "provisorio").

### Opcional / mejoras

- **Optimizar imágenes a WebP.** Hoy las fotos son JPG (150–490 KB c/u, con `loading="lazy"`). Para acelerar aún más, convertirlas a `.webp` (~50–80 KB) y actualizar las extensiones en `index.html` y `styles.css`. No se pudo hacer automáticamente porque el entorno no tenía `cwebp`/ImageMagick/`sharp`.
- **Imagen Open Graph dedicada.** Hoy se usa el logo (`assets/og-formen.jpg`, 632×626). Para una previsualización más rica al compartir, se puede reemplazar por un `.jpg` de 1200×630 con una foto real (actualizar también `og:image:width/height`).
- **Más fotos en la galería.** Ya hay 4 reales; agregar más copiando archivos a `assets/img/` y sumando `<figure class="gallery-item">` en `index.html`.
