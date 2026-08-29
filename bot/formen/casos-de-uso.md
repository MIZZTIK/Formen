# Formen — Casos de uso del chatbot

> Derivados de *"Formen — Especificación de contenido e infraestructura de decisión"* (Agustín Yiguerimian, 21/07/2026).
> Sirve como **checklist de QA**: probá cada caso por WhatsApp y marcá si la respuesta es la esperada.
> Salida esperada del AI: `{ respuesta, derivar, notificar_agustin, motivo }`

**Leyenda:** 🔴 deriva a humano · 🔔 además notifica a Agustín · 📌 texto fijo (no libre) · ✅ responde solo

---

## A. Reglas de derivación (sección 2 de la spec)

| # | Caso | Ejemplo de mensaje | Respuesta esperada | derivar | notif |
|---|---|---|---|---|---|
| A1 | 🔴🔔📌 Producto no contemplado | *"¿tienen valijas?"* · *"¿venden perfumes?"* | Texto fijo: *"No estoy seguro que trabajemos con ese producto, pero dejame que pregunto a una persona y te hago saber."* | ✔ | ✔ |
| A2 | 🔴 Pregunta no documentada | *"¿hacen factura A?"* · *"¿tienen estacionamiento?"* | No improvisa. Deriva. | ✔ | — |
| A3 | 🔴 Stock / talle / color puntual | *"¿tenés el traje azul en talle 52?"* | **No confirma ni niega stock.** Deriva o invita al local. | ✔ | — |
| A4 | 🔴 Traje para novios | *"busco traje para mi casamiento"* | Da la info de novios (smokings azul y negro + chalecos y accesorios), avisa que ya gestionan contacto personalizado e invita a seguir consultando. | ✔ | — |
| A5 | 🔴 Horario en feriado nacional | *"¿abren el 9 de julio?"* | **Nunca da el horario estándar.** Deriva para confirmar. | ✔ | — |
| A6 | 📌 Respuesta a Historia de Instagram | *(responde una story)* | Texto fijo: *"Hola, soy un chatbot de Formen y te voy a ayudar a contestar, pero como no puedo ver qué hay en la historia, decime por cuál artículo querés consultar."* | ✗ | — |
| A7 | 🔴 "¿Está listo mi ambo?" (taller) | *"¿ya está lista mi prenda?"* | **Nunca responde por su cuenta.** Deriva para que confirmen en el taller. | ✔ | — |
| A8 | ✅ Confirma reserva hecha en persona | *"confirmo el ambo que separé ayer"* | Agradece y confirma: *"¡Muchas gracias! Ya quedó separado tu ambo."* | ✗ | — |
| A9 | 🔴 Monto total de una reserva | *"¿cuánto me quedaba por pagar?"* | **No informa montos.** Deriva. | ✔ | — |
| A10 | 🔴 Fuera de temporada | *"¿tienen camperas?"* · *"¿sweaters?"* · *"¿bermudas?"* | **No da precios ni especificaciones.** Deriva. | ✔ | — |
| A11 | 🔴 Voucher de regalo | *"¿venden gift cards?"* | Se emiten **solo presencialmente** en el local, no por chat. Deriva. | ✔ | — |

---

## B. Catálogo de productos

| # | Caso | Ejemplo | Respuesta esperada |
|---|---|---|---|
| B1 | Trajes — general | *"¿cuánto sale un traje?"* | Desde **$349.890** (primero el más barato), otro rango $449.890. Marcas Rochas, La Dolfina, Hechter, Rinaldi, John Nicols. Talles 42–70. Colores azul, negro, gris, beige, bordó, verde. |
| B2 | Sinónimo "ambo" | *"¿tienen ambos?"* | Lo entiende como traje. Misma info que B1. |
| B3 | Traje — talle de niño | *"¿sirve para un chico de 16?"* | Talle 42 ≈ talle niño 16, **aclarando que la prueba en el local confirma el calce**. |
| B4 | Traje — lo que NO hay | *"¿tienen cruzado?"* · *"¿de lino?"* · *"¿blanco?"* · *"¿jacket?"* | No disponible. (El 100% lino existe **solo en sacos sport**.) |
| B5 | Traje — a medida desde cero | *"¿me hacen uno a medida?"* | **No se hacen desde cero.** Se modifican los existentes a medida del cliente. |
| B6 | Traje — comprar el saco solo | *"¿me vendés solo el saco?"* | **No se vende por separado.** Sí existen sacos sport y pantalones de vestir como productos independientes. |
| B7 | Traje — tela | *"¿es de lana?"* | Poliéster viscosa. **No se trabaja lana fría.** |
| B8 | Chalecos | *"¿el traje viene con chaleco?"* | No incluido, salvo el smoking Rinaldi (3 cuerpos, gala/novios). Sueltos: azul, negro, gris claro — $149.890. Conjunto con plastrón y pañuelo — $269.890. |
| B9 | Camisas | *"¿cuánto están las camisas?"* | Rango **$69.890 a $149.890** (sin desglosar por marca salvo que lo pidan). Marcas Rochas, La Dolfina, Toche, Mc Taylor, Manchester. Talles 36–52. |
| B10 | Camisas — lo que NO hay | *"¿con bolsillo?"* · *"¿manga corta?"* | No disponible (tampoco botones en el cuello ni talles de niño). |
| B11 | Camisas especiales | *"¿tienen para gemelos?"* | Con gemelos: talles 36–52, **solo blanco**, 100% algodón, puño doble. También cuello palomita. |
| B12 | Calzado | *"¿tienen zapatos?"* | Zapatos de vestir **$249.890** (negro, marrón, guinda, suela, charol; talles 39–45). Zapatillas Rochas desde **$189.890** (marrón, negro, blanco). |
| B13 | Pantalones | *"¿cuánto un pantalón?"* | De vestir: nacionales desde **$99.890**, importados desde **$119.890**. Gabardina chino desde **$119.890**. Talles 40–60. Arreglos sin costo. |
| B14 | Jeans | *"¿tienen jeans?"* | Rochas **$69.890–$99.890**; La Dolfina **$159.890** (pocos modelos). Mayormente azules. |
| B15 | Remeras y chombas | *"¿tienen remeras?"* | Remeras 100% algodón pima peruana **$79.890** (S–XXXL). Chombas **$89.890** (Hechter de hilo / Rochas algodón). |
| B16 | Sacos sport | *"¿cuánto un saco sport?"* | Nacionales (Rinaldi, John Nicols) desde **$349.890**; importados (Rochas, La Dolfina) desde **$449.890**. Talles 46–66. Hasta 6 cuotas sin interés. |
| B17 | Sinónimo "blazer" | *"¿tienen blazers?"* | Lo entiende como saco sport. Misma info que B16. |
| B18 | Sobretodos | *"¿tienen sobretodos?"* | Paño importado, Rochas, **$449.890**, negro/azul/gris. |
| B19 | Accesorios | *"¿cuánto una corbata?"* | Corbatas $39.890 (seda $59.890), corbatines y moños $29.890, tiradores $29.890, pines $6.990–$11.990, traba corbatas $19.890, conjunto corbata+pañuelo+gemelo $69.890. |
| B20 | ⚠️ Pañuelo — la trampa | *"¿venden pañuelos?"* | Distingue: **pañuelo de saco $8.990 → SÍ** (el decorativo de la solapa). **Pañuelo de bolsillo tradicional → NO se vende.** Lo preguntan seguido. |
| B21 | Gemelos sueltos | *"¿vendés gemelos?"* | **No se venden por separado.** (Sí en el conjunto de $69.890.) |
| B22 | Cinturones | *"¿tienen cinturones?"* | Sáez desde **$79.890**, Rochas **$99.890** (negro, marrón, suela). |
| B23 | ⚠️ Fotos | *"¿me mandás fotos de las corbatas?"* | **Nunca envía fotos.** Asegura disponibilidad en todos los colores e invita a verlas en el local. |

---

## C. Formas de pago

| # | Caso | Ejemplo | Respuesta esperada |
|---|---|---|---|
| C1 | ⚠️ Consulta general de pago | *"¿cómo puedo pagar?"* | Cuotas sin interés + **efectivo 15% de descuento**. **NO debe mencionar transferencia** (no se ofrece proactivamente). |
| C2 | ⚠️ Transferencia (solo si preguntan) | *"¿y si pago por transferencia?"* | Recién ahí: **10% de descuento**. |
| C3 | Cuotas estándar | *"¿en cuántas cuotas?"* | 1 o 3 cuotas sin interés con Visa/Mastercard bancaria o **Naranja común** (no Naranja Visa). |
| C4 | Monto alto | *"¿un traje de $500.000 en cuotas?"* | Desde $400.000 o productos grandes: hasta **6 cuotas** bancarias, o **5 cuotas** con Naranja. |
| C5 | Tarjetas no habilitadas | *"¿aceptan Amex?"* · *"¿Cabal?"* | Sí, pero **solo 1 pago**. |
| C6 | QR | *"¿puedo pagar con QR?"* | Aceptado sin inconveniente. |
| C7 | Dólares | *"¿toman dólares?"* | Sí, a la cotización **más alta del blue del día**. |
| C8 | Seña | *"¿puedo señarlo?"* | Con efectivo se puede dejar seña; la prenda va al taller y se abona el saldo al retirarla. |

---

## D. Políticas

| # | Caso | Ejemplo | Respuesta esperada |
|---|---|---|---|
| D1 | Envíos | *"¿hacen envíos a Buenos Aires?"* | **No hay envíos al interior ni ventas online.** El diferencial es la atención personalizada en el local. |
| D2 | Compra online | *"¿tienen tienda online?"* | No. Solo local físico. |
| D3 | Cambios | *"¿puedo cambiarlo?"* | Sí, presentando la **bolsa del local** y con la prenda **sin uso**. |
| D4 | ⚠️ Tintorería / arreglos incluidos | *"¿hacen los arreglos?"* | **Sí, sastrería, tintorería y planchado sin costo** — para la prenda comprada. |
| D5 | ⚠️ Arreglos a prenda externa | *"¿me arreglan un saco viejo mío?"* | **No.** Solo aplica a la prenda comprada en esa misma operación, no a prendas externas ni de compras anteriores. |

---

## E. Tono y formato

| # | Regla | Cómo verificarlo |
|---|---|---|
| E1 | **Sin emojis** (o mínimos) | Ninguna respuesta debería traer emojis |
| E2 | Respuestas **breves y concretas** | Nada de párrafos largos |
| E3 | Tono **formal pero cálido**, nunca robótico | Se nota trato personalizado, no genérico |
| E4 | Rango de precios: **primero el más económico** | *"desde $349.890"* antes que *"$449.890"* |
| E5 | **Nunca inventar** | Ante lo no documentado → deriva (A1/A2) |
| E6 | Reconoce sinónimos | "ambo"→traje (B2), "blazer"→saco sport (B17) |

---

## F. Información general

| # | Caso | Respuesta esperada |
|---|---|---|
| F1 | Horarios | L-V 8:30–12:30 y 17:00–21:00 · Sáb 9:00–13:00 y 17:00–21:00 · Dom cerrado |
| F2 | Ubicación | **Mendoza 758, Corrientes Capital** (único local) |
| F3 | Contacto | WhatsApp 3794568826 · Instagram @formen.ctes |

---

## Casos que hoy NO están implementados

| Caso | Estado | Nota |
|---|---|---|
| A6 — detectar respuesta a Historia de IG | ⚠️ Parcial | El bot tiene el texto fijo, pero **no hay forma técnica de detectar** que el mensaje responde a una story. Depende de que el payload de Kommo lo indique — **a verificar**. |
| A5 — feriados nacionales | ⚠️ Parcial | El bot deriva si el cliente **menciona** un feriado, pero no tiene calendario de feriados. Si preguntan *"¿abren mañana?"* un feriado, va a dar el horario estándar. |
| A8 — confirmar reserva | ⚠️ A validar | Depende de que la IA interprete bien la intención; no hay señal dura. |
