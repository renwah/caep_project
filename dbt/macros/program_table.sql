{#
    program_table(cte_name)
    runs the program table output on the given cte, so that the structure can be reused for different groups of students (i.e. noncredit only, college group, etc.)
#}
{% macro program_table(cte_name) %}

        with db as (select * from {{ cte_name }}),
        counts as (

            select
                count(*)                                                                as total,
                count(*) filter (where pell_grant_recipient)                            as pell_grant_recipient,
                count(*) filter (where not pell_grant_recipient)                        as not_pell_grant_recipient,
                count(*) filter (where eops_recipient)                                  as eops_recipient,
                count(*) filter (where not eops_recipient)                              as not_eops_recipient,
                count(*) filter (where special_admit_dual_enrollment)                   as special_admit_dual_enrollment,
                count(*) filter (where not special_admit_dual_enrollment)               as not_special_admit_dual_enrollment,
                count(*) filter (where english_or_math_enrollment)                      as english_or_math_enrollment,
                count(*) filter (where not english_or_math_enrollment)                  as not_english_or_math_enrollment,
                count(*) filter (where first_cb21_level_adj = 'A' OR first_cb21_level_credit_only = 'A')                          as starting_level_esl_a,
                count(*) filter (where first_cb21_level_adj = 'B' OR first_cb21_level_credit_only = 'B')                          as starting_level_esl_b,
                count(*) filter (where first_cb21_level_adj = 'C' OR first_cb21_level_credit_only = 'C')                          as starting_level_esl_c,
                count(*) filter (where first_cb21_level_adj = 'D' OR first_cb21_level_credit_only = 'D')                          as starting_level_esl_d,
                count(*) filter (where first_cb21_level_adj = 'E' OR first_cb21_level_credit_only = 'E')                          as starting_level_esl_e,
                count(*) filter (where first_cb21_level_adj = 'F' OR first_cb21_level_credit_only = 'F')                          as starting_level_esl_f,
                count(*) filter (where first_cb21_level_adj = 'G' OR first_cb21_level_credit_only = 'G')                          as starting_level_esl_g,
                count(*) filter (where first_cb21_level_adj = 'H' OR first_cb21_level_credit_only = 'H')                          as starting_level_esl_h,
                count(*) filter (where first_cb21_level_adj = 'Y')                                                                as starting_level_esl_y_noncredit,
                count(*) filter (where first_cb21_level_credit_only = 'Y')                                                        as starting_level_esl_y_credit,
                count(*) filter (where first_cb21_level_adj is null AND first_cb21_level_credit_only is null)                        as starting_level_esl_unknown
                from db
                    )
    select
        '{{ cte_name }}' as cte_name,
        total,
        pell_grant_recipient,
        not_pell_grant_recipient,
        eops_recipient,
        not_eops_recipient,
        special_admit_dual_enrollment,
        not_special_admit_dual_enrollment,
        english_or_math_enrollment,
        not_english_or_math_enrollment,
        starting_level_esl_a,
        starting_level_esl_b,
        starting_level_esl_c,
        starting_level_esl_d,
        starting_level_esl_e,
        starting_level_esl_f,
        starting_level_esl_g,
        starting_level_esl_h,
        starting_level_esl_y_credit,
        starting_level_esl_y_noncredit,
        starting_level_esl_unknown,
        earned_degree_3_year,
        not_earned_degree_3_year    
    from counts
    UNION ALL
    select 
        '{{ cte_name }}_pct' as cte_name,
        100 as total,
        {{ percentage('pell_grant_recipient', 'total') }} as pell_grant_recipient,
        {{ percentage('not_pell_grant_recipient', 'total') }} as not_pell_grant_recipient,
        {{ percentage('eops_recipient', 'total') }} as eops_recipient,
        {{ percentage('not_eops_recipient', 'total') }} as not_eops_recipient,
        {{ percentage('special_admit_dual_enrollment', 'total') }} as special_admit_dual_enrollment,
        {{ percentage('not_special_admit_dual_enrollment', 'total') }} as not_special_admit_dual_enrollment,
        {{ percentage('english_or_math_enrollment', 'total') }} as english_or_math_enrollment,
        {{ percentage('not_english_or_math_enrollment', 'total') }} as not_english_or_math_enrollment,
        {{ percentage('starting_level_esl_a', 'total') }} as starting_level_esl_a,
        {{ percentage('starting_level_esl_b', 'total') }} as starting_level_esl_b,
        {{ percentage('starting_level_esl_c', 'total') }} as starting_level_esl_c,
        {{ percentage('starting_level_esl_d', 'total') }} as starting_level_esl_d,
        {{ percentage('starting_level_esl_e', 'total') }} as starting_level_esl_e,
        {{ percentage('starting_level_esl_f', 'total') }} as starting_level_esl_f,
        {{ percentage('starting_level_esl_g', 'total') }} as starting_level_esl_g,
        {{ percentage('starting_level_esl_h', 'total') }} as starting_level_esl_h,
        {{ percentage('starting_level_esl_y_credit', 'total') }} as starting_level_esl_y_credit,
        {{ percentage('starting_level_esl_y_noncredit', 'total') }} as starting_level_esl_y_noncredit,
        {{ percentage('starting_level_esl_unknown', 'total') }} as starting_level_esl_unknown,
        {{ percentage('earned_degree_3_year', 'total') }} as earned_degree_3_year,
        {{ percentage('not_earned_degree_3_year', 'total') }} as not_earned_degree_3_year
    from counts
{% endmacro %}
