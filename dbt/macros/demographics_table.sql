{#
    demographics_table(cte_name)
    runs the demographics table output on the given cte, so that the structure can be reused for different groups of students (i.e. noncredit only, college group, etc.)
#}
{% macro demographics_table(cte_name) %}

        with db as (select * from {{ cte_name }}),
        counts as (

            select
                count(*) as total,
                count(*) filter (where gender = 'M') as gender_m,
                count(*) filter (where gender = 'F') as gender_f,
                count(*) filter (where gender not in ('M', 'F')) as gender_u,
                count(*) filter (where latin_american) as latin_american,
                count(*) filter (where black) as black,
                count(*) filter (where aapi) as aapi,
                count(*) filter (where white) as white,
                count(*) filter (where indigenous_american) as indigenous_american,
                count(*) filter (where unknown_race) as unknown_race,
                count(*) filter (where two_or_more_races) as two_or_more_races,
                count(*) filter (
                    where age_at_first_term::int <= 24
                ) as traditional_age_at_entry,
                count(*) filter (
                    where age_at_first_term::int > 24
                ) as over_traditional_age_at_entry,
                count(*) filter (
                    where age_at_first_term::int < 18
                ) as age_at_entry_below_18,
                count(*) filter (
                    where age_at_first_term::int between 18 and 24
                ) as age_at_entry_18_24,
                count(*) filter (
                    where age_at_first_term::int between 25 and 44
                ) as age_at_entry_25_44,
                count(*) filter (
                    where age_at_first_term::int between 45 and 54
                ) as age_at_entry_45_54,
                count(*) filter (
                    where age_at_first_term::int between 55 and 59
                ) as age_at_entry_55_59,
                count(*) filter (
                    where age_at_first_term::int between 60 and 110
                ) as age_at_entry_60_plus,
                count(*) filter (where has_disability) as has_disability,
                count(*) filter (where not has_disability) as not_has_disability,
                count(*) filter (
                    where citizenship_earliest = '1'
                ) as citizenship_earliest_us_citizen,
                count(*) filter (
                    where citizenship_earliest = '2'
                ) as citizenship_earliest_permanent_resident,
                count(*) filter (
                    where citizenship_earliest = '3'
                ) as citizenship_earliest_temporary_resident,
                count(*) filter (
                    where citizenship_earliest = '4'
                ) as citizenship_earliest_refugee_asylee,
                count(*) filter (
                    where citizenship_earliest = '5'
                ) as citizenship_earliest_student_visa,
                count(*) filter (
                    where citizenship_earliest = '6'
                ) as citizenship_earliest_other_status,
                count(*) filter (
                    where citizenship_earliest = 'X' or citizenship_earliest is null
                ) as citizenship_earliest_unknown
            from db
        )
    select
        '{{ cte_name }}' as cte_name,
        total,
        gender_m,
        {{ percentage('gender_m', 'total') }}as gender_m_pct,
        gender_f,
        {{ percentage('gender_f', 'total') }} as gender_f_pct,
        gender_u,
        {{ percentage('gender_u', 'total') }} as gender_u_pct,
        latin_american,
        {{ percentage('latin_american', 'total') }} as latin_american_pct,
        black,
        {{ percentage('black', 'total') }} as black_pct,
        aapi,
        {{ percentage('aapi', 'total') }} as aapi_pct,
        white,
        {{ percentage('white', 'total') }} as white_pct,
        indigenous_american,
        {{ percentage('indigenous_american', 'total') }} as indigenous_american_pct,
        unknown_race,
        {{ percentage('unknown_race', 'total') }} as unknown_race_pct,
        two_or_more_races,
        {{ percentage('two_or_more_races', 'total') }} as two_or_more_races_pct,
        traditional_age_at_entry,
        {{ percentage('traditional_age_at_entry', 'total') }} as traditional_age_at_entry_pct,
        over_traditional_age_at_entry,
        {{ percentage('over_traditional_age_at_entry', 'total') }} as over_traditional_age_at_entry_pct,
        age_at_entry_below_18,
        {{ percentage('age_at_entry_below_18', 'total') }} as age_at_entry_below_18_pct,
        age_at_entry_18_24,
        {{ percentage('age_at_entry_18_24', 'total') }} as age_at_entry_18_24_pct,
        age_at_entry_25_44,
        {{ percentage('age_at_entry_25_44', 'total') }} as age_at_entry_25_44_pct,
        age_at_entry_45_54,
        {{ percentage('age_at_entry_45_54', 'total') }} as age_at_entry_45_54_pct,
        age_at_entry_55_59,
        {{ percentage('age_at_entry_55_59', 'total') }} as age_at_entry_55_59_pct,
        age_at_entry_60_plus,
        {{ percentage('age_at_entry_60_plus', 'total') }} as age_at_entry_60_plus_pct,
        has_disability,
        {{ percentage('has_disability', 'total') }} as has_disability_pct,
        not_has_disability,
        {{ percentage('not_has_disability', 'total') }} as not_has_disability_pct,
        citizenship_earliest_us_citizen,
        {{ percentage(
            'citizenship_earliest_us_citizen', 'total'
        ) }} as citizenship_earliest_us_citizen_pct,
        citizenship_earliest_permanent_resident,
        {{ percentage(
            'citizenship_earliest_permanent_resident', 'total'
        ) }} as citizenship_earliest_permanent_resident_pct,
        citizenship_earliest_temporary_resident,
        {{ percentage(
            'citizenship_earliest_temporary_resident', 'total'
        ) }} as citizenship_earliest_temporary_resident_pct,
        citizenship_earliest_refugee_asylee,
        {{ percentage(
            'citizenship_earliest_refugee_asylee', 'total'
        ) }} as citizenship_earliest_refugee_asylee_pct,
        citizenship_earliest_student_visa,
        {{ percentage(
            'citizenship_earliest_student_visa', 'total'
        ) }} as citizenship_earliest_student_visa_pct,
        citizenship_earliest_other_status,
        {{ percentage(
            'citizenship_earliest_other_status', 'total'
        ) }} as citizenship_earliest_other_status_pct,
        citizenship_earliest_unknown,
        {{ percentage(
            'citizenship_earliest_unknown', 'total'
        ) }} as citizenship_earliest_unknown_pct
    from counts

{% endmacro %}
