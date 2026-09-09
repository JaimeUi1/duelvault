# Migraciones de diseño (anexo, NO van al repositorio)

Estos dos archivos son las migraciones que en su día corrigieron el esquema
durante la fase de diseño. Se aplastaron en `V1__init_schema.sql` antes del
primer despliegue, porque no había ninguna base de datos desplegada: no
documentaban la evolución de un sistema en marcha, sino la de una
conversación de diseño.

Se conservan **fuera del repositorio** por su valor documental para la
memoria del TFG: el `DROP`/`ADD` de cada corrección es la prueba de que el
defecto existió y de cómo se cerró. El razonamiento está en
`07-Casos-limite.md`; esto es el respaldo técnico.

| Archivo | Qué corregía |
|---|---|
| `V3__binders_slots_alt_art.sql` | Los tres huecos que destapó el diseño de pantallas: carpetas como entidad, hueco dentro de la página, arte alternativo y arte por impresión |
| `V4__fixes_frontron.sql` | Los defectos de la sesión de casos límite: cara de la hoja, restricciones diferibles, borrados que dejaban filas incoherentes, fechas imposibles, precios duplicados y datos de venta |

A partir de `V1`, cada cambio del esquema **sí** es una migración nueva y va
al repositorio.
