---
tags: [tfg, diseno, pantallas, sistema-de-diseno]
depende-de: "[[00-Descripcion-del-proyecto]]"
entregables: ["duelvault-tokens.css"]
estado: "Bocetos aprobados"
lienzo: "https://claude.ai/code/artifact/0dad5f4c-3aa6-4854-8234-db419690af46"
---

# Diseño de pantallas

> 🎨 **Lienzo con las diez pantallas:** https://claude.ai/code/artifact/0dad5f4c-3aa6-4854-8234-db419690af46
> Enlace permanente y privado. Desde ahí se exportan las pantallas como PNG o como un único PDF.

## 1. Dirección visual

**Híbrida.** La entrada (estantería y carpeta abierta) es oscura y táctil: representa la parte física de la colección. Todo lo demás —detalle, buscador, estadísticas, formularios— es claro y legible, porque son pantallas de leer y comparar entre miles de registros.

La paleta se afinó tras descartar tres direcciones alternativas (Holo, Duelo, Vitrina). Los cambios respecto al primer boceto: negros azulados profundos en lugar de marrones, blanco frío en lugar de crema, dorado más brillante y colores de tipo de carta más saturados.

**Tipografías:** Instrument Serif para títulos y cifras destacadas; Space Grotesk para interfaz y texto corrido. Se descartaron Inter y Roboto por genéricas.

Todos los valores están en `duelvault-tokens.css`, listo para importar en Angular.

## 2. El color por tipo de carta como sistema

Es el ancla visual del producto y viene del propio juego: cada tipo de carta tiene su color de marco. Se usa en la cabecera de la ficha, en las miniaturas del buscador, en los huecos de la carpeta y en los filtros.

| Tipo | Color |
|---|---|
| Monstruo Normal | `#FFCE1F` |
| Monstruo de Efecto | `#FF7A1A` |
| Ritual | `#3B82F6` |
| Fusión | `#A855F7` |
| Sincronía | `#D5D5DC` |
| Xyz | `#1F2026` |
| Enlace | `#2563EB` |
| Mágica | `#00C08B` |
| Trampa | `#F5308E` |

**Regla de accesibilidad:** el color nunca es el único portador de información — siempre va acompañado de la etiqueta de texto. Y en las gráficas no se usa como paleta categórica: el trío amarillo/verde/rosa no supera el umbral de separación para daltonismo deuteranope (ΔE 5,9 frente al mínimo de 6), así que las barras van en un solo tono y la identidad la lleva la etiqueta directa.

## 3. Inventario de pantallas

| # | Pantalla | Objetivo | Notas |
|---|---|---|---|
| 1 | Landing / Estantería | Entrada memorable; elegir carpeta | Lomos etiquetados, cifras de la colección, últimas incorporaciones |
| 2 | Carpeta abierta | Recorrer la colección como en físico | Doble página, rejilla 3×3, huecos vacíos como huecos, navegador de páginas |
| 3 | Detalle de carta | Ficha completa + relación personal con la carta | Estructura de la wiki modernizada, más el bloque "En mi colección" |
| 4 | Buscador y listado | Acceso directo entre miles de cartas | Texto + índice alfabético + facetas; cuadrícula o tabla; paginación |
| 5 | Estadísticas | Composición y valor de un vistazo | Cifras destacadas, evolución del valor, top por valor |
| 6 | Alta / edición | Gestión de la colección | Campos que cambian según la clase de carta; ubicación física y datos del ejemplar |
| 7 | Escaneo (captura) | Leer el código de la carta física | Marco guía, zona del passcode resaltada, salida manual siempre visible |
| 8 | Escaneo (resultado dudoso) | **El caso peor, no el ideal** | Confianza al 62 %, dígito dudoso marcado, dos candidatas, "ninguna: buscar" |
| 9 | Detalle en móvil | La ficha donde no caben dos columnas | Pestañas Datos / Mi colección / Ediciones |
| 10 | Acceso admin | Entrar como propietario | Sobrio; enlace de salida a la vista pública |

## 4. Decisiones de diseño que conviene defender

**El bloque "En mi colección" es lo que diferencia esta aplicación de la wiki.** La wiki cuenta qué es la carta; DuelVault además cuenta qué relación tiene el propietario con ella: cuántas copias, de qué rareza y edición, en qué carpeta y página está guardada cada una, qué se pagó, cuánto vale hoy y cómo ha evolucionado.

**Los campos mostrados dependen de la clase de carta.** Un monstruo enseña Atributo, Nivel, Tipo y ATK/DEF; una mágica enseña Icono, Duración y Velocidad. Nunca se muestran campos vacíos que no apliquen — coherente con la especialización por clase del modelo de datos.

**El escaneo se diseñó por su caso peor.** El éxito se resuelve solo; lo que hay que diseñar es la duda: qué se ve cuando el OCR no está seguro, cómo se corrige un dígito y cómo se sale a mano. Es el detalle que separa una demo de un producto.

**El móvil es web responsive, no una app.** El escaneo se hace con el móvil en la mano y funciona desde el navegador con `getUserMedia` (exige HTTPS, a tener en cuenta en el despliegue). No hay app nativa en el alcance.

**Sin propiedad intelectual ajena.** Las ilustraciones son marcadores de posición; no se reproducen artes ni logotipos oficiales de Konami en los bocetos.

## 5. Pendiente

- Definir los estados de carga, vacío y error de cada pantalla (hay convenciones esbozadas, falta escribirlas).
- Decidir el plan B de la animación de la estantería por si resulta cara de implementar en Angular.
- Revisar contraste real una vez implementado, no solo sobre el boceto.

---

*Última actualización: 2026-09-02*
