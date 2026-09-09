-- =====================================================================
-- DuelVault — Correcciones del frontón (PostgreSQL 16+)
-- Migración Flyway: V4__fixes_frontron.sql
--
-- Cierra los defectos encontrados al forzar el diseño contra la base de
-- datos real (ver 07-Casos-limite) y las decisiones de negocio ya
-- tomadas. Cada bloque dice a qué caso responde.
--
-- Criterio de reparto: la base de datos garantiza invariantes de dato e
-- integridad referencial; las reglas de negocio viven en el dominio. Los
-- dos disparadores de aquí NO deciden nada, solo limpian columnas que
-- quedarían incoherentes al desvincular una fila.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. La cara de la hoja (A7)
-- ---------------------------------------------------------------------
-- Una hoja de carpeta tiene dos caras de 9 huecos. "Página 5" a secas es
-- ambiguo: la carta puede estar en el anverso o en el reverso. Se guardan
-- los tres datos por separado, que es como se describe una carta al
-- buscarla en la estantería: carpeta 1, página 5, reverso, hueco 3.

CREATE TYPE binder_face AS ENUM ('FRONT', 'BACK');

ALTER TABLE collection_items ADD COLUMN face binder_face;

COMMENT ON COLUMN collection_items.face IS 'Cara de la hoja: FRONT anverso, BACK reverso';
COMMENT ON COLUMN collection_items.slot_number IS 'Hueco dentro de la cara, 1..slots_per_face';

-- El hueco pasa a ser relativo a una cara, no a una hoja entera.
ALTER TABLE collection_items DROP CONSTRAINT collection_items_slot_number_check;
ALTER TABLE collection_items ADD CONSTRAINT ck_collection_items_slot_range
    CHECK (slot_number BETWEEN 1 AND 16);

-- slots_per_page medía en realidad huecos por CARA. Se renombra para que
-- el nombre no mienta.
ALTER TABLE binders RENAME COLUMN slots_per_page TO slots_per_face;
COMMENT ON COLUMN binders.slots_per_face IS 'Huecos por cara (9 = 3x3); una hoja tiene el doble';

-- Un hueco pertenece a una cara concreta. La ubicación sigue admitiendo
-- estados intermedios: una carta puede estar en una carpeta y una página
-- sin haberle asignado todavía cara y hueco (así llegan los datos
-- importados, que no registran ninguna de las dos cosas).
ALTER TABLE collection_items ADD CONSTRAINT ck_collection_items_slot_needs_face
    CHECK (slot_number IS NULL OR face IS NOT NULL);

ALTER TABLE collection_items DROP CONSTRAINT ck_collection_items_location;
ALTER TABLE collection_items ADD CONSTRAINT ck_collection_items_location CHECK (
    (binder_id IS NULL AND page_number IS NULL AND face IS NULL AND slot_number IS NULL)
    OR (binder_id IS NOT NULL AND page_number IS NOT NULL)
);

ALTER TABLE collection_items DROP CONSTRAINT ck_collection_items_sold_has_no_location;
ALTER TABLE collection_items ADD CONSTRAINT ck_collection_items_sold_has_no_location CHECK (
    status <> 'SOLD'
    OR (binder_id IS NULL AND page_number IS NULL AND face IS NULL AND slot_number IS NULL)
);

-- ---------------------------------------------------------------------
-- 2. Unicidad de hueco, ahora diferible (A6 + A1)
-- ---------------------------------------------------------------------
-- El índice parcial de V3 impedía intercambiar dos cartas de hueco: al
-- mover A al hueco de B chocaba con B, que aún estaba allí. Y un índice
-- parcial NO se puede declarar DEFERRABLE en PostgreSQL.
--
-- No hace falta que sea parcial: los nulos se consideran distintos entre
-- sí, así que una restricción UNIQUE normal deja pasar igual todas las
-- filas sin hueco asignado, y además sí admite diferirse.
--
-- Queda INITIALLY IMMEDIATE para que un error aparezca en el momento; el
-- caso de uso de reordenar abre transacción y hace
-- SET CONSTRAINTS uq_collection_items_slot DEFERRED.

DROP INDEX IF EXISTS uq_collection_items_slot;

ALTER TABLE collection_items
    ADD CONSTRAINT uq_collection_items_slot
    UNIQUE (binder_id, page_number, face, slot_number)
    DEFERRABLE INITIALLY IMMEDIATE;

DROP INDEX IF EXISTS idx_collection_items_location;
CREATE INDEX idx_collection_items_location
    ON collection_items (binder_id, page_number, face, slot_number);

-- ---------------------------------------------------------------------
-- 3. Reordenar carpetas y renumerarlas (A3 + A1)
-- ---------------------------------------------------------------------
-- Intercambiar dos carpetas de posición, o de número, chocaba con la
-- unicidad en el primer UPDATE. Mismo patrón que el hueco.

ALTER TABLE binders DROP CONSTRAINT uq_binder_shelf_position;
ALTER TABLE binders
    ADD CONSTRAINT uq_binder_shelf_position UNIQUE (shelf_position)
    DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE binders DROP CONSTRAINT binders_number_key;
ALTER TABLE binders
    ADD CONSTRAINT uq_binder_number UNIQUE (number)
    DEFERRABLE INITIALLY IMMEDIATE;

-- ---------------------------------------------------------------------
-- 4. Borrar una carpeta que tiene cartas dentro (A1)
-- ---------------------------------------------------------------------
-- La clave ajena ON DELETE SET NULL solo vaciaba binder_id y dejaba la
-- página con valor, lo que viola "la ubicación es todo o nada" y hacía
-- fallar el borrado entero con un mensaje incomprensible.
--
-- Al borrar la carpeta, sus cartas quedan sin ubicación y se pueden
-- recolocar. El disparador no decide nada: solo mantiene coherente lo que
-- la clave ajena deja a medias.

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

-- ---------------------------------------------------------------------
-- 5. Borrar la carta original de un arte alternativo (A2)
-- ---------------------------------------------------------------------
-- Mismo patrón: alternate_art_of se ponía a NULL y artwork_label conservaba
-- su valor, violando la regla de que toda variante lleva etiqueta.

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

-- ---------------------------------------------------------------------
-- 6. Fechas imposibles (A4 + A8)
-- ---------------------------------------------------------------------
-- Un precio fechado en 2099 pasaría a ser "el precio actual" de la carta
-- y contaminaría el total de la colección. Una compra en el futuro no
-- existe.

ALTER TABLE price_snapshots ADD CONSTRAINT ck_price_snapshots_not_future
    CHECK (observed_on <= CURRENT_DATE);

ALTER TABLE collection_items ADD CONSTRAINT ck_collection_items_purchase_not_future
    CHECK (purchase_date <= CURRENT_DATE);

-- ---------------------------------------------------------------------
-- 7. Precios duplicados el mismo día (A5)
-- ---------------------------------------------------------------------
-- La unicidad incluye la fuente, y dos nulos no son iguales entre sí: con
-- la fuente sin informar se colaban dos precios del mismo día para la
-- misma impresión, y cuál ganaba dependía del orden de lectura.

UPDATE price_snapshots SET source = 'MANUAL' WHERE source IS NULL;
ALTER TABLE price_snapshots ALTER COLUMN source SET DEFAULT 'MANUAL';
ALTER TABLE price_snapshots ALTER COLUMN source SET NOT NULL;

-- ---------------------------------------------------------------------
-- 8. Datos de la venta (B1)
-- ---------------------------------------------------------------------
-- El precio de venta puede ser distinto del de compra y del de mercado, y
-- es un dato que interesa conservar.
--
-- Decisión de negocio asociada: cada venta es UNA FILA. Vender 1 de 3
-- copias baja la fila original a 2 y crea otra con cantidad 1, estado
-- SOLD y su propio precio y fecha. No se fusionan las ventas, porque
-- fusionarlas destruiría el precio de cada una. Agrupar "3 vendidas" es
-- trabajo de la pantalla.

ALTER TABLE collection_items ADD COLUMN sale_price NUMERIC(10,2)
      CHECK (sale_price >= 0);
ALTER TABLE collection_items ADD COLUMN sold_on DATE;

COMMENT ON COLUMN collection_items.sale_price IS 'Importe real de la venta, por ejemplar';
COMMENT ON COLUMN collection_items.sold_on IS 'Fecha de la venta';

ALTER TABLE collection_items ADD CONSTRAINT ck_collection_items_sold_not_future
    CHECK (sold_on <= CURRENT_DATE);

-- Los datos de venta solo tienen sentido en una fila vendida, y una fila
-- vendida no puede ser anterior a su compra.
ALTER TABLE collection_items ADD CONSTRAINT ck_collection_items_sale_data
    CHECK (status = 'SOLD' OR (sale_price IS NULL AND sold_on IS NULL));

ALTER TABLE collection_items ADD CONSTRAINT ck_collection_items_sold_after_purchase
    CHECK (sold_on IS NULL OR purchase_date IS NULL OR sold_on >= purchase_date);

CREATE INDEX idx_collection_items_sold_on ON collection_items (sold_on)
    WHERE status = 'SOLD';

-- ---------------------------------------------------------------------
-- 9. La vista de la estantería, con la cara (A10)
-- ---------------------------------------------------------------------
-- card_count cuenta cartas archivadas; copy_count suma ejemplares
-- poseídos, incluidos los que se guardan fuera de la carpeta.
-- sheet_count es el número de hojas, que es lo que se hojea en pantalla.

DROP VIEW IF EXISTS binder_summary;

CREATE VIEW binder_summary AS
SELECT b.id,
       b.number,
       b.name,
       b.spine_color,
       b.slots_per_face,
       b.shelf_position,
       COALESCE(MAX(ci.page_number), 0)             AS sheet_count,
       COUNT(ci.id) FILTER (WHERE ci.status <> 'SOLD') AS card_count,
       COALESCE(SUM(ci.quantity) FILTER (WHERE ci.status <> 'SOLD'), 0) AS copy_count
FROM binders b
LEFT JOIN collection_items ci ON ci.binder_id = b.id
GROUP BY b.id;

COMMENT ON VIEW binder_summary IS 'Datos derivados de cada carpeta para la pantalla de estantería';
COMMENT ON COLUMN binder_summary.sheet_count IS 'Hojas de la carpeta; cada hoja tiene dos caras';
COMMENT ON COLUMN binder_summary.card_count IS 'Cartas archivadas físicamente en la carpeta';
COMMENT ON COLUMN binder_summary.copy_count IS 'Ejemplares poseídos de esas cartas, incluidas las copias guardadas fuera';
