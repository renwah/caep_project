# CAEP dbt project

Rebuilds the calculated `students` fields (previously produced by ad-hoc
`ALTER TABLE` / `UPDATE` scripts in `../source_sql`) as version-controlled dbt
models, so each field's derivation is recorded clearly.

## Layout

Raw data lives in the Postgres `caep_data` schema (declared as a dbt source in
`staging/_sources.yml`). The `sr*` tables are untouched source extracts.

Models are built as a **layered chain** — each one selects from the previous and
adds its category of columns, so the final model is the complete students table:

```
students              identity spine (maskedsb00, uuid)
   └─ students_demographics    + gender, race, citizenship, education, disability, age
        └─ students_degree_info     + earliest/highest degree, degree term & counts
             └─ students_cohort_info    + sample membership, cohort, first campus,
                                          first course type, first CB21 level (adjusted)
```

Each stored column maps to the source SQL it came from:

| Model                   | Source SQL                                             |
|-------------------------|--------------------------------------------------------|
| students                | `ddl.sql` (identity), `adding_student_uuid.sql`        |
| students_demographics   | `demographics study.sql`                               |
| students_degree_info    | `demographics study.sql` (degree sections)             |
| students_cohort_info    | `building sample.sql`, `console_2.sql`, `pathways_calculations.sql` |

### Marts (`marts/`)

`console_7.sql` ("methods tables 1-3") is converted into:

- **methods_demographic_base** — one row per sampled student (first_term_enrolled
  175-234) with the recoded analysis features (the source's `demographic_base` CTE).
- **methods_table1_demographics / _table2_education / _table3_program** — the three
  count rollups, each aggregating `methods_demographic_base`.

Models are written to the **`caep_analytics`** schema (see `profiles.yml`) so the
`students` model does not overwrite the raw `caep_data.students` table it reads
its identity spine from.

## Running

This project targets **Postgres**, which the `dbt` (dbt-fusion) preview on your
PATH does not yet support. Use dbt-core with the Postgres adapter — it's already
installed in the repo's `.venv` (`dbt-core` 1.12 + `dbt-postgres` 1.11):

```bash
cd dbt
export DBT_PROFILES_DIR="$PWD"
export DBT_PG_PASSWORD="<your postgres password>"

../.venv/bin/dbt debug     # verify the connection
../.venv/bin/dbt build     # run the models + tests, in dependency order
```

`dbt build` runs `students → students_demographics → students_degree_info →
students_cohort_info` in order and executes the uniqueness / not-null tests in
`staging/schema.yml`. `dbt parse` and `dbt compile` have been verified; `build`
needs a live connection to your local Postgres.

## Notes / assumptions

- The identity spine takes the existing `(maskedsb00, uuid)` mapping from
  `caep_data.students` as-is, because the raw `sr*` tables already reference those
  uuids via their `student_uuid` columns. Regenerating uuids would break joins.
- The staging models started as a **core representative** field set and grow as
  marts need more. Fields added to support the console_7 mart:
  `students_demographics` gained `special_admit_dual_enrollment`,
  `sb14_student_ed_goal`, `english_or_math_enrollment`, `pell_grant_recipient`,
  `eops_recipient`; `students_cohort_info` gained `both_credit_noncredit_esl`,
  `term_in_6`, `term_in_12`, `terms_to_full_completion_adjusted_bf_to_a`,
  `full_completion_levels_adjusted_bf_to_a`.
- Still not carried over (no mart needs them yet): the other special populations,
  EFL scores, credits earned, residence/zip, `terms_to_full_completion` (the
  non-`bf_to_a` variants), and the 6/12-term boolean attendance flags.
- `term_in_6` / `term_in_12` reproduce the FALL/SPRING window arithmetic from
  console_2.sql verbatim, including its quirks — not "fixed" here, so results
  match the original.
- `students_cohort_info.in_sample` reproduces the `ells_started_17_w_attendance`
  sample definition from `building sample.sql` (ESL in the study window, 12+
  attendance hours, first ESL term in window, no ESL before the window).


### scratch: macros to build:
```
select count(*), age_at_first_term from students WHERE first_term_enrolled BETWEEN 175 AND 234 group BY age_at_first_term order by age_at_first_term::int ;

--macros:
cb.cb03 in ('493084', '493085', '493086', '493087') --all esl courses
cb.cb03 in ('493084', '493085', '493086') --all esl courses except integrated (for cb21 calculations)

--combine terms into semesters:
case
    when trim(term.term) in ('SUMMER TERM', 'SUMMER QUARTER', 'FALL SEMESTER', 'FALL QUARTER', 'ANNUAL')
        then 'F'
    when trim(term.term) in ('WINTER INTERSESSION', 'WINTER QUARTER', 'SPRING SEMESTER', 'SPRING QUARTER')
        then 'S'
end as cohort

--study terms of interest:
sx.gi03 between 174 and 234


--didn't drop or fail course:
      and sx.sx02 = '19080808'                -- didn't drop
      and sx.sx04 not in ('W', 'FW', 'DR')  -- didn't withdraw/drop
      and sx.sx04 not in ('NP', 'INP', 'FW', 'F') --didn't fail
```