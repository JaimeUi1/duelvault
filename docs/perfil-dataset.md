---
tags: [tfg, datos, yugioh]
fuente: "cartas.sql — volcado MySQL de la colección personal (4533 filas)"
generado: 2026-09-02
---

# Perfil del dataset histórico (`cartas.sql`)

Resumen del análisis del volcado real de la colección. Sustituye al archivo `cartas.sql`
completo (2,4 MB) como material de referencia: contiene las cifras y las anomalías, que
es lo único que hace falta para razonar sobre el diseño.

> ⚠️ Este dataset **no es fuente de verdad** del dominio. Se rellenó a mano durante años
> y contiene erratas y clasificaciones incorrectas. Sirve para saber qué casos reales
> existen; la autoridad son las reglas oficiales de Yu-Gi-Oh! TCG.

## Estructura de origen

Una única tabla MySQL `cartas`, sin normalizar, que mezcla en cada fila tres cosas
distintas: los datos canónicos de la carta, los de su edición concreta y los de la copia
poseída.

Columnas: `id`, `nombre`, `descripcionEfecto`, `descripcionPendulo`, `tipoCarta`,
`tipoTrampa`, `tipoMagica`, `tipoMonstruo`, `categoriaMonstruo`, `coleccion`,
`coleccionAbrev`, `nivel`, `ataque`, `defensa`, `numLink`, `escala`, `atributo`,
`rareza`, `precio`, `idCarta`, `fechaUpdate`, `venta`, `copias`, `pagina`, `carpeta`.

Semántica confirmada de los campos ambiguos:
- `idCarta` = passcode oficial de Konami (guardado como entero → pierde ceros iniciales).
- `venta` = 0 no está en venta · 1 en venta · 2 vendida.
- `fechaUpdate` = fecha de alta en la base de datos y/o de última consulta del precio.
  **No** es fecha de compra: esa información nunca se registró.
- `carpeta` / `pagina` = ubicación física en las carpetas de archivado.

## Cifras generales

| Métrica | Valor |
|---|---|
| Filas | 4533 |
| Cartas distintas (por passcode) | 3363 |
| Copias totales (`SUM(copias)`) | 7004 |
| Sets distintos | 173 |
| Rango de precios | 0,02 € – 60 € |
| Rango de fechas | 2023-11-11 – 2026-08-31 |
| Monstruos / Mágicas / Trampas | 2762 / 1033 / 720 |
| Fichas y cartas de Habilidad | 14 |
| Filas con carpeta y página | 4463 |

## Casos reales que el modelo debe soportar

- **Un mismo número de set en varias rarezas:** 202 códigos aparecen con más de una
  rareza (`RA01-SP057` existe en ultra, ultimate y quarter century secret).
- **ATK/DEF no numéricos:** 18 ATK y 8 DEF con `'?'`, `'????'` o `'X000'`.
- **Cartas sin passcode:** 32 filas, incluidas las 14 Fichas y Habilidades.
- **Passcodes con ceros iniciales perdidos:** 4023 de 8 dígitos, 434 de 7, 32 de 6,
  9 de 5, 1 de 4 y 1 de un solo dígito.
- **Categorías combinadas:** 22 filas con dos categorías en el mismo campo
  (`sincronía/cantante`, `Xyz/péndulo`, `fusion/pendulo`, `ritual/cantante`,
  `cantante/volteo`, `normal/volteo`).
- **Dos idiomas:** 3890 cartas con código de región SP y 130 con EN.
- **Atributo DIVINE:** 12 cartas.
- **Escalas de péndulo** guardadas como texto `'4/4'`, siempre simétricas.
- **Link ratings** presentes: 1 a 5.

## Anomalías conocidas (a limpiar en la migración)

- **`tipoCarta`:** `monstruo` (2751) junto a `mosntruo` (10), `monstro`, `magico`,
  `magia`, una cadena vacía y un `NULL`.
- **`categoriaMonstruo`:** `fusion`/`fusión`, `sincronia`/`sincronía`,
  `Xyz`/`xyz`/`Xyx`/`Xz` como valores distintos. Y sobre todo: **`normal` se usó tanto
  para monstruos sin efecto como, por error, para monstruos de Efecto** → ese campo no
  sirve para distinguir Normal de Efecto.
- **`rareza`:** 30 valores distintos con duplicados por errata (`platinum secret` vs
  `planitum secret`, `ultra parallel` vs `ultra prallel`, `ultra ` con espacio final).
- **`tipoMonstruo`:** 41 valores distintos, de los que 16 no son Tipos oficiales:
  erratas (`dargon`, `inescto`, `deinosaurio`, `besteia`, `guerrero-besetia`,
  `lanzador de conujuros`, `dinosaruio`) y valores de otra dimensión colados ahí
  (`pendulo`, `enlace`, `tierra`, `agua`, `humano`, `ishizu`, `pegasus`, `yami yugi`).
- **`atributo`:** contiene `magica` (1030) y `trampa` (719) para cartas que no son
  monstruos — se usaba como "icono mostrado", no como Atributo. Más erratas:
  `tgrampa`, `oscurdiad`, `aqua`, `magico`, `equipo`.
- **`nivel`:** además de 1-12, hay tres filas con 800, 1400 y 2300 (valores de ATK que
  acabaron en la columna equivocada).
- **`nombre`:** 33 passcodes tienen el mismo nombre escrito de dos formas distintas
  (acentos y mayúsculas).
- **`coleccionAbrev`:** 513 códigos no siguen el patrón `PREFIJO-RR###`; hay erratas
  (`RA01-SPO09`, con letra O en vez de cero) y formatos legítimos con letra de serie
  (`YGLD-SPC01`).
- **Duplicados sin resolver:** 151 combinaciones carta+código+rareza aparecen en más de
  una fila. Pendiente decidir si son lotes de compra distintos o ruido de carga.

## Campos que no existen y habría que empezar a registrar

`precio de compra real` (solo hay precio de mercado observado), `estado de conservación`
y `notas`.
