# SQL validation snapshot

Validation source: `psql -h pg -d ucheb`, user host `se.ifmo.ru`, database `ucheb`.

The exact variant SQL in [variant_lab3.sql](variant_lab3.sql) was checked against the real schema. Row counts used by the SPO7 VM demo:

| Query | Result rows |
|---|---:|
| Q1 | 1 |
| Q2 | 0 |
| Q3 | 5004 |
| Q4 | 40 |
| Q5 | 85 |
| Q6 | 0 |
| Q7 | 0 |

Notes:

- Q2 is empty with the exact variant constants because person `112514` has patronymic `Сергеевич`, which does not satisfy `ОТЧЕСТВО < 'Владимирович'`.
- Q6 is empty with the exact variant constants because no students in the checked data match first-year correspondence plans before `2012-09-01`.
- Q7 is zero for strict excellent-student semantics: every numeric mark of the student in group `3100` must be `5`.
