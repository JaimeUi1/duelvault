---
tags: [tfg, adr, ocr, vision, escaneo]
adr: 005
estado: "Aceptada"
fecha-decision: 2026-09-05
redactado: 2026-09-14
---

# ADR-005 · Reconocimiento de cartas por cámara mediante OCR del passcode

## Contexto

El TFG necesita al menos un componente técnico que vaya más allá de un CRUD. Y hay un
problema real detrás: dar de alta cartas a mano es lento, y la colección crece.

La idea es apuntar con la cámara del móvil a una carta física y que la aplicación
identifique cuál es para autorrellenar el formulario de alta.

Un dato del dominio cambia por completo el planteamiento: **cada carta lleva impreso un
passcode de 8 dígitos**, que es un identificador exacto y único. No hace falta reconocer
la carta, basta con leer un número.

## Decisión

**OCR del passcode**, con este pipeline: captura → corrección de perspectiva y
preprocesado con OpenCV → recorte de la región del passcode → OCR con Tesseract (Tess4j) →
búsqueda en el catálogo por passcode → sugerencia editable.

Tres decisiones que lo acompañan:

- **Web responsive, no aplicación nativa.** El escaneo funciona desde el navegador del
  móvil con `getUserMedia`.
- **Diseñado por su caso peor.** El acierto se resuelve solo; lo que hay que diseñar es la
  duda. La pantalla 8 del diseño muestra confianza al 62 %, el dígito dudoso marcado, dos
  candidatas y una salida manual siempre visible.
- **Es una mejora posterior al MVP.** Si se complica, el proyecto sigue siendo entregable
  sin ella.

## Alternativas

**Reconocimiento de la carta por su ilustración completa** (comparación de imágenes o red
neuronal). Descartado por tres motivos: haría falta un corpus de imágenes de todas las
cartas, esas ilustraciones son propiedad intelectual de Konami, y resuelve peor un
problema que el passcode resuelve de forma exacta. Un identificador impreso siempre gana a
un parecido.

**Lectura del código de barras.** No todas las cartas lo llevan, y en las que lo llevan no
codifica el passcode de forma útil.

**Servicio de OCR en la nube** (Google Vision, AWS Textract). Más preciso con menos
esfuerzo, pero añade una dependencia externa, coste por uso y una clave que gestionar. Y
académicamente es menos interesante: el trabajo se lo lleva otro.

**Aplicación nativa** para tener mejor acceso a la cámara. Fuera del alcance declarado.

## Consecuencias

**A favor**

- Da al TFG un componente evaluable con una cifra real: porcentaje de aciertos sobre fotos
  propias en distintas condiciones de luz y ángulo. Una medición vale más que "funciona
  bien".
- El passcode es `CHAR(8)` en el esquema precisamente porque es lo que el OCR devolverá
  tal cual, con sus ceros a la izquierda.

**En contra, y asumido**

- **HTTPS obligatorio en el despliegue**, porque `getUserMedia` no funciona sin él. Esto
  condiciona la infraestructura, no solo esta funcionalidad.
- El resultado del OCR se guarda en `card_scans` con el payload bruto en `JSONB`, porque su
  forma va a cambiar con cada iteración del algoritmo. Replicar la ficha de carta en 30
  columnas `detected_*` obligaría a mantener dos esquemas sincronizados para siempre.
- Quedan dos casos de interfaz abiertos en `07-Casos-limite §C`: qué hacer si el passcode
  detectado no está en el catálogo, y si el OCR devuelve 7 dígitos (¿el backend rellena con
  ceros a la izquierda antes de buscar, o lo rechaza?).
- Tess4j y los bindings de OpenCV pueden ir por detrás de Java 25. Hay que comprobarlo
  antes de comprometerse, aunque al ser post-MVP el riesgo está acotado.
