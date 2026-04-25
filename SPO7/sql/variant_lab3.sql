\pset pager off
\pset null '<null>'

-- Query 1. RIGHT JOIN: Н_ТИПЫ_ВЕДОМОСТЕЙ + Н_ВЕДОМОСТИ.
SELECT
    tv."ИД" AS type_id,
    ved."ЧЛВК_ИД" AS person_id
FROM "Н_ТИПЫ_ВЕДОМОСТЕЙ" tv
RIGHT JOIN "Н_ВЕДОМОСТИ" ved
    ON ved."ТВ_ИД" = tv."ИД"
WHERE tv."ИД" = 1
  AND ved."ИД" = 1250981
  AND ved."ИД" < 1490007;

-- Query 2. INNER JOIN: Н_ЛЮДИ + Н_ОБУЧЕНИЯ + Н_УЧЕНИКИ.
SELECT
    ppl."ФАМИЛИЯ",
    edu."ЧЛВК_ИД",
    stu."ИД" AS student_id
FROM "Н_ЛЮДИ" ppl
INNER JOIN "Н_ОБУЧЕНИЯ" edu
    ON edu."ЧЛВК_ИД" = ppl."ИД"
INNER JOIN "Н_УЧЕНИКИ" stu
    ON stu."ЧЛВК_ИД" = edu."ЧЛВК_ИД"
   AND stu."ВИД_ОБУЧ_ИД" = edu."ВИД_ОБУЧ_ИД"
WHERE ppl."ОТЧЕСТВО" < 'Владимирович'
  AND edu."ЧЛВК_ИД" = 112514;

-- Query 3. Count unique surname/name pairs without DISTINCT.
SELECT COUNT(*) AS unique_last_first_count
FROM (
    SELECT ppl."ФАМИЛИЯ", ppl."ИМЯ"
    FROM "Н_ЛЮДИ" ppl
    GROUP BY ppl."ФАМИЛИЯ", ppl."ИМЯ"
) grouped_names;

-- Query 4. Plans with exactly two groups at the Computer Engineering department.
SELECT plan."НОМЕР" AS plan_no
FROM "Н_ГРУППЫ_ПЛАНОВ" gp
JOIN "Н_ПЛАНЫ" plan
    ON plan."ИД" = gp."ПЛАН_ИД"
JOIN "Н_ОТДЕЛЫ" dept
    ON dept."ИД" = plan."ОТД_ИД_ЗАКРЕПЛЕН_ЗА"
WHERE dept."КОРОТКОЕ_ИМЯ" = 'ВТ'
GROUP BY plan."ИД", plan."НОМЕР"
HAVING COUNT(DISTINCT gp."ГРУППА") = 2
ORDER BY plan."НОМЕР";

-- Query 5. Average marks in group 4100 above average mark in group 1101.
WITH marks AS (
    SELECT
        stu."ГРУППА" AS group_no,
        ppl."ИД" AS person_id,
        ppl."ФАМИЛИЯ",
        ppl."ИМЯ",
        ppl."ОТЧЕСТВО",
        CASE ved."ОЦЕНКА"
            WHEN '5' THEN 5
            WHEN '4' THEN 4
            WHEN '3' THEN 3
            WHEN '2' THEN 2
        END AS mark_value
    FROM "Н_УЧЕНИКИ" stu
    JOIN "Н_ЛЮДИ" ppl
        ON ppl."ИД" = stu."ЧЛВК_ИД"
    JOIN "Н_ВЕДОМОСТИ" ved
        ON ved."ЧЛВК_ИД" = stu."ЧЛВК_ИД"
    WHERE ved."ОЦЕНКА" IN ('5', '4', '3', '2')
), student_avg AS (
    SELECT
        group_no,
        person_id,
        "ФАМИЛИЯ",
        "ИМЯ",
        "ОТЧЕСТВО",
        AVG(mark_value) AS avg_mark
    FROM marks
    GROUP BY group_no, person_id, "ФАМИЛИЯ", "ИМЯ", "ОТЧЕСТВО"
)
SELECT
    person_id AS "Номер",
    "ФАМИЛИЯ" || ' ' || "ИМЯ" || ' ' || COALESCE("ОТЧЕСТВО", '') AS "ФИО",
    ROUND(avg_mark::numeric, 2) AS "Ср_оценка"
FROM student_avg
WHERE group_no = '4100'
  AND avg_mark > (
      SELECT AVG(mark_value)
      FROM marks
      WHERE group_no = '1101'
  )
ORDER BY "ФИО";

-- Query 6. Students enrolled before 2012-09-01 into first-year correspondence plans.
-- The IN subquery is used as required.
SELECT
    stu."ГРУППА" AS group_no,
    edu."НЗК" AS student_book_no,
    ppl."ФАМИЛИЯ",
    ppl."ИМЯ",
    ppl."ОТЧЕСТВО",
    stu."П_ПРКОК_ИД" AS order_item_no,
    stu."СОСТОЯНИЕ" AS order_item_state
FROM "Н_УЧЕНИКИ" stu
JOIN "Н_ЛЮДИ" ppl
    ON ppl."ИД" = stu."ЧЛВК_ИД"
JOIN "Н_ОБУЧЕНИЯ" edu
    ON edu."ЧЛВК_ИД" = stu."ЧЛВК_ИД"
   AND edu."ВИД_ОБУЧ_ИД" = stu."ВИД_ОБУЧ_ИД"
WHERE stu."НАЧАЛО" < DATE '2012-09-01'
  AND stu."ПЛАН_ИД" IN (
      SELECT plan."ИД"
      FROM "Н_ПЛАНЫ" plan
      JOIN "Н_ФОРМЫ_ОБУЧЕНИЯ" form
          ON form."ИД" = plan."ФО_ИД"
      WHERE plan."КУРС" = 1
        AND form."НАИМЕНОВАНИЕ" = 'Заочная'
  )
ORDER BY stu."ГРУППА", ppl."ФАМИЛИЯ", ppl."ИМЯ";

-- Query 7. Number of excellent students in group 3100.
WITH numeric_marks AS (
    SELECT
        stu."ЧЛВК_ИД",
        CASE ved."ОЦЕНКА"
            WHEN '5' THEN 5
            WHEN '4' THEN 4
            WHEN '3' THEN 3
            WHEN '2' THEN 2
        END AS mark_value
    FROM "Н_УЧЕНИКИ" stu
    JOIN "Н_ВЕДОМОСТИ" ved
        ON ved."ЧЛВК_ИД" = stu."ЧЛВК_ИД"
    WHERE stu."ГРУППА" = '3100'
      AND ved."ОЦЕНКА" IN ('5', '4', '3', '2')
), excellent_students AS (
    SELECT "ЧЛВК_ИД"
    FROM numeric_marks
    GROUP BY "ЧЛВК_ИД"
    HAVING MIN(mark_value) = 5
)
SELECT COUNT(*) AS excellent_count
FROM excellent_students;
