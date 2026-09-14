---
tags: [tfg, adr, modelo-datos, ubicacion-fisica]
adr: 009
estado: "Aceptada"
fecha-decision: 2026-09-05
redactado: 2026-09-14
depende-de: "[[02-Diseno-de-pantallas]]"
---

# ADR-009 · Las carpetas son una entidad, no un número

## Contexto

El dataset guarda la ubicación física como dos enteros sueltos: `carpeta` y `pagina`.
4.463 de las 4.533 filas los tienen informados, así que es un dato que se ha estado
registrando con constancia durante años.

**Lo que destapó el problema fue una pantalla, no el modelo.** Al diseñar la estantería
quedó claro que un entero suelto no da para nada: hacen falta nombre, color de lomo para
reconocerla de un vistazo, y orden en la estantería, que no tiene por qué coincidir con el
número rotulado en el lomo.

Y al probar el diseño contra casos límite salieron tres defectos más:

- **"Página 5, hueco 3" es ambiguo.** Una hoja de carpeta tiene **dos caras** de 9 huecos,
  así que la ubicación no identifica un bolsillo.
- **Reordenar la estantería era imposible.** Con `shelf_position` único, intercambiar dos
  carpetas choca contra la posición que aún ocupa la otra.
- **La estantería contaba mal.** `SUM(quantity)` sumaba copias guardadas fuera de la
  carpeta, y una cara de nueve huecos declaraba más cartas de las que caben.

## Decisión

**Tabla `binders`** con número de lomo, nombre, color, `slots_per_face` y
`shelf_position`. `collection_items.binder_number` pasa a ser `binder_id` con clave ajena.

**La ubicación son cuatro datos, no dos**: `binder_id`, `page_number` (la hoja), `face`
(`FRONT`/`BACK`) y `slot_number` (1..9 dentro de esa cara). Se lee igual que se busca una
carta en la estantería real: *carpeta 1, página 5, reverso, hueco 3*.

**El número de páginas y el total de cartas no se guardan**: se derivan en la vista
`binder_summary`, que separa `card_count` (cartas físicamente archivadas, con `COUNT`) de
`copy_count` (ejemplares poseídos, con `SUM`). Así no pueden quedar desincronizados.

**Las restricciones de unicidad son `DEFERRABLE INITIALLY IMMEDIATE`**, tanto la del hueco
como el número y la posición de estantería de las carpetas. Los errores siguen apareciendo
en el momento, y el caso de uso de recolocar abre transacción y hace
`SET CONSTRAINTS ... DEFERRED`.

Un detalle de interfaz que arrastra esta decisión: al abrir una carpeta de anillas **no ves
una hoja, ves dos medias hojas**, el reverso de la 5 y el anverso de la 6. La vista de
carpeta abierta se dibuja así.

## Alternativas

**Dejar `binder_number` como entero** y guardar nombre y color en un fichero de
configuración del frontend. Descartado: son datos del dominio, y la carpeta pasa a ser algo
que se crea, se renombra y se reordena.

**Numerar los huecos del 1 al 18 por hoja** y deducir la cara del rango. Descartado: es un
dato escondido dentro de otro, y obliga a hacer cuentas mentales para localizar una carta.

**Contar caras en vez de hojas**, de forma que la hoja 5 sean las páginas 9 y 10.
Descartado por lo mismo: no coincide con lo que está rotulado ni con cómo se busca a mano.

**Índice parcial** en vez de restricción `UNIQUE` para la unicidad de hueco. Era la
primera opción y **no funciona**: en PostgreSQL un índice parcial no admite `DEFERRABLE`.
Además resultó innecesario, porque como los nulos no se consideran iguales entre sí, una
restricción `UNIQUE` normal deja pasar igual todas las filas sin hueco asignado.

**Un disparador que cuente ejemplares por cara** para limitar cuántas caben. Descartado a
propósito: sería lógica de negocio escondida en la infraestructura, justo lo que la
arquitectura hexagonal quiere evitar. La unicidad de hueco ya acota el máximo por
construcción, de forma declarativa y atómica.

## Consecuencias

**A favor**

- La pantalla de estantería tiene todos los datos que necesita sin inventarse nada.
- Recolocar cartas y reordenar carpetas es posible, que era el uso continuo del sistema.
- El límite de cuántas cartas caben en una cara queda garantizado sin contar nada.

**En contra, y asumido**

- La migración tiene un paso extra: crear una carpeta por cada número en uso y enlazar
  cada ejemplar. Nombres y colores se rellenan a mano después, porque el dataset solo tiene
  el número.
- **Los ejemplares importados llegan sin cara ni hueco**, y la restricción de unicidad los
  ignora hasta que se asignen. Es un estado intermedio legítimo, no un error: una carta
  puede estar en una carpeta y una hoja sin colocar todavía.
- Borrar una carpeta con cartas dentro necesita un disparador que limpie toda la ubicación
  a la vez. La clave ajena `ON DELETE SET NULL` solo vaciaría `binder_id` y dejaría la
  página con valor, violando la regla de "todo o nada" y haciendo fallar el borrado entero.
- La comprobación fina, que el hueco esté dentro del `slots_per_face` real de esa carpeta,
  **vive en el dominio**, no en la base de datos, porque necesita consultar otra tabla y
  porque ahí puede explicar el error: *"la página 10 de Magos, reverso, está llena, 9 de
  9"*.
