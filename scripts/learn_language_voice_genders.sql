\set ON_ERROR_STOP on

-- Run: scripts/postgres_shell.sh learn-language < scripts/learn_language_voice_genders.sql
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

CREATE TEMP TABLE voice_genders (
    voice_id text PRIMARY KEY,
    gender text NOT NULL CHECK (gender IN ('male', 'female'))
) ON COMMIT DROP;

INSERT INTO voice_genders VALUES
    ('iOLZqmXTaFktMrY5oZ2z', 'female'), -- Nadja
    ('ZQFCSsF1tIcjtMZJ6VCA', 'female'), -- Louisa
    ('z1EhmmPwF0ENGYE8dBE6', 'male'),   -- Christian Plasa
    ('TumdjBNWanlT3ysvclWh', 'male');   -- Magyar Férfi / Hungarian Male

UPDATE learn_language.voice_configurations c
SET gender = g.gender
FROM voice_genders g
WHERE c.voice_id = g.voice_id AND c.gender IS DISTINCT FROM g.gender
RETURNING c.id, c.display_name, c.model, c.language, c.gender, c.is_enabled;

DO $$
BEGIN
    IF EXISTS (
        SELECT FROM learn_language.voice_configurations
        WHERE gender IS NULL OR gender NOT IN ('male', 'female')
    ) THEN
        RAISE EXCEPTION 'Unclassified voice configurations remain';
    END IF;
END $$;

COMMIT;
