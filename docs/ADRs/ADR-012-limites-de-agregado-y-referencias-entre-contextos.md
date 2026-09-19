---
tags: [tfg, adr, arquitectura, ddd, agregados, contextos]
adr: 012
estado: "Aceptada"
fecha: 2026-09-19
depende-de: ["[[ADR-002-separar-carta-impresion-ejemplar]]", "[[ADR-004-arquitectura-hexagonal]]", "[[ADR-009-carpetas-como-entidad]]", "[[ADR-011-persistencia-jpa-vs-jdbc]]"]
---

# ADR-012 · Límites de agregado y referencias entre contextos

## Contexto

Este ADR (Architecture Decision Record, registro de decisión de arquitectura) cierra la
decisión abierta **D2** del `ROADMAP.md`, que bloquea la creación de los paquetes
hexagonales.

El ADR-004 ya fijó dos reglas: *un repositorio por raíz de agregado, no por tabla* y
*referencia entre agregados por id*. Pero no dijo **qué es raíz de agregado** entre las 27
tablas, ni **cómo se referencian los contextos** entre sí. Sin eso, al crear los paquetes:

- Cada tabla acaba con su repositorio y el dominio pierde el dueño de sus reglas.
- `shared` se convierte en el sitio donde va todo lo que no se sabe dónde poner.
- Cada contexto importa las clases de los demás, y el hexágono deja de serlo.

Un **agregado** es un grupo de filas que se cargan, se modifican y se guardan como una
unidad, a través de una única clase (la **raíz**) que garantiza sus reglas. Dónde acaba uno
y empieza otro se decide con tres preguntas:

1. ¿La parte existe sin la raíz? Si no, cuelga de ella.
2. ¿Hay una regla que afecte a las dos a la vez? Si sí, van juntas, salvo que juntarlas
   obligue a cargar cientos de filas.
3. ¿Cuántos padres tiene? Lo que pertenece a dos cosas no puede colgar de ninguna.

Hay además dos hechos del proyecto que condicionan la decisión:

- **Propietario único, una base de datos, un despliegue.** No hay servicios separados que
  aislar: la separación entre contextos es de código, no de red ni de datos.
- **Las pantallas cruzan contextos constantemente.** Una carpeta muestra ejemplares (colección)
  con el nombre y la imagen de la carta (catálogo) y su precio (pricing).

## Decisión

### 1. Raíces de agregado

| Contexto | Raíz | Cuelga de ella (sin repositorio propio) |
|---|---|---|
| `catalog` | **`Card`** | `card_translations`, `monster_cards` / `spell_cards` / `trap_cards`, `monster_card_abilities`, `monster_link_arrows`, `card_archetypes`, `card_effect_categories`, `card_limitations`, `card_images` |
| `catalog` | **`CardPrint`** | nada |
| `catalog` | **`CardSet`** | `card_set_translations` |
| `catalog` | **`Archetype`** | `archetype_translations` |
| `catalog` | **`EffectCategory`** | `effect_category_translations` (y su jerarquía por `parent_category_id`) |
| `collection` | **`CollectionItem`** | la ubicación (`Ubicacion`) como objeto valor |
| `collection` | **`Binder`** | nada |
| `pricing` | **`PriceSnapshot`** | nada |
| `scanning` | **`CardScan`** | nada |
| `security` | **`AppUser`** | nada |

**Datos de referencia, no agregados:** `languages`, `monster_types`, `rarities`,
`set_types`. Son listas cerradas o casi, sin comportamiento. Se cargan como valores y se
referencian por código o id; no tienen repositorio con lógica.

**Por qué cada decisión no obvia:**

- **`Card` es un agregado con todo su árbol** porque ninguna de sus partes existe sin ella
  (pregunta 1) y se crea, se corrige y se lee como una unidad: `RegistrarEjemplar` da de
  alta la carta entera de una vez y la ficha (`GET /cards/{id}`) la sirve entera. Las reglas
  que cruzan `cards` con su especialización (un Xyz lleva Rango, un Enlace nunca lleva DEF)
  ya las garantizan los `CHECK` del esquema, y `catalog` se modela ligero (ADR-004): el
  agregado es sobre todo una **unidad de carga y guardado**, no un guardián de invariantes
  complejas. Por eso no existe `MonsterCardRepository`: se carga y se guarda `Card` entera.
- **`CardPrint` es raíz propia y no cuelga de `Card`.** Tiene **dos padres**, la carta y el
  set (`card_id` y `card_set_id`), así que colgarla de uno sería arbitrario (pregunta 3).
  Además, una carta tiene decenas de impresiones y cambia con otro ritmo: cargar *Mago
  Oscuro* para leer su efecto no debe traer todas sus versiones. Y `collection_items` la
  referencia directamente, no a través de la carta (ADR-002: el valor de mercado y lo que se
  posee viven en la impresión).
- **`card_archetypes` y `card_effect_categories` pertenecen a `Card`.** La relación se lee
  desde la carta (la ficha muestra sus arquetipos y categorías) y ninguna pantalla diseñada
  las edita hoy: se pueblan por carga de datos o análisis del texto de efecto. Si algún día
  se editan, será desde la carta, no desde el arquetipo. `Card` guarda referencias por id a
  `Archetype` y `EffectCategory`. La consulta inversa ("las cartas de este arquetipo") es una
  proyección de lectura, no un agregado.
- **`card_images` cuelga de `Card`** aunque una imagen pueda apuntar a una impresión concreta
  (`card_print_id`): esa referencia es un `CardPrintId` opcional, por id. La unicidad de imagen
  por tipo la sostienen los dos índices únicos de la base de datos.
- **`Binder` es raíz separada de `CollectionItem`.** Una carpeta y un ejemplar se pueden
  crear y borrar de forma independiente (una carpeta puede estar vacía, un ejemplar puede no
  estar archivado). Meter la carpeta *dentro* del ejemplar, o los ejemplares dentro de la
  carpeta, obligaría a cargar miles de filas para validar un hueco (las 4.533 de la
  migración, en una sola carpeta grande). La regla que las cruza se resuelve en el punto 3.
- **`PriceSnapshot` es una raíz por observación, no un agregado "historial de precios".**
  Cada fila es una observación (impresión, día, fuente) sin reglas con las demás.
  `RegistrarEjemplar` la escribe y, si ya hay una del mismo día para esa impresión, la
  **sobreescribe** (`docs/05`, pantalla 6): no son registros estrictamente inmutables. Un
  agregado por impresión cargaría toda la serie histórica para escribir un solo punto.

### 2. Referencia entre contextos

**Entre agregados, siempre por id. Entre contextos, además, con estas tres reglas:**

**a) El identificador lo publica su dueño.** `CardPrintId`, `CardId`, `BinderId`… son objetos
valor definidos en el dominio del contexto que posee la raíz. Otro contexto puede importar
**solo esos tipos de identidad** del dominio ajeno, nada más. Se comprueba con un test de
ArchUnit en el paso 2 del roadmap.

**b) Escritura: `collection` no ve el modelo de `catalog`; le pregunta por un puerto.**
Lo que `collection` necesita del catálogo para *decidir* lo declara `collection` como puerto
de salida con sus propios términos. Un adaptador en `collection/infrastructure` lo implementa
llamando al caso de uso de `catalog`. `CollectionItem` guarda un `CardPrintId` y no lleva
ninguna copia de la carta.

El caso que lo pone a prueba es `RegistrarEjemplar` (`docs/05`, pantalla 6): en **una sola
transacción** busca o crea la `Card` por passcode, busca o crea la `CardPrint` por su clave
natural, y registra o fusiona el `CollectionItem`. Por eso el puerto es **de grano grueso**:
*"asegura que existe esta impresión y devuelve su id"*, no una llamada por agregado. Su
parámetro lleva los datos de la carta (marco, atributo, traducciones…) porque, si la carta no
existe, hay que crearla; el adaptador los traduce al comando de `catalog`. Esa traducción es
el coste asumido de no compartir el modelo. Como el adaptador llama a casos de uso de
`catalog` marcados `@Transactional` con propagación por defecto, se unen a la transacción de
`RegistrarEjemplar` en vez de abrir otra.

`scanning` sigue el mismo patrón: su puerto de salida resuelve `passcode → CardId` y las
candidatas de arte alternativo, y `card_scans.matched_card_id` guarda un `CardId`.

**c) Lectura: las pantallas se resuelven con proyecciones SQL, sin pasar por el dominio.**
La estantería, el detalle de carpeta y las estadísticas necesitan nombre, imagen y precio de
la carta junto al ejemplar. Eso es una consulta de pantalla (ADR-011: *agregado contra
proyección*) que devuelve un `record` y puede hacer `JOIN` sobre tablas de varios contextos.
No es un agregado, no se modifica y no respeta invariantes; por tanto no cruza ninguna
frontera de dominio.

**La lectura cruza en las dos direcciones**, no solo de `collection` hacia `catalog`. El
buscador (`GET /cards`, módulo `catalog`) devuelve `ownedQuantity` y filtra por `owned`,
`duplicated`, `status` y `condition`, que son columnas de `collection_items`. Lo mismo pasa con
las candidatas del escaneo, que combinan catálogo y colección. La regla es: **una proyección
vive en el módulo dueño del endpoint y puede leer tablas de cualquier contexto, solo en
lectura.** La dirección de dependencia entre *dominios* sigue siendo una sola; las
proyecciones no son dominio.

### 3. Invariantes que cruzan agregados: quién las garantiza

| Regla | Quién | Por qué |
|---|---|---|
| Un hueco físico admite una sola carta | `UNIQUE` de la base de datos (`uq_collection_items_slot`); el dominio traduce el error | Cruza todos los `CollectionItem` de una carpeta; garantizarla en memoria exige cargarlos todos (ADR-004) |
| El hueco cabe en `slots_per_face` de la carpeta | **Servicio de dominio** en `collection`, que recibe el ejemplar y el `Binder` cargados por el caso de uso | Cruza dos agregados; el dominio puede dar el mensaje útil (ADR-009) |
| Unicidad de impresión (`uq_card_print`) | `UNIQUE` de la base de datos | Cruza las impresiones hermanas de una carta |
| La impresión de un ejemplar existe | Clave ajena + comprobación previa vía puerto (b) | La base de datos lo impide; el caso de uso lo explica antes |
| Borrar una carta o un set con ejemplares poseídos | Puerto de salida en `catalog` que pregunta si hay ejemplares, implementado con una consulta de recuento | Sin la comprobación, el error viene de `collection_items`, una tabla que el usuario no ha tocado |
| Alta de ejemplar registra el precio de mercado | El caso de uso `RegistrarEjemplar` llama a un puerto de salida de `pricing` | Referencia por id, mismo patrón que `CollectionItem` → `CardPrintId` |
| Recolocar cartas modifica varios `CollectionItem` a la vez | Un solo caso de uso, una transacción, con `SET CONSTRAINTS ... DEFERRED` | Excepción asumida a "un agregado por transacción": es la operación para la que existen las restricciones diferibles (ADR-009, ADR-011) |

### 4. Qué entra en `shared`

`shared` contiene **solo lo que ningún contexto posee y que no depende de ninguno**:

- **`Money`** (`collection` guarda el precio pagado, `pricing` el de mercado; ninguno es su
  dueño natural).
- **La jerarquía de errores** (`TipoDeError` y las tres excepciones abstractas, ver
  `docs/04 §4`).

Criterio para cualquier tipo nuevo: **va a `shared` solo si lo usan dos o más contextos y
ninguno de ellos es su dueño natural.** Si tiene dueño natural, vive allí y los demás lo
importan según la regla 2a. Ejemplo: `Passcode` es la identidad natural de `Card`, así que
vive en `catalog`, aunque `collection` lo reciba en un comando.

### 5. Comprobación contra las diez pantallas

Contrastado con `docs/05-Mapeo-Pantallas-Endpoints.md` y `docs/06-Carencias-Diseno-UI.md`
el 2026-09-19. Las carencias de `06` no cambian ninguna frontera, pero dejan cuatro
operaciones sin pantalla que este ADR ya da por hechas:

| Operación | Estado en el diseño | Efecto sobre este ADR |
|---|---|---|
| Recolocar cartas, partir una fila, borrar carta/set con ejemplares (A12) | Sin pantalla (`06`, "Estado") | Los agregados están decididos; el flujo de cada uno se diseña en el paso 8 |
| Editar una carta o un ejemplar ya registrado | Sin pantalla (`06`, pantalla 6) | Confirma `Card` como unidad de carga y guardado |
| Alta de carpeta | Hueco punteado, sin formulario (`06`, pantalla 1) | `Binder` es raíz propia; su alta será un caso de uso propio |
| **Crear un set** | **Ninguna pantalla ni endpoint lo contempla.** El alta de ejemplar (`docs/05`) parte de un `cardSetId` que ya existe | Nueva carencia, no recogida en `06`. `CardSet` se comporta hoy como dato cargado por migración o importación; no hay caso de uso que lo cree |

El resto de pantallas (1, 2, 3, 5, 9) son proyecciones de solo lectura y encajan en la regla
2c sin tocar ningún agregado.

## Alternativas

**`CardPrint` dentro del agregado `Card`.** Es lo más intuitivo (una impresión "es de" una
carta). Descartada por los dos padres, porque obliga a cargar todas las impresiones al leer
una carta y porque `collection_items` no pasa por la carta para llegar a ella.

**Un repositorio por tabla.** Es lo que sale por defecto de Spring Data. Descartada: nadie es
dueño de las reglas y cualquiera puede dejar una fila en estado inválido. Es exactamente el
problema que el ADR-004 quiere evitar.

**Un agregado `Colección` que contenga carpetas y ejemplares.** Garantizaría en memoria "el
hueco cabe" y "un hueco, una carta". Descartada: cada alta o recolocación cargaría toda la
colección, y las operaciones sin relación entre sí se bloquearían mutuamente. Los dos casos
se resuelven mejor con `UNIQUE` y un servicio de dominio.

**`collection` con su propio modelo de la carta** (`CartaEnColeccion` con nombre, imagen y
rareza copiados). Es lo que haría un sistema de servicios separados. Descartada: no hay ninguna
regla de `collection` que necesite esos datos, y copiarlos crea un problema de sincronización
que hoy no existe (una base de datos, un despliegue). Se reconsideraría solo si `catalog` y
`collection` se separaran en servicios distintos.

**`collection` importa `Card` y `CardPrint` de `catalog`.** Simple y sin mapeos. Descartada:
acopla los modelos, obliga a cargar el árbol completo de la carta para cada ejemplar y hace
que un cambio en `catalog` rompa `collection`.

**Los identificadores en `shared`.** Evita que un contexto importe de otro. Descartada: `shared`
acabaría conteniendo la identidad de todo, que es el "cajón" que este ADR quiere evitar.

## Consecuencias

**A favor**

- Cada paquete tiene un dueño claro y `shared` tiene un criterio de admisión escrito.
- `collection` puede evolucionar y testearse sin cargar el modelo de `catalog`.
- Las pantallas que cruzan contextos se resuelven con SQL directo, sin cadenas de casos de
  uso ni copias de datos.
- El test de ArchUnit del paso 2 tiene una regla concreta que comprobar: el dominio de un
  contexto solo importa tipos de identidad de otro.

**En contra, y asumido**

- **Las proyecciones de lectura leen tablas de varios contextos, en las dos direcciones.** El
  acoplamiento existe a nivel de esquema, no de dominio. Se acepta porque es un solo
  despliegue y solo lectura; quedaría como deuda si los contextos se separaran. El caso más
  visible es el buscador de `catalog`, que depende de `collection_items` por el parámetro
  `owned` (política B4).
- **`RegistrarEjemplar` es un caso de uso grande** (carta, impresión y ejemplar en una
  transacción) y su puerto hacia `catalog` es de grano grueso, con traducción de datos en el
  adaptador. Es el punto del diseño con más riesgo de fricción.
- **El adaptador de `collection` llama a un caso de uso de `catalog`.** No viola la regla de
  que los casos de uso no se llaman entre sí (el que llama es un adaptador, fuera de la
  capa de aplicación), pero es un salto entre contextos que hay que mantener a la vista.
- **`Card` es un agregado grande** (traducciones, especialización, imágenes, clasificación).
  Cargarlo entero para cambiar una errata es más caro que actualizar una fila. Se acepta
  porque `catalog` se modela ligero y se escribe rara vez.
- **Varias reglas quedan en la base de datos**, no en memoria (unicidad de hueco y de
  impresión). Es la excepción que ya recogía el ADR-004 y hay que explicar el error desde el
  dominio.
- `CLAUDE.md` lista `Passcode` entre los objetos valor de `collection`. Con este ADR, el
  dueño es `catalog`; habrá que ajustarlo cuando se acepte.

## Confirmación de las decisiones (2026-09-19)

1. **`CardPrint` como raíz propia**, en vez de dentro de `Card`. *Conforme (2026-09-19).*
2. **`Binder` separada de `CollectionItem`**, con el servicio de dominio para "el hueco cabe".
   *Conforme (2026-09-19).*
3. **Referencia entre contextos: id + puerto de grano grueso para escritura, proyección SQL
   en las dos direcciones para lectura**, frente a copiar un modelo propio de la carta en
   `collection`. Revisado contra las diez pantallas. *Conforme (2026-09-19).*
4. **`card_limitations` y `card_images` dentro de `Card`.** *Aceptado como provisional:*
   revisar en el paso 5 (catálogo en lectura), al escribir el mapper. `card_images` es la
   más dudosa, porque una imagen con `card_print_id` es conceptualmente el arte de esa
   impresión. Si cambia, se hace con un ADR que sustituya a este, no editándolo.
