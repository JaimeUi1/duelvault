---
tags: [tfg, adr, modelo-datos, yugioh]
adr: 008
estado: "Aceptada"
fecha-decision: 2026-09-05
redactado: 2026-09-14
---

# ADR-008 · Marco y habilidades como dimensiones distintas

## Contexto

La propuesta previa modelaba el tipo de monstruo como un `ENUM` de un solo valor:
`('NORMAL','EFFECT','FUSION','SYNCHRO','XYZ','PENDULUM','LINK')`. Tres cosas fallan ahí, y
todas tienen evidencia en los datos reales:

- **No puede representar combinaciones.** 22 filas del dataset ya llevan dos valores en el
  mismo campo: `sincronía/cantante`, `Xyz/péndulo`, `fusion/pendulo`, `ritual/cantante`,
  `cantante/volteo`.
- **No incluye RITUAL.** Los Monstruos de Ritual no tenían representación posible, y el
  dataset tiene 29.
- **Faltan habilidades enteras** (Volteo y Toon), aunque existían banderas para otras
  cuatro. Incoherente además con `card_scans`, que sí tenía `detected_is_flip` y
  `detected_is_toon`. En el dataset hay 35 cartas de volteo y 11 toon.

La raíz del problema es que ese `ENUM` mezcla **dos dimensiones distintas** que la propia
base oficial de Konami también presenta juntas en un mismo filtro.

## Decisión

Separar las dos dimensiones, más una tercera que se superpone a ambas:

- **`frame`** como columna `monster_frame`: Normal, Efecto, Ritual, Fusión, Sincronía,
  Xyz, Enlace. **Excluyentes entre sí**, exactamente uno.
- **`monster_card_abilities`** como tabla: Cantante, Volteo, Géminis, Espíritu, Toon,
  Unión. **Multivalor**, se combinan entre ellas y con cualquier marco.
- **`is_pendulum`** como booleano aparte, porque Péndulo **no es un marco**: se superpone a
  cualquiera de ellos (existen Fusión/Péndulo y Xyz/Péndulo).

Y una cuarta columna que no se deduce de las anteriores: **`has_effect`**. Existen
monstruos de Extra Deck sin efecto, como las Fusiones Normales del tipo "Gaia el Campeón
Dragón", así que "tiene efecto" no se infiere del marco. Un `CHECK` garantiza la
coherencia: Normal implica sin efecto, Efecto implica con efecto, y el resto de marcos
admiten ambos.

## Alternativas

**Ampliar el `ENUM` con las combinaciones.** `SYNCHRO_TUNER`, `XYZ_PENDULUM`,
`RITUAL_TUNER`... Explota combinatoriamente: 7 marcos × 2 péndulo × 63 combinaciones de
habilidades. Inmantenible.

**Seis columnas booleanas** (`is_tuner`, `is_gemini`, ...), que es lo que hacía a medias la
propuesta previa. Funciona, pero añadir una habilidad nueva es un `ALTER TABLE`, y
consultar "todos los monstruos con alguna habilidad" obliga a un `OR` de seis términos.

**Un campo de texto con los valores separados por barra**, que es literalmente lo que hacía
el dataset legado. Es el origen del problema, no la solución.

## Consecuencias

**A favor**

- Representa fielmente lo que existe en el juego, incluidas las combinaciones raras.
- Añadir una habilidad futura es un valor más en el `ENUM` de habilidades, sin tocar la
  estructura.
- El filtro del buscador por habilidad es un `EXISTS` sobre una tabla, no seis `OR`.

**En contra, y asumido**

- Una tabla más y un join más para pintar la ficha.
- **La migración se complica**: hay que separar por `/` los valores combinados del dataset
  y mapear cada trozo a su dimensión, distinguiendo cuál es marco y cuál habilidad.
- La distinción Normal contra Efecto **no se puede tomar del dataset**, porque el valor
  `normal` se usó también para monstruos de Efecto. Se resuelve consultando la base oficial
  por passcode durante la carga. Es un enriquecimiento puntual en la migración, no una
  dependencia en tiempo de ejecución.
