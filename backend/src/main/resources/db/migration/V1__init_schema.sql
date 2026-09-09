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
-- A partir de aquí, cada cambio SÍ es una migración nueva.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0 bis. Extensiones
--    Ambas son "trusted" desde PostgreSQL 13: las puede instalar el
--    propietario de la base de datos, no hace falta superusuario.
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

-- 7 atributos oficiales (los 6 clásicos + DIVINE de las Cartas de Dios).
CREATE TYPE monster_attribute AS ENUM
    ('DARK', 'LIGHT', 'EARTH', 'WATER', 'FIRE', 'WIND', 'DIVINE');

-- Marco de la carta / método de Invocación. Excluyentes entre sí.
CREATE TYPE monster_frame AS ENUM
    ('NORMAL', 'EFFECT', 'RITUAL', 'FUSION', 'SYNCHRO', 'XYZ', 'LINK');

-- Habilidades: se SUPERPONEN al marco y pueden combinarse entre ellas
-- (existen "Synchro Tuner", "Flip Tuner", "Pendulum Xyz"...).
CREATE TYPE monster_ability AS ENUM
    ('TUNER', 'FLIP', 'GEMINI', 'SPIRIT', 'TOON', 'UNION');

CREATE TYPE spell_type AS ENUM
    ('NORMAL', 'CONTINUOUS', 'EQUIP', 'QUICK_PLAY', 'FIELD', 'RITUAL');

CREATE TYPE trap_type AS ENUM ('NORMAL', 'CONTINUOUS', 'COUNTER');

CREATE TYPE print_edition AS ENUM
    ('FIRST_EDITION', 'UNLIMITED', 'LIMITED_EDITION');

-- Escala de conservación estándar del mercado de coleccionismo.
CREATE TYPE card_condition AS ENUM
    ('MINT', 'NEAR_MINT', 'EXCELLENT', 'GOOD', 'LIGHT_PLAYED', 'PLAYED', 'POOR');

-- Estado del ejemplar dentro de la colección (deriva de `venta` 0/1/2).
CREATE TYPE ownership_status AS ENUM ('OWNED', 'FOR_SALE', 'SOLD');

-- Cara de una hoja de carpeta. Una hoja tiene dos caras de 9 huecos, así
-- que "página 5, hueco 3" sin la cara es ambiguo.
CREATE TYPE binder_face AS ENUM ('FRONT', 'BACK');

CREATE TYPE banlist_format AS ENUM ('ADVANCED', 'TRADITIONAL');

CREATE TYPE banlist_status AS ENUM
    ('FORBIDDEN', 'LIMITED', 'SEMI_LIMITED', 'UNLIMITED');

CREATE TYPE image_kind AS ENUM ('FULL_CARD', 'ARTWORK', 'THUMBNAIL');

CREATE TYPE scan_status AS ENUM
    ('PENDING', 'MATCHED', 'CONFIRMED', 'REJECTED', 'FAILED');

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

-- Las rarezas son el vocabulario que más crece del juego (>35 a día de
-- hoy, varias nuevas por año). Tabla obligatoriamente.
CREATE TABLE rarities (
    id          SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code        VARCHAR(50) NOT NULL UNIQUE,
    name_es     VARCHAR(80) NOT NULL,
    name_en     VARCHAR(80) NOT NULL
);

CREATE TABLE set_types (
    id          SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code        VARCHAR(40) NOT NULL UNIQUE,
    name_es     VARCHAR(80) NOT NULL,
    name_en     VARCHAR(80) NOT NULL
);

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
COMMENT ON COLUMN cards.passcode IS 'Passcode oficial de 8 dígitos; NULL solo para Fichas y Habilidades';
COMMENT ON COLUMN cards.alternate_art_of IS 'Carta original de la que esta es arte alternativo; NULL si es la original';
COMMENT ON COLUMN cards.artwork_label IS 'Nombre de la variante de arte (p. ej. "Arkana")';

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
COMMENT ON COLUMN card_translations.card_text IS 'Texto de efecto, o texto ambientación en monstruos Normales';

CREATE INDEX idx_card_translations_name ON card_translations (language_code, name);

-- Búsqueda del buscador: por NOMBRE o por TEXTO DE EFECTO, en ambos casos
-- por coincidencia parcial e insensible a mayúsculas y acentos.
--
-- unaccent() no es IMMUTABLE (depende del diccionario, que se puede
-- cambiar), y PostgreSQL no indexa expresiones no inmutables. Se envuelve
-- fijando el diccionario explícitamente, que es el patrón estándar.
CREATE OR REPLACE FUNCTION immutable_unaccent(text)
RETURNS text AS $$ SELECT public.unaccent('public.unaccent', $1) $$
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

-- Flechas de Enlace: 8 direcciones posibles; su número es el Link Rating.
CREATE TABLE monster_link_arrows (
    card_id   BIGINT NOT NULL REFERENCES monster_cards (card_id) ON DELETE CASCADE,
    arrow     VARCHAR(12) NOT NULL
              CHECK (arrow IN ('TOP_LEFT', 'TOP', 'TOP_RIGHT',
                               'LEFT', 'RIGHT',
                               'BOTTOM_LEFT', 'BOTTOM', 'BOTTOM_RIGHT')),
    PRIMARY KEY (card_id, arrow)
);

CREATE TABLE spell_cards (
    card_id     BIGINT PRIMARY KEY REFERENCES cards (id) ON DELETE CASCADE,
    spell_type  spell_type NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_spell_type ON spell_cards (spell_type);

CREATE TABLE trap_cards (
    card_id     BIGINT PRIMARY KEY REFERENCES cards (id) ON DELETE CASCADE,
    trap_type   trap_type NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
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

CREATE TABLE archetype_translations (
    archetype_id  BIGINT NOT NULL REFERENCES archetypes (id) ON DELETE CASCADE,
    language_code CHAR(2) NOT NULL REFERENCES languages (code),
    name          VARCHAR(255) NOT NULL,
    description   TEXT,
    PRIMARY KEY (archetype_id, language_code)
);

CREATE TABLE card_archetypes (
    card_id      BIGINT NOT NULL REFERENCES cards (id) ON DELETE CASCADE,
    archetype_id BIGINT NOT NULL REFERENCES archetypes (id) ON DELETE CASCADE,
    -- FALSE = la carta pertenece al arquetipo; TRUE = solo lo apoya.
    is_support   BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (card_id, archetype_id)
);
CREATE INDEX idx_card_archetypes_archetype ON card_archetypes (archetype_id);

CREATE TABLE effect_categories (
    id                 BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code               VARCHAR(80) NOT NULL UNIQUE,
    parent_category_id BIGINT REFERENCES effect_categories (id)
);

CREATE TABLE effect_category_translations (
    effect_category_id BIGINT NOT NULL REFERENCES effect_categories (id) ON DELETE CASCADE,
    language_code      CHAR(2) NOT NULL REFERENCES languages (code),
    name               VARCHAR(255) NOT NULL,
    PRIMARY KEY (effect_category_id, language_code)
);

CREATE TABLE card_effect_categories (
    card_id            BIGINT NOT NULL REFERENCES cards (id) ON DELETE CASCADE,
    effect_category_id BIGINT NOT NULL REFERENCES effect_categories (id) ON DELETE CASCADE,
    PRIMARY KEY (card_id, effect_category_id)
);

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

CREATE TABLE card_set_translations (
    card_set_id   BIGINT NOT NULL REFERENCES card_sets (id) ON DELETE CASCADE,
    language_code CHAR(2) NOT NULL REFERENCES languages (code),
    name          VARCHAR(255) NOT NULL,
    PRIMARY KEY (card_set_id, language_code)
);

-- Una impresión concreta: esta carta, en este set, con este número,
-- esta rareza, este idioma y esta edición.
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
COMMENT ON COLUMN card_images.card_print_id IS 'Impresión concreta cuyo arte difiere; NULL = ilustración por defecto de la carta';

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
COMMENT ON COLUMN binders.slots_per_face IS 'Huecos por cara (9 = 3x3); una hoja tiene el doble';

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
COMMENT ON COLUMN collection_items.quantity IS 'Copias poseídas de esta impresión, incluidas las guardadas fuera de la carpeta';
COMMENT ON COLUMN collection_items.page_number IS 'La hoja dentro de la carpeta';
COMMENT ON COLUMN collection_items.face IS 'Cara de la hoja: FRONT anverso, BACK reverso';
COMMENT ON COLUMN collection_items.slot_number IS 'Hueco dentro de la cara, 1..slots_per_face';
COMMENT ON COLUMN collection_items.sale_price IS 'Importe real de la venta, por ejemplar';
COMMENT ON COLUMN collection_items.sold_on IS 'Fecha de la venta';

CREATE INDEX idx_collection_items_print ON collection_items (card_print_id);
CREATE INDEX idx_collection_items_status ON collection_items (status);
CREATE INDEX idx_collection_items_location
    ON collection_items (binder_id, page_number, face, slot_number);
CREATE INDEX idx_collection_items_sold_on ON collection_items (sold_on)
    WHERE status = 'SOLD';

-- Datos derivados de cada carpeta para la pantalla de estantería. NO son
-- columnas: se calculan, para que no puedan desincronizarse de la realidad.
--
-- card_count cuenta cartas archivadas (una por fila); copy_count suma
-- ejemplares poseídos, incluidos los guardados fuera. Contar con SUM en la
-- estantería haría que una cara de nueve huecos declarase más cartas de
-- las que caben.
CREATE VIEW binder_summary AS
SELECT b.id,
       b.number,
       b.name,
       b.spine_color,
       b.slots_per_face,
       b.shelf_position,
       COALESCE(MAX(ci.page_number), 0)                AS sheet_count,
       COUNT(ci.id) FILTER (WHERE ci.status <> 'SOLD')  AS card_count,
       COALESCE(SUM(ci.quantity) FILTER (WHERE ci.status <> 'SOLD'), 0) AS copy_count
FROM binders b
LEFT JOIN collection_items ci ON ci.binder_id = b.id
GROUP BY b.id;

COMMENT ON VIEW binder_summary IS 'Datos derivados de cada carpeta para la pantalla de estantería';
COMMENT ON COLUMN binder_summary.sheet_count IS 'Hojas de la carpeta; cada hoja tiene dos caras';
COMMENT ON COLUMN binder_summary.card_count IS 'Cartas archivadas físicamente en la carpeta';
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

CREATE TRIGGER trg_card_images_print_matches_card
    BEFORE INSERT OR UPDATE ON card_images
    FOR EACH ROW EXECUTE FUNCTION check_card_image_print_matches_card();
