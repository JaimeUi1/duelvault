---
tags: [tfg, backend, api, convenciones]
depende-de: ["[[02-Diseno-de-pantallas]]", "[[03-Modelo-de-datos]]"]
estado: "En progreso — 4 de 5 convenciones decididas, falta el formato de errores (RFC 9457)"
fecha: 2026-09-15
---

# Convenciones de API

Lo que se decide **una vez y para siempre**, no los 27 recursos. El contrato
de cada endpoint concreto sale de OpenAPI generado desde el código en su
corte vertical; el trabajo previo de qué endpoint hace falta vive en
`[[05-Mapeo-Pantallas-Endpoints]]`.

## 1. Envoltorio de respuesta · decidido

Toda respuesta 2xx tiene la forma:

```json
{
  "metadata": { "timestamp": "2026-09-15T10:32:00Z", "requestId": "a1b2c3d4-...", "apiVersion": "v1" },
  "data": { }
}
```

- **`metadata`**: fijo, siempre los mismos tres campos, sobre la petición —
  nunca sobre el recurso. No lleva paginación.
- **`data`**: forma libre por endpoint. Un recurso único va plano
  (`GET /cards/{id}` → `data` es la ficha). Un listado paginado lleva la
  paginación **dentro de `data`**, no en `metadata`:

```json
"data": { "items": [ ], "page": { "number": 0, "size": 20, "totalElements": 134, "totalPages": 7 } }
```

Un recurso con agregados propios (p. ej. "En mi colección": copias, ediciones,
pagado) también va dentro de `data`, con la forma que le pida ese endpoint —
`{ "summary": {...}, "items": [...] }` no es una regla nueva, es `data`
tomando la forma que ese recurso necesita.

## 2. Parámetro `owned` · decidido

Todo endpoint de listado de **cartas** (`catalog`) lleva `owned`, por defecto
`true`. Política B4 (`07-Casos-limite.md`). Hoy no hace nada (el dataset son
las cartas poseídas); el día que se importe el catálogo Konami completo, es
aditivo. No aplica a endpoints de `collection` — un ejemplar ya es
inherentemente "lo que tienes".

## 3. Paginación y ordenación · decidido

Salió trabajando pantalla 4 (buscador) y pantalla 5 (estadísticas), en
`[[05-Mapeo-Pantallas-Endpoints]]`.

- Query params: `page` (0-based) y `size`.
- Va dentro de `data` (regla 1), nunca en `metadata`:
  `"page": { "number": 0, "size": 20, "totalElements": 134, "totalPages": 7 }`.
- Un listado **sin** paginación (docenas de filas como mucho — `binders`,
  `collection-items` de una carta) no lleva objeto `page`: `data` es el
  array directamente. Envolver algo que nunca pagina es peso muerto.
- Ordenación: query param `sort`, valores nombrados por criterio
  (`NAME_ASC`), no por columna+dirección sueltos. Se amplía la lista de
  valores cuando la pantalla que lo pida lo necesite — no se preinventan.

## 4. Formato de errores (RFC 9457) · pendiente

Sale cuando haya el primer caso real que lo necesite (violación de `CHECK`
o `UNIQUE` llegando como 500 en vez de 4xx explicado).

## 5. Representación de dinero, fechas y enums · decidido

- **Dinero**: `NUMERIC(10,2)` → número JSON (no `string`), dos decimales.
  Sin campo de moneda — el esquema no la lleva
  (`purchase_price`/`sale_price`/`price_snapshots.price`) y el alcance es
  un único propietario en España: **`EUR` implícito en toda la API**, no se
  migra el esquema para algo que no hace falta.
- `purchase_price` es **casi siempre `null`**: el propietario compra
  producto sellado (sobres, cajas, latas), no cartas sueltas — decidido en
  la conversación de pantalla 6. No confundir con `price_snapshots.price`
  (precio de mercado, se registra siempre al dar de alta, `source=MANUAL`
  por defecto).
- **Fechas**: `DATE` → `"YYYY-MM-DD"` (ISO 8601, sin hora). `TIMESTAMPTZ`
  (`metadata.timestamp`, `created_at`) → ISO 8601 completo con offset.
- **Enums**: se serializan por su **nombre** (`"NEAR_MINT"`, `"MONSTER"`),
  nunca por posición ordinal — es literalmente el valor de `CREATE TYPE ...
  AS ENUM` de Postgres, no hay traducción intermedia que mantener.
