-- =====================================================================
-- DuelVault — Carpetas, huecos y arte alternativo (PostgreSQL 16+)
-- Migración Flyway: V3__binders_slots_alt_art.sql
--
-- Cierra los tres huecos que destapó el diseño de pantallas:
--   1. Las carpetas no existían como entidad, solo como un entero suelto.
--      La pantalla de estantería necesita nombre, color de lomo y orden.
--   2. No se guardaba el hueco dentro de la página, y la vista de carpeta
--      abierta coloca cada carta en su posición de la rejilla.
--   3. El arte alternativo de una carta (otro passcode, mismo nombre) no
--      tenía forma de relacionarse con la carta original.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Carpetas físicas
-- ---------------------------------------------------------------------

CREATE TABLE binders (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    -- Número rotulado en el lomo. Es la referencia que se usa al buscar
    -- una carta en la estantería real, así que es único y obligatorio.
    number         SMALLINT NOT NULL UNIQUE CHECK (number > 0),
    name           VARCHAR(80) NOT NULL,
    -- Color del lomo en la estantería (#RRGGBB). Decorativo, pero es lo
    -- que permite reconocer la carpeta de un vistazo.
    spine_color    CHAR(7) CHECK (spine_color ~ '^#[0-9A-Fa-f]{6}$'),
    -- Huecos por página: lo normal son 9 (3x3), pero existen fundas de
    -- 4, 12 y 16. Determina el máximo de slot_number de esta carpeta.
    slots_per_page SMALLINT NOT NULL DEFAULT 9
                   CHECK (slots_per_page IN (4, 8, 9, 12, 16)),
    -- Orden en la estantería, independiente del número del lomo.
    shelf_position SMALLINT NOT NULL,
    notes          TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_binder_shelf_position UNIQUE (shelf_position)
);

COMMENT ON TABLE binders IS 'Carpetas de anillas físicas donde se archiva la colección';
COMMENT ON COLUMN binders.slots_per_page IS 'Huecos por página; acota slot_number en collection_items';

CREATE TRIGGER trg_binders_updated_at BEFORE UPDATE ON binders
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ---------------------------------------------------------------------
-- 2. collection_items: de número suelto a relación, más el hueco
-- ---------------------------------------------------------------------

ALTER TABLE collection_items ADD COLUMN binder_id   BIGINT;
ALTER TABLE collection_items ADD COLUMN slot_number SMALLINT
      CHECK (slot_number BETWEEN 1 AND 16);

-- Se crea una carpeta por cada número que ya estuviera en uso, para no
-- perder la ubicación de nada durante la migración de los datos legados.
INSERT INTO binders (number, name, shelf_position)
SELECT DISTINCT binder_number,
       'Carpeta ' || LPAD(binder_number::text, 2, '0'),
       binder_number
FROM collection_items
WHERE binder_number IS NOT NULL
ORDER BY binder_number;

UPDATE collection_items ci
SET binder_id = b.id
FROM binders b
WHERE ci.binder_number = b.number;

ALTER TABLE collection_items DROP COLUMN binder_number;

ALTER TABLE collection_items
    ADD CONSTRAINT fk_collection_items_binder
    FOREIGN KEY (binder_id) REFERENCES binders (id) ON DELETE SET NULL;

-- La ubicación es todo o nada: no tiene sentido una página sin carpeta,
-- ni un hueco sin página.
ALTER TABLE collection_items
    ADD CONSTRAINT ck_collection_items_location CHECK (
        (binder_id IS NULL AND page_number IS NULL AND slot_number IS NULL)
        OR (binder_id IS NOT NULL AND page_number IS NOT NULL)
    );

-- Una carta vendida ya no está en ninguna carpeta: al marcarla como
-- vendida se borra su ubicación. Se conserva la fila con los datos del
-- ejemplar, pero no dónde estuvo archivado.
ALTER TABLE collection_items
    ADD CONSTRAINT ck_collection_items_sold_has_no_location CHECK (
        status <> 'SOLD'
        OR (binder_id IS NULL AND page_number IS NULL AND slot_number IS NULL)
    );

DROP INDEX IF EXISTS idx_collection_items_location;
CREATE INDEX idx_collection_items_location
    ON collection_items (binder_id, page_number, slot_number);

-- Un hueco físico solo admite una carta. Confirmado contra la colección
-- real: no se apilan copias en un mismo bolsillo, cada hueco lleva
-- exactamente una carta.
--
-- El índice es PARCIAL, y eso importa por dos motivos:
--   · Ignora las filas sin hueco asignado, que son todas las importadas
--     del dataset legado (el volcado no registra el hueco). La migración
--     no se rompe.
--   · Las cartas vendidas quedan fuera: el CHECK de arriba les borra la
--     ubicación, así que liberan su hueco de inmediato y se puede
--     reutilizar. Los huecos vacíos en mitad de una página son normales
--     y no hace falta que los ocupados sean consecutivos.
--
-- Esta regla es además lo que acota cuántas cartas caben en una página:
-- si cada carta archivada ocupa un hueco y no puede haber dos en el
-- mismo, el máximo queda limitado por construcción, sin necesidad de un
-- disparador que cuente. La comprobación fina —que el hueco esté dentro
-- del slots_per_page real de esa carpeta— vive en el dominio.
CREATE UNIQUE INDEX uq_collection_items_slot
    ON collection_items (binder_id, page_number, slot_number)
    WHERE binder_id IS NOT NULL AND slot_number IS NOT NULL;

-- ---------------------------------------------------------------------
-- 3. Arte alternativo
-- ---------------------------------------------------------------------
-- Una carta con arte alternativo es una carta distinta con su propio
-- passcode (Mago Oscuro 46986414 / Arkana 36996508). Se apunta a la
-- carta original en lugar de duplicar sus datos.

ALTER TABLE cards ADD COLUMN alternate_art_of BIGINT
      REFERENCES cards (id) ON DELETE SET NULL;
ALTER TABLE cards ADD COLUMN artwork_label VARCHAR(60);

COMMENT ON COLUMN cards.alternate_art_of IS 'Carta original de la que esta es arte alternativo; NULL si es la original';
COMMENT ON COLUMN cards.artwork_label IS 'Nombre de la variante de arte (p. ej. "Arkana")';

ALTER TABLE cards ADD CONSTRAINT ck_cards_alt_art_not_self
    CHECK (alternate_art_of IS NULL OR alternate_art_of <> id);

-- Una variante debe decir de qué variante se trata, y una carta original
-- no puede llevar etiqueta de variante.
ALTER TABLE cards ADD CONSTRAINT ck_cards_artwork_label
    CHECK ((alternate_art_of IS NULL AND artwork_label IS NULL)
        OR (alternate_art_of IS NOT NULL AND artwork_label IS NOT NULL));

CREATE INDEX idx_cards_alternate_art ON cards (alternate_art_of);

-- ---------------------------------------------------------------------
-- 3 bis. Ilustraciones por impresión
-- ---------------------------------------------------------------------
-- Hay dos fenómenos distintos que no deben confundirse:
--
--   a) Mismo nombre, PASSCODE DISTINTO, arte distinto. Son dos cartas
--      diferentes (Mago Oscuro 46986414 / Arkana 36996508). Se resuelve
--      con alternate_art_of, arriba.
--
--   b) Mismo nombre, MISMO PASSCODE, arte distinto. Es la MISMA carta,
--      reimpresa con otra ilustración en otro set. Ahí el arte no
--      pertenece a la carta sino a la impresión concreta.
--
-- Para el caso (b), una imagen puede colgar de una impresión: si
-- card_print_id es NULL, es la ilustración por defecto de la carta; si
-- tiene valor, es el arte específico de esa impresión.

ALTER TABLE card_images ADD COLUMN card_print_id BIGINT
      REFERENCES card_prints (id) ON DELETE CASCADE;

COMMENT ON COLUMN card_images.card_print_id IS 'Impresión concreta cuyo arte difiere; NULL = ilustración por defecto de la carta';

-- El UNIQUE original solo admitía una imagen por carta y tipo, lo que
-- impedía guardar el arte alternativo de una reimpresión.
ALTER TABLE card_images DROP CONSTRAINT card_images_card_id_image_kind_key;

CREATE UNIQUE INDEX uq_card_images_default
    ON card_images (card_id, image_kind)
    WHERE card_print_id IS NULL;

CREATE UNIQUE INDEX uq_card_images_print
    ON card_images (card_print_id, image_kind)
    WHERE card_print_id IS NOT NULL;

-- Una imagen de impresión debe pertenecer a la misma carta que la
-- impresión. Un CHECK no puede consultar otra tabla, así que la
-- invariante se valida en el dominio y se refuerza aquí con un trigger.
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

-- ---------------------------------------------------------------------
-- 4. Vista de apoyo para la pantalla de estantería
-- ---------------------------------------------------------------------
-- El número de páginas y el total de cartas NO se guardan como columnas:
-- se derivan de los ejemplares archivados, para que no puedan quedar
-- desincronizados con la realidad.
--
-- Se distinguen dos cifras, porque significan cosas distintas:
--   · card_count: cartas FÍSICAMENTE en la carpeta, una por fila archivada.
--     Es la que tiene sentido en la estantería, y la que se puede comparar
--     con la capacidad de la carpeta.
--   · copy_count: total de ejemplares poseídos de esas cartas, incluidas
--     las copias que se guardan fuera de la carpeta (ver quantity).
-- Usar SUM(quantity) como "cartas de la carpeta" haría que una página de
-- nueve huecos declarase más cartas de las que caben.

CREATE VIEW binder_summary AS
SELECT b.id,
       b.number,
       b.name,
       b.spine_color,
       b.slots_per_page,
       b.shelf_position,
       COALESCE(MAX(ci.page_number), 0) AS page_count,
       COUNT(ci.id)                     AS card_count,
       COALESCE(SUM(ci.quantity), 0)    AS copy_count
FROM binders b
LEFT JOIN collection_items ci ON ci.binder_id = b.id
GROUP BY b.id;

COMMENT ON VIEW binder_summary IS 'Datos derivados de cada carpeta para la pantalla de estantería';
COMMENT ON COLUMN binder_summary.card_count IS 'Cartas archivadas físicamente en la carpeta';
COMMENT ON COLUMN binder_summary.copy_count IS 'Ejemplares poseídos de esas cartas, incluidas las copias guardadas fuera';
