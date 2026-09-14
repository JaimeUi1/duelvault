---
tags: [tfg, adr, base-de-datos, postgresql]
adr: 001
estado: "Aceptada"
fecha-decision: 2026-09-02
redactado: 2026-09-14
---

# ADR-001 · PostgreSQL como base de datos

## Contexto

La propuesta previa (`V1.0.0__createalltables.sql`) era MySQL puro: `ENUM(...)` en
línea, `ON UPDATE CURRENT_TIMESTAMP`, comillas invertidas. No ejecuta en PostgreSQL. Al
tener que reescribir el DDL de todas formas, tocaba elegir motor conscientemente.

Lo que el dominio pide, mirando las pantallas ya diseñadas:

- **Búsqueda por subcadena** sobre miles de cartas, insensible a mayúsculas y acentos:
  `%mago%` debe encontrar "Mago Oscuro" y "Guerrero del Mago", y "dragon" debe encontrar
  "Dragón".
- **Búsqueda por concepto**: `invocar cementerio` debe encontrar cartas con esas palabras
  sueltas, en cualquier orden y a cualquier distancia.
- **Recolocar cartas** intercambiando dos huecos ocupados, lo que exige poder aplazar la
  comprobación de unicidad al final de la transacción.
- **Restricciones expresivas** que atrapen los errores reales del dataset legado (un ATK
  en la columna de nivel, un monstruo de Enlace con DEF, una carta vendida que conserva
  ubicación).
- **Guardar la salida bruta del OCR**, cuya forma va a cambiar con cada iteración del
  algoritmo.

## Decisión

**PostgreSQL 16**, con migraciones versionadas con Flyway.

Se apoya en cuatro capacidades concretas, no en preferencia: `pg_trgm` con índices GIN
para la subcadena, `tsvector` con configuración de texto propia para el concepto,
restricciones `DEFERRABLE` para el intercambio de huecos, y `JSONB` para el payload del
OCR. Más `CHECK` con expresiones arbitrarias y tipos enumerados nativos.

## Alternativas

**MySQL 8.** Habría sido válido para un catálogo y un CRUD. Se descarta porque no aporta
ninguna de las cuatro capacidades de arriba: no tiene índices de trigramas, su texto
completo es más pobre en español, no admite restricciones diferibles (así que recolocar
dos cartas exigiría trucos como una posición temporal), y su tipo JSON no tiene un
equivalente al índice GIN. Ampliar un `ENUM` requiere `ALTER TABLE` igualmente.

**MariaDB.** Mismas carencias que MySQL en lo que aquí importa.

**Motor de búsqueda aparte (Elasticsearch, Meilisearch).** Resolvería la búsqueda de
sobra, pero añade un servicio más que desplegar, sincronizar y explicar, para un catálogo
que como mucho llegará a 13.000 filas. Complejidad operativa sin beneficio a esta escala.

**SQLite.** Descartado: la aplicación se despliega con Docker Compose y necesita
concurrencia y tipos ricos.

## Consecuencias

**A favor**

- Toda la búsqueda vive dentro de la base de datos, sin un servicio extra que mantener.
- Las restricciones declarativas atrapan errores que hoy existen en el dataset real. El
  `CHECK (level BETWEEN 0 AND 13)` habría impedido las tres filas con nivel 800, 1400 y
  2300.
- Medido sobre 13.000 cartas: una búsqueda selectiva pasa de 18,9 ms de recorrido
  secuencial a 0,23 ms con índice GIN, a cambio de 0,6 MB para el nombre y 1,8 MB para el
  texto de efecto.

**En contra, y asumido**

- El DDL de la propuesta previa se reescribe entero. No se aprovecha nada del original.
- `unaccent()` no es `IMMUTABLE`, así que no se puede indexar directamente. Hay que
  envolverla en `immutable_unaccent()` fijando el diccionario, y **escribir la consulta
  con la misma expresión que define el índice** o no se usa.
- La configuración `spanish` de serie no ignora acentos, así que hace falta una propia
  (`spanish_unaccent`) copiada y con `unaccent` antes del lematizador.
- La vía estándar para los pronombres enclíticos sería un diccionario de sinónimos, que
  exige dejar un fichero en `$SHAREDIR/tsearch_data` **del servidor**. Es viable en
  Docker e imposible en muchos PostgreSQL gestionados, así que se resuelve dentro del
  esquema con `strip_enclitics()`. Esta restricción condiciona el despliegue.
- Ata el proyecto a PostgreSQL de verdad, no de forma nominal: el esquema usa funciones y
  tipos que no son portables. Es una decisión consciente, no un descuido.
