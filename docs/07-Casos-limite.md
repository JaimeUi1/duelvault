---
tags: [tfg, testing, casos-limite, modelo-datos, pantallas]
depende-de: ["[[03-Modelo-de-datos]]", "[[02-Diseno-de-pantallas]]"]
estado: "Rondas A y B cerradas y corregidas contra PostgreSQL 16"
fecha: 2026-09-05
---

# Casos límite y pruebas de estabilidad

Ejercicio deliberado de romper el diseño antes de implementarlo: plantear situaciones raras y comprobar qué hace el sistema. Los casos marcados como **probado** se ejecutaron contra el esquema real sobre PostgreSQL 16, no se razonaron sobre el papel.

> Para la memoria: este capítulo demuestra que el diseño se sometió a prueba antes de escribir código, y que los defectos encontrados se corrigieron con evidencia. Vale más que una batería de tests que solo comprueba el camino feliz.

---

## A. Defectos confirmados en el modelo

### A1. No se puede borrar una carpeta que tenga cartas dentro · **probado, falla**

*¿Qué pasa si borro la carpeta 1, que tiene 400 cartas archivadas?*

La clave ajena está declarada `ON DELETE SET NULL`, así que PostgreSQL intenta poner `binder_id` a NULL en cada ejemplar. Pero `page_number` conserva su valor, y eso viola la regla de "la ubicación es todo o nada". **El borrado falla entero**, con un mensaje de error incomprensible para el usuario.

```
ERROR: new row for relation "collection_items" violates check
constraint "ck_collection_items_location"
```

**Corrección.** Al desvincular una carpeta hay que limpiar toda la ubicación, no solo la carpeta. La forma robusta es un disparador `BEFORE DELETE` sobre `binders` que ponga `binder_id`, `page_number` y `slot_number` a NULL en un solo movimiento. Alternativa de producto: prohibir borrar una carpeta no vacía y obligar a vaciarla antes, que probablemente es lo que el usuario espera de todos modos.

### A2. No se puede borrar la carta original de un arte alternativo · **probado, falla**

*¿Qué pasa si borro el Mago Oscuro normal, teniendo registrada la versión de Arkana?*

Mismo patrón: `alternate_art_of` se pone a NULL, `artwork_label` conserva "Arkana", y eso viola la regla de que toda variante debe llevar etiqueta. El borrado falla.

**Corrección.** Disparador que limpie ambas columnas a la vez, o decidir que la variante se promociona a carta independiente al borrar su original.

### A3. Reordenar la estantería es imposible · **probado, falla**

*¿Qué pasa si arrastro la carpeta 1 al segundo puesto?*

`shelf_position` es único, así que un intercambio directo choca contra la posición ya ocupada. La pantalla de estantería está diseñada para reordenar carpetas, y ahora mismo el modelo no lo permite sin trucos.

**Corrección.** Declarar la restricción como `DEFERRABLE INITIALLY DEFERRED`, de forma que la unicidad se compruebe al final de la transacción y no en cada fila. Es el patrón estándar para listas ordenadas.

### A4. Un precio con fecha futura envenena el valor de la colección · **probado, se acepta**

*¿Qué pasa si un scraper mal configurado guarda un precio fechado en 2099?*

Se acepta sin más. Y como "valor hoy" se calcula tomando el snapshot más reciente por fecha, ese precio fantasma pasaría a ser el precio actual de la carta, y contaminaría el total de la colección y la gráfica de evolución.

**Corrección.** `CHECK (observed_on <= CURRENT_DATE)`. Barato y cierra la puerta del todo.

### A5. Dos precios del mismo día se duplican si no se indica la fuente · **probado, se acepta**

*¿Qué pasa si consulto el precio dos veces el mismo día?*

La restricción de unicidad incluye la fuente, y en PostgreSQL dos valores nulos no se consideran iguales. Con la fuente sin informar se colaron dos precios del mismo día para la misma impresión: 3,50 € y 9,99 €. Cuál gana depende del orden de lectura.

**Corrección.** Hacer `source` obligatorio con un valor por defecto (`'MANUAL'`), o usar `UNIQUE NULLS NOT DISTINCT`, disponible desde PostgreSQL 15.

### A6. Caben más cartas en una página de las que tiene huecos · **probado, se acepta**

*¿Qué pasa si meto 13 cartas en una página de 9 huecos?*

Se aceptan las 13 sin una sola queja. Nada limita cuántos ejemplares pueden apuntar a la misma página, y la restricción de unicidad de hueco no ayuda porque solo actúa cuando el hueco está asignado.

**Este es el hallazgo más importante**, porque conecta modelo e interfaz: la pantalla de carpeta abierta dibuja una rejilla de 9 huecos, y se encontraría con 13 cartas que colocar. No está decidido qué hace entonces — ¿las apila?, ¿desborda la rejilla?, ¿muestra un aviso?

**Corrección (revisada).** La primera idea fue un disparador que contara los ejemplares de la página, pero es innecesario y además mete lógica de negocio en la infraestructura, en contra de la arquitectura elegida. Basta con **activar la unicidad de hueco y exigir hueco siempre que haya ubicación**: si cada carta archivada ocupa un hueco y no puede haber dos en el mismo, el máximo por página queda limitado por construcción, de forma declarativa y atómica.

La validación fina (que el hueco esté dentro del tamaño real de esa carpeta) va en el dominio, donde puede dar un mensaje útil: *"la página 10 de Magos está llena, 9 de 9"*.

**Requisito previo: resuelto.** En la colección real no se apilan copias en un mismo bolsillo, y de hecho no se guardan varias copias de la misma carta. La unicidad de hueco **está activada** y probada: rechaza el segundo ejemplar en `(1, 10, 6)`, ignora las filas legadas sin hueco asignado y libera el hueco en cuanto la carta se vende.

**Y decidir aparte** qué muestra la interfaz si el dato ya viene corrupto de la migración.

### A9. Un hueco con `quantity = 3` · **falsa alarma, retirado**

*Si en un bolsillo va una sola carta, ¿qué impide guardar `quantity = 3` en el hueco 4?*

Nada, y **está bien que sea así**. La restricción que se propuso aquí (`CHECK (slot_number IS NULL OR quantity = 1)`) partía de una lectura equivocada de qué significa `quantity`.

El significado real: el hueco localiza el ejemplar **archivado en la carpeta**, y `quantity` cuenta **todas las copias poseídas de esa carta**, incluidas las que se guardan fuera de la carpeta. Una fila con hueco 4 y cantidad 3 dice "tengo tres copias, y la que está archivada está en el hueco 4". Es exactamente lo que la web debe mostrar.

Lo que sí se deriva de esto: **una fila ocupa como mucho un hueco**. Si algún día se quisiera archivar dos copias de la misma carta en dos huecos distintos, habría que partir la fila en dos, la misma operación pendiente de B1.

> Vale la pena dejarlo escrito en la memoria: se estuvo a punto de congelar en el DDL una regla de negocio que resultó ser falsa. Una restricción declarativa es barata de añadir y cara de quitar — cada cambio es una migración. Es el argumento más concreto a favor de que el dominio sea el dueño de las reglas.

### A10. La estantería cuenta más cartas de las que caben · **probado, corregido**

Consecuencia directa de lo anterior. La vista `binder_summary` calculaba las cartas de una carpeta con `SUM(quantity)`, así que sumaba copias que no están dentro. Con seis huecos ocupados y dos filas sin colocar, la carpeta declaraba diez cartas en vez de ocho.

**Corregido**: se separan dos cifras con significados distintos — `card_count` (cartas físicamente archivadas, `COUNT`) y `copy_count` (ejemplares poseídos, `SUM`). La estantería muestra la primera; la segunda es un dato de colección, no de carpeta. Probado: 8 y 10 respectivamente sobre el mismo juego de datos.

### A7. Cambiar el tamaño de página deja huecos imposibles · **probado, se acepta**

*¿Qué pasa si cambio una carpeta de 9 a 4 huecos por página, teniendo una carta en el hueco 7?*

Se acepta, y queda una carta en un hueco que ya no existe. El `CHECK` de `slot_number` es genérico (1 a 16) y no consulta el tamaño real de su carpeta.

**Corrección.** Por el mismo razonamiento de A6, esto no es trabajo de la base de datos: el `CHECK` genérico se queda como red de seguridad, y la comprobación real —que el hueco cabe en *esa* carpeta— vive en el dominio, que es quien conoce `slots_per_face`.

**Decisión tomada:** todas las carpetas son de 9 huecos por cara y el tamaño no va a cambiar. Si algún día se cambia de tipo de carpeta, será una pantalla de migración específica que recoloque carpeta, página, cara y hueco — no un desplegable en la edición.

### A7 bis. "Página 5" es ambiguo · **defecto de diseño, corregido**

La pregunta anterior destapó algo más gordo: una hoja de carpeta tiene **dos caras de 9 huecos**, y el modelo solo guardaba página y hueco. "Mago Oscuro, página 5, hueco 3" no dice si está en el anverso o en el reverso.

Las dos salidas obvias eran malas. Contar hojas obliga a numerar huecos del 1 al 18 y codificar la cara en el rango, que es un dato escondido dentro de otro. Contar caras convierte la hoja 5 en las páginas 9 y 10, y obliga a hacer cuentas mentales cada vez que buscas una carta.

**Corrección.** Tres datos explícitos: `page_number` (la hoja), `face` (`FRONT`/`BACK`) y `slot_number` (1..9 dentro de esa cara). Se describe una carta igual que al buscarla en la estantería: *carpeta 1, página 5, reverso, hueco 3*. La unicidad pasa a ser `(binder_id, page_number, face, slot_number)`, y `slots_per_page` se renombró a `slots_per_face`, que es lo que siempre midió.

Arrastra un detalle de interfaz que estaba mal: al abrir una carpeta de anillas **no ves una hoja, ves dos medias hojas** — el reverso de la 5 y el anverso de la 6. La vista de carpeta abierta muestra `(5, BACK)` a la izquierda y `(6, FRONT)` a la derecha.

### A8. Fechas de compra imposibles · **probado, se acepta**

*¿Qué pasa si registro que compré una carta en 1990, o que la compraré en 2030?*

Ambas se aceptan. La primera es anterior a la existencia del juego; la segunda está en el futuro.

**Corrección.** `CHECK (purchase_date <= CURRENT_DATE)` como mínimo. Comparar contra la fecha de publicación de la carta es más fino pero requiere disparador, y probablemente no compensa: las reimpresiones lo complican.

### A11. Intercambiar dos cartas de hueco es imposible · **probado, falla**

*¿Qué pasa si quiero cambiar de sitio dos cartas de la misma página?*

Al mover la primera al hueco de la segunda choca con ella, que todavía está allí. Es el mismo problema que A3 con la estantería, y aparece en cuanto se toca la colección: recolocar cartas no es un caso raro, es lo que se hace continuamente.

Y el arreglo de A3 no servía tal cual: en PostgreSQL **un índice parcial no admite `DEFERRABLE`**, solo las restricciones `UNIQUE`, que a su vez no admiten condición.

**Corrección.** Resulta que la condición sobraba: como los nulos se consideran distintos entre sí, una restricción `UNIQUE` normal deja pasar igual todas las filas sin hueco asignado, con la misma semántica que el índice parcial, y además sí se puede diferir. Se sustituye por `UNIQUE (binder_id, page_number, face, slot_number) DEFERRABLE INITIALLY IMMEDIATE`: los errores siguen apareciendo en el momento, y el caso de uso de recolocar abre transacción y hace `SET CONSTRAINTS ... DEFERRED`.

Probado: el intercambio falla sin diferir y funciona difiriendo. Lo mismo se aplicó a `number` y `shelf_position` de las carpetas, para poder renumerarlas y reordenarlas.

### A8. Fechas de compra imposibles · **probado, se acepta**

*¿Qué pasa si registro que compré una carta en 1990, o que la compraré en 2030?*

Ambas se aceptan. La primera es anterior a la existencia del juego; la segunda está en el futuro.

**Corrección.** `CHECK (purchase_date <= CURRENT_DATE)` como mínimo. Comparar contra la fecha de publicación de la carta es más fino pero requiere disparador, y probablemente no compensa: las reimpresiones lo complican.

---

## B. Decisiones de negocio · **cerradas**

### B1. Vender solo algunas copias de una fila · **decidido**

Se parte la fila: la original baja a 2 y nace otra con cantidad 1, estado `SOLD`, su propio `sale_price` y su `sold_on`. Poner la cantidad a 0 está prohibido, correctamente.

**Cada venta es una fila.** No se fusionan, aunque se acaben vendiendo las tres: el precio de venta puede variar de una a otra —12 € una, 8 € las siguientes— y fusionarlas destruiría ese dato. Agrupar "3 vendidas" es trabajo de la pantalla, no de la tabla. Si la copia vendida era la archivada, la fila que queda hereda el hueco.

`sale_price` y `sold_on` se añaden al esquema con tres reglas: solo pueden tener valor en una fila vendida, la venta no puede ser futura y no puede ser anterior a la compra.

### B2. Qué vale una carta de la que no hay precio · **decidido**

Una carta sin valorar **no lleva ningún `price_snapshot`**. Ausencia de dato, no un cero: un snapshot de 0 € contaminaría la gráfica de evolución con una línea plana y haría indistinguible "no lo sé" de "vale cero", que son cosas distintas y la primera es la que interesa contar.

Lo que fuerza la decisión es la pantalla: el formulario obliga a elegir —o pones precio, o marcas explícitamente *"pendiente de valorar"*—, y las estadísticas muestran el total acompañado de *"87 cartas pendientes de valorar"*. Un número que miente por omisión es peor que un número ausente.

No confundir con `purchase_price`, que es lo que pagaste y puede estar informado aunque no haya valoración de mercado.

### B3. Cambiar la clase de una carta · **decidido**

Comprobado contra la documentación oficial de erratas y las wikis: **no hay ningún caso** de una carta que cambiara entre Monstruo, Mágica y Trampa. Lo que sí existe es el cambio de *Magic* a *Spell* en 2004, que fue de nombre; erratas que corrigen el Atributo o el Tipo de un monstruo; y los Géminis, que son de Efecto pero se tratan como Normal en juego — un estado de partida, no el tipo de la carta.

Así que la edición normal **no ofrece** cambiar de clase. Pero hace falta un camino aparte, porque el catálogo propio sí tiene errores de clasificación: una acción explícita de *"corregir clasificación"* que avise de que se van a descartar los datos específicos de la clase anterior.

Ojo con no confundir dos cosas: **Normal ↔ Efecto no es un cambio de clase**. Es `frame` y `has_effect` dentro de `monster_cards`, un campo más del formulario, sin nada que destruir — y es justo la corrección que hay que hacer en masa durante la migración.

### B4. El catálogo, ¿incluye cartas que no tengo? · **decidido, con póliza**

Hoy **solo se muestran cartas poseídas**. El estado en gris del buscador queda diseñado pero sin datos que lo alimenten.

El esquema ya soporta lo contrario: una `card` sin `collection_items` es una carta del catálogo que no posees. Lo caro de cambiar de idea más tarde no es la base de datos, son los contratos publicados. Por eso se paga ahora una sola línea: **todo endpoint de listado lleva desde el primer día un parámetro `owned`, con valor por defecto `true`**. Hoy no hace nada. El día que se importe el catálogo completo (~13.000 cartas), el cambio es aditivo y ninguna firma existente se rompe.

Lo que quedaría pendiente ese día, y no antes: importar el catálogo desde una fuente externa, y que las estadísticas digan de qué universo hablan ("173 sets **de 1.240**").

---

## C. Casos de interfaz por resolver

Estos no se pueden probar contra la base de datos, pero rompen pantallas igual:

| Situación | Pregunta sin responder |
|---|---|
| Una carpeta recién creada, con 0 páginas | ¿Qué muestra la vista de carpeta abierta? Está diseñada asumiendo que siempre hay contenido |
| Una carpeta de 200 páginas | El navegador de páginas dibuja una barra por página. Con 200 se vuelve ilegible |
| Una carta con 40 ejemplares | El bloque "En mi colección" lista uno por fila. ¿Se pagina? ¿Se agrupa por edición? |
| La estantería con 1 sola carpeta, o con 60 | Diseñada para unas 12. Con una queda vacía; con 60 no cabe |
| Búsqueda sin resultados | Diseñado como estado, falta redactar qué dice y qué ofrece hacer |
| Un nombre de carta muy largo en la cuadrícula | Las tarjetas tienen altura fija. ¿Trunca, ajusta o desborda? |
| El escaneo detecta un passcode que no está en el catálogo | Ninguna candidata. ¿Ofrece crear la carta desde cero con ese código? |
| El OCR devuelve 7 dígitos | La columna exige exactamente 8. ¿El backend rellena con ceros a la izquierda antes de buscar, o lo rechaza? |
| Se pierde la conexión durante el escaneo | La foto ya está hecha. ¿Se reintenta, se guarda para después, se descarta? |
| El JWT caduca con un formulario largo a medio rellenar | ¿Se pierde lo escrito? Es la forma más rápida de que el usuario odie la aplicación |
| Dos pestañas editando la misma carta | Gana la última en guardar, en silencio. ¿Se detecta con versionado optimista? |
| Un visitante anónimo llama a un endpoint de administración | Debe responder 401/403, nunca 500 ni datos parciales |

---

## D. Lo que sí aguanta

No todo falla, y conviene dejarlo escrito:

- Vender una carta y reutilizar después su hueco: **funciona**, y la regla de "vendida sin ubicación" se cumple. Vender sin borrar la ubicación queda **rechazado**.
- Dos ejemplares en el mismo hueco: **rechazado** desde que se activó la unicidad.
- Huecos no consecutivos en una misma página (1, 3, 9 ocupados y el resto libres): **aceptado**, que es como se ve una carpeta real.
- Filas legadas sin hueco asignado, varias en la misma página: **aceptadas**, porque el índice es parcial y la carga histórica no se rompe.
- Guardar dos ilustraciones distintas del mismo passcode para dos impresiones, más una por defecto: **funciona**, con sus duplicados rechazados.
- Dos restricciones del mismo formato para la misma carta y fecha: **rechazado**, como debe.
- Nombres de carta de más de 255 caracteres: **rechazados** (los nombres reales más largos rondan los 70).
- Cantidad cero: **rechazada**.
- Una carpeta vacía en la vista de estantería: devuelve 0 páginas y 0 cartas sin romperse.

---

## E. Siguiente paso

Los defectos de la sección A están corregidos en el esquema, con un reparto deliberado entre las dos capas:

| Caso | Dónde se corrige | Por qué ahí |
|---|---|---|
| A1, A2 | Disparador en la base de datos | Integridad referencial pura, sin regla de negocio: limpiar columnas que quedan incoherentes al desvincular |
| A3, A4, A5, A8, A11 | Restricción declarativa | Son invariantes de dato, no decisiones |
| A6, A7 | Restricción única + dominio | "En una cara caben nueve cartas" es regla de negocio: va en el dominio, y la unicidad de hueco la sostiene de forma atómica |
| A7 bis | Columna nueva | La cara faltaba en el modelo: es un dato, no una regla |
| A9 | — | Retirado: no era un defecto |
| A10 | Vista | `binder_summary` separa cartas archivadas de ejemplares poseídos |
| B1 | Columnas nuevas | `sale_price` y `sold_on`, con sus reglas de coherencia |

**Dónde se pone el límite entre restricción y dominio.** Una restricción declarativa se justifica cuando cumple las tres condiciones: (1) es estable, no cambia con una decisión de producto; (2) se puede expresar sobre una sola fila, sin consultar otras tablas; (3) una violación corrompe datos de forma cara de detectar después. "Una carta vendida no tiene ubicación" cumple las tres. "En una página caben nueve" falla la (2), porque el tamaño lo dice otra tabla. Y la que se propuso en A9 fallaba la (1) — se demostró falsa el mismo día. Cuando la regla entra en el esquema, el dominio la sigue teniendo: la base de datos la garantiza pase lo que pase, el dominio la explica.

El criterio: **la base de datos garantiza invariantes que no pueden depender del código; el dominio decide y explica.** Un disparador que calcula cuántas cartas caben en una página sería lógica de negocio escondida en la infraestructura, justo lo que la arquitectura hexagonal quiere evitar.

Las correcciones se ejecutaron sobre la cadena completa desde cero, y después una batería de trece pruebas: anverso y reverso de la misma hoja con el mismo número de hueco conviven; repetir hueco en la misma cara se rechaza; un hueco sin cara se rechaza; las filas importadas sin cara ni hueco entran; intercambiar dos cartas falla sin diferir y funciona difiriendo; renumerar dos carpetas entre sí funciona; borrar una carpeta con cartas dentro las deja sin ubicar en vez de fallar; un precio con fecha futura, un segundo precio del mismo día, datos de venta en una fila no vendida y una venta anterior a su compra se rechazan.

Las decisiones de la sección B están cerradas y ya se pueden diseñar los endpoints. Los casos de la sección C alimentan directamente el capítulo de estados vacíos y de error del diseño de pantallas, y siguen abiertos.

Cerrada la ronda, las cuatro migraciones de diseño se **aplastaron en una sola** `V1__init_schema.sql` antes del primer despliegue: no había ninguna base de datos desplegada, así que no documentaban la evolución de un sistema sino la de este documento. Se conservan en `anexo-migraciones-historicas/` como respaldo — el `DROP`/`ADD` de cada corrección es la prueba de que el defecto existió. El esquema aplastado se verificó comparando su volcado con el de la cadena original y repitiendo las trece pruebas: comportamiento idéntico.

**Siguiente:** `04-Diseno-de-API-Endpoints.md`, con dos requisitos que salen de aquí — el parámetro `owned` en todo listado, y un caso de uso explícito de recolocar cartas que abra transacción y difiera la unicidad.
