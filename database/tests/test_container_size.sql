-- =====================================================================
-- test_container_size.sql : checks that container.size is a GENERATED
-- column derived from iso_type (the 3NF fix for
-- container_no -> iso_type -> size).
-- Run after sample_data.sql.  Rolled back at the end.
-- =====================================================================

BEGIN;

CREATE FUNCTION pg_temp.expect(label TEXT, query TEXT, expected TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
    got TEXT;
BEGIN
    EXECUTE query INTO got;
    IF got IS NOT DISTINCT FROM expected THEN
        RAISE NOTICE 'PASS  %  -> %', label, got;
    ELSE
        RAISE NOTICE 'FAIL  %  -> got [%], expected [%]', label, got, expected;
    END IF;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'FAIL  %  -> %', label, SQLERRM;
END;
$$;

CREATE FUNCTION pg_temp.expect_reject(label TEXT, stmt TEXT, exp_msg TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE stmt;
    RAISE NOTICE 'FAIL  %  (statement was accepted)', label;
EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%' || exp_msg || '%' THEN
        RAISE NOTICE 'PASS  %  -> %', label, SQLERRM;
    ELSE
        RAISE NOTICE 'FAIL  %  -> wrong error: %', label, SQLERRM;
    END IF;
END;
$$;

SELECT pg_temp.expect('1. sample containers got their size from iso_type',
  $q$SELECT string_agg(size || 'ft=' || n, ', ' ORDER BY size)
     FROM (SELECT size, count(*) AS n FROM container GROUP BY size) x$q$,
  '20ft=3, 40ft=3, 45ft=1');

SAVEPOINT t;
INSERT INTO container (container_no, iso_type) VALUES ('ABCU1234567', 'L5G1');
SELECT pg_temp.expect('2. size is computed on INSERT',
  $q$SELECT size::text FROM container WHERE container_no = 'ABCU1234567'$q$,
  '45');
ROLLBACK TO SAVEPOINT t;

SELECT pg_temp.expect_reject('3. size cannot be inserted by hand',
  $q$INSERT INTO container (container_no, iso_type, size) VALUES ('ABCU1234567', '22G1', 40)$q$,
  'cannot insert a non-DEFAULT value into column "size"');

SELECT pg_temp.expect_reject('4. size cannot be updated by hand',
  $q$UPDATE container SET size = 40 WHERE container_no = 'MSCU1234565'$q$,
  'column "size" can only be updated to DEFAULT');

-- Re-coding a container (e.g. a data-entry fix) updates its size automatically.
SAVEPOINT t;
UPDATE container SET iso_type = '45G1' WHERE container_no = 'MSCU1234565';
SELECT pg_temp.expect('5. changing iso_type recomputes size',
  $q$SELECT iso_type || ' -> ' || size FROM container WHERE container_no = 'MSCU1234565'$q$,
  '45G1 -> 40');
ROLLBACK TO SAVEPOINT t;

SELECT pg_temp.expect_reject('6. type code with an unknown length character',
  $q$INSERT INTO container (container_no, iso_type) VALUES ('ABCU1234567', '9XG1')$q$,
  'container_iso_type_check');

ROLLBACK;
