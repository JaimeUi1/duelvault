---
tags: [tfg, adr, arquitectura, hexagonal, ddd]
adr: 004
estado: "Aceptada"
fecha-decision: 2026-09-14
redactado: 2026-09-14
---

# ADR-004 · Arquitectura hexagonal por contexto

## Contexto

DuelVault se presenta como TFG, así que tiene que demostrar diseño y no solo un CRUD que
funcione. Tres necesidades concretas empujan hacia una separación estricta:

- **Poder probar las reglas de negocio sin levantar Spring.** Las reglas de ubicación
  física, venta y recolocación son donde está el valor, y testearlas arrancando un
  contexto entero las hace lentas y frágiles.
- **Que la auditoría no ensucie el dominio.** Envers se anota sobre entidades JPA; si esas
  entidades fueran el modelo de dominio, el dominio quedaría salpicado de infraestructura.
- **Poder cambiar el adaptador de persistencia** sin tocar las reglas. Esto dejó de ser
  hipotético al abrirse el ADR-011.

## Decisión

**Arquitectura hexagonal, con módulo por contexto y hexágono dentro de cada uno:**

```
com.duelvault.{catalog,collection,pricing,scanning,security,shared}
  └─ domain/
     application/{usecase, port/{in,out}}
     infrastructure/{in/web, out/{jpa,jdbc}}
```

Reglas que la concretan:

- `domain/` no importa Spring, JPA ni ninguna librería de terceros. Un test de ArchUnit
  falla si lo hace, para que la regla no dependa de la disciplina.
- Las `@Entity` viven solo en `infrastructure/out/jpa`, con mapper explícito al modelo de
  dominio en ambos sentidos. Nunca cruzan hacia `application` ni hacia `web`.
- Los puertos los define el dominio **por lo que necesita**, no el adaptador por lo que
  Spring Data ofrece.
- **Interfaz obligatoria en los puertos de salida, opcional en los de entrada.** La razón
  es la dirección de la flecha: el caso de uso no puede importar el adaptador, así que la
  interfaz invierte esa dependencia y hace trabajo real. El controlador, en cambio, ya
  puede importar el caso de uso porque va de fuera hacia dentro, y una interfaz ahí no
  cambia ninguna dirección. Se opta por la clase directa.
- **Un caso de uso, un método público, y los casos de uso no se llaman entre sí.** Cada
  uno es un límite de transacción, y la lista de clases en `application/usecase` es la
  lista de lo que el sistema sabe hacer. Lo que dos casos de uso comparten **baja al
  dominio**, no se extrae a un tercer caso de uso.
- Se nombran por el problema, no por la operación CRUD: `ArchivarEjemplar`,
  `RecolocarCarta`, `VenderEjemplar`, no `ActualizarCollectionItem`.
- Entrada al caso de uso por objeto `Command` propio, salida por `record` de respuesta.
  Nunca el DTO del controlador ni la entidad.

**DDD táctico donde paga.** `collection` lleva modelo rico (objetos valor como
`Ubicacion`, comportamiento en la raíz, servicio de dominio para lo que cruza agregados).
`catalog` se modela ligero, porque una carta no tiene invariantes propias más allá de las
que ya impone el esquema. Esa asimetría es deliberada.

## Alternativas

**Tres capas clásicas (controlador → servicio → repositorio).** Es lo que se hace por
defecto y funciona. Se descarta porque ata el modelo a JPA desde el primer día y hace que
las reglas acaben repartidas entre el servicio y la entidad, que es precisamente lo que se
quiere demostrar que se sabe evitar.

**Hexagonal "técnica": `domain / application / infrastructure` en la raíz del proyecto,
sin contextos.** Cumple la regla de dependencias pero no marca ninguna frontera de
negocio, así que todo acaba en un único paquete `domain` gigante donde una carta y un
escaneo conviven sin relación.

**DDD completo: eventos de dominio, event sourcing, CQRS con dos bases de datos.** Se
descarta porque no resuelve ningún problema que este proyecto tenga. No hay nada que
reaccione a nada. Cada pieza añadida es superficie que mantener y que defender.

## Consecuencias

**A favor**

- El dominio se testea sin contenedor, y esos tests son rápidos.
- Envers vive en infraestructura y no toca el modelo.
- El ADR-011 puede aplazar la decisión de `JdbcClient` precisamente porque el puerto aísla
  la implementación.

**En contra, y asumido**

- **Mapper explícito entre `@Entity` y dominio, en los dos sentidos.** Es trabajo aburrido
  y repetitivo, y es innegociable: el atajo de usar la `@Entity` como modelo de dominio es
  la "hexagonal de mentira", el error más fácil de cometer aquí.
- Muchos más ficheros que en tres capas. Seguir un flujo obliga a abrir más pestañas.
- **`@Transactional` es una anotación de Spring en una clase de `application`.** Es una
  concesión consciente: la alternativa pura sería un decorador en infraestructura o pasar
  la transacción como puerto de salida. Se acepta la anotación por pragmatismo y se deja
  documentado aquí, porque la peor respuesta ante la pregunta es no habérsela hecho.
- Alguna invariante no cabe dentro de un agregado. La unicidad de hueco cruza dos
  `CollectionItem`, y garantizarla en memoria obligaría a cargar la carpeta entera en cada
  inserción. La sostiene la restricción `UNIQUE` de la base de datos, y el dominio la
  explica con un mensaje útil. El criterio completo está en `07-Casos-limite §E`.
