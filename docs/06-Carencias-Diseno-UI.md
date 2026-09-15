---
tags: [tfg, frontend, ui, pendiente]
depende-de: ["[[02-Diseno-de-pantallas]]", "[[05-Mapeo-Pantallas-Endpoints]]"]
estado: "En progreso — se rellena pantalla a pantalla, en paralelo a 05"
fecha: 2026-09-15
---

# Carencias de diseño UI detectadas desde el backend

Huecos del diseño de pantallas que aparecen al intentar servirlas con datos
reales — no son bocetos nuevos, salen de bajar al detalle en
`[[05-Mapeo-Pantallas-Endpoints]]`. Para revisar cuando se ataque el
frontend (Angular), no bloquean el backend hoy.

Complementa, no sustituye, a `[[02-Diseno-de-pantallas]] §5` (Pendiente de
diseño): aquello es estética sin resolver (estados de carga/vacío/error,
animación de estantería, contraste real); esto es dato que el mockup pide y
el esquema no tiene, o control que hace falta y no está dibujado.

## Pantalla 3 — Detalle de carta

- La lectura romanizada del nombre japonés ("Burakku Majishan") no tiene
  columna — `card_translations` no guarda transliteración. Decidir: se
  añade el dato (columna o cálculo) o se quita del diseño.

## Pantalla 4 — Buscador

- La caja de búsqueda única se decidió como OR de nombre + texto de efecto +
  passcode (subcadena/trigram). El **tercer modo** documentado en
  `03-Modelo-de-datos.md` — búsqueda por **concepto** (`tsvector`/`ts_rank`,
  palabras sueltas en cualquier orden: "invocar cementerio" encuentra
  *Renacimiento del Monstruo*) — se queda **sin UI**. Existe en el esquema
  (índice GIN ya montado) pero ningún control de la pantalla lo dispara. Si
  se quiere ese modo hace falta un segundo campo, un toggle, o un atajo de
  sintaxis dentro de la misma caja — sin diseñar.
- El panel de filtros dibujado cubre 5 grupos (tipo de carta, atributo,
  nivel, en mi colección, rareza). El backend va a soportar **17
  dimensiones más** desde el corte vertical 2 (decidido): marco, rango, link
  rating, péndulo, ATK/DEF, tipo de Mágica/Trampa, arquetipo, categoría de
  efecto, edición, idioma de impresión, restricción (banlist), estado del
  ejemplar, condición. Ninguna tiene control en el mockup — la API llegará
  antes que la pantalla que la usa. Diseñar esos controles cuando se ataque
  el frontend.
- El chip activo "Lanzador de Conjuros" (filtro por tipo de monstruo) prueba
  que la intención existe, pero su sección del panel de filtros no aparece
  completa en el lienzo — falta dibujarla o se cortó al exportar.

## Pantalla 1 — Estantería (landing)

- "Añadir carpeta" está dibujado como hueco punteado en la estantería, pero
  no hay pantalla ni formulario de alta de carpeta en las 10 diseñadas —
  qué campos pide (nombre, color de lomo, `slots_per_face`, posición) queda
  sin definir visualmente.

## Pantalla 6 — Alta / edición

- El nombre de la pantalla dice "Alta / edición" pero el mockup
  (`AltaCarta.dc.html`) solo dibuja **alta** (desde escaneo o manual). La
  **edición** — corregir una carta ya catalogada, o corregir un
  `collection_item` ya registrado (precio, ubicación, estado, notas) — no
  tiene pantalla. Confirmado en la conversación: nunca se dispara desde el
  escaneo, así que hace falta un flujo propio, sin dibujar todavía.
- El mockup solo dibuja un **Monstruo Normal**. Probando el resto de
  clases/marcos contra él, faltan seis cosas:
  - Sin control de "¿tiene efecto?" — en Fusión/Sincronía/Ritual/Xyz/Enlace
    no se deduce del marco (sí en Normal/Efecto).
  - "Nivel" es un único campo fijo; para Xyz debería pedir Rango, para
    Enlace Link Rating — son excluyentes entre sí, no variantes del mismo
    campo.
  - Sin control de **flechas de Enlace** (hasta 8 posiciones). No existe en
    el mockup.
  - **DEF sigue visible para Enlace**, que nunca lleva DEF impresa.
  - El checkbox **Péndulo no despliega campos dependientes**: falta la
    Escala (obligatoria si se marca) y un segundo cuadro de texto para el
    texto de Péndulo, distinto del texto de efecto normal.
  - **Mágica y Trampa no tienen estado dibujado** — el selector "Clase de
    carta" solo se ve fijado en "Monstruo"; qué sustituye al bloque
    "Datos de monstruo" para esas dos clases (o para Ficha/Habilidad, que
    ni siquiera se mencionan) no está diseñado.
- **El precio de mercado no tiene campo en el mockup.** Lo único que dibuja
  `AltaCarta.dc.html` es "Precio pagado" (lo que costó el ejemplar, casi
  siempre vacío — se compra por sobre/caja, no carta suelta). El precio que
  sí se registra siempre — lo que vale hoy en el mercado, decidido en la
  conversación — no tiene campo, etiqueta ni sitio en el formulario. Falta
  diseñarlo entero: dónde va, cómo se distingue visualmente de "Precio
  pagado" para que no se confundan.
- Aviso de duplicado: no hay pantalla de confirmación diseñada — el mockup
  no contempla registrar una carta que ya tienes, solo el alta de algo
  nuevo. Decidido con el backend: el aviso salta **solo si la ubicación no
  coincide** (no por precio — el de mercado se actualiza siempre sin
  preguntar, el de compra casi nunca está relleno), y ofrece dos acciones
  ("juntar con las que ya tengo" / "guardar aparte"). Ninguna de las dos
  tiene boceto visual.

## Pantalla 5 — Estadísticas

- El selector "Últimos 24 meses" de la cabecera no deja claro a qué afecta.
  Visualmente solo la gráfica de evolución tiene fechas ("sep 2024 – ago
  2026"); "Composición" y "Cartas más valiosas" no muestran ninguna
  dependencia del rango. Sin confirmar si el selector debería filtrar
  también esos dos paneles o es exclusivo de la gráfica.

## Pantallas 7/8 — Escaneo

- El algoritmo de `candidates` (qué otras cartas ofrecer cuando un dígito
  del passcode es dudoso) no está cerrado — y no es una carencia de este
  análisis, lo dice el propio `ADR-005`: *"qué hacer si el passcode
  detectado no está en el catálogo, y si el OCR devuelve 7 dígitos"*
  siguen abiertos. El mockup dibuja un caso (arte alternativo conocido)
  que no cubre el caso general.

## Pantalla 10 — Acceso admin

- Todo el contrato depende de `ADR-003` (`Propuesta`, sin cerrar). El
  mockup dibuja usuario+contraseña, pero el mecanismo (sesión vs JWT) lo
  decide el ADR, no el diseño visual — nada que anotar aquí hasta que
  cierre.

## Estado

Las 10 pantallas ya pasaron por `[[05-Mapeo-Pantallas-Endpoints]]`. No
queda ninguna sin analizar.

Ya conocido, sin analizar en detalle: ninguna de las 10 pantallas cubre
**recolocar cartas**, **partir una fila** (vender copias sueltas) ni
**borrar carta/set con ejemplares** (caso A12) — son operaciones del
roadmap (paso 8) sin pantalla ni flujo dibujado todavía.
