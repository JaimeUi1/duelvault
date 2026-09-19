---
tags: [tfg, frontend, ui, diseno, brief]
depende-de: ["[[02-Diseno-de-pantallas]]", "[[05-Mapeo-Pantallas-Endpoints]]", "[[07-Casos-limite]]"]
estado: "Brief consolidado — listo para pasar a Claude Design"
fecha: 2026-09-19
---

# Brief de diseño pendiente (para Claude Design)

Todo lo que falta por diseñar visualmente en DuelVault, en un solo sitio. Antes estaba
repartido en tres documentos: este mismo (carencias detectadas desde el backend),
`02-Diseno-de-pantallas §5` (estados y estética) y `07-Casos-limite §C` (casos de
interfaz). Este documento los reúne y es **autocontenido**: se puede pasar a Claude Design
sin que tenga que leer nada más, aunque conviene adjuntar los tres materiales de la
sección 1.3.

Cada punto indica dónde se decidió, por si hay que volver al razonamiento. Cuando algo se
diseñe, se tacha aquí y se actualiza el inventario de `02`.

## 1. Lo que ya está cerrado (no reabrir)

### 1.1 El producto
DuelVault cataloga **una colección real de Yu-Gi-Oh!** (unas 4.500 filas históricas). Un
único propietario administra; hay una vista pública anónima de solo lectura. Es **web
responsive, no app nativa**; el escaneo se hace con la cámara del móvil desde el navegador.

### 1.2 Dirección visual y sistema de diseño
- **Híbrida.** La entrada (estantería y carpeta abierta) es oscura y táctil: representa la
  parte física. Todo lo demás —detalle, buscador, estadísticas, formularios— es claro y
  legible, porque son pantallas de leer y comparar.
- **Tipografías:** Instrument Serif para títulos y cifras destacadas; Space Grotesk para
  interfaz y texto corrido. Descartadas Inter y Roboto.
- **Color por tipo de carta**, ancla visual del producto (cabecera de la ficha, miniaturas,
  huecos de la carpeta, filtros):

  | Tipo | Color | | Tipo | Color |
  |---|---|---|---|---|
  | Monstruo Normal | `#FFCE1F` | | Xyz | `#1F2026` |
  | Monstruo de Efecto | `#FF7A1A` | | Enlace | `#2563EB` |
  | Ritual | `#3B82F6` | | Mágica | `#00C08B` |
  | Fusión | `#A855F7` | | Trampa | `#F5308E` |
  | Sincronía | `#D5D5DC` | | | |

- **Accesibilidad:** el color nunca es el único portador de información, siempre va con la
  etiqueta de texto. En gráficas no se usa como paleta categórica (el trío
  amarillo/verde/rosa no supera el umbral de daltonismo deuteranope): barras en un solo tono
  e identidad por etiqueta directa.
- **Sin propiedad intelectual ajena:** las ilustraciones son marcadores de posición; no se
  reproducen artes ni logotipos oficiales de Konami.
- **Los campos mostrados dependen de la clase de carta.** Un monstruo enseña Atributo,
  Nivel, Tipo y ATK/DEF; una mágica enseña Icono, Duración y Velocidad. Nunca se muestran
  campos vacíos que no apliquen.

### 1.3 Pantallas ya diseñadas y materiales a adjuntar
Diez pantallas con boceto aprobado, en el lienzo
`https://claude.ai/code/artifact/0dad5f4c-3aa6-4854-8234-db419690af46`:

| # | Pantalla | Fichero del boceto |
|---|---|---|
| 1 | Landing / Estantería | `Main.dc.html` |
| 2 | Carpeta abierta | `CarpetaAbierta.dc.html` |
| 3 | Detalle de carta | `DetalleCarta.dc.html` |
| 4 | Buscador y listado | `Buscador.dc.html` |
| 5 | Estadísticas | `Estadisticas.dc.html` |
| 6 | Alta / edición | `AltaCarta.dc.html` |
| 7 | Escaneo (captura) | `Escaneo.dc.html` |
| 8 | Escaneo (resultado dudoso) | `EscaneoResultado.dc.html` |
| 9 | Detalle en móvil | `DetalleMovil.dc.html` |
| 10 | Acceso admin | `Login.dc.html` |

A adjuntar: este documento, `02-Diseno-de-pantallas.md`, `duelvault-tokens.css` y el lienzo.

### 1.4 Vocabulario del dominio (para no inventar términos)
- **Carta** (la abstracta: nombre, efecto, passcode), **impresión** (una versión concreta:
  set, número, rareza, edición, idioma) y **ejemplar** (una copia que se posee).
- **Ubicación física** = carpeta + hoja (página) + **cara** (anverso/reverso) + hueco. Se lee
  como se busca en la estantería real: *«carpeta 1, página 5, reverso, hueco 3»*. Una cara
  tiene 4, 8, 9, 12 o 16 huecos según la carpeta (lo normal, 9). Al abrir una carpeta se ven
  **dos medias hojas**: el reverso de la 5 y el anverso de la 6.
- **La cantidad cuenta todas las copias; el hueco localiza solo la archivada.** Una fila con
  hueco 4 y cantidad 3 es correcta.
- Estado del ejemplar: en propiedad, en venta, vendido. **Una vendida no tiene ubicación.**
- **Precio pagado** (lo que costó el ejemplar; casi siempre vacío, porque se compra por
  sobre o caja) **no es** el **precio de mercado** (lo que vale hoy; se registra siempre al
  dar de alta).

### 1.5 Cómo responde el sistema (lo que la interfaz tiene que poder mostrar)
Los errores llegan en un formato estándar con un texto en español para humanos:

| Situación | Qué debe ver la persona |
|---|---|
| Campo mal rellenado (400) | El mensaje bajo el campo concreto |
| No existe lo pedido (404) | Aviso de que ya no está |
| Choca con el estado actual (409) | Un aviso con la elección posible (p. ej. el duplicado del bloque A) |
| Regla de negocio incumplida (422) | Explicación útil, p. ej. *«la página 10 de Magos, reverso, está llena, 9 de 9»* |
| Fallo inesperado (500) | Mensaje genérico con opción de reintentar |

## 2. Qué hay que diseñar

Prioridad **sugerida** (la decides tú): A, B y C bloquean el uso real, porque sin ellos no se
pueden dar de alta cartas de un set nuevo ni colocar las ~4.500 filas migradas.

| Bloque | Qué | Prioridad sugerida |
|---|---|---|
| A | Alta de carta completa (pantalla 6) | 1 |
| B | Colocar, mover y vender ejemplares | 1 |
| C | Pantalla 11: Sets (nueva) | 1 |
| D | Gestión de carpetas (pantalla 1) | 2 |
| E | Buscador: panel de filtros y modos (pantalla 4) | 2 |
| H | Estados transversales | 2 |
| F | Detalle y estadísticas (3 y 5) | 3 |
| G | Escaneo (7 y 8) | 3 |

Para cada bloque: **Falta** (lo que no existe), **Decidido** (restricciones, no se reabre) y
**Abierto** (donde se espera propuesta).

---

### Bloque A · Alta de carta completa (pantalla 6)

El boceto solo dibuja el alta de un **Monstruo Normal**.

**Falta**
- **Variantes por clase y marco**, probadas contra el boceto:
  - Control explícito de **«¿tiene efecto?»**: en Fusión, Sincronía, Ritual, Xyz y Enlace no
    se deduce del marco (sí en Normal y Efecto).
  - **Nivel, Rango y Link Rating son excluyentes**: el campo cambia según el marco (Xyz pide
    Rango, Enlace pide Link Rating). Hoy es un único campo «Nivel».
  - **Flechas de Enlace**: hasta 8 posiciones, y tantas marcadas como el Link Rating. No
    existe en el boceto.
  - **DEF oculto para Enlace**, que nunca la lleva.
  - **Péndulo** despliega la **Escala** (obligatoria si se marca) y un **segundo texto**,
    distinto del texto de efecto.
  - **Mágica y Trampa** no tienen estado dibujado: qué sustituye al bloque «Datos de
    monstruo» (tipo de Mágica o de Trampa). Tampoco **Ficha** ni **Habilidad**, que pueden
    no tener passcode.
- **Precio de mercado.** El boceto solo tiene «Precio pagado». Falta el campo de lo que vale
  hoy, distinto del anterior. **El formulario obliga a elegir: o se pone un precio, o se
  marca explícitamente «pendiente de valorar»** (`07 §B2`); una carta sin valorar no lleva
  ningún precio, nunca un cero.
- **Aviso de duplicado.** Hoy solo contempla el alta de algo nuevo. Cuando ya tienes esa
  carta con otra ubicación, aparece un aviso con dos acciones: *«juntar con las que ya
  tengo»* o *«guardar aparte»*. Texto de referencia: *«Ya tienes 3 copias en la carpeta 3.
  Esta la quieres archivar en la carpeta 7: ¿juntarla con las otras (pierde su ubicación
  propia) o guardarla aparte?»*.
- **Atajo «+ Crear set»** en el selector de set (ver bloque C): la opción, el diálogo y el
  estado «set no encontrado» del selector.
- **Edición.** El nombre dice «Alta / edición» pero solo existe el alta. Faltan dos flujos:
  corregir una carta ya catalogada y corregir un ejemplar ya registrado (precio, ubicación,
  estado, notas). Nunca se dispara desde el escaneo.

**Decidido**
- El aviso de duplicado **solo salta si la ubicación no coincide**. Si coincide, se suma a la
  cantidad sin preguntar. El precio no cuenta: el de mercado se actualiza siempre y el de
  compra casi nunca está relleno.
- El alta pide **carpeta y página**. Cara y hueco no se piden aquí (ver bloque B).
- Clasificación de campos ya fijada en `docs/05` (pantalla 6).

**Abierto**
- Cómo se distinguen visualmente «Precio pagado» y «Precio de mercado» para que no se
  confundan.

---

### Bloque B · Colocar, mover y vender ejemplares

Ninguna de estas operaciones tiene pantalla ni flujo. Son el uso continuo del sistema.

**Falta**
- **Colocar un ejemplar por primera vez** (asignar cara y hueco). Los ejemplares migrados
  llegan a una carpeta y página pero **sin cara ni hueco**; son miles. ¿Desde la carpeta
  abierta pulsando un hueco vacío? ¿Con una cola de «sin colocar» por carpeta? Tiene que ser
  rápido, porque se hará muchas veces seguidas.
- **Recolocar cartas**: mover una carta a otro hueco e **intercambiar dos de sitio**.
- **Vender**: elegir cuántas copias y a qué precio y fecha. Vender 1 de 3 deja la original en
  2 y crea una fila aparte, vendida. **Cada venta es una fila**, y agrupar «3 vendidas» es
  trabajo de la pantalla. Si la copia vendida era la archivada, la otra hereda el hueco.
- **Marcar en venta** (estado intermedio, no vendida todavía).
- **Borrar una carta o un set de los que se poseen ejemplares.** Es un error correcto, pero
  la interfaz debe explicarlo: qué ejemplares lo impiden y qué hacer, no un mensaje sobre una
  tabla que la persona no ha tocado (caso A12).
- **Hueco lleno o fuera de rango**: mensaje de error con contexto (ver 1.5).

**Decidido**
- Un hueco físico admite **una sola carta**.
- Una vendida **no tiene ubicación** y su hueco queda libre de inmediato.
- Los huecos no tienen por qué ser consecutivos: una carpeta real tiene huecos vacíos.

---

### Bloque C · Pantalla 11: Sets (nueva, sin boceto)

Decidido el 2026-09-19: **una sola pantalla** con el listado de sets y el alta. Contrato en
`05`, sección «Sets».

**Falta**
- **El listado**: tarjetas o tabla, con nombre, prefijo (`RA01`), tipo de producto, fecha de
  salida y el **avance** (números que se poseen frente al total del set, que puede faltar).
- **El interruptor «Mis sets / Todos»**, su estado por defecto («Mis sets») y qué se ve en
  «Todos» cuando aún no se ha importado el catálogo completo (casi lo mismo que «Mis sets»).
- **El estado vacío**: no se posee ningún set.
- **El botón «Nuevo set» y su formulario** dentro de la misma pantalla (panel o diálogo).
  Campos: prefijo (obligatorio, único, hasta 10 caracteres), nombre por idioma (al menos
  uno), tipo de producto, fecha de salida, total de cartas. Error de prefijo repetido: ofrece
  ir al set que ya existe.
- **El enlace de cada set al buscador** con el filtro de set puesto.
- **El atajo «+ Crear set»** dentro del formulario de alta (bloque A): mismo formulario,
  precargando el prefijo del número de set que ya se escribió (`RA05-SP024` → `RA05`).
- La cifra «173 sets» de la estantería y de estadísticas podría enlazar aquí.

**Decidido**
- El buscador es **solo de cartas**. Los sets no se buscan ahí.
- Una sola pantalla de alta **no** basta: el atajo dentro del formulario de alta se mantiene,
  para no romper el flujo de dar de alta varias cartas seguidas de un set nuevo.

---

### Bloque D · Gestión de carpetas (pantalla 1)

**Falta**
- **Alta de carpeta.** «Añadir carpeta» está dibujado como hueco punteado, pero no hay
  formulario. Campos: número del lomo, nombre, color del lomo, huecos por cara (4, 8, 9, 12
  o 16), posición en la estantería, notas.
- **Editar una carpeta.**
- **Reordenar la estantería** (la posición es independiente del número del lomo).
  Intercambiar dos carpetas es una operación normal.
- **Borrar una carpeta**: las cartas dentro quedan sin ubicar; hace falta un aviso claro.

**Decidido**
- La estantería se diseñó para unas 12 carpetas (ver bloque H para los extremos).

---

### Bloque E · Buscador: panel de filtros y modos (pantalla 4)

El panel dibujado cubre 5 grupos (tipo de carta, atributo, nivel, en mi colección, rareza).
El sistema soporta bastantes más, ninguno con control en el boceto.

**Falta: controles para todas estas dimensiones.** Según la forma del dato:

| Forma | Filtros | Control sugerido |
|---|---|---|
| Lista de opciones | tipo de carta, tipo de monstruo, atributo, marco, habilidades, tipo de Mágica, tipo de Trampa, arquetipo, categoría de efecto, rareza, edición, idioma de impresión, estado del ejemplar, estado de conservación, restricción (banlist) | Casillas o chips, cada opción con su recuento |
| Rango | nivel, rango Xyz, Link Rating, escala de Péndulo, ATK, DEF | Slider de dos extremos |
| Sí / no | con efecto, es Péndulo, solo las que tengo, duplicadas | Interruptor o casilla |
| Texto | caja de búsqueda, índice alfabético | Ya existen |
| Selector con búsqueda | **set** | Se escribe y sugiere (hay cientos de sets; no cabe una lista) |

**Falta: estados del panel**, derivados de reglas ya decididas:
- Un grupo cuya lista de opciones viene **vacía** (la dimensión no aplica, p. ej. Atributo
  con Mágicas) se **oculta o se desactiva**.
- Un control numérico cuyo rango llega **nulo** se **desactiva** (p. ej. Nivel con Enlace).
- Una opción con **recuento 0** se ve, pero sin resultados.
- El chip activo «Lanzador de Conjuros» (tipo de monstruo) prueba que la intención existe,
  pero su sección no aparece completa en el lienzo.

**Falta: el tercer modo de búsqueda**, por **concepto** («invocar cementerio» encuentra
*Renacimiento del Monstruo*: palabras sueltas en cualquier orden). Existe en el sistema pero
ningún control lo dispara. Hace falta un segundo campo, un interruptor o un atajo de sintaxis
en la misma caja.

**Decidido**
- La caja única busca **a la vez** en nombre, texto de efecto y passcode. No detecta formato
  ni pide elegir modo.
- El recuento de cada opción es **reactivo**: cambia con los filtros ya activos.
- El filtro de set **no lleva recuentos** (selector con búsqueda).
- El listado es una fila por carta, aunque se tengan varias impresiones.
- El estado en gris de las cartas no poseídas ya está diseñado.

---

### Bloque F · Detalle de carta y estadísticas (pantallas 3 y 5)

**Falta**
- **Una carta con muchos ejemplares** (p. ej. 40): el bloque «En mi colección» lista uno por
  fila. ¿Se pagina? ¿Se agrupa por edición? (`07 §C`)
- **Estadísticas**: el selector «Últimos 24 meses» no deja claro a qué afecta. Solo la
  gráfica de evolución muestra fechas. ¿Filtra también «Composición» y «Cartas más
  valiosas» o es solo de la gráfica?
- **«N cartas pendientes de valorar»** junto al valor total (`07 §B2`): comprobar que el
  boceto lo incluye.

**Decidir antes de diseñar**
- La lectura romanizada del nombre japonés («Burakku Majishan») del boceto **no tiene dato**
  detrás. Se añade el dato o se quita del diseño.

**Decidido**
- El valor mostrado es lo que se posee **hoy**, valorado con el precio de cada fecha; no es
  la cartera histórica exacta.

---

### Bloque G · Escaneo (pantallas 7 y 8)

**Falta**
- **El passcode detectado no está en el catálogo**: no hay candidatas. ¿Se ofrece crear la
  carta desde cero con ese código? (`07 §C`)
- **El OCR devuelve 7 dígitos** cuando el código son 8: ¿se rellena con un cero a la
  izquierda o se rechaza? (Es también una decisión de backend, del ADR-005.)
- **Se pierde la conexión con la foto ya hecha**: ¿se reintenta, se guarda para después o se
  descarta?
- **Candidatas en el caso general**: el boceto dibuja un caso (arte alternativo conocido)
  que no cubre las demás. Cómo se muestran candidatas por un dígito dudoso.

**Decidido**
- El escaneo se diseña por su **caso peor**: la duda, no el éxito. Corregir un dígito y salir
  a mano deben ser siempre posibles («Ninguna: buscar», «Introducir los datos a mano»).

---

### Bloque H · Estados transversales

Aplican a todas las pantallas. Existen convenciones esbozadas, sin escribir.

**Falta**
- **Estados de carga, vacío y error de cada pantalla.**
- **Plan B de la animación de la estantería**, por si resulta cara de implementar.
- **Extremos de contenido** (`07 §C`):

  | Situación | Pregunta |
  |---|---|
  | Carpeta recién creada, con 0 páginas | ¿Qué muestra la carpeta abierta? Está pensada para que siempre haya contenido |
  | Carpeta de 200 páginas | El navegador de páginas dibuja una barra por página y se vuelve ilegible |
  | Estantería con 1 carpeta o con 60 | Diseñada para unas 12: con una queda vacía, con 60 no cabe |
  | Búsqueda sin resultados | Diseñado como estado; falta redactar qué dice y qué ofrece |
  | Nombre de carta muy largo | Las tarjetas tienen altura fija: ¿trunca, ajusta o desborda? |

- **Sesión y concurrencia** (`07 §C`):
  - Si la sesión caduca con un **formulario largo** a medio rellenar, ¿se pierde lo escrito?
  - Si hay **dos pestañas editando** la misma carta, ¿se detecta el conflicto y se avisa?

**Decidido**
- Acceso admin (pantalla 10): no hay nada visual pendiente hasta que se cierre el mecanismo
  de autenticación (ADR-003).
- El **contraste real** se revisa con la interfaz implementada, no sobre el boceto.
