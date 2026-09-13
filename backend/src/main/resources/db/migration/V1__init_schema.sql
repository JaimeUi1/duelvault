-- =====================================================================
-- DuelVault — Esquema inicial (PostgreSQL 16+)
-- Migración Flyway: V1__init_schema.sql
--
-- Fuente de verdad de la taxonomía: base de datos oficial de Konami
-- (db.yugioh-card.com / Neuron) y reglamento oficial del TCG.
-- Ámbito: colección de un único propietario + vista pública de solo
-- lectura. Sin módulo de tienda (aplazado a futuro).
--
-- NOTA SOBRE EL HISTORIAL: este archivo es el resultado de aplastar
-- cuatro migraciones de diseño (esquema inicial, carpetas y arte
-- alternativo, y las correcciones de la sesión de casos límite) en una
-- sola, antes del primer despliegue. No había ninguna base de datos
-- desplegada, así que no había historia real que conservar: las cuatro
-- documentaban la evolución del diseño, no la de un sistema en marcha, y
-- esa historia vive donde debe, en 03-Modelo-de-datos y 07-Casos-limite.
-- REVISION 2026-09-14 (antes del primer despliegue, sin base desplegada):
-- se declara el esquema en vez de heredarlo de Flyway, se cierran los dos
-- CHECK que faltaban para emparejar marco y medida en Xyz y Enlace, se
-- documenta la cadena de borrado carta/set -> impresion -> ejemplar, y
-- binder_summary separa las cartas asignadas de las ya colocadas.
--
-- A partir de aquí, cada cambio SÍ es una migración nueva.
--
-- DOCUMENTACIÓN: todos los objetos llevan COMMENT ON. Los comentarios
-- van sin tildes a propósito, para no depender de la codificación del
-- cliente que los lea (DataGrip, psql, el generador de la memoria).
-- El criterio: el comentario dice lo que el nombre NO dice.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. Esquema
--    immutable_unaccent() mas abajo cita el diccionario por su nombre
--    completo (duelvault.unaccent), asi que el esquema no puede quedar
--    implicito en la configuracion de Flyway: si el fichero se ejecuta
--    con psql, o si algun dia cambia default-schema, la funcion apuntaria
--    a un diccionario inexistente y el error saldria lejos de aqui, en el
--    primer INSERT de una traduccion. Se declara la dependencia.
--
--    El search_path afecta solo a esta sesion, que es justo lo que se
--    quiere: fija donde se crean las extensiones de abajo.
-- ---------------------------------------------------------------------

CREATE SCHEMA IF NOT EXISTS duelvault;
SET search_path TO duelvault, public;

-- ---------------------------------------------------------------------
-- 0 bis. Extensiones
--    Ambas son "trusted" desde PostgreSQL 13: las puede instalar el
--    propietario de la base de datos, no hace falta superusuario.
--    Se crean en el esquema duelvault, que es el primero del search_path.
-- ---------------------------------------------------------------------

-- Trigramas: aceleran las búsquedas por subcadena (ILIKE '%mago%'), que
-- es lo que hace el buscador. OJO: para subcadena arbitraria NO sirve la
-- búsqueda de texto completo (tsvector), que trabaja con palabras enteras.
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Para que "dragon" encuentre "Dragón".
CREATE EXTENSION IF NOT EXISTS unaccent;

-- ---------------------------------------------------------------------
-- 0. Tipos enumerados (conjuntos CERRADOS por las reglas del juego)
--    Los conjuntos que Konami amplía cada pocos años (Tipos de monstruo,
--    rarezas, tipos de producto) NO van aquí: van en tablas de catálogo.
-- ---------------------------------------------------------------------

-- Monster / Spell / Trap son las 3 clases oficiales. Se añaden TOKEN y
-- SKILL porque existen físicamente en la colección real (14 unidades)
-- y no encajan en las 3 oficiales.
CREATE TYPE card_class AS ENUM ('MONSTER', 'SPELL', 'TRAP', 'TOKEN', 'SKILL');
COMMENT ON TYPE card_class IS 'Clase de carta: las 3 oficiales mas Ficha y Habilidad, que existen fisicamente en la coleccion';

-- 7 atributos oficiales (los 6 clásicos + DIVINE de las Cartas de Dios).
CREATE TYPE monster_attribute AS ENUM
    ('DARK', 'LIGHT', 'EARTH', 'WATER', 'FIRE', 'WIND', 'DIVINE');
COMMENT ON TYPE monster_attribute IS 'Los 7 Atributos oficiales; DIVINE es el de las Cartas de Dios Egipcias';

-- Marco de la carta / método de Invocación. Excluyentes entre sí.
CREATE TYPE monster_frame AS ENUM
    ('NORMAL', 'EFFECT', 'RITUAL', 'FUSION', 'SYNCHRO', 'XYZ', 'LINK');
COMMENT ON TYPE monster_frame IS 'Marco impreso / metodo de Invocacion; excluyentes entre si. Pendulo NO esta aqui: se superpone al marco';

-- Habilidades: se SUPERPONEN al marco y pueden combinarse entre ellas
-- (existen "Synchro Tuner", "Flip Tuner", "Pendulum Xyz"...).
CREATE TYPE monster_ability AS ENUM
    ('TUNER', 'FLIP', 'GEMINI', 'SPIRIT', 'TOON', 'UNION');
COMMENT ON TYPE monster_ability IS 'Habilidades que se superponen al marco y se combinan entre si (Cantante, Volteo, Geminis, Espiritu, Toon, Union)';

CREATE TYPE spell_type AS ENUM
    ('NORMAL', 'CONTINUOUS', 'EQUIP', 'QUICK_PLAY', 'FIELD', 'RITUAL');
COMMENT ON TYPE spell_type IS 'Los 6 tipos de Magica; determina el icono impreso junto al nombre';

CREATE TYPE trap_type AS ENUM ('NORMAL', 'CONTINUOUS', 'COUNTER');
COMMENT ON TYPE trap_type IS 'Los 3 tipos de Trampa; COUNTER es Contraefecto';

CREATE TYPE print_edition AS ENUM
    ('FIRST_EDITION', 'UNLIMITED', 'LIMITED_EDITION');
COMMENT ON TYPE print_edition IS 'Edicion impresa en la carta: 1st Edition, ilimitada o Limited Edition';

-- Escala de conservación estándar del mercado de coleccionismo.
CREATE TYPE card_condition AS ENUM
    ('MINT', 'NEAR_MINT', 'EXCELLENT', 'GOOD', 'LIGHT_PLAYED', 'PLAYED', 'POOR');
COMMENT ON TYPE card_condition IS 'Escala de conservacion estandar del mercado de coleccionismo, de Mint a Poor';

-- Estado del ejemplar dentro de la colección (deriva de `venta` 0/1/2).
CREATE TYPE ownership_status AS ENUM ('OWNED', 'FOR_SALE', 'SOLD');
COMMENT ON TYPE ownership_status IS 'Situacion del ejemplar: poseido, en venta o vendido. Deriva del campo venta 0/1/2 del dataset historico';

-- Cara de una hoja de carpeta. Una hoja tiene dos caras de 9 huecos, así
-- que "página 5, hueco 3" sin la cara es ambiguo.
CREATE TYPE binder_face AS ENUM ('FRONT', 'BACK');
COMMENT ON TYPE binder_face IS 'Cara de una hoja de carpeta: FRONT anverso, BACK reverso';

CREATE TYPE banlist_format AS ENUM ('ADVANCED', 'TRADITIONAL');
COMMENT ON TYPE banlist_format IS 'Formato de juego al que aplica la restriccion: Avanzado (el de torneo) o Tradicional';

CREATE TYPE banlist_status AS ENUM
    ('FORBIDDEN', 'LIMITED', 'SEMI_LIMITED', 'UNLIMITED');
COMMENT ON TYPE banlist_status IS 'Cuantas copias se permiten: prohibida, 1, 2 o sin limite';

CREATE TYPE image_kind AS ENUM ('FULL_CARD', 'ARTWORK', 'THUMBNAIL');
COMMENT ON TYPE image_kind IS 'Que muestra la imagen: la carta entera, solo la ilustracion, o una miniatura';

CREATE TYPE scan_status AS ENUM
    ('PENDING', 'MATCHED', 'CONFIRMED', 'REJECTED', 'FAILED');
COMMENT ON TYPE scan_status IS 'Ciclo de vida de un escaneo: pendiente, emparejado, confirmado por el usuario, rechazado o fallido';

-- ---------------------------------------------------------------------
-- 1. Catálogos de vocabulario ABIERTO (crecen sin desplegar código)
-- ---------------------------------------------------------------------

-- Idiomas de impresión. Se usa el código de región impreso en la carta
-- (SP, EN, FR, DE, IT, PT, JP, KR, TC, SC), no el ISO 639-1, porque es
-- lo que aparece en el número de set (p. ej. RA01-SP001).
CREATE TABLE languages (
    code        CHAR(2) PRIMARY KEY,
    name_es     VARCHAR(50) NOT NULL,
    name_en     VARCHAR(50) NOT NULL
);
COMMENT ON TABLE languages IS 'Códigos de región/idioma impresos en el número de set';
COMMENT ON COLUMN languages.code IS 'Codigo de region impreso en el numero de set (SP, EN, JP...), no el ISO 639-1';
COMMENT ON COLUMN languages.name_es IS 'Nombre del idioma en espanol, para la interfaz';
COMMENT ON COLUMN languages.name_en IS 'Nombre del idioma en ingles, para la interfaz';

-- 26 Tipos oficiales a día de hoy. Konami añade uno cada 3-4 años
-- (Psychic 2008, Creator God 2011, Wyrm 2014, Cyberse 2017, Illusion 2022),
-- por eso es tabla y no ENUM: añadir uno nuevo es un INSERT, no un deploy.
CREATE TABLE monster_types (
    id          SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code        VARCHAR(30) NOT NULL UNIQUE,
    name_es     VARCHAR(50) NOT NULL,
    name_en     VARCHAR(50) NOT NULL,
    introduced_year SMALLINT
);
COMMENT ON TABLE monster_types IS 'Tipo de criatura del monstruo (Dragón, Hada, Ciberso...)';
COMMENT ON COLUMN monster_types.id IS 'Clave sustituta; la referencian los monstruos';
COMMENT ON COLUMN monster_types.code IS 'Clave estable en mayusculas (DRAGON, SPELLCASTER); es lo que referencia el codigo, no el nombre traducido';
COMMENT ON COLUMN monster_types.name_es IS 'Nombre oficial en espanol, tal como se imprime en la carta';
COMMENT ON COLUMN monster_types.name_en IS 'Nombre oficial en ingles';
COMMENT ON COLUMN monster_types.introduced_year IS 'Ano en que Konami introdujo el Tipo; documenta por que esto es tabla y no ENUM';

-- Las rarezas son el vocabulario que más crece del juego (>35 a día de
-- hoy, varias nuevas por año). Tabla obligatoriamente.
CREATE TABLE rarities (
    id          SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code        VARCHAR(50) NOT NULL UNIQUE,
    name_es     VARCHAR(80) NOT NULL,
    name_en     VARCHAR(80) NOT NULL
);
COMMENT ON TABLE rarities IS 'Rarezas de impresion. Es el vocabulario que mas crece del juego (mas de 35 y varias nuevas al ano), por eso es tabla';
COMMENT ON COLUMN rarities.id IS 'Clave sustituta; la referencian las impresiones';
COMMENT ON COLUMN rarities.code IS 'Clave estable en mayusculas (ULTRA_RARE, QUARTER_CENTURY_SECRET_RARE)';
COMMENT ON COLUMN rarities.name_es IS 'Nombre comercial en espanol';
COMMENT ON COLUMN rarities.name_en IS 'Nombre comercial en ingles, que es como suele aparecer en las tiendas';

CREATE TABLE set_types (
    id          SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code        VARCHAR(40) NOT NULL UNIQUE,
    name_es     VARCHAR(80) NOT NULL,
    name_en     VARCHAR(80) NOT NULL
);
COMMENT ON TABLE set_types IS 'Tipo de producto en que se distribuyo un set: sobre de expansion, baraja de estructura, lata, promocional...';
COMMENT ON COLUMN set_types.id IS 'Clave sustituta; la referencian los sets';
COMMENT ON COLUMN set_types.code IS 'Clave estable en mayusculas (BOOSTER_PACK, STRUCTURE_DECK)';
COMMENT ON COLUMN set_types.name_es IS 'Nombre del tipo de producto en espanol';
COMMENT ON COLUMN set_types.name_en IS 'Nombre del tipo de producto en ingles';

-- ---------------------------------------------------------------------
-- 2. Carta canónica (independiente de edición e idioma)
-- ---------------------------------------------------------------------

CREATE TABLE cards (
    id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    -- Passcode oficial de 8 dígitos impreso en la carta. Se guarda como
    -- texto y NO como entero: los ceros a la izquierda son significativos
    -- (00102380 ≠ 102380) y es el valor que devolverá el OCR tal cual.
    passcode         CHAR(8) UNIQUE
                     CHECK (passcode ~ '^[0-9]{8}$'),
    card_class       card_class NOT NULL,
    tcg_release_date DATE,
    ocg_release_date DATE,
    -- Arte alternativo con passcode PROPIO: son dos cartas distintas
    -- (Mago Oscuro 46986414 / la versión de Arkana 36996508). La variante
    -- apunta a la original en vez de duplicar sus datos.
    -- Ojo, no confundir con el otro fenómeno: misma carta, MISMO passcode,
    -- reimpresa con otra ilustración. Eso cuelga de la impresión, en
    -- card_images.card_print_id.
    alternate_art_of BIGINT REFERENCES cards (id) ON DELETE SET NULL,
    artwork_label    VARCHAR(60),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- Fichas y cartas de Habilidad no llevan passcode impreso.
    CONSTRAINT ck_cards_passcode_required
        CHECK (passcode IS NOT NULL OR card_class IN ('TOKEN', 'SKILL')),
    CONSTRAINT ck_cards_alt_art_not_self
        CHECK (alternate_art_of IS NULL OR alternate_art_of <> id),
    -- Una variante debe decir de qué variante se trata, y una carta
    -- original no puede llevar etiqueta de variante.
    CONSTRAINT ck_cards_artwork_label
        CHECK ((alternate_art_of IS NULL AND artwork_label IS NULL)
            OR (alternate_art_of IS NOT NULL AND artwork_label IS NOT NULL))
);
COMMENT ON TABLE cards IS 'La carta como concepto, independiente de edicion, rareza e idioma. Aqui solo esta lo que NO cambia entre impresiones';
COMMENT ON COLUMN cards.id IS 'Clave sustituta. El passcode no sirve de clave primaria porque las Fichas y Habilidades no lo llevan';
COMMENT ON COLUMN cards.passcode IS 'Passcode oficial de 8 dígitos; NULL solo para Fichas y Habilidades';
COMMENT ON COLUMN cards.card_class IS 'Determina que tabla de especializacion tiene asociada (monster_cards, spell_cards o trap_cards)';
COMMENT ON COLUMN cards.tcg_release_date IS 'Primera aparicion en el mercado occidental (TCG), que es el que se colecciona';
COMMENT ON COLUMN cards.ocg_release_date IS 'Primera aparicion en el mercado asiatico (OCG); informativo, suele preceder en meses al TCG';
COMMENT ON COLUMN cards.alternate_art_of IS 'Carta original de la que esta es arte alternativo; NULL si es la original';
COMMENT ON COLUMN cards.artwork_label IS 'Nombre de la variante de arte (p. ej. "Arkana")';
COMMENT ON COLUMN cards.created_at IS 'Alta del registro en el sistema';
COMMENT ON COLUMN cards.updated_at IS 'Ultima modificacion; lo mantiene el disparador trg_cards_updated_at';

CREATE INDEX idx_cards_class ON cards (card_class);
CREATE INDEX idx_cards_tcg_release ON cards (tcg_release_date);
CREATE INDEX idx_cards_alternate_art ON cards (alternate_art_of);

-- Nombre y texto por idioma. Resuelve de raíz las 33 cartas del dataset
-- legado que tenían el mismo passcode con nombres escritos de dos formas.
CREATE TABLE card_translations (
    card_id          BIGINT NOT NULL REFERENCES cards (id) ON DELETE CASCADE,
    language_code    CHAR(2) NOT NULL REFERENCES languages (code),
    name             VARCHAR(255) NOT NULL,
    card_text        TEXT,
    pendulum_text    TEXT,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (card_id, language_code)
);
COMMENT ON TABLE card_translations IS 'Nombre y textos de la carta por idioma. Separarlo de cards resuelve las 33 cartas del dataset legado con el mismo passcode y el nombre escrito de dos formas';
COMMENT ON COLUMN card_translations.card_id IS 'Carta a la que traduce';
COMMENT ON COLUMN card_translations.language_code IS 'Idioma de esta version del texto; tambien decide que diccionario usa search_vector';
COMMENT ON COLUMN card_translations.name IS 'Nombre oficial de la carta en ese idioma';
COMMENT ON COLUMN card_translations.card_text IS 'Texto de efecto, o texto ambientación en monstruos Normales';
COMMENT ON COLUMN card_translations.pendulum_text IS 'Texto de la mitad de Pendulo; NULL en cartas que no lo son';
COMMENT ON COLUMN card_translations.created_at IS 'Alta del registro en el sistema';
COMMENT ON COLUMN card_translations.updated_at IS 'Ultima modificacion; lo mantiene un disparador';

CREATE INDEX idx_card_translations_name ON card_translations (language_code, name);

-- Búsqueda del buscador: por NOMBRE o por TEXTO DE EFECTO, en ambos casos
-- por coincidencia parcial e insensible a mayúsculas y acentos.
--
-- unaccent() no es IMMUTABLE (depende del diccionario, que se puede
-- cambiar), y PostgreSQL no indexa expresiones no inmutables. Se envuelve
-- fijando el diccionario explícitamente, que es el patrón estándar.
CREATE OR REPLACE FUNCTION immutable_unaccent(text)
RETURNS text AS $$ SELECT duelvault.unaccent('duelvault.unaccent', $1) $$
LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE;

COMMENT ON FUNCTION immutable_unaccent(text) IS 'unaccent() indexable; el diccionario va fijado para que sea inmutable';

-- Índices GIN de trigramas. Medido sobre 13.000 cartas (el tamaño del
-- catálogo completo): una búsqueda selectiva pasa de 18,9 ms de recorrido
-- secuencial a 0,23 ms. Ocupan 0,6 MB el del nombre y 1,8 MB el del texto.
CREATE INDEX idx_card_translations_name_trgm
    ON card_translations USING GIN (immutable_unaccent(name) gin_trgm_ops);

CREATE INDEX idx_card_translations_text_trgm
    ON card_translations USING GIN (immutable_unaccent(card_text) gin_trgm_ops);

-- Para que el índice se use, la consulta debe escribirse con la MISMA
-- expresión que lo define:
--   WHERE immutable_unaccent(name) ILIKE immutable_unaccent('%' || :q || '%')

-- ..................................................................
-- Tercer modo del buscador: POR CONCEPTO
-- ..................................................................
-- Los dos índices de arriba resuelven "encuentra esta secuencia de
-- letras". No resuelven "cartas que hablen de invocar desde el
-- cementerio": ahí las palabras van sueltas, en cualquier orden y a
-- cualquier distancia. Eso es búsqueda de texto completo, y convive con
-- los trigramas en vez de sustituirlos: el mismo texto indexado dos
-- veces, cada índice para lo suyo.

-- La configuración "spanish" de serie NO ignora acentos: buscar
-- "invocacion" no encuentra "Invocación". Se crea una propia que aplica
-- unaccent antes de lematizar.
CREATE TEXT SEARCH CONFIGURATION spanish_unaccent (COPY = spanish);
ALTER TEXT SEARCH CONFIGURATION spanish_unaccent
    ALTER MAPPING FOR hword, hword_part, word WITH unaccent, spanish_stem;

COMMENT ON TEXT SEARCH CONFIGURATION spanish_unaccent IS 'Español con acentos normalizados, para la búsqueda por concepto';

-- Los pronombres enclíticos son un problema aparte, y NO se arregla
-- quitando acentos: "Invócalo" y "Invocalo" se lematizan igual, como
-- 'invocal', y una búsqueda de "invocar" busca 'invoc'. Es morfología,
-- no diacríticos. El texto de carta en español está lleno de esas formas.
--
-- La vía estándar de PostgreSQL es un diccionario de sinónimos, pero
-- exige dejar un fichero en $SHAREDIR/tsearch_data del SERVIDOR: viable
-- en Docker, imposible en muchos PostgreSQL gestionados. Esta función lo
-- resuelve dentro del esquema, sin depender del sistema de ficheros.
--
-- La regla se apoya en una propiedad de la ortografía española: añadir un
-- pronombre enclítico OBLIGA a tildar la palabra ("invoca" → "invócalo").
-- Por eso solo se tocan palabras que llevan tilde Y terminan en pronombre,
-- lo que deja intactas las normales: cielo, suelo, cementerio, adversario.
--
-- IMPRESCINDIBLE: se aplica en los DOS lados, al construir el índice y al
-- construir la consulta. Si solo se normalizara la entrada del usuario, el
-- índice seguiría guardando 'invocal' y no serviría de nada.
CREATE OR REPLACE FUNCTION strip_enclitics(txt text) RETURNS text AS $$
  SELECT regexp_replace(
      txt,
      '([A-Za-zñÑ]*[áéíóúÁÉÍÓÚ][a-zñ]*?)(selo|sela|selos|selas|melo|mela|telo|tela|noslo|nosla|los|las|les|lo|la|le|me|te|se|nos)\M',
      '\1', 'gi')
$$ LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE;

COMMENT ON FUNCTION strip_enclitics(text) IS 'Quita pronombres enclíticos para que "Invócalo" se lematice igual que "invocar"';

-- Columna generada: se recalcula sola al cambiar el texto, así que no
-- puede quedar desincronizada. La configuración depende del idioma de la
-- fila: lematizar texto español con el diccionario inglés da resultados
-- malos.
--
-- Solo indexa los textos de efecto. El nombre ya tiene su índice de
-- trigramas, y una consulta por concepto no tiene sentido sobre un nombre.
ALTER TABLE card_translations ADD COLUMN search_vector tsvector
GENERATED ALWAYS AS (
    to_tsvector(
        CASE language_code
            WHEN 'SP' THEN 'spanish_unaccent'::regconfig
            WHEN 'EN' THEN 'english'::regconfig
            WHEN 'FR' THEN 'french'::regconfig
            WHEN 'DE' THEN 'german'::regconfig
            WHEN 'IT' THEN 'italian'::regconfig
            WHEN 'PT' THEN 'portuguese'::regconfig
            ELSE 'simple'::regconfig
        END,
        strip_enclitics(coalesce(card_text, '') || ' ' || coalesce(pendulum_text, ''))
    )
) STORED;

COMMENT ON COLUMN card_translations.search_vector IS 'Texto de efecto lematizado para la búsqueda por concepto; se regenera solo';

CREATE INDEX idx_card_translations_search
    ON card_translations USING GIN (search_vector);

-- Del lado de la consulta hay que usar websearch_to_tsquery, NO
-- to_tsquery: este último revienta con un error de sintaxis ante una
-- entrada de usuario cualquiera ("invocar cementerio" ya falla).
-- websearch_to_tsquery admite texto libre, comillas para frase exacta y
-- guion para excluir:
--   WHERE search_vector @@ websearch_to_tsquery('spanish_unaccent',
--                                                strip_enclitics(:q))
--   ORDER BY ts_rank(search_vector, websearch_to_tsquery(...)) DESC
--
-- El strip_enclitics del lado de la consulta NO es decorativo: hace falta
-- para que el usuario pueda escribir él mismo una forma enclítica.
--
-- LIMITACIÓN QUE QUEDA: los verbos irregulares con cambio de raíz. El
-- lematizador reduce "devuelve" a 'devuelv' y "devolver" a 'devolv', así
-- que no se encuentran entre sí por mucho que se quite el pronombre. No
-- tiene arreglo limpio con un lematizador de raíces; haría falta un
-- diccionario de formas verbales completo. Documentado, no olvidado.

-- ..................................................................
-- Si la configuración de texto o el diccionario unaccent cambian, las
-- filas YA calculadas no se recalculan solas. Hay que forzarlo:
--   UPDATE card_translations SET card_text = card_text;
--   REINDEX INDEX idx_card_translations_search;
-- ..................................................................

-- ---------------------------------------------------------------------
-- 3. Especialización por clase de carta (1:1 con cards)
-- ---------------------------------------------------------------------

CREATE TABLE monster_cards (
    card_id          BIGINT PRIMARY KEY REFERENCES cards (id) ON DELETE CASCADE,
    attribute        monster_attribute NOT NULL,
    monster_type_id  SMALLINT NOT NULL REFERENCES monster_types (id),
    frame            monster_frame NOT NULL,
    -- Existen monstruos de Extra Deck SIN efecto (p. ej. Fusiones
    -- Normales como "Gaia el Campeón Dragón"), de ahí que "tiene efecto"
    -- no se pueda deducir solo del marco.
    has_effect       BOOLEAN NOT NULL,
    -- Péndulo se superpone al marco (existen Fusión/Péndulo, Xyz/Péndulo).
    is_pendulum      BOOLEAN NOT NULL DEFAULT FALSE,

    -- ATK/DEF: valor numérico O indeterminado ('?', '????', 'X000').
    atk              INTEGER CHECK (atk >= 0),
    atk_undetermined BOOLEAN NOT NULL DEFAULT FALSE,
    def              INTEGER CHECK (def >= 0),
    def_undetermined BOOLEAN NOT NULL DEFAULT FALSE,

    level            SMALLINT CHECK (level BETWEEN 0 AND 13),
    xyz_rank         SMALLINT CHECK (xyz_rank BETWEEN 0 AND 13),
    link_rating      SMALLINT CHECK (link_rating BETWEEN 1 AND 6),
    pendulum_scale   SMALLINT CHECK (pendulum_scale BETWEEN 0 AND 13),

    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- Un monstruo se mide por Nivel, por Rango o por Link: exactamente uno.
    CONSTRAINT ck_monster_single_measure CHECK (
        (CASE WHEN level       IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN xyz_rank    IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN link_rating IS NOT NULL THEN 1 ELSE 0 END) = 1
    ),
    CONSTRAINT ck_monster_rank_only_xyz
        CHECK (xyz_rank IS NULL OR frame = 'XYZ'),
    CONSTRAINT ck_monster_link_only_link
        CHECK (link_rating IS NULL OR frame = 'LINK'),
    -- Y la implicacion contraria, que faltaba: sin estas dos, un Xyz con
    -- Nivel en vez de Rango pasaba las tres restricciones anteriores, y es
    -- una carta que no existe. Con las cuatro juntas, marco y medida quedan
    -- emparejados en los dos sentidos.
    CONSTRAINT ck_monster_xyz_has_rank
        CHECK (frame <> 'XYZ' OR xyz_rank IS NOT NULL),
    CONSTRAINT ck_monster_link_has_rating
        CHECK (frame <> 'LINK' OR link_rating IS NOT NULL),
    -- Los monstruos de Enlace no tienen DEF impresa.
    CONSTRAINT ck_monster_link_has_no_def
        CHECK (frame <> 'LINK' OR (def IS NULL AND def_undetermined = FALSE)),
    CONSTRAINT ck_monster_scale_only_pendulum
        CHECK (is_pendulum OR pendulum_scale IS NULL),
    CONSTRAINT ck_monster_pendulum_has_scale
        CHECK (NOT is_pendulum OR pendulum_scale IS NOT NULL),
    -- Un valor no puede ser numérico e indeterminado a la vez.
    CONSTRAINT ck_monster_atk_exclusive
        CHECK (NOT (atk IS NOT NULL AND atk_undetermined)),
    CONSTRAINT ck_monster_def_exclusive
        CHECK (NOT (def IS NOT NULL AND def_undetermined)),
    -- Coherencia entre el marco impreso y la existencia de efecto.
    CONSTRAINT ck_monster_frame_effect CHECK (
        (frame = 'NORMAL' AND has_effect = FALSE) OR
        (frame = 'EFFECT' AND has_effect = TRUE)  OR
        (frame NOT IN ('NORMAL', 'EFFECT'))
    )
);
COMMENT ON TABLE monster_cards IS 'Datos que solo tienen los Monstruos. Relacion 1:1 con cards, para no arrastrar columnas vacias en Magicas y Trampas';
COMMENT ON COLUMN monster_cards.card_id IS 'Carta que especializa; es a la vez clave primaria y ajena';
COMMENT ON COLUMN monster_cards.attribute IS 'Atributo impreso en la esquina superior derecha';
COMMENT ON COLUMN monster_cards.monster_type_id IS 'Tipo de criatura (Dragon, Hada, Ciberso...)';
COMMENT ON COLUMN monster_cards.frame IS 'Marco impreso / metodo de Invocacion; uno solo por carta';
COMMENT ON COLUMN monster_cards.has_effect IS 'Si la carta tiene efecto. No se deduce del marco: existen Fusiones y Sincronias sin efecto';
COMMENT ON COLUMN monster_cards.is_pendulum IS 'Pendulo se superpone a cualquier marco (existen Fusion/Pendulo y Xyz/Pendulo), por eso es booleano aparte';
COMMENT ON COLUMN monster_cards.atk IS 'ATK impreso; NULL si es indeterminado (ver atk_undetermined)';
COMMENT ON COLUMN monster_cards.atk_undetermined IS 'ATK impreso como ? o X000. Bandera aparte para poder seguir ordenando y sumando por la columna numerica';
COMMENT ON COLUMN monster_cards.def IS 'DEF impresa; NULL si es indeterminada o si el monstruo es de Enlace, que no lleva';
COMMENT ON COLUMN monster_cards.def_undetermined IS 'DEF impresa como ? o X000';
COMMENT ON COLUMN monster_cards.level IS 'Nivel (estrellas). Excluyente con xyz_rank y link_rating';
COMMENT ON COLUMN monster_cards.xyz_rank IS 'Rango; solo en monstruos Xyz, que no tienen Nivel';
COMMENT ON COLUMN monster_cards.link_rating IS 'Link Rating; coincide con el numero de flechas de monster_link_arrows';
COMMENT ON COLUMN monster_cards.pendulum_scale IS 'Escala de Pendulo. En la practica siempre es simetrica: el mismo valor a izquierda y derecha';
COMMENT ON COLUMN monster_cards.created_at IS 'Alta del registro en el sistema';
COMMENT ON COLUMN monster_cards.updated_at IS 'Ultima modificacion; lo mantiene un disparador';

CREATE INDEX idx_monster_attribute ON monster_cards (attribute);
CREATE INDEX idx_monster_type ON monster_cards (monster_type_id);
CREATE INDEX idx_monster_frame ON monster_cards (frame);
CREATE INDEX idx_monster_level ON monster_cards (level);
CREATE INDEX idx_monster_atk ON monster_cards (atk);

-- Habilidades (multivalor). Un monstruo puede ser Cantante y de Volteo
-- a la vez: por eso es tabla y no una columna.
CREATE TABLE monster_card_abilities (
    card_id   BIGINT NOT NULL REFERENCES monster_cards (card_id) ON DELETE CASCADE,
    ability   monster_ability NOT NULL,
    PRIMARY KEY (card_id, ability)
);
COMMENT ON TABLE monster_card_abilities IS 'Habilidades del monstruo. Es tabla y no columna porque se combinan: existen Sincronia + Cantante o Cantante + Volteo';
COMMENT ON COLUMN monster_card_abilities.card_id IS 'Monstruo que tiene la habilidad';
COMMENT ON COLUMN monster_card_abilities.ability IS 'Habilidad concreta; una fila por cada una';

-- Flechas de Enlace: 8 direcciones posibles; su número es el Link Rating.
CREATE TABLE monster_link_arrows (
    card_id   BIGINT NOT NULL REFERENCES monster_cards (card_id) ON DELETE CASCADE,
    arrow     VARCHAR(12) NOT NULL
              CHECK (arrow IN ('TOP_LEFT', 'TOP', 'TOP_RIGHT',
                               'LEFT', 'RIGHT',
                               'BOTTOM_LEFT', 'BOTTOM', 'BOTTOM_RIGHT')),
    PRIMARY KEY (card_id, arrow)
);
COMMENT ON TABLE monster_link_arrows IS 'Flechas de Enlace impresas en el marco. Su cantidad es el Link Rating del monstruo';
COMMENT ON COLUMN monster_link_arrows.card_id IS 'Monstruo de Enlace al que pertenece la flecha';
COMMENT ON COLUMN monster_link_arrows.arrow IS 'Direccion de la flecha; 8 posiciones posibles alrededor de la carta';

CREATE TABLE spell_cards (
    card_id     BIGINT PRIMARY KEY REFERENCES cards (id) ON DELETE CASCADE,
    spell_type  spell_type NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE spell_cards IS 'Datos que solo tienen las Magicas. Relacion 1:1 con cards';
COMMENT ON COLUMN spell_cards.card_id IS 'Carta que especializa; es a la vez clave primaria y ajena';
COMMENT ON COLUMN spell_cards.spell_type IS 'Tipo de Magica; determina el icono impreso junto al nombre';
COMMENT ON COLUMN spell_cards.created_at IS 'Alta del registro en el sistema';
COMMENT ON COLUMN spell_cards.updated_at IS 'Ultima modificacion; lo mantiene un disparador';

CREATE INDEX idx_spell_type ON spell_cards (spell_type);

CREATE TABLE trap_cards (
    card_id     BIGINT PRIMARY KEY REFERENCES cards (id) ON DELETE CASCADE,
    trap_type   trap_type NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trap_cards IS 'Datos que solo tienen las Trampas. Relacion 1:1 con cards';
COMMENT ON COLUMN trap_cards.card_id IS 'Carta que especializa; es a la vez clave primaria y ajena';
COMMENT ON COLUMN trap_cards.trap_type IS 'Tipo de Trampa; determina el icono impreso junto al nombre';
COMMENT ON COLUMN trap_cards.created_at IS 'Alta del registro en el sistema';
COMMENT ON COLUMN trap_cards.updated_at IS 'Ultima modificacion; lo mantiene un disparador';

CREATE INDEX idx_trap_type ON trap_cards (trap_type);

-- ---------------------------------------------------------------------
-- 4. Arquetipos, clasificación de efectos y limitaciones
--    (los tres bloques que muestra la ficha de la wiki)
-- ---------------------------------------------------------------------

CREATE TABLE archetypes (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code        VARCHAR(80) NOT NULL UNIQUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE archetypes IS 'Familias de cartas que comparten nombre y se apoyan entre si (Mago Oscuro, Blue-Eyes, Salamangreat)';
COMMENT ON COLUMN archetypes.id IS 'Clave sustituta';
COMMENT ON COLUMN archetypes.code IS 'Clave estable del arquetipo, independiente del idioma';
COMMENT ON COLUMN archetypes.created_at IS 'Alta del registro en el sistema';

CREATE TABLE archetype_translations (
    archetype_id  BIGINT NOT NULL REFERENCES archetypes (id) ON DELETE CASCADE,
    language_code CHAR(2) NOT NULL REFERENCES languages (code),
    name          VARCHAR(255) NOT NULL,
    description   TEXT,
    PRIMARY KEY (archetype_id, language_code)
);
COMMENT ON TABLE archetype_translations IS 'Nombre y descripcion del arquetipo por idioma';
COMMENT ON COLUMN archetype_translations.archetype_id IS 'Arquetipo al que traduce';
COMMENT ON COLUMN archetype_translations.language_code IS 'Idioma de esta version';
COMMENT ON COLUMN archetype_translations.name IS 'Nombre oficial del arquetipo en ese idioma';
COMMENT ON COLUMN archetype_translations.description IS 'Descripcion libre del arquetipo, para la ficha';

CREATE TABLE card_archetypes (
    card_id      BIGINT NOT NULL REFERENCES cards (id) ON DELETE CASCADE,
    archetype_id BIGINT NOT NULL REFERENCES archetypes (id) ON DELETE CASCADE,
    -- FALSE = la carta pertenece al arquetipo; TRUE = solo lo apoya.
    is_support   BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (card_id, archetype_id)
);
COMMENT ON TABLE card_archetypes IS 'Relaciona cartas con arquetipos. Una carta puede pertenecer a varios y apoyar a otros distintos';
COMMENT ON COLUMN card_archetypes.card_id IS 'Carta relacionada';
COMMENT ON COLUMN card_archetypes.archetype_id IS 'Arquetipo relacionado';
COMMENT ON COLUMN card_archetypes.is_support IS 'FALSE la carta pertenece al arquetipo; TRUE solo lo apoya sin llevar el nombre';

CREATE INDEX idx_card_archetypes_archetype ON card_archetypes (archetype_id);

CREATE TABLE effect_categories (
    id                 BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code               VARCHAR(80) NOT NULL UNIQUE,
    parent_category_id BIGINT REFERENCES effect_categories (id)
);
COMMENT ON TABLE effect_categories IS 'Clasificacion jerarquica de lo que hace una carta (destruir, robar, invocar desde el Cementerio...). Se poblara analizando el texto de efecto';
COMMENT ON COLUMN effect_categories.id IS 'Clave sustituta';
COMMENT ON COLUMN effect_categories.code IS 'Clave estable de la categoria, independiente del idioma';
COMMENT ON COLUMN effect_categories.parent_category_id IS 'Categoria padre; NULL en las de primer nivel. Es lo que hace jerarquica la clasificacion';

CREATE TABLE effect_category_translations (
    effect_category_id BIGINT NOT NULL REFERENCES effect_categories (id) ON DELETE CASCADE,
    language_code      CHAR(2) NOT NULL REFERENCES languages (code),
    name               VARCHAR(255) NOT NULL,
    PRIMARY KEY (effect_category_id, language_code)
);
COMMENT ON TABLE effect_category_translations IS 'Nombre de la categoria de efecto por idioma';
COMMENT ON COLUMN effect_category_translations.effect_category_id IS 'Categoria a la que traduce';
COMMENT ON COLUMN effect_category_translations.language_code IS 'Idioma de esta version';
COMMENT ON COLUMN effect_category_translations.name IS 'Nombre de la categoria en ese idioma';

CREATE TABLE card_effect_categories (
    card_id            BIGINT NOT NULL REFERENCES cards (id) ON DELETE CASCADE,
    effect_category_id BIGINT NOT NULL REFERENCES effect_categories (id) ON DELETE CASCADE,
    PRIMARY KEY (card_id, effect_category_id)
);
COMMENT ON TABLE card_effect_categories IS 'Relaciona cada carta con las categorias de efecto que le aplican; una carta puede tener varias';
COMMENT ON COLUMN card_effect_categories.card_id IS 'Carta clasificada';
COMMENT ON COLUMN card_effect_categories.effect_category_id IS 'Categoria que le aplica';

-- Estado en la lista de prohibidas/limitadas, con histórico por fecha.
CREATE TABLE card_limitations (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    card_id        BIGINT NOT NULL REFERENCES cards (id) ON DELETE CASCADE,
    format         banlist_format NOT NULL,
    status         banlist_status NOT NULL,
    effective_from DATE NOT NULL,
    UNIQUE (card_id, format, effective_from)
);
COMMENT ON TABLE card_limitations IS 'Histórico de restricción por formato (Avanzado/Tradicional)';
COMMENT ON COLUMN card_limitations.id IS 'Clave sustituta';
COMMENT ON COLUMN card_limitations.card_id IS 'Carta restringida';
COMMENT ON COLUMN card_limitations.format IS 'Formato al que aplica la restriccion';
COMMENT ON COLUMN card_limitations.status IS 'Cuantas copias se permiten en ese formato';
COMMENT ON COLUMN card_limitations.effective_from IS 'Fecha de entrada en vigor. El estado actual es la fila mas reciente por carta y formato';

-- ---------------------------------------------------------------------
-- 5. Sets e impresiones físicas
-- ---------------------------------------------------------------------

CREATE TABLE card_sets (
    id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    set_prefix       VARCHAR(10) NOT NULL UNIQUE,   -- RA01, LOB, YGLD...
    set_type_id      SMALLINT REFERENCES set_types (id),
    tcg_release_date DATE,
    total_cards      INTEGER,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE card_sets IS 'Productos en que se distribuyen las cartas: expansiones, barajas de estructura, latas...';
COMMENT ON COLUMN card_sets.id IS 'Clave sustituta';
COMMENT ON COLUMN card_sets.set_prefix IS 'Prefijo impreso en el numero de set, antes del guion (RA01, LOB, YGLD)';
COMMENT ON COLUMN card_sets.set_type_id IS 'Tipo de producto';
COMMENT ON COLUMN card_sets.tcg_release_date IS 'Fecha de salida del producto en el mercado occidental';
COMMENT ON COLUMN card_sets.total_cards IS 'Cartas distintas que componen el set segun su listado oficial';
COMMENT ON COLUMN card_sets.created_at IS 'Alta del registro en el sistema';

CREATE TABLE card_set_translations (
    card_set_id   BIGINT NOT NULL REFERENCES card_sets (id) ON DELETE CASCADE,
    language_code CHAR(2) NOT NULL REFERENCES languages (code),
    name          VARCHAR(255) NOT NULL,
    PRIMARY KEY (card_set_id, language_code)
);
COMMENT ON TABLE card_set_translations IS 'Nombre comercial del set por idioma';
COMMENT ON COLUMN card_set_translations.card_set_id IS 'Set al que traduce';
COMMENT ON COLUMN card_set_translations.language_code IS 'Idioma de esta version';
COMMENT ON COLUMN card_set_translations.name IS 'Nombre comercial del set en ese idioma';

-- Una impresión concreta: esta carta, en este set, con este número,
-- esta rareza, este idioma y esta edición.
--
-- OJO CON LA CADENA DE BORRADO, y es deliberada: cards y card_sets
-- cascadean hasta aquí, pero collection_items referencia esta tabla con
-- ON DELETE RESTRICT. Resultado: borrar una carta o un set de los que se
-- poseen ejemplares FALLA, que es lo correcto. Lo que no es aceptable es
-- el mensaje, que habla de collection_items, una tabla que el usuario no
-- ha tocado. El caso de uso de borrado comprueba antes si hay ejemplares
-- y lo explica; la restriccion queda como garantia de ultimo recurso.
CREATE TABLE card_prints (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    card_id       BIGINT NOT NULL REFERENCES cards (id) ON DELETE CASCADE,
    card_set_id   BIGINT NOT NULL REFERENCES card_sets (id) ON DELETE CASCADE,
    -- Código completo tal como está impreso: 'RA01-SP001', 'YGLD-SPC01'.
    set_number    VARCHAR(20) NOT NULL,
    language_code CHAR(2) NOT NULL REFERENCES languages (code),
    rarity_id     SMALLINT NOT NULL REFERENCES rarities (id),
    edition       print_edition NOT NULL DEFAULT 'UNLIMITED',
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- La rareza FORMA PARTE de la clave: un mismo número de set se
    -- imprime en varias rarezas (202 casos reales en la colección).
    CONSTRAINT uq_card_print
        UNIQUE (card_id, card_set_id, set_number, rarity_id, edition, language_code)
);
COMMENT ON TABLE card_prints IS 'Una impresion concreta: esta carta, en este set, con este numero, rareza, idioma y edicion. Es el nivel que se cotiza y del que se poseen ejemplares';
COMMENT ON COLUMN card_prints.id IS 'Clave sustituta';
COMMENT ON COLUMN card_prints.card_id IS 'Carta impresa';
COMMENT ON COLUMN card_prints.card_set_id IS 'Producto en que se imprimio';
COMMENT ON COLUMN card_prints.set_number IS 'Codigo completo tal como esta impreso, incluido el prefijo (RA01-SP001, YGLD-SPC01)';
COMMENT ON COLUMN card_prints.language_code IS 'Idioma de esta impresion; se deriva del codigo de region del numero de set';
COMMENT ON COLUMN card_prints.rarity_id IS 'Rareza de esta impresion. Forma parte de la clave unica: un mismo numero de set se imprime en varias rarezas (202 casos reales)';
COMMENT ON COLUMN card_prints.edition IS 'Edicion impresa en la carta; afecta al valor de mercado';
COMMENT ON COLUMN card_prints.created_at IS 'Alta del registro en el sistema';
COMMENT ON COLUMN card_prints.updated_at IS 'Ultima modificacion; lo mantiene un disparador';

CREATE INDEX idx_card_prints_card ON card_prints (card_id);
CREATE INDEX idx_card_prints_set ON card_prints (card_set_id);
CREATE INDEX idx_card_prints_set_number ON card_prints (set_number);
CREATE INDEX idx_card_prints_rarity ON card_prints (rarity_id);

-- Ilustraciones. Una imagen puede colgar de la carta (la ilustración por
-- defecto, card_print_id NULL) o de una IMPRESIÓN concreta, para el caso
-- de la misma carta con el mismo passcode reimpresa con otro arte.
-- Va después de card_prints porque la referencia.
CREATE TABLE card_images (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    card_id       BIGINT NOT NULL REFERENCES cards (id) ON DELETE CASCADE,
    card_print_id BIGINT REFERENCES card_prints (id) ON DELETE CASCADE,
    image_kind    image_kind NOT NULL,
    image_path    VARCHAR(500) NOT NULL,
    mime_type     VARCHAR(50) NOT NULL DEFAULT 'image/jpeg',
    width         INTEGER,
    height        INTEGER,
    file_size     BIGINT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE card_images IS 'Ilustraciones. Una imagen cuelga de la carta (la version por defecto) o de una impresion concreta, cuando la misma carta se reimprime con otro arte bajo el mismo passcode';
COMMENT ON COLUMN card_images.id IS 'Clave sustituta';
COMMENT ON COLUMN card_images.card_id IS 'Carta a la que corresponde la imagen';
COMMENT ON COLUMN card_images.card_print_id IS 'Impresión concreta cuyo arte difiere; NULL = ilustración por defecto de la carta';
COMMENT ON COLUMN card_images.image_kind IS 'Que muestra: carta entera, solo ilustracion o miniatura';
COMMENT ON COLUMN card_images.image_path IS 'Localizacion del fichero de imagen';
COMMENT ON COLUMN card_images.mime_type IS 'Tipo de contenido del fichero, para servirlo con la cabecera correcta';
COMMENT ON COLUMN card_images.width IS 'Ancho en pixeles; permite reservar el espacio antes de cargar la imagen';
COMMENT ON COLUMN card_images.height IS 'Alto en pixeles';
COMMENT ON COLUMN card_images.file_size IS 'Tamano del fichero en bytes';
COMMENT ON COLUMN card_images.created_at IS 'Alta del registro en el sistema';

-- Una sola imagen por tipo a nivel de carta, y una sola por tipo a nivel
-- de impresión. Índices parciales porque son dos reglas distintas.
CREATE UNIQUE INDEX uq_card_images_default
    ON card_images (card_id, image_kind)
    WHERE card_print_id IS NULL;

CREATE UNIQUE INDEX uq_card_images_print
    ON card_images (card_print_id, image_kind)
    WHERE card_print_id IS NOT NULL;

-- Histórico de precio de mercado. Sustituye a una columna `market_price`
-- mutable: sin histórico no hay gráfica de evolución del valor.
--
-- Una carta SIN VALORAR no tiene ninguna fila aquí. Nunca se registra un
-- precio de 0 para decir "no lo sé": eso contaminaría la gráfica de
-- evolución y haría indistinguible "desconocido" de "no vale nada".
CREATE TABLE price_snapshots (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    card_print_id BIGINT NOT NULL REFERENCES card_prints (id) ON DELETE CASCADE,
    price         NUMERIC(10, 2) NOT NULL CHECK (price >= 0),
    currency      CHAR(3) NOT NULL DEFAULT 'EUR',
    -- Obligatoria: forma parte de la clave única, y con nulos (que no se
    -- consideran iguales entre sí) se colaban dos precios distintos del
    -- mismo día para la misma impresión.
    source        VARCHAR(60) NOT NULL DEFAULT 'MANUAL',
    observed_on   DATE NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (card_print_id, observed_on, source),
    -- Un precio fechado en el futuro pasaría a ser "el precio actual" de
    -- la carta y contaminaría el valor total de la colección.
    CONSTRAINT ck_price_snapshots_not_future
        CHECK (observed_on <= CURRENT_DATE)
);
COMMENT ON TABLE price_snapshots IS 'Historico de precio de mercado por impresion. Sustituye a una columna mutable: sin historico no hay grafica de evolucion del valor';
COMMENT ON COLUMN price_snapshots.id IS 'Clave sustituta';
COMMENT ON COLUMN price_snapshots.card_print_id IS 'Impresion cotizada. El precio depende de la rareza y la edicion, no solo de la carta';
COMMENT ON COLUMN price_snapshots.price IS 'Precio observado. Una carta sin valorar NO tiene ninguna fila aqui; nunca se registra 0 para decir que se desconoce';
COMMENT ON COLUMN price_snapshots.currency IS 'Divisa del precio observado';
COMMENT ON COLUMN price_snapshots.source IS 'De donde sale el precio (MANUAL, o el nombre de la tienda consultada). Obligatoria porque forma parte de la clave unica';
COMMENT ON COLUMN price_snapshots.observed_on IS 'Fecha a la que corresponde el precio. El valor actual de una carta es su snapshot mas reciente';
COMMENT ON COLUMN price_snapshots.created_at IS 'Momento en que se registro la observacion';

CREATE INDEX idx_price_snapshots_print_date
    ON price_snapshots (card_print_id, observed_on DESC);

-- ---------------------------------------------------------------------
-- 6. Colección personal (propietario único)
-- ---------------------------------------------------------------------

-- Carpetas de anillas físicas. Existen como entidad, y no como un simple
-- número suelto, porque la pantalla de estantería necesita nombre, color
-- de lomo y orden.
CREATE TABLE binders (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    -- Número rotulado en el lomo: la referencia que se usa al buscar una
    -- carta en la estantería real.
    number         SMALLINT NOT NULL CHECK (number > 0),
    name           VARCHAR(80) NOT NULL,
    -- Color del lomo (#RRGGBB). Decorativo, pero es lo que permite
    -- reconocer la carpeta de un vistazo.
    spine_color    CHAR(7) CHECK (spine_color ~ '^#[0-9A-Fa-f]{6}$'),
    -- Huecos por CARA, no por hoja: lo normal son 9 (3x3), y una hoja
    -- tiene dos caras, así que una hoja de 9 admite 18 cartas.
    slots_per_face SMALLINT NOT NULL DEFAULT 9
                   CHECK (slots_per_face IN (4, 8, 9, 12, 16)),
    -- Orden en la estantería, independiente del número del lomo.
    shelf_position SMALLINT NOT NULL,
    notes          TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- DEFERRABLE en las dos: sin diferir, intercambiar dos carpetas de
    -- número o de posición choca contra la carpeta que aún ocupa el sitio.
    -- El caso de uso de reordenar abre transacción y hace
    -- SET CONSTRAINTS ... DEFERRED.
    CONSTRAINT uq_binder_number UNIQUE (number)
        DEFERRABLE INITIALLY IMMEDIATE,
    CONSTRAINT uq_binder_shelf_position UNIQUE (shelf_position)
        DEFERRABLE INITIALLY IMMEDIATE
);
COMMENT ON TABLE binders IS 'Carpetas de anillas físicas donde se archiva la colección';
COMMENT ON COLUMN binders.id IS 'Clave sustituta; la referencian los ejemplares archivados';
COMMENT ON COLUMN binders.number IS 'Numero rotulado en el lomo; es la referencia que se usa al buscar una carta en la estanteria real';
COMMENT ON COLUMN binders.name IS 'Nombre con que el propietario identifica la carpeta (Magos, Dragones...)';
COMMENT ON COLUMN binders.spine_color IS 'Color del lomo en #RRGGBB; decorativo, pero es lo que permite reconocerla de un vistazo en la pantalla de estanteria';
COMMENT ON COLUMN binders.slots_per_face IS 'Huecos por cara (9 = 3x3); una hoja tiene el doble';
COMMENT ON COLUMN binders.shelf_position IS 'Orden fisico en la estanteria, independiente del numero del lomo. Diferible para poder reordenar';
COMMENT ON COLUMN binders.notes IS 'Anotaciones libres sobre la carpeta';
COMMENT ON COLUMN binders.created_at IS 'Alta del registro en el sistema';
COMMENT ON COLUMN binders.updated_at IS 'Ultima modificacion; lo mantiene un disparador';

-- Un ejemplar de la colección.
--
-- quantity cuenta TODAS las copias poseídas de esa impresión; la
-- ubicación localiza la que está archivada en la carpeta, y las demás se
-- guardan fuera. Por eso una fila puede tener hueco y cantidad 3.
--
-- La venta es UNA FILA POR VENTA: vender 1 de 3 copias baja la original a
-- 2 y crea otra con cantidad 1, estado SOLD y su propio precio y fecha.
-- No se fusionan, porque el precio de venta puede variar entre una y otra.
CREATE TABLE collection_items (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    card_print_id  BIGINT NOT NULL REFERENCES card_prints (id) ON DELETE RESTRICT,
    quantity       INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
    condition      card_condition NOT NULL DEFAULT 'NEAR_MINT',
    status         ownership_status NOT NULL DEFAULT 'OWNED',
    purchase_price NUMERIC(10, 2) CHECK (purchase_price >= 0),
    purchase_date  DATE,
    sale_price     NUMERIC(10, 2) CHECK (sale_price >= 0),
    sold_on        DATE,

    -- Ubicación física: carpeta, hoja, cara y hueco dentro de esa cara.
    -- Se lee igual que al buscar la carta en la estantería:
    -- "carpeta 1, página 5, reverso, hueco 3".
    binder_id      BIGINT,
    page_number    INTEGER CHECK (page_number > 0),
    face           binder_face,
    slot_number    SMALLINT,

    notes          TEXT,
    registered_on  DATE NOT NULL DEFAULT CURRENT_DATE,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- La parte obligatoria de la ubicación es todo o nada: no hay página
    -- sin carpeta. Cara y hueco pueden faltar mientras la carta está en la
    -- carpeta pero sin colocar (así llegan los datos importados).
    CONSTRAINT fk_collection_items_binder FOREIGN KEY (binder_id)
        REFERENCES binders (id) ON DELETE SET NULL,
    -- Red de seguridad genérica; que el hueco quepa en el slots_per_face
    -- real de esa carpeta lo comprueba el dominio.
    CONSTRAINT ck_collection_items_slot_range
        CHECK (slot_number BETWEEN 1 AND 16),
    CONSTRAINT ck_collection_items_location CHECK (
        (binder_id IS NULL AND page_number IS NULL
                           AND face IS NULL AND slot_number IS NULL)
        OR (binder_id IS NOT NULL AND page_number IS NOT NULL)
    ),
    -- Un hueco pertenece a una cara concreta.
    CONSTRAINT ck_collection_items_slot_needs_face
        CHECK (slot_number IS NULL OR face IS NOT NULL),
    -- Una carta vendida ya no está en ninguna carpeta: se conserva la
    -- fila y el hecho de la venta, no dónde estuvo archivada. Y su hueco
    -- queda libre de inmediato.
    CONSTRAINT ck_collection_items_sold_has_no_location CHECK (
        status <> 'SOLD'
        OR (binder_id IS NULL AND page_number IS NULL
                              AND face IS NULL AND slot_number IS NULL)
    ),
    -- Los datos de venta solo existen en una fila vendida.
    CONSTRAINT ck_collection_items_sale_data
        CHECK (status = 'SOLD' OR (sale_price IS NULL AND sold_on IS NULL)),
    CONSTRAINT ck_collection_items_purchase_not_future
        CHECK (purchase_date <= CURRENT_DATE),
    CONSTRAINT ck_collection_items_sold_not_future
        CHECK (sold_on <= CURRENT_DATE),
    CONSTRAINT ck_collection_items_sold_after_purchase
        CHECK (sold_on IS NULL OR purchase_date IS NULL OR sold_on >= purchase_date),

    -- Un hueco físico admite una sola carta. En la colección real no se
    -- apilan copias en un mismo bolsillo.
    --
    -- Es una restricción UNIQUE y NO un índice parcial, por dos motivos:
    -- los nulos no se consideran iguales entre sí, así que deja pasar
    -- igual todas las filas sin hueco asignado; y a diferencia de un
    -- índice parcial, SÍ se puede diferir, que es lo único que permite
    -- intercambiar dos cartas de sitio sin chocar con la que aún está allí.
    --
    -- Es además lo que acota cuántas cartas caben en una cara, sin
    -- necesidad de contar nada: la comprobación fina (que el hueco esté
    -- dentro del slots_per_face de esa carpeta) vive en el dominio.
    CONSTRAINT uq_collection_items_slot
        UNIQUE (binder_id, page_number, face, slot_number)
        DEFERRABLE INITIALLY IMMEDIATE
);
COMMENT ON TABLE collection_items IS 'Los ejemplares poseidos. Una fila por impresion y situacion: la venta parcial parte la fila, de modo que cada venta conserva su propio precio';
COMMENT ON COLUMN collection_items.id IS 'Clave sustituta';
COMMENT ON COLUMN collection_items.card_print_id IS 'Impresion concreta que se posee. ON DELETE RESTRICT: no se borra una impresion de la que hay ejemplares';
COMMENT ON COLUMN collection_items.quantity IS 'Copias poseídas de esta impresión, incluidas las guardadas fuera de la carpeta';
COMMENT ON COLUMN collection_items.condition IS 'Estado de conservacion del ejemplar; afecta a su valor real frente al precio de mercado';
COMMENT ON COLUMN collection_items.status IS 'Situacion del ejemplar: poseido, en venta o vendido';
COMMENT ON COLUMN collection_items.purchase_price IS 'Lo que se pago por el ejemplar. Independiente de que exista o no valoracion de mercado';
COMMENT ON COLUMN collection_items.purchase_date IS 'Fecha de compra. No existe en el dataset historico: se empieza a registrar a partir de ahora';
COMMENT ON COLUMN collection_items.sale_price IS 'Importe real de la venta, por ejemplar';
COMMENT ON COLUMN collection_items.sold_on IS 'Fecha de la venta';
COMMENT ON COLUMN collection_items.binder_id IS 'Carpeta donde esta archivado. NULL si la carta no esta colocada o si se vendio';
COMMENT ON COLUMN collection_items.page_number IS 'La hoja dentro de la carpeta';
COMMENT ON COLUMN collection_items.face IS 'Cara de la hoja: FRONT anverso, BACK reverso';
COMMENT ON COLUMN collection_items.slot_number IS 'Hueco dentro de la cara, 1..slots_per_face';
COMMENT ON COLUMN collection_items.notes IS 'Anotaciones libres sobre el ejemplar';
COMMENT ON COLUMN collection_items.registered_on IS 'Fecha de alta en la coleccion; equivale al fechaUpdate del dataset historico';
COMMENT ON COLUMN collection_items.created_at IS 'Alta del registro en el sistema';
COMMENT ON COLUMN collection_items.updated_at IS 'Ultima modificacion; lo mantiene un disparador';

CREATE INDEX idx_collection_items_print ON collection_items (card_print_id);
CREATE INDEX idx_collection_items_status ON collection_items (status);
CREATE INDEX idx_collection_items_location
    ON collection_items (binder_id, page_number, face, slot_number);
CREATE INDEX idx_collection_items_sold_on ON collection_items (sold_on)
    WHERE status = 'SOLD';

-- Datos derivados de cada carpeta para la pantalla de estantería. NO son
-- columnas: se calculan, para que no puedan desincronizarse de la realidad.
--
-- Tres cifras con significados distintos, y conviene no confundirlas:
--   · card_count   cartas en la carpeta, una por fila archivada.
--   · placed_count las que ademas tienen hueco asignado. Mientras la
--     migracion no reparta huecos sera 0, y la diferencia con card_count
--     es exactamente el trabajo pendiente de colocacion.
--   · copy_count   ejemplares poseidos, incluidos los guardados fuera.
-- Contar con SUM en la estantería haría que una cara de nueve huecos
-- declarase más cartas de las que caben.
CREATE VIEW binder_summary AS
SELECT b.id,
       b.number,
       b.name,
       b.spine_color,
       b.slots_per_face,
       b.shelf_position,
       COALESCE(MAX(ci.page_number), 0)                AS sheet_count,
       COUNT(ci.id) FILTER (WHERE ci.status <> 'SOLD')  AS card_count,
       COUNT(ci.id) FILTER (WHERE ci.status <> 'SOLD'
                              AND ci.slot_number IS NOT NULL) AS placed_count,
       COALESCE(SUM(ci.quantity) FILTER (WHERE ci.status <> 'SOLD'), 0) AS copy_count
FROM binders b
LEFT JOIN collection_items ci ON ci.binder_id = b.id
GROUP BY b.id;

COMMENT ON VIEW binder_summary IS 'Datos derivados de cada carpeta para la pantalla de estantería';
COMMENT ON COLUMN binder_summary.id IS 'Carpeta descrita';
COMMENT ON COLUMN binder_summary.number IS 'Numero rotulado en el lomo';
COMMENT ON COLUMN binder_summary.name IS 'Nombre de la carpeta';
COMMENT ON COLUMN binder_summary.spine_color IS 'Color del lomo en #RRGGBB';
COMMENT ON COLUMN binder_summary.slots_per_face IS 'Huecos por cara; una hoja tiene el doble';
COMMENT ON COLUMN binder_summary.shelf_position IS 'Orden fisico en la estanteria';
COMMENT ON COLUMN binder_summary.sheet_count IS 'Hojas de la carpeta; cada hoja tiene dos caras';
COMMENT ON COLUMN binder_summary.card_count IS 'Cartas asignadas a la carpeta, tengan o no hueco concreto';
COMMENT ON COLUMN binder_summary.placed_count IS 'De esas, las que ya tienen hueco asignado; la diferencia es lo que queda por colocar';
COMMENT ON COLUMN binder_summary.copy_count IS 'Ejemplares poseídos de esas cartas, incluidas las copias guardadas fuera';

-- ---------------------------------------------------------------------
-- 7. Acceso (administrador único + lectura pública anónima)
-- ---------------------------------------------------------------------

CREATE TABLE app_users (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    username      VARCHAR(60) NOT NULL UNIQUE,
    email         VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    role          VARCHAR(20) NOT NULL DEFAULT 'ADMIN'
                  CHECK (role IN ('ADMIN')),
    is_active     BOOLEAN NOT NULL DEFAULT TRUE,
    last_login_at TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE app_users IS 'Solo administradores; la vista pública es anónima y de solo lectura';
COMMENT ON COLUMN app_users.id IS 'Clave sustituta';
COMMENT ON COLUMN app_users.username IS 'Identificador de acceso del administrador';
COMMENT ON COLUMN app_users.email IS 'Correo del administrador; unico, para recuperacion de acceso';
COMMENT ON COLUMN app_users.password_hash IS 'Hash de la contrasena. Nunca se guarda en claro';
COMMENT ON COLUMN app_users.role IS 'Hoy solo ADMIN. La vista publica es anonima y no tiene fila aqui';
COMMENT ON COLUMN app_users.is_active IS 'Permite revocar el acceso sin borrar la cuenta ni perder su rastro';
COMMENT ON COLUMN app_users.last_login_at IS 'Ultimo acceso correcto; util para detectar uso no esperado';
COMMENT ON COLUMN app_users.created_at IS 'Alta del registro en el sistema';
COMMENT ON COLUMN app_users.updated_at IS 'Ultima modificacion; lo mantiene un disparador';

-- ---------------------------------------------------------------------
-- 8. Escaneo de cartas por cámara (fase 3)
--    El detalle bruto del OCR va en JSONB: replicar aquí las 30 columnas
--    de la ficha de carta duplicaría el modelo y habría que mantener dos
--    esquemas en paralelo.
-- ---------------------------------------------------------------------

CREATE TABLE card_scans (
    id                 BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    image_path         VARCHAR(500) NOT NULL,
    detected_passcode  CHAR(8) CHECK (detected_passcode ~ '^[0-9]{8}$'),
    detected_set_number VARCHAR(20),
    confidence         NUMERIC(5, 4) CHECK (confidence BETWEEN 0 AND 1),
    raw_ocr            JSONB,
    engine_version     VARCHAR(50) NOT NULL,
    processing_time_ms INTEGER,
    status             scan_status NOT NULL DEFAULT 'PENDING',
    matched_card_id    BIGINT REFERENCES cards (id) ON DELETE SET NULL,
    failure_reason     TEXT,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolved_at        TIMESTAMPTZ
);
COMMENT ON TABLE card_scans IS 'Cada intento de leer una carta fisica con la camara. Se conservan tambien los fallidos: son la evidencia de la evaluacion empirica del reconocimiento';
COMMENT ON COLUMN card_scans.id IS 'Clave sustituta';
COMMENT ON COLUMN card_scans.image_path IS 'Localizacion de la foto capturada';
COMMENT ON COLUMN card_scans.detected_passcode IS 'Passcode leido por el OCR; NULL si no se pudo leer';
COMMENT ON COLUMN card_scans.detected_set_number IS 'Numero de set leido, si se intento. Permite desambiguar entre impresiones de la misma carta';
COMMENT ON COLUMN card_scans.confidence IS 'Confianza del OCR entre 0 y 1. Por debajo del umbral la interfaz muestra candidatas en vez de autorellenar';
COMMENT ON COLUMN card_scans.raw_ocr IS 'Salida completa del OCR. Va en JSONB porque su forma cambiara con cada iteracion del algoritmo';
COMMENT ON COLUMN card_scans.engine_version IS 'Version del motor y del preprocesado usados; sin ella los porcentajes de acierto no son comparables entre iteraciones';
COMMENT ON COLUMN card_scans.processing_time_ms IS 'Duracion del procesado; metrica de rendimiento de la evaluacion';
COMMENT ON COLUMN card_scans.status IS 'En que punto del ciclo esta el escaneo';
COMMENT ON COLUMN card_scans.matched_card_id IS 'Carta del catalogo con la que se emparejo; NULL mientras no haya coincidencia';
COMMENT ON COLUMN card_scans.failure_reason IS 'Por que fallo, en texto. Sirve para clasificar los fallos al evaluar el reconocimiento';
COMMENT ON COLUMN card_scans.created_at IS 'Momento de la captura';
COMMENT ON COLUMN card_scans.resolved_at IS 'Momento en que el usuario confirmo o descarto la propuesta';

CREATE INDEX idx_card_scans_status ON card_scans (status);
CREATE INDEX idx_card_scans_passcode ON card_scans (detected_passcode);
CREATE INDEX idx_card_scans_created ON card_scans (created_at DESC);

-- ---------------------------------------------------------------------
-- 9. Disparadores
--
--    Ninguno de estos decide nada de negocio: mantienen coherentes
--    columnas que quedarían a medias, o comprueban una invariante que un
--    CHECK no puede expresar porque necesita consultar otra tabla. Las
--    reglas de negocio viven en el dominio.
-- ---------------------------------------------------------------------

-- 9.1 updated_at automático. En PostgreSQL no existe el
--     ON UPDATE CURRENT_TIMESTAMP de MySQL: hace falta un disparador.

CREATE OR REPLACE FUNCTION set_updated_at() RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION set_updated_at() IS 'Mantiene updated_at; PostgreSQL no tiene el ON UPDATE CURRENT_TIMESTAMP de MySQL';

CREATE TRIGGER trg_cards_updated_at BEFORE UPDATE ON cards
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_card_translations_updated_at BEFORE UPDATE ON card_translations
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_monster_cards_updated_at BEFORE UPDATE ON monster_cards
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_spell_cards_updated_at BEFORE UPDATE ON spell_cards
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_trap_cards_updated_at BEFORE UPDATE ON trap_cards
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_card_prints_updated_at BEFORE UPDATE ON card_prints
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_collection_items_updated_at BEFORE UPDATE ON collection_items
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_binders_updated_at BEFORE UPDATE ON binders
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_app_users_updated_at BEFORE UPDATE ON app_users
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- 9.2 Al borrar una carpeta, sus cartas quedan SIN UBICACIÓN, listas para
--     recolocar. La clave ajena ON DELETE SET NULL solo vaciaría
--     binder_id y dejaría la página con valor, lo que viola la regla de
--     "todo o nada" y haría fallar el borrado entero.

CREATE OR REPLACE FUNCTION clear_location_on_binder_delete()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE collection_items
    SET binder_id = NULL, page_number = NULL, face = NULL, slot_number = NULL
    WHERE binder_id = OLD.id;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION clear_location_on_binder_delete() IS 'Al borrar una carpeta deja sus cartas sin ubicacion. Sin esto, ON DELETE SET NULL vaciaria solo binder_id y el borrado fallaria por la regla de todo o nada';

CREATE TRIGGER trg_binders_clear_location
    BEFORE DELETE ON binders
    FOR EACH ROW EXECUTE FUNCTION clear_location_on_binder_delete();

-- 9.3 Mismo patrón al borrar la carta original de un arte alternativo:
--     alternate_art_of se pondría a NULL y artwork_label conservaría su
--     valor, violando la regla de que toda variante lleva etiqueta.

CREATE OR REPLACE FUNCTION clear_artwork_label_on_original_delete()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE cards
    SET alternate_art_of = NULL, artwork_label = NULL
    WHERE alternate_art_of = OLD.id;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION clear_artwork_label_on_original_delete() IS 'Al borrar la carta original limpia tambien la etiqueta de sus variantes, que si no quedaria huerfana y violaria su CHECK';

CREATE TRIGGER trg_cards_clear_artwork_label
    BEFORE DELETE ON cards
    FOR EACH ROW EXECUTE FUNCTION clear_artwork_label_on_original_delete();

-- 9.4 Una imagen de impresión debe pertenecer a la misma carta que la
--     impresión. Un CHECK no puede consultar otra tabla.

CREATE OR REPLACE FUNCTION check_card_image_print_matches_card()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.card_print_id IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM card_prints p
            WHERE p.id = NEW.card_print_id AND p.card_id = NEW.card_id
        ) THEN
            RAISE EXCEPTION 'La impresión % no pertenece a la carta %',
                NEW.card_print_id, NEW.card_id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION check_card_image_print_matches_card() IS 'Impide asignar a una carta el arte de una impresion que no es suya; un CHECK no puede consultar otra tabla';

CREATE TRIGGER trg_card_images_print_matches_card
    BEFORE INSERT OR UPDATE ON card_images
    FOR EACH ROW EXECUTE FUNCTION check_card_image_print_matches_card();
