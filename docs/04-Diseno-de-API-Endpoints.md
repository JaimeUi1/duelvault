---
tags: [tfg, backend, api, convenciones]
depende-de: ["[[02-Diseno-de-pantallas]]", "[[03-Modelo-de-datos]]"]
estado: "Decidido — 5 de 5 convenciones cerradas"
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

## 4. Formato de errores (RFC 9457) · decidido

Toda respuesta de error es **RFC 9457 puro, en la raíz** — no se envuelve en
`{metadata, data}` (regla 1 es solo para 2xx). `Content-Type:
application/problem+json`.

```json
{
  "type": "https://duelvault.dev/problems/hueco-ocupado",
  "title": "Hueco ya ocupado",
  "status": 409,
  "detail": "El hueco 4 de la cara A (página 2) ya está ocupado",
  "instance": "/collection-items/17/ubicacion"
}
```

- **`type`**: URI estable, no necesita resolver a una página real (RFC 9457
  lo permite como identificador). Es la clave que usa el cliente para
  discriminar el error por código, nunca por texto de `detail`.
- **`detail`**: texto en español para humanos, puede reformularse sin que
  cambie el contrato.
- **`instance`**: la ruta de la petición que falló.
- Miembro de extensión `errors: [{ "field", "detail" }]` cuando el error es
  de validación de campos (Bean Validation en el DTO de entrada).

### Mapeo de status

| Status | Categoría | Ejemplo |
|---|---|---|
| 400 | Validación de campos (Bean Validation) | `quantity` negativo en el body |
| 401 / 403 | Reservado — se activa en el paso 7 (seguridad) | anónimo contra endpoint de admin |
| 404 | Recurso no encontrado | `GET /cards/{id}` con id inexistente |
| 409 | Conflicto de estado (concurrencia / unicidad) | hueco ya ocupado (A11), borrar carta con ejemplares (A12) |
| 422 | Invariante de dominio violada | vender más copias de las que hay, hueco fuera de `slots_per_face` |
| 500 | No reconocido / fallback | violación de `CHECK`/`UNIQUE` sin traducir, excepción no controlada |

422 se reserva para lo que **nunca** podría haber funcionado (regla de
negocio); 409 para lo que falla por chocar con el estado actual de otra fila
(concurrencia, unicidad). Evita meter ambos casos bajo un único 409 genérico.

### Jerarquía de excepciones

Tres clases abstractas en `shared.domain` (`RecursoNoEncontradoException`,
`ConflictoDeEstadoException`, `InvarianteDeDominioException`), todas
`extends RuntimeException`, cero import de Spring/JPA — el test de ArchUnit
del paso 2 las cubre igual que al resto de `domain`. Cada una implementa una
interfaz mínima `TipoDeError { String tipo(); Object[] argumentos(); }`:
`tipo()` es el slug fijo (`"hueco-ocupado"`), `argumentos()` son los datos
en bruto que necesita el mensaje (id, cantidad, ubicación), **nunca** texto
ya formateado — ver más abajo por qué.

Cada excepción concreta vive en el dominio de su contexto
(`collection.domain.HuecoOcupadoException extends ConflictoDeEstadoException`)
y no sabe nada de HTTP: el status lo decide la clase abstracta que extiende,
en un único `@RestControllerAdvice` de `shared.infrastructure.in.web` con un
`@ExceptionHandler` por clase abstracta (tres, más uno para validación y uno
de fallback). Añadir una regla de negocio nueva es añadir una excepción
concreta; el handler no se toca.

Las violaciones de `CHECK`/`UNIQUE` que hoy llegan como 500 se atrapan en el
**adaptador JPA** (`infrastructure/out/jpa`), no en el handler: el
repositorio captura `DataIntegrityViolationException`, mira el nombre de la
constraint y relanza la excepción de dominio concreta. Si no reconoce la
constraint, la deja subir tal cual y la coge el fallback genérico (500) — el
handler global nunca ve una excepción de Hibernate.

### Mensajes: catálogo en base de datos, no texto en el código

Decisión deliberada, evaluada contra la alternativa más simple y descartada
a propósito:

| Opción | Complejidad | Redespliegue para cambiar redacción |
|---|---|---|
| Texto en el constructor de la excepción | ninguna | sí, tocando dominio |
| `MessageSource` + `.properties` | baja | sí, sin tocar dominio |
| **Catálogo en tabla `error_catalog`** | media | no — `UPDATE` en caliente |

Se elige el catálogo en BD **no porque DuelVault lo necesite** (el ciclo de
desarrollo es local y se recarga en segundos) sino como decisión de
aprendizaje explícita — el TFG se usa también para practicar un patrón
aplicable al trabajo, donde el ciclo de despliegue sí es caro (+30 min). Se
documenta el trade-off para que quede explícito en la memoria: es YAGNI
respecto a las necesidades del propio proyecto, y se justifica solo como
ejercicio deliberado.

Tabla:

```sql
CREATE TABLE error_catalog (
    type_slug       TEXT PRIMARY KEY,
    http_status     INT NOT NULL,
    title           TEXT NOT NULL,
    detail_template TEXT NOT NULL,   -- placeholders {0}, {1}... (MessageFormat)
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by      TEXT NOT NULL
);
```

El handler resuelve `tipo()` + `argumentos()` contra esta tabla para
construir `title`/`detail`. Reglas no negociables para que el catálogo no
se convierta en un punto de fallo del propio sistema de errores:

- **Caché en memoria delante de la tabla** (TTL corto), nunca lectura a BD
  en el camino caliente de cada error.
- **Fallback embebido en el binario** si falta la fila o la BD no responde
  — el sistema de errores no puede depender de que la propia BD esté sana.
- `updated_at`/`updated_by` dan auditoría gratis por ser una tabla.

Semilla inicial del catálogo (un slug por excepción concreta) entra en su
propia migración, no en `V1`/`V2` — esas dos son el esquema de dominio y los
datos de referencia de Yu-Gi-Oh!, esto es infraestructura de la API.

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
