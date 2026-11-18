\set ON_ERROR_STOP on

-- Run: scripts/postgres_shell.sh learn-language < scripts/learn_language_532.sql
-- https://github.com/mucsi96/learn-language/issues/532
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

CREATE TEMP TABLE deck_before ON COMMIT DROP AS
SELECT * FROM learn_language.cards WHERE false;

INSERT INTO deck_before
SELECT * FROM learn_language.cards
WHERE source_id = 'beszedfordulatok'
ORDER BY id FOR UPDATE;

DO $$
BEGIN
    -- Refuse repeat runs or edits made since the reviewed production snapshot.
    IF (SELECT md5(jsonb_agg(jsonb_build_object(
            'id', id, 'data', data, 'readiness', readiness) ORDER BY id)::text)
        FROM deck_before) IS DISTINCT FROM '2b91a8d30dc873952479c47166eee2d8' THEN
        RAISE EXCEPTION 'Deck content changed since review, or this script already ran';
    END IF;
    IF (SELECT count(*) FROM deck_before) <> 300
       OR EXISTS (SELECT FROM deck_before WHERE type <> 'SPEECH'
           OR id !~ '^nemet-300-beszedfordulat-[0-9]{3}$'
           OR jsonb_array_length(data->'examples') IS DISTINCT FROM 1
           OR data#>>'{examples,0,de}' IS NULL
           OR data#>>'{examples,0,hu}' IS NULL) THEN
        RAISE EXCEPTION 'Unexpected Beszédfordulatok deck; review before applying';
    END IF;
END $$;

CREATE TEMP TABLE informal_edits (
    sequence integer GENERATED ALWAYS AS IDENTITY,
    card_number integer NOT NULL,
    old_text text NOT NULL,
    new_text text NOT NULL
) ON COMMIT DROP;

INSERT INTO informal_edits (card_number, old_text, new_text) VALUES
    (1, 'Haben Sie', 'Hast du'),
    (1, 'Jól aludt?', 'Jól aludtál?'),
    (2, 'Guten Tag!', 'Hallo!'),
    (2, 'Jó napot!', 'Szia!'),
    (3, 'Schön, dass Sie da sind.', 'Schön, dass du da bist.'),
    (3, 'Örülök, hogy itt van.', 'Örülök, hogy itt vagy.'),
    (7, 'Sie kennenzulernen', 'dich kennenzulernen'),
    (7, 'megismerhetem', 'megismerhetlek'),
    (25, 'Meinen Sie', 'Meinst du'),
    (25, 'gondol?', 'gondolsz?'),
    (26, 'Können Sie', 'Kannst du'),
    (26, 'können Sie', 'kannst du'),
    (26, 'Megismételné, kérem?', 'Megismételnéd, kérlek?'),
    (26, 'megismételné, kérem?', 'megismételnéd, kérlek?'),
    (27, 'Können Sie', 'Kannst du'),
    (27, 'Beszélne lassabban, kérem?', 'Beszélnél lassabban, kérlek?'),
    (31, 'Können Sie', 'Kannst du'),
    (31, 'Ihren Namen', 'deinen Namen'),
    (31, 'Lebetűzné, kérem?', 'Lebetűznéd, kérlek?'),
    (31, 'Lebetűzné a nevét, kérem?', 'Lebetűznéd a nevedet, kérlek?'),
    (33, 'Meinen Sie', 'Meinst du'),
    (33, 'gondol,', 'gondolsz,'),
    (34, 'Egy pillanat, kérem.', 'Egy pillanat, kérlek.'),
    (36, 'Können Sie', 'Kannst du'),
    (36, 'Beszélne köznyelvi németül, kérem?', 'Beszélnél köznyelvi németül, kérlek?'),
    (37, 'Ihr Platz', 'dein Platz'),
    (37, 'az Ön helye', 'a te helyed'),
    (40, 'Ihre Hilfe', 'deine Hilfe'),
    (40, 'segítségét', 'segítségedet'),
    (41, 'von Ihnen', 'von dir'),
    (41, 'Sie helfen', 'Du hilfst'),
    (41, 'Öntől', 'tőled'),
    (41, 'Sokat segít nekem.', 'Sokat segítesz nekem.'),
    (45, 'Entschuldigen Sie', 'Entschuldige'),
    (46, 'Ihr Verständnis', 'dein Verständnis'),
    (46, 'megértését', 'megértésedet'),
    (47, 'Sie nehmen sich', 'Du nimmst dir'),
    (47, 'Időt szán rám.', 'Időt szánsz rám.'),
    (48, 'Nach Ihnen.', 'Nach dir.'),
    (48, 'nach Ihnen.', 'nach dir.'),
    (48, 'Ön után. / Tessék előremenni.', 'Utánad. / Menj csak előre.'),
    (48, 'Tessék előremenni.', 'Menj csak előre.'),
    (49, 'Könnten Sie', 'Könntest du'),
    (49, 'Megtenné, kérem,', 'Megtennéd, kérlek,'),
    (49, 'Becsukná az ablakot, kérem?', 'Becsuknád az ablakot, kérlek?'),
    (54, 'Hätten Sie', 'Hättest du'),
    (54, 'pillanata?', 'pillanatod?'),
    (55, 'Könnten Sie', 'Könntest du'),
    (55, 'Megmutatná,', 'Megmutatnád,'),
    (62, 'Wissen Sie', 'Weißt du'),
    (62, 'Tudja,', 'Tudod,'),
    (63, 'Können Sie', 'Kannst du'),
    (63, 'Meg tudná', 'Meg tudnád'),
    (140, 'Mit szólnál/szólna', 'Mit szólnál'),
    (157, 'Guten Tag,', 'Hallo,'),
    (157, 'Jó napot,', 'Szia,'),
    (158, 'Ihnen', 'dir'),
    (158, 'Önnek', 'Neked'),
    (215, 'Könnten Sie', 'Könntest du'),
    (215, 'Figyelne arra, kérem,', 'Figyelnél arra, kérlek,'),
    (231, 'Haben Sie', 'Habt ihr'),
    (231, 'Van ... készleten?', 'Van nálatok ... készleten?'),
    (231, 'Van ez a modell készleten?', 'Van nálatok ez a modell készleten?'),
    (241, 'Haben Sie', 'Habt ihr'),
    (241, 'asztaluk', 'asztalotok'),
    (245, 'kérem.', 'kérlek.'),
    (246, 'können Sie', 'kannst du'),
    (246, 'Mit tud ajánlani?', 'Mit tudsz ajánlani?'),
    (255, 'Gehen Sie', 'Geh'),
    (255, 'Menjen', 'Menj'),
    (256, 'Biegen Sie', 'Bieg'),
    (256, 'Forduljon', 'Fordulj'),
    (256, 'forduljon', 'fordulj'),
    (277, 'Guten Tag,', 'Hallo,'),
    (277, 'Jó napot,', 'Szia,'),
    (279, 'Frau Meier', 'Anna'),
    (279, 'Meier asszonnyal', 'Annával'),
    (280, 'Können Sie', 'Kannst du'),
    (280, 'Visszahívna, kérem?', 'Visszahívnál, kérlek?'),
    (280, 'Visszahívna ma délután, kérem?', 'Visszahívnál ma délután, kérlek?'),
    (281, 'Sie', 'dich'),
    (281, 'hallom Önt', 'hallak'),
    (282, 'Ihnen', 'dir'),
    (282, 'Önnek', 'neked'),
    (283, 'Ihre Bestätigung', 'deine Bestätigung'),
    (283, 'visszaigazolását', 'visszaigazolásodat'),
    (284, 'Können Sie', 'Kannst du'),
    (284, 'Megerősítené', 'Megerősítenéd'),
    (289, 'Egy pillanat, kérem.', 'Egy pillanat, kérlek.');

CREATE FUNCTION pg_temp.informal(card_number integer, original text) RETURNS text
LANGUAGE sql STABLE STRICT AS $$
    WITH RECURSIVE edits AS (
        SELECT row_number() OVER (ORDER BY sequence) AS n, old_text, new_text
        FROM informal_edits WHERE card_number = $1
    ), result AS (
        SELECT 0::bigint AS n, $2 AS value
        UNION ALL
        SELECT edits.n, replace(result.value, edits.old_text, edits.new_text)
        FROM result JOIN edits ON edits.n = result.n + 1
    )
    SELECT value FROM result ORDER BY n DESC LIMIT 1;
$$;

-- VoiceGenderService permits explicit speaker identification, never the addressee,
-- relatives, noun gender or occupational stereotypes. Anna, Paul and Peter introduce
-- themselves; the other examples do not unambiguously identify the speaker's gender.
WITH revised AS (
    SELECT id, (data - 'audio') || jsonb_build_object(
        'frontText', pg_temp.informal(right(id, 3)::integer, data->>'frontText'),
        'backText', pg_temp.informal(right(id, 3)::integer,
            replace(data->>'backText',
                'Magázó forma (a fordulatban vagy a példában).',
                'Tegező forma (a fordulatban vagy a példában).')),
        'examples', (
            SELECT jsonb_agg(example || jsonb_build_object(
                'de', pg_temp.informal(right(id, 3)::integer, example->>'de'),
                'hu', pg_temp.informal(right(id, 3)::integer, example->>'hu'),
                'voiceGenderHint', CASE right(id, 3)
                    WHEN '007' THEN 'female'
                    WHEN '008' THEN 'male'
                    WHEN '013' THEN 'male'
                    WHEN '277' THEN 'male'
                    ELSE NULL END
            ) ORDER BY ordinal)
            FROM jsonb_array_elements(data->'examples') WITH ORDINALITY AS e(example, ordinal)
        )
    ) AS data FROM deck_before
)
UPDATE learn_language.cards c
SET data = revised.data, readiness = 'DRAFT'
FROM revised WHERE c.id = revised.id;

DO $$
BEGIN
    IF EXISTS (
        SELECT FROM learn_language.cards c JOIN deck_before b USING (id)
        WHERE c.readiness <> 'DRAFT' OR c.data ? 'audio'
           OR c.data->>'backText' ~ '\m(Sie|Ihnen|Ihr|Ihre|Ihren|Magázó)\M'
           OR c.data->>'frontText' ~ '\m(Ön|Önnek|Önt|Öntől)\M'
           OR NOT (c.data#>'{examples,0}' ? 'voiceGenderHint')
           OR (to_jsonb(c) - 'data' - 'readiness') IS DISTINCT FROM
              (to_jsonb(b) - 'data' - 'readiness')
           OR (c.data - 'audio' - 'frontText' - 'backText' - 'examples') IS DISTINCT FROM
              (b.data - 'audio' - 'frontText' - 'backText' - 'examples')
           OR ((c.data#>'{examples,0}') - 'de' - 'hu' - 'voiceGenderHint') IS DISTINCT FROM
              ((b.data#>'{examples,0}') - 'de' - 'hu' - 'voiceGenderHint')
    ) THEN
        RAISE EXCEPTION 'Deck postconditions failed';
    END IF;
END $$;

SELECT count(*) AS cards, count(*) FILTER (WHERE readiness = 'DRAFT') AS drafts,
       count(*) FILTER (WHERE data ? 'audio') AS cards_with_audio
FROM learn_language.cards WHERE source_id = 'beszedfordulatok';

COMMIT;
