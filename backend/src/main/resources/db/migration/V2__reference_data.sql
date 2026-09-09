-- =====================================================================
-- DuelVault — Datos de referencia (PostgreSQL)
-- Migración Flyway: V2__reference_data.sql
--
-- Vocabularios tomados de la base de datos oficial de Konami
-- (db.yugioh-card.com / Neuron) y del reglamento oficial del TCG.
-- =====================================================================

-- Códigos de región tal como se imprimen en el número de set.
INSERT INTO languages (code, name_es, name_en) VALUES
    ('SP', 'Español',              'Spanish'),
    ('EN', 'Inglés',               'English'),
    ('FR', 'Francés',              'French'),
    ('DE', 'Alemán',               'German'),
    ('IT', 'Italiano',             'Italian'),
    ('PT', 'Portugués',            'Portuguese'),
    ('JP', 'Japonés',              'Japanese'),
    ('KR', 'Coreano',              'Korean'),
    ('TC', 'Chino tradicional',    'Traditional Chinese'),
    ('SC', 'Chino simplificado',   'Simplified Chinese');

-- Los 26 Tipos oficiales de monstruo, con el año en que Konami los introdujo.
INSERT INTO monster_types (code, name_es, name_en, introduced_year) VALUES
    ('AQUA',          'Aqua',                 'Aqua',          1998),
    ('BEAST',         'Bestia',               'Beast',         1997),
    ('BEAST_WARRIOR', 'Guerrero-Bestia',      'Beast-Warrior', 1996),
    ('CREATOR_GOD',   'Dios Creador',         'Creator God',   2011),
    ('CYBERSE',       'Ciberso',              'Cyberse',       2017),
    ('DINOSAUR',      'Dinosaurio',           'Dinosaur',      1997),
    ('DIVINE_BEAST',  'Bestia Divina',        'Divine-Beast',  2000),
    ('DRAGON',        'Dragón',               'Dragon',        1997),
    ('FAIRY',         'Hada',                 'Fairy',         1998),
    ('FIEND',         'Demonio',              'Fiend',         1996),
    ('FISH',          'Pez',                  'Fish',          1998),
    ('ILLUSION',      'Ilusión',              'Illusion',      2022),
    ('INSECT',        'Insecto',              'Insect',        1998),
    ('MACHINE',       'Máquina',              'Machine',       1998),
    ('PLANT',         'Planta',               'Plant',         1998),
    ('PSYCHIC',       'Psíquico',             'Psychic',       2008),
    ('PYRO',          'Piro',                 'Pyro',          1998),
    ('REPTILE',       'Reptil',               'Reptile',       1998),
    ('ROCK',          'Roca',                 'Rock',          1998),
    ('SEA_SERPENT',   'Serpiente Marina',     'Sea Serpent',   1998),
    ('SPELLCASTER',   'Lanzador de Conjuros', 'Spellcaster',   1998),
    ('THUNDER',       'Trueno',               'Thunder',       1998),
    ('WARRIOR',       'Guerrero',             'Warrior',       1998),
    ('WINGED_BEAST',  'Bestia Alada',         'Winged Beast',  1998),
    ('WYRM',          'Wyrm',                 'Wyrm',          2014),
    ('ZOMBIE',        'Zombi',                'Zombie',        1996);

-- Rarezas del TCG. Lista abierta: se amplía con un INSERT cuando Konami
-- inventa una nueva (pasa prácticamente cada año).
INSERT INTO rarities (code, name_es, name_en) VALUES
    ('COMMON',                     'Común',                          'Common'),
    ('SHORT_PRINT',                'Tirada corta',                   'Short Print'),
    ('RARE',                       'Rara',                           'Rare'),
    ('SUPER_RARE',                 'Super Rara',                     'Super Rare'),
    ('ULTRA_RARE',                 'Ultra Rara',                     'Ultra Rare'),
    ('ULTIMATE_RARE',              'Ultimate Rara',                  'Ultimate Rare'),
    ('SECRET_RARE',                'Secreta',                        'Secret Rare'),
    ('ULTRA_SECRET_RARE',          'Ultra Secreta',                  'Ultra Secret Rare'),
    ('PRISMATIC_SECRET_RARE',      'Secreta Prismática',             'Prismatic Secret Rare'),
    ('PLATINUM_SECRET_RARE',       'Secreta Platino',                'Platinum Secret Rare'),
    ('EXTRA_SECRET_RARE',          'Secreta Extra',                  'Extra Secret Rare'),
    ('QUARTER_CENTURY_SECRET_RARE','Secreta Quarter Century',        'Quarter Century Secret Rare'),
    ('GHOST_RARE',                 'Fantasma',                       'Ghost Rare'),
    ('PLATINUM_RARE',              'Platino',                        'Platinum Rare'),
    ('COLLECTORS_RARE',            'De Coleccionista',               'Collector''s Rare'),
    ('PRISMATIC_COLLECTORS_RARE',  'De Coleccionista Prismática',    'Prismatic Collector''s Rare'),
    ('STARLIGHT_RARE',             'Starlight',                      'Starlight Rare'),
    ('STARFOIL_RARE',              'Starfoil',                       'Starfoil Rare'),
    ('MOSAIC_RARE',                'Mosaico',                        'Mosaic Rare'),
    ('SHATTERFOIL_RARE',           'Shatterfoil',                    'Shatterfoil Rare'),
    ('PARALLEL_RARE',              'Paralela',                       'Parallel Rare'),
    ('NORMAL_PARALLEL_RARE',       'Paralela Normal',                'Normal Parallel Rare'),
    ('SUPER_PARALLEL_RARE',        'Super Paralela',                 'Super Parallel Rare'),
    ('ULTRA_PARALLEL_RARE',        'Ultra Paralela',                 'Ultra Parallel Rare'),
    ('GOLD_RARE',                  'Dorada',                         'Gold Rare'),
    ('GOLD_SECRET_RARE',           'Dorada Secreta',                 'Gold Secret Rare'),
    ('PREMIUM_GOLD_RARE',          'Premium Gold',                   'Premium Gold Rare'),
    ('PHARAOHS_RARE',              'Del Faraón',                     'Pharaoh''s Rare'),
    ('ULTRA_RARE_BLUE',            'Ultra Rara (azul)',              'Ultra Rare (Blue)'),
    ('ULTRA_RARE_RED',             'Ultra Rara (roja)',              'Ultra Rare (Red)');

-- Tipos de producto.
INSERT INTO set_types (code, name_es, name_en) VALUES
    ('BOOSTER_PACK',        'Sobre de expansión',        'Booster Pack'),
    ('STARTER_DECK',        'Mazo inicial',              'Starter Deck'),
    ('STRUCTURE_DECK',      'Mazo estructurado',         'Structure Deck'),
    ('DUELIST_PACK',        'Pack de duelista',          'Duelist Pack'),
    ('SPEED_DUEL',          'Duelo rápido',              'Speed Duel'),
    ('TIN',                 'Lata',                      'Tin'),
    ('MEGA_TIN',            'Mega lata',                 'Mega Tin'),
    ('RARITY_COLLECTION',   'Colección de rarezas',      'Rarity Collection'),
    ('LEGENDARY_COLLECTION','Colección legendaria',      'Legendary Collection'),
    ('BATTLE_PACK',         'Pack de batalla',           'Battle Pack'),
    ('REPRINT_PACK',        'Pack de reimpresiones',     'Reprint Pack'),
    ('BLISTER_PACK',        'Blíster',                   'Blister Pack'),
    ('BOX_SET',             'Caja recopilatoria',        'Box Set'),
    ('DECK_BUILD_PACK',     'Pack constructor de mazos', 'Deck Build Pack'),
    ('PROMOTIONAL',         'Promocional',               'Promotional');
