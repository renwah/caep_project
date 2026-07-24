with demo_base as (
    select * from {{ ref('methods_demographic_base') }}
),
raw_numbers as (
select
    first_cb21_level_adj,
    count(distinct uuid) as total,
    count(distinct uuid) filter (where always_noncredit_esl) as noncredit_only,
    count(distinct uuid) filter (where always_credit_esl) as credit_only,
    count(distinct uuid) filter (where both_credit_noncredit_esl) as both_credit_noncredit,
    count(distinct uuid) filter (where first_college_group_adj = 'CONFIRMED CC - 6 LEVELS') as confirmed_cc_6_levels,
    count(distinct uuid) filter (where first_college_group_adj = 'CONFIRMED CC - A/B') as confirmed_cc_a_b_levels,
    count(distinct uuid) filter (where first_college_group_adj = 'CONFIRMED CC - E/F') as confirmed_cc_e_f_levels,
    count(distinct uuid) filter (where first_college_group_adj = 'POSSIBLE CC') as possible_cc
    from demo_base WHERE first_college_group_adj != 'Other CC'
    group by first_cb21_level_adj
)
select
    first_cb21_level_adj,
    total,
    noncredit_only,
    {{ percentage('noncredit_only', 'total') }} as noncredit_only_pct,
    credit_only,
    {{ percentage('credit_only', 'total') }} as credit_only_pct,
    both_credit_noncredit,
    {{ percentage('both_credit_noncredit', 'total') }} as both_credit_noncredit_pct,
    confirmed_cc_6_levels,
    {{ percentage('confirmed_cc_6_levels', 'total') }} as confirmed_cc_6_levels_pct,
    confirmed_cc_a_b_levels,
    {{ percentage('confirmed_cc_a_b_levels', 'total') }} as confirmed_cc_a_b_levels_pct,
    confirmed_cc_e_f_levels,
    {{ percentage('confirmed_cc_e_f_levels', 'total') }} as confirmed_cc_e_f_levels_pct,
    possible_cc,
    {{ percentage('possible_cc', 'total') }} as possible_cc_pct
    from raw_numbers
UNION ALL
select 
    'Total' as first_cb21_level_adj,
    sum(total) as total,
    sum(noncredit_only) as noncredit_only,
    100,
    sum(credit_only) as credit_only,
    100,
    sum(both_credit_noncredit) as both_credit_noncredit,
    100,
    sum(confirmed_cc_6_levels) as confirmed_cc_6_levels,
    100,
    sum(confirmed_cc_a_b_levels) as confirmed_cc_a_b_levels,
    100,
    sum(confirmed_cc_e_f_levels) as confirmed_cc_e_f_levels,
    100,
    sum(possible_cc) as possible_cc,
    100
from raw_numbers