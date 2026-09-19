---
tags: [tfg, backend, api, endpoints, pantallas]
depende-de: ["[[02-Diseno-de-pantallas]]", "[[03-Modelo-de-datos]]", "[[04-Diseno-de-API-Endpoints]]"]
estado: "En progreso — se rellena pantalla a pantalla"
fecha: 2026-09-15
---

# Mapeo pantallas → endpoints

Nota de trabajo, no cierre de diseño. Para cada una de las 10 pantallas de
`[[02-Diseno-de-pantallas]]`, qué endpoint(s) hace(n) falta, de qué módulo
hexagonal son responsabilidad, y en qué paso del roadmap se implementan.

**No sustituye a `[[04-Diseno-de-API-Endpoints]]`** (que es solo lo que se
decide una vez: paginación, errores, dinero/fechas, `owned`) ni al contrato
final de cada recurso, que sale de OpenAPI generado desde el código en su
corte vertical. Esto es el paso previo: decidir qué endpoint hace falta antes
de escribirlo.

## Método

Por cada bloque visual de la pantalla:

1. **¿Lee o escribe?** → GET vs POST/PUT/PATCH/DELETE.
2. **¿Quién es dueño del dato?** — a qué módulo (`catalog`, `collection`,
   `pricing`, `scanning`, `security`) pertenece la responsabilidad. Un bloque
   visual puede mezclar dos módulos sin ser un único endpoint.
3. **¿Agregado o proyección?** (ADR-011) — si se edita o respeta invariantes,
   repo con dominio; si es solo lectura de pantalla, `record` de proyección.
4. **¿Varía por tipo/condición?** — si cambia por clase de carta, sigue
   siendo un único endpoint con salida polimórfica, no uno por clase.
5. **¿El dato existe ya en el esquema?** — si el mockup pide algo que no está
   en las 27 tablas, se anota como gap, no se inventa ahí.

---

## Pantalla 3 — Detalle de carta

Mockup real revisado (`DetalleCarta.dc.html` del lienzo), no solo la
descripción de `02`. Contrato verificado contra `V1__init_schema.sql`, no
solo contra el mockup — corrige una nota antigua (ver abajo).

Sin parámetro `owned` en ninguno de los dos — no aplica: el primero es ficha
por id, no listado; el segundo ya es inherentemente "lo que tienes", no
existe versión "no owned" de un ejemplar.

### `GET /cards/{id}` — módulo `catalog` — corte vertical 1 (paso 5)

**Path param:** `id` (`BIGINT`, PK sustituta de `cards`). No `passcode`:
es `NULL` en Fichas/Habilidades (`ck_cards_passcode_required`), no vale como
identificador universal. El escaneo (futuro) resuelve `passcode → id` con su
propio lookup.

**Query params:** ninguno. La ficha muestra varias traducciones a la vez
(ES/EN/JA en el mockup), así que `translations` es una lista completa, no se
filtra por idioma con un query param.

```json
{
  "metadata": { "timestamp": "...", "requestId": "...", "apiVersion": "v1" },
  "data": {
    "id": 101,
    "passcode": "46986414",
    "cardClass": "MONSTER",
    "tcgReleaseDate": "2002-03-08",
    "ocgReleaseDate": "1999-02-04",
    "alternateArtOf": null,
    "artworkLabel": null,
    "translations": [
      { "languageCode": "ES", "name": "Mago Oscuro", "cardText": "...", "pendulumText": null },
      { "languageCode": "EN", "name": "Dark Magician", "cardText": "...", "pendulumText": null }
    ],
    "monster": {
      "attribute": "DARK", "monsterType": "SPELLCASTER", "frame": "NORMAL",
      "hasEffect": false, "isPendulum": false,
      "atk": 2500, "atkUndetermined": false, "def": 2100, "defUndetermined": false,
      "level": 7, "xyzRank": null, "linkRating": null, "pendulumScale": null,
      "abilities": [], "linkArrows": []
    },
    "spell": null,
    "trap": null,
    "archetypes": { "memberOf": ["Mago/a Oscuro/a"], "supportsFor": [] },
    "effectCategories": [],
    "limitations": [
      { "format": "ADVANCED", "status": "UNLIMITED", "effectiveFrom": "2026-02-02" },
      { "format": "TRADITIONAL", "status": "UNLIMITED", "effectiveFrom": "2026-02-02" }
    ],
    "defaultImage": { "path": "...", "width": 400, "height": 580 }
  }
}
```

`monster`/`spell`/`trap`: exactamente uno no-nulo según `cardClass` — un solo
endpoint, salida polimórfica (regla catalog ligero, CLAUDE.md).

**Corrección sobre una nota anterior:** dije que el bloque "Restricción" no
tenía tabla, citando `03-Modelo-de-datos.md:52`. Esa nota está desactualizada
— el `V1` revisado el 14/09 añadió `card_limitations` (`format`
ADVANCED/TRADITIONAL, `status` FORBIDDEN/LIMITED/SEMI_LIMITED/UNLIMITED,
`effective_from`). El bloque **sí** tiene dato detrás; sale en `limitations`.

La "lectura" romanizada del nombre japonés ("Burakku Majishan") del mockup
no tiene columna — `card_translations` no guarda transliteración. Floritura
sin dato; se omite.

### `GET /cards/{id}/collection-items?status=` — módulo `collection` — corte vertical 3 (paso 8)

**Path param:** `id` — mismo `cards.id` de arriba. `collection_items` no
referencia `cards` directo: va `collection_items.card_print_id →
card_prints.card_id`, así que el repo de `collection` hace ese join (o su
proyección nativa) contra una tabla de `catalog`, por id — el patrón de
referencia entre agregados de siempre, aplicado a una consulta.

**Query params:** `status` (opcional, enum `ownership_status`: `OWNED` ·
`FOR_SALE` · `SOLD`). Si no se manda, excluye `SOLD` por defecto — igual que
la pantalla hoy. Se añade ya (no es YAGNI aquí) porque hay caso concreto
cercano: histórico de vendidas.

**`totalPaid` va a salir incompleto en la práctica, y es esperado.**
`purchase_price` es opcional (decidido): el usuario compra sobres/cajas/latas,
no cartas sueltas, así que la mayoría de `collection_items` no va a tener
precio individual. `totalPaid` suma solo las filas donde sí se registró —
no es un error el día que salga bajo, es la naturaleza del dato.

```json
{
  "metadata": { "timestamp": "...", "requestId": "...", "apiVersion": "v1" },
  "data": {
    "summary": {
      "totalItems": 3,
      "distinctPrints": 2,
      "totalPaid": 4.15
    },
    "items": [
      {
        "id": 501,
        "cardPrintId": 88,
        "setNumber": "RA01-SP001",
        "setName": "Rarity Collection",
        "rarity": "Secret Rare",
        "edition": "FIRST_EDITION",
        "languageCode": "ES",
        "condition": "NEAR_MINT",
        "quantity": 1,
        "status": "OWNED",
        "purchasePrice": 3.80,
        "purchaseDate": "2023-11-02",
        "location": { "binderId": 3, "binderNumber": 3, "pageNumber": 12, "face": "FRONT", "slotNumber": 1 }
      }
    ]
  }
}
```

`location` es `null` si el ejemplar no está colocado (`ck_collection_items_location`
lo permite: carpeta sin hueco todavía).

**Corregido tras diseñar pantalla 6:** `currentValue`/`variationPct`
("Valor hoy", "Variación" del mockup) **ya no son puro fase 2** —
`price_snapshots` empieza a poblarse desde el alta (paso 8), no en el
paso 11. `currentValue` = último `price_snapshots.price` por
`observed_on` de cada `card_print_id` que tengas; `variationPct` compara
contra el primer snapshot registrado. Sigue habiendo hueco real, pero es
otro: **si nunca diste de alta esa impresión concreta con este flujo
nuevo** (viene de datos migrados antes de que existiera `observedPrice`,
o nunca se actualizó), no hay snapshot y sale `null` — no por fase, sino
por dato ausente. Se añaden a la respuesta ya:

```json
"summary": { "totalItems": 3, "distinctPrints": 2, "totalPaid": 4.15, "currentValue": 7.35, "variationPct": 77 }
```

**Fuera de alcance, anotado:**

- Gráfica "Evolución de precio" (la serie completa, no solo el valor
  actual) — necesita agregación sobre histórico, eso sí es la pantalla de
  Estadísticas, paso 11.
- Botón "Editar carta" — mutación, depende de ADR-003/auth (paso 7).

---

## Pantalla 4 — Buscador y listado

Mockup real revisado (`Buscador.dc.html`). Un único endpoint (`GET /cards`),
decidido en la conversación previa: los contadores de facetas son
**reactivos** (recalculan con los filtros ya activos), así que separar
facetas de resultados no ahorraba llamadas — las dos dependen de los mismos
parámetros a la vez.

### Mecanismo de incompatibilidad entre filtros — sin tabla de reglas

Un Enlace no tiene `level` (`ck_monster_single_measure`), un Xyz no tiene
`level` ni `link_rating`, un Enlace no tiene `def`
(`ck_monster_link_has_no_def`). En vez de codificar esas incompatibilidades
a mano, se reutiliza el mismo cálculo reactivo de las facetas: además de
`facets` (listas con recuento), la respuesta lleva `ranges` — el min/max real
de cada eje numérico **bajo los filtros ya activos, excluyendo el propio
eje**. Si `frame=LINK` está activo, `ranges.level` sale `{min: null, max:
null}` porque cero filas tienen nivel — el front desactiva el control
cuando ve `null`, sin necesidad de conocer la regla de negocio que lo causa.
Un único mecanismo cubre las tres incompatibilidades del schema y cualquier
otra que exista sin haberla escrito explícitamente.

### Filtros completos, pintados y no pintados en el mockup

Revisión contra el schema completo, no solo contra lo visible en el
recorte. Los marcados **nuevo** no están en el mockup pero existen en el
modelo de datos — **decidido: se implementan todos ya**, en el corte
vertical 2, no se pospone ninguno.

| Filtro | Query param | Fuente | Solo si |
|---|---|---|---|
| Texto libre | `q` | OR de tres condiciones a la vez: `card_translations.name` (trigram), `card_translations.card_text` (trigram), `cards.passcode` (exacto) | — decidido: una caja, tres campos a la vez, no detección de formato |
| Índice alfabético | `letter` | `card_translations.name` | — |
| Tipo de carta | `cardClass[]` | `cards.card_class` | — |
| Tipo de monstruo | `monsterType[]` | `monster_types` | `cardClass` incluye MONSTER |
| Atributo | `attribute[]` | `monster_cards.attribute` | ídem |
| **Marco** (nuevo) | `frame[]` | `monster_cards.frame` | ídem — es la clave de las exclusiones de medida |
| **Habilidades** (nuevo) | `ability[]` | `monster_card_abilities` | ídem |
| **Con efecto** (nuevo) | `hasEffect` | `monster_cards.has_effect` | ídem |
| **Péndulo** (nuevo) | `isPendulum` | `monster_cards.is_pendulum` | ídem |
| Nivel | `levelMin`/`levelMax` | `monster_cards.level` | `frame` no es XYZ ni LINK (o ninguno elegido) |
| **Rango** (nuevo) | `xyzRankMin`/`xyzRankMax` | `monster_cards.xyz_rank` | `frame=XYZ` |
| **Link Rating** (nuevo) | `linkRatingMin`/`linkRatingMax` | `monster_cards.link_rating` | `frame=LINK` |
| **Escala Péndulo** (nuevo) | `pendulumScaleMin`/`Max` | `monster_cards.pendulum_scale` | `isPendulum=true` |
| **ATK** (nuevo) | `atkMin`/`atkMax`, `atkUndetermined` | `monster_cards.atk` | cardClass MONSTER |
| **DEF** (nuevo) | `defMin`/`defMax`, `defUndetermined` | `monster_cards.def` | ídem, sin sentido si `frame=LINK` (sale `ranges.def = null` solo) |
| **Tipo de Mágica** (nuevo) | `spellType[]` | `spell_cards.spell_type` | `cardClass` incluye SPELL |
| **Tipo de Trampa** (nuevo) | `trapType[]` | `trap_cards.trap_type` | `cardClass` incluye TRAP |
| **Arquetipo** (nuevo) | `archetype[]` | `archetypes`/`card_archetypes` | — |
| **Categoría de efecto** (nuevo) | `effectCategory[]` | `effect_categories`/`card_effect_categories` | — |
| Rareza | `rarity[]` | `card_prints.rarity_id` | EXISTS: el resultado es por carta, no por impresión |
| **Edición** (nuevo) | `edition[]` | `card_prints.edition` | EXISTS, mismo motivo |
| **Idioma de impresión** (nuevo) | `language[]` | `card_prints.language_code` | EXISTS, mismo motivo |
| **Set** (nuevo) | `cardSet[]` | `card_prints.card_set_id` | EXISTS, mismo motivo. **No aparece en `facets`**: se elige con un selector con búsqueda sobre `GET /card-sets?q=`. Es lo que sigue el enlace desde la pantalla 11 (ver "Sets") |
| **Restricción** (nuevo) | `banlistFormat`, `banlistStatus[]` | `card_limitations` (vigente = fila más reciente por carta+formato) | — |
| Solo las que tengo | `owned` (ya decidido en `04`) | política B4 | — |
| Duplicadas | `duplicated` | `collection_items` con `quantity > 1` para esa carta | fuerza `owned=true` |
| **Estado del ejemplar** (nuevo, generaliza "En venta" del mockup) | `status[]` | `collection_items.status` (`OWNED`/`FOR_SALE`/`SOLD`) | fuerza `owned=true` |
| **Estado de conservación** (nuevo) | `condition[]` | `collection_items.condition` | fuerza `owned=true` |

**Regla de EXISTS vs grano del resultado:** el listado es una fila por
**carta**, aunque tengas dos impresiones distintas de la misma. Filtrar por
`rarity`/`edition`/`language`/`status`/`condition` no cambia el grano —
selecciona cartas que tienen **al menos una** impresión/ejemplar que cumple,
vía `EXISTS`, no aplana el resultado a una fila por impresión.

**Regla de filtros de colección:** `duplicated`, `status` y `condition` solo
tienen sentido sobre lo que posees — si llegan junto con `owned=false`, el
caso de uso ignora ese `owned=false` y fuerza `true`. No es un error del
cliente, es una combinación sin sentido que se resuelve sola.

```json
{
  "metadata": { "timestamp": "...", "requestId": "...", "apiVersion": "v1" },
  "data": {
    "items": [
      { "id": 101, "name": "Mago Oscuro", "cardClass": "MONSTER",
        "summaryLine": "Nivel 7 · 2500/2100", "ownedQuantity": 3,
        "thumbnail": { "path": "...", "width": 200, "height": 200 } }
    ],
    "page": { "number": 0, "size": 12, "totalElements": 147, "totalPages": 13 },
    "facets": {
      "cardClass": [{ "value": "MONSTER", "label": "Monstruo", "count": 2762 }],
      "attribute": [{ "value": "DARK", "label": "Oscuridad", "count": 812 }],
      "frame": [{ "value": "LINK", "label": "Enlace", "count": 140 }],
      "rarity": [{ "value": 12, "label": "Secret", "count": 217 }],
      "banlistStatus": [{ "value": "LIMITED", "label": "Limitada", "count": 6 }]
    },
    "ranges": {
      "level": { "min": null, "max": null },
      "xyzRank": { "min": null, "max": null },
      "linkRating": { "min": 1, "max": 3 },
      "pendulumScale": { "min": null, "max": null },
      "atk": { "min": 1800, "max": 3000 },
      "def": { "min": null, "max": null }
    }
  }
}
```

Ejemplo con `frame=LINK` activo: `level`/`xyzRank`/`pendulumScale`/`def`
salen `null` — Enlace no tiene ninguno de los cuatro. El front no necesita
saber por qué, solo desactivar el control.

### Qué devuelve `facets` cuando una dimensión no aplica

Decidido el 2026-09-19. Es el mismo criterio que `ranges`, aplicado a las listas:
**el front no conoce las reglas de aplicabilidad, las lee del dato.**

- **Una dimensión que no aplica devuelve su lista vacía (`[]`) en `facets`.** El front
  oculta o desactiva ese grupo de filtros cuando ve una lista vacía. Por ejemplo, con
  `cardClass=SPELL` las listas `attribute`, `frame` y `monsterType` salen `[]`: las
  mágicas no tienen ninguna de las tres.
- **Una dimensión que sí aplica lista siempre todas sus opciones**, con `count: 0` en las
  que no tengan resultados bajo los filtros activos. Así una lista vacía significa solo
  «no aplica», nunca «aplica pero no hay resultados».
- **Cuándo aplica cada dimensión** lo fija la columna «Solo si» de la tabla de filtros.
  Es la misma regla que el `WHERE` de cada consulta de faceta, no una segunda tabla de
  reglas que mantener.
- **El backend no dice cómo se dibuja cada filtro.** El tipo de control (casillas,
  slider, interruptor, selector con búsqueda) lo decide el front y se deduce de la forma
  del parámetro: lista (`x[]`), rango (`xMin`/`xMax`), booleano, texto. Lo único
  presentacional que manda el backend es el `label` de cada opción, para que Angular no
  lleve las traducciones de todos los valores.

**Decidido hoy:**

- `q` busca nombre + texto de efecto + passcode **a la vez** (OR), una sola
  caja, sin detectar formato ni pedir que el usuario elija modo.
- Todos los filtros marcados **nuevo** en la tabla entran en el corte vertical 2
  (paso 6), no se posponen.

**Sigue abierto, sin resolver hoy:**

- El tercer modo de búsqueda documentado en `docs/03` (**concepto**,
  `tsvector`/`ts_rank` — "cartas que hablen de invocar desde el
  Cementerio") queda **fuera** de lo que decidimos: `q` no lo cubre, es
  búsqueda por subcadena (trigram) + passcode exacto, no por palabras
  sueltas en cualquier orden. Si se quiere ese modo, hace falta un
  parámetro o pantalla aparte — anotado en `06-Carencias-Diseno-UI.md`.

## Pantalla 1 — Estantería (landing)

Mockup real revisado (`Main.dc.html`). Es la pantalla de entrada, no un
genérico — confirmado antes de analizar, mismo criterio que las anteriores.

| Endpoint | Módulo | Devuelve | Paso roadmap |
|---|---|---|---|
| `GET /binders` | `collection` | Carpetas con resumen: número, nombre, color de lomo, posición, hojas, cartas archivadas, colocadas, ejemplares | Corte vertical 3 (paso 8) |
| `GET /collection/summary` | `collection` (+ `catalog`/`pricing`, proyección) | Cartas distintas, copias totales, sets distintos poseídos, valor estimado | Paso 8 — `valor estimado` sale de `price_snapshots`, que ya se puebla desde este mismo paso (ver pantalla 6) |
| `GET /collection/recent?limit=` | `collection` | Últimas incorporaciones: ejemplar + nombre de carta + set/rareza, por `registered_on` desc | Paso 8 |

**`GET /binders` no necesita SQL nuevo** — la vista `binder_summary`
(`V1__init_schema.sql:929`) ya calcula `card_count`, `placed_count`,
`sheet_count` y `copy_count` por carpeta. El proyecto de `04-Diseno-de-API-Endpoints`
llama exactamente a esto: proyección de pantalla, `record` directo desde
una vista, sin pasar por agregado.

**Sin paginación, `data` es el array directamente** — no `{items, page}`.
Esa forma (decidida en `04`) es solo para listados que sí paginan; `binders`
son como mucho una docena, no hace falta envolverlos.

```json
{
  "metadata": { "timestamp": "...", "requestId": "...", "apiVersion": "v1" },
  "data": [
    {
      "id": 3, "number": 3, "name": "Mago Oscuro", "spineColor": "#6D28D9",
      "slotsPerFace": 9, "shelfPosition": 2,
      "sheetCount": 46, "cardCount": 412, "placedCount": 398, "copyCount": 430
    }
  ]
}
```

**`GET /collection/summary`**, regla de alcance: `distinctCards`,
`totalCopies` y `distinctSets` cuentan solo `status <> 'SOLD'` — mismo
criterio que usa `binder_summary` para sus propias cifras, por consistencia.
`estimatedValue` = suma de (último `price_snapshots.price` de cada
`card_print_id` poseído × `quantity`) — sale `0`/parcial, no `null`, para
las impresiones que aún no tienen ningún snapshot (dato migrado antes de
`observedPrice`, o nunca actualizado), no por fase pendiente.

Se le añaden dos campos más al llegar a pantalla 5 (`totalSetsInCatalog`,
`totalPaid`) — mismo endpoint, no uno nuevo, ver esa sección.

```json
{
  "metadata": { "timestamp": "...", "requestId": "...", "apiVersion": "v1" },
  "data": {
    "distinctCards": 3363,
    "totalCopies": 7004,
    "distinctSets": 173,
    "estimatedValue": 1842.00
  }
}
```

**`GET /collection/recent?limit=`**, respuesta:

```json
{
  "metadata": { "timestamp": "...", "requestId": "...", "apiVersion": "v1" },
  "data": [
    {
      "collectionItemId": 9012, "cardId": 501, "cardName": "Kashtira Fenrir",
      "cardClass": "MONSTER", "setNumber": "RA05-SP024", "rarity": "Ultra",
      "registeredOn": "2026-09-10"
    }
  ]
}
```

**Fuera de alcance, anotado:**

- "Entrar" — auth, ADR-003, paso 7.
- "Añadir carpeta" — mutación (crear `binder`), paso 8, sin detallar el
  contrato hoy (no es lectura, y el alta de carpeta no tiene mockup de
  formulario dibujado — otro hueco para `06`).

## Pantalla 2 — Carpeta abierta

Mockup real revisado (`CarpetaAbierta.dc.html`). Propuesta inicial tuya, 3
endpoints — repasados uno a uno contra el mockup:

| Endpoint | Módulo | Devuelve | Paso roadmap |
|---|---|---|---|
| `GET /binders/{id}` | `collection` | Nombre, `cardCount`, `sheetCount` — **reutiliza** `GET /binders` de pantalla 1, un id concreto en vez de la lista. No es endpoint nuevo. | Paso 8 |
| `GET /binders/{id}/spread?at=` | `collection` | Doble página: `left`/`right`, cada uno con `pageNumber`, `face`, y `slots_per_face` huecos (ocupado o `null`) | Paso 8 |
| `GET /binders/{id}/search?q=` | `collection` | Carta + página + cara + hueco, buscando solo dentro de este binder | Paso 8 |

**`GET /binders/{id}`** — mismo objeto que una fila de `GET /binders`, sin
envoltorio de array:

```json
{
  "metadata": { "timestamp": "...", "requestId": "...", "apiVersion": "v1" },
  "data": {
    "id": 3, "number": 3, "name": "Mago Oscuro", "spineColor": "#6D28D9",
    "slotsPerFace": 9, "shelfPosition": 2,
    "sheetCount": 46, "cardCount": 412, "placedCount": 398, "copyCount": 430
  }
}
```

**El detalle que no sale de la descripción, solo del mockup:** la doble
página muestra **dos `page_number` distintos**, no la misma hoja con sus dos
caras — "PÁGINA 12" a la izquierda, "PÁGINA 13" a la derecha. Es cómo se
abre físicamente un álbum de 9 bolsillos: lo que ves es el **reverso de la
hoja N** (izquierda) y el **anverso de la hoja N+1** (derecha). `at=12`
devuelve `{ left: {pageNumber:12, face:BACK}, right: {pageNumber:13,
face:FRONT} }`.

`slots` siempre trae las `slots_per_face` posiciones, ocupadas o no — un
hueco libre no tiene fila en `collection_items`, así que se genera
`1..slots_per_face` y se hace `LEFT JOIN`. Si no, el front no distingue
"hueco vacío" de "no me han mandado ese número".

```json
{
  "metadata": { "timestamp": "...", "requestId": "...", "apiVersion": "v1" },
  "data": {
    "left": {
      "pageNumber": 12, "face": "BACK",
      "slots": [
        { "slotNumber": 1, "item": { "collectionItemId": 501, "cardId": 101, "cardName": "Mago Oscuro", "setNumber": "RA01-SP001", "rarity": "Secret" } },
        { "slotNumber": 8, "item": null }
      ]
    },
    "right": {
      "pageNumber": 13, "face": "FRONT",
      "slots": [
        { "slotNumber": 5, "item": { "collectionItemId": 640, "cardId": 340, "cardName": "Wynn la Canalizadora", "setNumber": "RA01-SP018", "rarity": "Ultimate" } }
      ]
    }
  }
}
```

**`GET /binders/{id}/search?q=`** — array, puede haber más de un ejemplar
de la misma carta en el binder:

```json
{
  "metadata": { "timestamp": "...", "requestId": "...", "apiVersion": "v1" },
  "data": [
    { "collectionItemId": 501, "cardId": 101, "cardName": "Mago Oscuro",
      "pageNumber": 12, "face": "BACK", "slotNumber": 1 }
  ]
}
```

**Descartado tras discutirlo:** un cuarto endpoint de resumen de ocupación
por página, para una barra de navegación visual (46 barritas de altura
variable). Se cae solo — "ir a la página que quiera" ya lo cubre `at=` como
parámetro libre, no como cursor secuencial; no hace falta precalcular nada
para saltar a una página cualquiera. El rango válido (46) ya viene de
`GET /binders/{id}`.

## Pantalla 6 — Alta (edición: sin mockup, ver `06`)

Mockup real revisado (`AltaCarta.dc.html`). Cruza tres agregados a la vez
(`cards`+`card_translations`+especialización, `card_prints`,
`collection_items`) — encaja exacto con la regla de CLAUDE.md: *"`CardPrint`
no se crea sola, nace al registrar un ejemplar"*. Un único caso de uso, un
único límite transaccional, un único endpoint.

### `POST /collection-items` — módulo `collection` — caso de uso `RegistrarEjemplar`

**Revisión probando cada clase/marco contra el mockup**, que solo dibuja un
Monstruo Normal — encontré seis huecos reales, listados también en `06`:

- Sin control de `hasEffect`. En Normal es `false` fijo y en Efecto `true`
  fijo (`ck_monster_frame_effect`), pero en Fusión/Sincronía/Ritual/Xyz/
  Enlace no se deduce del marco — hace falta campo explícito.
- "Nivel" no cambia de etiqueta ni de campo destino: para Xyz debería pedir
  `xyzRank`, para Enlace `linkRating` — son mutuamente excluyentes
  (`ck_monster_single_measure`), el mockup fija un único campo "Nivel".
- Sin control de flechas de Enlace (`monster_link_arrows`, hasta 8
  posiciones, tantas marcadas como `link_rating`).
- DEF no se oculta para Enlace (`ck_monster_link_has_no_def`: nunca lleva).
- Péndulo es un checkbox sin campos dependientes: si se marca, hacen falta
  `pendulumScale` (obligatorio, `ck_monster_pendulum_has_scale`) y un
  segundo texto — `pendulumText` vive en `card_translations`, no en
  `monster_cards`, aparte de `cardText`.
- Mágica y Trampa no tienen mockup: qué reemplaza al bloque "Datos de
  monstruo" (`spellType`/`trapType`) no está dibujado. Tampoco Ficha/
  Habilidad (`card_class` TOKEN/SKILL, passcode `NULL` permitido).

El `Command` incorpora los seis, aunque el mockup de hoy no los pinte:

```json
{
  "card": {
    "passcode": "46986414", "cardClass": "MONSTER", "tcgReleaseDate": "2002-03-08",
    "translations": [
      { "languageCode": "ES", "name": "Mago Oscuro", "cardText": "...", "pendulumText": null },
      { "languageCode": "EN", "name": "Dark Magician" }
    ],
    "monster": {
      "frame": "NORMAL", "attribute": "DARK", "monsterTypeId": 7,
      "hasEffect": false, "isPendulum": false, "pendulumScale": null,
      "level": 7, "xyzRank": null, "linkRating": null, "linkArrows": [],
      "atk": 2500, "atkUndetermined": false, "def": 2100, "defUndetermined": false,
      "abilities": []
    },
    "spell": null,
    "trap": null
  },
  "print": {
    "cardSetId": 12, "setNumber": "RA01-SP001", "rarityId": 12,
    "edition": "FIRST_EDITION", "languageCode": "ES",
    "observedPrice": { "price": 6.50, "currency": "EUR" }
  },
  "item": { "quantity": 1, "condition": "NEAR_MINT", "binderId": 3, "pageNumber": 12, "purchasePrice": null, "purchaseDate": null, "notes": null }
}
```

`purchasePrice`/`purchaseDate` casi siempre `null` — decidido: el usuario
compra producto sellado (sobres, cajas, latas), no cartas sueltas, así que
no hay precio individual real que registrar la mayoría de las veces.

`print.observedPrice` es distinto: **el precio de mercado que compruebas al
dar de alta, siempre, venda o no la carta.** Escribe una fila en
`price_snapshots` (`card_print_id`, `price`, `currency`, `source='MANUAL'`,
`observed_on=hoy`, puestos por el servidor). Si ya hay una observación de
hoy para esa impresión, se sobreescribe — no es un conflicto, es la misma
observación repetida el mismo día. Esto es de `pricing`, no de `collection`
— el caso de uso `RegistrarEjemplar` (en `collection`) escribe ahí a través
de un puerto de salida hacia `pricing`, mismo patrón que la referencia por
id de `CollectionItem→CardPrintId`, aplicado a escritura en vez de lectura.

**Consecuencia de roadmap:** `price_snapshots` deja de esperar al paso 11 —
empieza a poblarse desde aquí, paso 8. El paso 11 sigue siendo cuándo se
construye la pantalla de Estadísticas con gráficas y agregados; el dato en
sí nace antes. Afecta a lo que dije en pantallas 1 y 3 sobre
`estimatedValue`/"Valor hoy" — corregido más abajo.

Para Mágica/Trampa, `monster` es `null` y se manda `spell: {spellType}` o
`trap: {trapType}`. Validación exactamente igual a los `CHECK` del schema:
`linkArrows` solo si `frame=LINK` y su longitud coincide con `linkRating`;
`def`/`defUndetermined` vacíos si `frame=LINK`; `pendulumScale`/
`pendulumText` obligatorios solo si `isPendulum=true`.

**Aviso ante un duplicado — solo si algo difiere, no en cada match.**
`onDuplicate` como campo del `Command` se descarta: una vez se conoce el id
de la fila existente, seguir usando el mismo `POST` con un flag es mezclar
"crear" y "editar" bajo un verbo que no lo dice. El verbo pasa a llevar la
intención — tres endpoints, no uno:

| Paso | Endpoint | Cuándo |
|---|---|---|
| Alta | `POST /collection-items` | Siempre, primera llamada — Command completo |
| Fusionar | `PATCH /collection-items/{id}` | Tras el aviso, si el usuario confirma que es la misma compra |
| Registrar aparte | `POST /card-prints/{cardPrintId}/collection-items` | Tras el aviso, si el usuario quiere una fila propia |

Por dentro de `POST /collection-items`:

1. Busca `cards` por `passcode`. Si no existe, la crea. Si existe,
   **ignora** identidad/monstruo del `Command` — este endpoint nunca edita
   una carta existente.
2. Busca `card_prints` por su clave natural. Si no existe, la crea.
3. Busca una fila `collection_items` con el **mismo `card_print_id` y
   `condition`**, en estado `OWNED`.
   - **Sin match** → crea todo, `201`.
   - **Con match y nada relevante difiere** (misma ubicación o ninguna de
     las dos trae ubicación) → **fusiona directamente, sin aviso**: suma
     `quantity`, `200`. Es la compra repetida sin más — lo que pediste
     desde el principio.
   - **Con match y difiere la ubicación** → no escribe nada, `409` con la
     fila existente. **El precio no cuenta para esto**: es opcional
     (el usuario compra sobres/cajas, no cartas sueltas — casi siempre va
     vacío), así que no es una señal fiable de "esto es una compra
     distinta". Lo único que de verdad distingue una copia de otra a
     efectos físicos es dónde la archivas.

```json
// 409 — la ubicación no coincide, decide el usuario.
// RFC 9457 puro, sin envolver en {metadata, data} (04 §4). existingItem y
// submittedLocation son miembros de extensión en la raíz.
{
  "type": "https://duelvault.dev/problems/ejemplar-duplicado",
  "title": "Ya tienes esta carta",
  "status": 409,
  "detail": "Ya tienes 3 copias en la carpeta 3; esta iría a la carpeta 7",
  "instance": "/collection-items",
  "existingItem": {
    "collectionItemId": 501, "cardPrintId": 88, "condition": "NEAR_MINT",
    "quantity": 3, "binderId": 3, "pageNumber": 12, "face": "FRONT", "slotNumber": 1
  },
  "submittedLocation": { "binderId": 7, "pageNumber": 2 }
}
```

Pantalla: *"Ya tienes 3 copias en Carpeta 03. Esta la quieres archivar en
Carpeta 07 — ¿juntarla con las otras (pierde su ubicación propia) o
guardarla aparte?"*

```json
// PATCH /collection-items/501 — fusionar
{ "quantity": 4, "notes": null }
```

```json
// POST /card-prints/88/collection-items — aparte
{ "quantity": 1, "condition": "NEAR_MINT", "binderId": 7, "pageNumber": 2, "notes": null }
```

Ambos responden con el mismo objeto de fila (`collectionItemId`,
`cardPrintId`, `quantity`, ubicación) — `200` el `PATCH`, `201` el `POST`
de la fila nueva.

**Fuera de alcance, anotado:**

- **Edición** (la otra mitad del nombre de la pantalla) no tiene mockup.
  Ni corregir identidad de una carta ni corregir un `collection_item` ya
  registrado (precio, ubicación, estado, notas) están diseñados
  visualmente — son casos de uso distintos (`CorregirDatosCarta`,
  algo tipo `ActualizarUbicacion`/`CorregirEjemplar`, nunca CRUD genérico),
  sin pantalla que servir todavía. Anotado en `06`.
- Origen "viene del escaneo" (banner amarillo, código detectado) — depende
  de `scanning`, post-MVP.

## Sets — pantalla 11 (listado y alta)

Pantalla nueva del 2026-09-19, sin mockup. Sale de dos necesidades: comprar un producto
de un set que no está catalogado no puede bloquear el alta, y hace falta consultar los
sets. Decidido:

- **Una sola pantalla** con el listado de sets y un interruptor «Mis sets / Todos», que
  es el parámetro `owned` de `GET /card-sets`. Un botón «Nuevo set» abre el formulario de
  alta en la misma pantalla.
- **El atajo «+ Crear set»** del selector de set del formulario de alta de carta
  (pantalla 6) se mantiene y llama al mismo `POST /card-sets`, para no salir del
  formulario al dar de alta varias cartas de un set nuevo.
- **El buscador es solo de cartas.** Los sets no se buscan ahí; el filtro `cardSet[]`
  sirve para buscar cartas dentro de un set.

Módulo `catalog`: `CardSet` es raíz propia (ADR-012).

| Endpoint | Módulo | Devuelve | Paso roadmap |
|---|---|---|---|
| `POST /card-sets` | `catalog` | El set creado | Paso 8, junto a `RegistrarEjemplar`, que lo necesita |
| `GET /card-sets` | `catalog` (proyección, lee `collection_items`) | Sets con lo que se posee de cada uno | Paso 5 |

### `POST /card-sets` — caso de uso `RegistrarSet`

Lo llaman dos sitios del front: el botón «Nuevo set» de la pantalla 11 y el atajo
«+ Crear set «RA05»» del formulario de alta de carta (pantalla 6). En el segundo caso, el
front envía **después** `POST /collection-items` con el `cardSetId` devuelto.
`RegistrarEjemplar` no llama a `RegistrarSet` (ADR-004: los casos de uso no se llaman
entre sí).

```json
{
  "setPrefix": "RA05",
  "setTypeId": 3,
  "tcgReleaseDate": "2026-08-15",
  "totalCards": 100,
  "translations": [
    { "languageCode": "ES", "name": "Rarity Collection 5" }
  ]
}
```

- Obligatorios: `setPrefix` (hasta 10 caracteres; se normaliza a mayúsculas y sin
  espacios) y al menos una traducción con nombre. El nombre vive en
  `card_set_translations`, no en `card_sets`, así que la base de datos no obliga a
  tenerlo: lo exige el constructor del dominio, y `400` en el borde.
- Opcionales: `setTypeId`, `tcgReleaseDate`, `totalCards` (mayor que 0 si viene).
- **`409` si el prefijo ya existe** (`set-duplicado`, `ConflictoDeEstadoException`).
  Es RFC 9457 puro, según `04 §4`, con el miembro de extensión `existingSetId` para que
  el diálogo seleccione el set que ya está en vez de fallar.

```json
// 201 — cuerpo: el mismo objeto que un item de GET /card-sets, con los recuentos a 0
{
  "metadata": { "timestamp": "...", "requestId": "...", "apiVersion": "v1" },
  "data": {
    "id": 1241, "setPrefix": "RA05", "name": "Rarity Collection 5",
    "setType": { "id": 3, "label": "Colección" },
    "tcgReleaseDate": "2026-08-15", "totalCards": 100,
    "ownedDistinctNumbers": 0, "ownedCopies": 0
  }
}
```

### `GET /card-sets` — proyección de solo lectura

**Query params:**

| Param | Notas |
|---|---|
| `owned` | Por defecto `true`: solo sets con al menos un ejemplar que no esté `SOLD` (mismo criterio que `binder_summary` y `GET /collection/summary`). **El interruptor «Mis sets / Todos» de la pantalla 11 es este parámetro** (`true` / `false`). **El selector del formulario de alta también manda `owned=false`**: un set recién creado no tiene ejemplares y, si no, no aparecería. |
| `q` | Opcional. Prefijo o nombre, sin acentos ni mayúsculas. Sirve para el desplegable con búsqueda. |
| `sort` | `NAME_ASC` (por defecto), `RELEASE_DESC`, `OWNED_DESC` (más números poseídos primero). |
| `page`, `size` | Paginado: hoy son unos 173, y con el catálogo completo importado serían ~1.240. |

```json
{
  "metadata": { "timestamp": "...", "requestId": "...", "apiVersion": "v1" },
  "data": {
    "items": [
      {
        "id": 12, "setPrefix": "RA01", "name": "25th Anniversary Rarity Collection",
        "setType": { "id": 3, "label": "Colección" },
        "tcgReleaseDate": "2023-04-28", "totalCards": 100,
        "ownedDistinctNumbers": 41, "ownedCopies": 58
      }
    ],
    "page": { "number": 0, "size": 20, "totalElements": 173, "totalPages": 9 }
  }
}
```

- **`ownedDistinctNumbers` es `COUNT(DISTINCT set_number)`, no cartas distintas.** Es la
  medida comparable con `totalCards`, que cuenta números del listado oficial. Un mismo
  número existe en varias rarezas (202 casos reales), y contarlas por separado
  inflaría el avance. `ownedCopies` es `SUM(quantity)`.
- `totalCards` puede ser `null` si no se conoce. El porcentaje de avance lo calcula el
  front, y solo si hay total.
- `name` va en un solo idioma, ES con caída a otro disponible si falta la traducción.
  Mismo criterio que los demás listados; no está escrito todavía en `04`.
- **Ver las cartas de un set** no es un endpoint nuevo: es `GET /cards?cardSet=12` (filtro
  añadido a la tabla de la pantalla 4). Cada set del listado enlaza al buscador con ese
  filtro puesto.
- **El filtro `cardSet[]` del buscador no lleva contadores en `facets`** (decidido
  2026-09-19): son cientos de opciones (173 hoy, ~1.240 con el catálogo completo). El
  control es un **selector con búsqueda** que reutiliza `GET /card-sets?q=`. Se pierde el
  recuento por set bajo los filtros activos, a cambio de no engordar la respuesta de
  `GET /cards` ni recalcular un recuento por set en cada búsqueda.
- No hay `GET /card-sets/{id}`: nada de lo diseñado lo necesita hoy.

**Cae en el patrón de ADR-012:** `catalog` es dueño del endpoint y lee `collection_items`
por SQL, solo lectura, sin pasar por el dominio.

## Pantalla 5 — Estadísticas

Mockup real revisado (`Estadisticas.dc.html`). Primera pantalla que cae de
lleno en `pricing`, paso 11 — no hay vista ya hecha que reutilizar como
`binder_summary`.

**Decisión previa, real:** la gráfica de evolución muestra **lo que posees
hoy, valorado con los precios de cada fecha** — no la cartera histórica
exacta (qué tenías comprado/vendido en cada momento). Más barato: no hace
falta cruzar `purchase_date`/`sold_on` de cada fila, que además van a
faltar casi siempre (compra por sobre). La curva sube y baja con el
mercado, no con tus compras/ventas pasadas.

| Endpoint | Módulo | Devuelve | Paso roadmap |
|---|---|---|---|
| `GET /collection/summary` (extendido) | `collection` | Se añaden `totalSetsInCatalog` y `totalPaid` a lo ya definido en pantalla 1 | Paso 8 + campos nuevos en paso 11 |
| `GET /statistics/value-evolution?months=` | `collection`+`pricing` | Serie `{date, value}`, un punto por mes | Paso 11 |
| `GET /statistics/composition` | `collection`+`catalog` | Recuento por tipo de carta y por atributo, global | Paso 11 |
| `GET /statistics/top-value?limit=` | `collection`+`pricing` | Top N impresiones por precio de mercado actual | Paso 11 |

**`GET /collection/summary`, campos nuevos:** `totalSetsInCatalog` es
`COUNT(*)` de `card_sets` entero, sin filtrar por posesión — a diferencia
de `distinctSets`, que sí cuenta solo lo tuyo. `totalPaid` es la suma
global de `purchase_price`; mismo hueco ya documentado en pantalla 3 —
casi siempre por debajo de la realidad, porque el campo se deja vacío en
compra de producto sellado.

```json
{
  "metadata": { "timestamp": "...", "requestId": "...", "apiVersion": "v1" },
  "data": {
    "distinctCards": 3363, "totalCopies": 7004, "distinctSets": 173,
    "totalSetsInCatalog": 1240, "estimatedValue": 1842.00, "totalPaid": 1183.00
  }
}
```

**`GET /statistics/value-evolution?months=24`** — un punto por mes: para
cada impresión que tienes **hoy**, su snapshot de precio más reciente
`≤` fin de ese mes, × cantidad actual, sumado entre todas. Un mes sin
observaciones nuevas repite el valor del mes anterior — el precio no
caduca, se mantiene hasta la siguiente observación.

```json
{
  "metadata": { "timestamp": "...", "requestId": "...", "apiVersion": "v1" },
  "data": [
    { "date": "2024-09-30", "value": 1183.00 },
    { "date": "2024-10-31", "value": 1205.50 },
    { "date": "2026-08-31", "value": 1842.00 }
  ]
}
```

**`GET /statistics/composition`** — devuelve las categorías **completas**
(las 3 clases de carta + "Otras", los 7 atributos), no recortadas. El
"top 4" de atributos que pinta el mockup es corte del front sobre la
respuesta entera, no un `limit` del backend — recortar qué se enseña es
presentación, no dato.

```json
{
  "metadata": { "timestamp": "...", "requestId": "...", "apiVersion": "v1" },
  "data": {
    "byCardClass": [
      { "value": "MONSTER", "label": "Monstruo", "count": 2762 },
      { "value": "SPELL", "label": "Mágica", "count": 1033 },
      { "value": "TRAP", "label": "Trampa", "count": 720 },
      { "value": "OTHER", "label": "Otras", "count": 14 }
    ],
    "byAttribute": [
      { "value": "DARK", "label": "Oscuridad", "count": 815 },
      { "value": "LIGHT", "label": "Luz", "count": 651 }
    ]
  }
}
```

**`GET /statistics/top-value?limit=5`**:

```json
{
  "metadata": { "timestamp": "...", "requestId": "...", "apiVersion": "v1" },
  "data": [
    { "cardPrintId": 340, "cardName": "Impulso Dominus", "rarity": "Collector's", "currentValue": 60.00 }
  ]
}
```

**Fuera de alcance, anotado:**

- Selector "Últimos 24 meses" del mockup solo se asume que afecta a la
  gráfica de evolución (`months=`) — no está confirmado si también debería
  filtrar `composition`/`top-value`. Sin decidir, anotado en `06`.

## Pantalla 9 — Detalle en móvil

Mockup real revisado (`DetalleMovil.dc.html`). **Cero endpoints nuevos** —
las pestañas "Datos" y "Mi colección" son la misma información de
`GET /cards/{id}` y `GET /cards/{id}/collection-items` (pantalla 3), solo
que en pestañas en vez de columnas lado a lado. "Ediciones" es la misma
respuesta de `collection-items` vista agrupada por impresión, no una
tercera llamada. "Ver en la carpeta" navega a `GET /binders/{id}/spread?at=`
(pantalla 2) con la ubicación que ya trae el ejemplar. El campo
"Restricción" que aparece aquí ya viene en `limitations` de `GET
/cards/{id}` — no hacía falta rediseñarlo.

## Pantallas 7/8 — Escaneo

Mockups reales revisados (`Escaneo.dc.html`, `EscaneoResultado.dc.html`),
contra `ADR-005` y la tabla `card_scans`. Dos endpoints nuevos, módulo
`scanning`; el resto reutiliza lo ya diseñado.

| Endpoint | Devuelve | Nota |
|---|---|---|
| `POST /card-scans` | Resultado del OCR: passcode detectado, confianza, candidatos | Server-side: `ADR-005` fija el pipeline con Tess4j (Java) — el preprocesado y el OCR corren en el backend, no en el móvil |
| `PATCH /card-scans/{id}` | Confirma o descarta el resultado | Alimenta `matched_card_id`/`resolved_at`, es la evidencia medible del TFG ("% de aciertos") que pide `ADR-005` |

```json
// POST /card-scans — multipart: la imagen capturada
{
  "metadata": { "timestamp": "...", "requestId": "...", "apiVersion": "v1" },
  "data": {
    "scanId": 9001, "status": "MATCHED",
    "detectedPasscode": "46986414",
    "digitConfidence": [0.99, 0.98, 0.97, 0.99, 0.61, 0.98, 0.99, 0.97],
    "overallConfidence": 0.62,
    "candidates": [
      { "cardId": 101, "cardName": "Mago Oscuro", "cardClass": "MONSTER", "summaryLine": "Monstruo Normal · Nivel 7 · 2500/2100", "ownedQuantity": 3, "matchType": "EXACT" },
      { "cardId": 340, "cardName": "Mago Oscuro (Arkana)", "cardClass": "MONSTER", "summaryLine": "Arte alternativo · 36996508", "ownedQuantity": 0, "matchType": "ALTERNATE_ART" }
    ]
  }
}
```

```json
// PATCH /card-scans/9001
{ "status": "CONFIRMED", "matchedCardId": 101 }
```

**Abierto, y lo dice el propio `ADR-005`, no lo invento yo:** *"Quedan dos
casos de interfaz abiertos: qué hacer si el passcode detectado no está en
el catálogo, y si el OCR devuelve 7 dígitos."* No cierro el algoritmo de
`candidates` — el ejemplo usa el emparejamiento exacto más el arte
alternativo conocido (`cards.alternate_art_of`), pero **no está decidido**
si debe intentar además candidatos por distancia de edición sobre el
dígito dudoso. Anotado en `06`, es del propio ADR, no una carencia mía.

**Reutilizado, sin endpoint nuevo:**

- "Corregir" el dígito, "Ninguna: buscar" → `GET /cards?q=` (pantalla 4).
- "Revisar y añadir" → `GET /cards/{id}` para precargar (pantalla 3) +
  `POST /collection-items` para guardar (pantalla 6).
- "Introducir los datos a mano" → salta directo a pantalla 6 sin pasar por
  `card-scans`.

## Pantalla 10 — Acceso admin

Mockup real revisado (`Login.dc.html`). **No se cierra el contrato** —
depende de `ADR-003`, hoy `Propuesta`, y la pregunta que lo desbloquea
("¿el frontend se sirve desde el mismo origen?") decide el mecanismo
entero (cookie de sesión vs JWT en header), no solo el payload. Diseñar el
body de un `POST /auth/login` ahora sería adivinar la respuesta del ADR
antes de que exista.

Lo único que sí es estable, porque no depende del mecanismo: existe un
endpoint de login con `username`+`password`, y un enlace "Ver la
colección" que no es más que navegar a la pantalla pública sin autenticar
— cero llamada.
