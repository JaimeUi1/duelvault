---
tags: [tfg, adr, modelo-datos, postgresql]
adr: 007
estado: "Aceptada"
fecha-decision: 2026-09-05
redactado: 2026-09-14
depende-de: "[[ADR-001-eleccion-base-de-datos]]"
---

# ADR-007 · ENUM nativo para lo cerrado, tabla de catálogo para lo abierto

## Contexto

El dominio tiene una docena de vocabularios: atributos, marcos, habilidades, tipos de
mágica y de trampa, tipos de monstruo, rarezas, ediciones, idiomas, tipos de producto.

La propuesta previa los resolvía todos igual, con `ENUM` de MySQL, y eso produjo dos
errores opuestos:

- **`rarity` como `ENUM` de 15 valores.** La lista oficial supera los 35 y crece cada año.
  El dataset real ya tiene valores fuera de ese enumerado: `premium gold`,
  `ultra parallel`, `blue ultra`.
- **`race VARCHAR(100)` libre** mientras todo lo demás era `ENUM`. Sin integridad ninguna:
  41 valores distintos, de los que 16 no son Tipos oficiales, entre erratas (`dargon`,
  `inescto`, `deinosaurio`) y valores de otra dimensión colados ahí (`pendulo`, `enlace`,
  `tierra`, `ishizu`).

La pregunta no es "ENUM o tabla", es **con qué criterio se decide cada caso**.

## Decisión

El criterio es **la frecuencia con la que Konami amplía el vocabulario**:

| Va como `CREATE TYPE ... AS ENUM` | Va como tabla de catálogo |
|---|---|
| Atributos (7, sin cambios en 20 años) | Tipos de monstruo (26 hoy, uno nuevo cada 3-4 años) |
| Marcos de monstruo (7) | Rarezas (>35 y creciendo cada año) |
| Habilidades (6) | Tipos de producto |
| Tipos de mágica (6) y de trampa (3) | Idiomas de impresión |
| Edición, estado de conservación, estado de propiedad | |

La regla en una frase: **si añadir un valor nuevo debe ser un `INSERT` y no un `ALTER
TYPE` con despliegue, es una tabla.**

Las tablas de catálogo llevan `code` único más nombre en español e inglés, y en el caso de
`monster_types` también el año de introducción.

## Alternativas

**Todo `ENUM`.** Es lo que hacía la propuesta previa. Ampliar rarezas exigiría `ALTER
TYPE` y un despliegue cada vez que Konami se invente una, que es varias veces al año.

**Todo tabla de catálogo.** Uniforme y defendible. Se descarta porque convierte siete
conjuntos que llevan dos décadas sin cambiar en siete joins permanentes, y pierde la
comprobación en tiempo de definición: con `ENUM` nativo, un valor mal escrito es un error
inmediato de PostgreSQL.

**Texto libre con `CHECK IN (...)`.** Tiene los inconvenientes del `ENUM` (cambiarlo es
una migración) sin la ventaja del tipo.

## Consecuencias

**A favor**

- Añadir la rareza número 36 o el Tipo de monstruo número 27 es una fila en `V*_.sql`, sin
  tocar código Java ni desplegar.
- Los conjuntos cerrados se mapean a `enum` de Java de forma natural y sin join.

**En contra, y asumido**

- **Dos mecanismos conviviendo**, y hay que saber por qué cada cosa está donde está. Este
  documento es esa explicación.
- Si Konami hiciera algo imprevisto (añadir un octavo atributo, por ejemplo), tocaría
  `ALTER TYPE` y despliegue. Se asume: lleva 20 años sin pasar.
- Los `ENUM` de PostgreSQL tienen un detalle práctico incómodo: eliminar un valor no es
  posible sin recrear el tipo. Solo importa si se comete un error al definirlos.
