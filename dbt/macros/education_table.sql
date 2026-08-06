{#
    education_table(cte_name)
    runs the education table output on the given cte, so that the structure can be reused for different groups of students (i.e. noncredit only, college group, etc.)
#}
{% macro education_table(cte_name) %}

    -- Methods table 2: highest level of education and educational goal at entry.
    -- Source: console_7.sql (table2).
        with db as (select * from {{ cte_name }}),
        counts as (
            select
                count(*) as total,
                count(*) filter (where highest_ed = '0') as highest_ed_no_high_school,
                count(*) filter (
                    where highest_ed = '1'
                ) as highest_ed_k_12_special_admit,
                count(*) filter (where highest_ed = '2') as highest_ed_adult_school,
                count(*) filter (
                    where highest_ed = '3'
                ) as highest_ed_high_school_diploma,
                count(*) filter (where highest_ed = '4') as highest_ed_ged_equivalent,
                count(*) filter (
                    where highest_ed = '5'
                ) as highest_ed_chs_proficiency_certificate,
                count(*) filter (
                    where highest_ed = '6'
                ) as highest_ed_foreign_secondary_school_diploma,
                count(*) filter (where highest_ed = '7') as highest_ed_associate_degree,
                count(*) filter (
                    where highest_ed = '8'
                ) as highest_ed_bachelor_or_higher_degree,
                count(*) filter (
                    where highest_ed = 'X' or highest_ed is null
                ) as highest_ed_unknown,
                count(*) filter (
                    where sb14_student_ed_goal = 'A'
                ) as "Obtain an AD and transfer to a 4-year institution",
                count(*) filter (
                    where sb14_student_ed_goal = 'B'
                ) as "Transfer to a 4-year institution without an AD",
                count(*) filter (
                    where sb14_student_ed_goal = 'C'
                ) as "Transfer to a 4-year institution without an associate degree",
                count(*) filter (
                    where sb14_student_ed_goal = 'E'
                ) as "Earn a vocational certificate without transfer",
                count(*) filter (
                    where sb14_student_ed_goal = 'F'
                ) as "Discover / formulate career interests, plans, goals",
                count(*) filter (
                    where sb14_student_ed_goal = 'G'
                ) as "Prepare for a new career (acquire job skills)",
                count(*) filter (
                    where sb14_student_ed_goal = 'H'
                ) as "Advance in current job / career (update job skills)",
                count(*) filter (
                    where sb14_student_ed_goal = 'I'
                ) as "Maintain certificate or license (e.g. Nursing, Real Estate)",
                count(*) filter (
                    where sb14_student_ed_goal = 'J'
                ) as "Educational development (intellectual, cultural)",
                count(*) filter (
                    where sb14_student_ed_goal = 'K'
                ) as "Improve basic skills in English, reading or math",
                count(*) filter (
                    where sb14_student_ed_goal = 'L'
                ) as "Complete credits for high school diploma or GED",
                count(*) filter (
                    where sb14_student_ed_goal = 'M'
                ) as "Undecided on goal",
                count(*) filter (
                    where sb14_student_ed_goal = 'N'
                ) as "To move from noncredit coursework to credit coursework",
                count(*) filter (
                    where sb14_student_ed_goal = 'O'
                ) as "4-year college student taking courses to meet requirements"
            from db
        )
    select
        '{{ cte_name }}' as cte_name,
        total,
        highest_ed_no_high_school,
        highest_ed_k_12_special_admit,
        highest_ed_adult_school,
        highest_ed_high_school_diploma,
        highest_ed_ged_equivalent,
        highest_ed_chs_proficiency_certificate,
        highest_ed_foreign_secondary_school_diploma,
        highest_ed_associate_degree,
        highest_ed_bachelor_or_higher_degree,
        highest_ed_unknown,
        "Obtain an AD and transfer to a 4-year institution",
        "Transfer to a 4-year institution without an AD",
        "Transfer to a 4-year institution without an associate degree",
        "Earn a vocational certificate without transfer",
        "Discover / formulate career interests, plans, goals",
        "Prepare for a new career (acquire job skills)",
        "Advance in current job / career (update job skills)",
        "Maintain certificate or license (e.g. Nursing, Real Estate)",
        "Educational development (intellectual, cultural)",
        "Improve basic skills in English, reading or math",
        "Complete credits for high school diploma or GED",
        "Undecided on goal",
        "To move from noncredit coursework to credit coursework",
        "4-year college student taking courses to meet requirements"
    from counts
    union all
    select
        '{{ cte_name }}_pct' as cte_name,
        100 as total,
        {{ percentage('highest_ed_no_high_school', 'total') }}
        as highest_ed_no_high_school,
        {{ percentage('highest_ed_k_12_special_admit', 'total') }}
        as highest_ed_k_12_special_admit,
        {{ percentage('highest_ed_adult_school', 'total') }} as highest_ed_adult_school,
        {{ percentage('highest_ed_high_school_diploma', 'total') }}
        as highest_ed_high_school_diploma,
        {{ percentage('highest_ed_ged_equivalent', 'total') }}
        as highest_ed_ged_equivalent,
        {{ percentage('highest_ed_chs_proficiency_certificate', 'total') }}
        as highest_ed_chs_proficiency_certificate,
        {{ percentage('highest_ed_foreign_secondary_school_diploma', 'total') }}
        as highest_ed_foreign_secondary_school_diploma,
        {{ percentage('highest_ed_associate_degree', 'total') }}
        as highest_ed_associate_degree,
        {{ percentage('highest_ed_bachelor_or_higher_degree', 'total') }}
        as highest_ed_bachelor_or_higher_degree,
        {{ percentage('highest_ed_unknown', 'total') }} as highest_ed_unknown,
        {{ percentage('"Obtain an AD and transfer to a 4-year institution"', 'total') }}
        as "Obtain an AD and transfer to a 4-year institution",
        {{ percentage('"Transfer to a 4-year institution without an AD"', 'total') }}
        as "Transfer to a 4-year institution without an AD",
        {{ percentage('"Transfer to a 4-year institution without an associate degree"', 'total') }}
        as "Transfer to a 4-year institution without an associate degree",
        {{ percentage('"Earn a vocational certificate without transfer"', 'total') }}
        as "Earn a vocational certificate without transfer",
        {{ percentage('"Discover / formulate career interests, plans, goals"', 'total') }}
        as "Discover / formulate career interests, plans, goals",
        {{ percentage('"Prepare for a new career (acquire job skills)"', 'total') }}
        as "Prepare for a new career (acquire job skills)",
        {{ percentage('"Advance in current job / career (update job skills)"', 'total') }}
        as "Advance in current job / career (update job skills)",
        {{ percentage('"Maintain certificate or license (e.g. Nursing, Real Estate)"', 'total') }}
        as "Maintain certificate or license (e.g. Nursing, Real Estate)",
        {{ percentage('"Educational development (intellectual, cultural)"', 'total') }}
        as "Educational development (intellectual, cultural)",
        {{ percentage('"Improve basic skills in English, reading or math"', 'total') }}
        as "Improve basic skills in English, reading or math",
        {{ percentage('"Complete credits for high school diploma or GED"', 'total') }}
        as "Complete credits for high school diploma or GED",
        {{ percentage('"Undecided on goal"', 'total') }} as "Undecided on goal",
        {{ percentage('"To move from noncredit coursework to credit coursework"', 'total') }}
        as "To move from noncredit coursework to credit coursework",
        {{ percentage('"4-year college student taking courses to meet requirements"', 'total') }}
        as "4-year college student taking courses to meet requirements"
    from counts
{% endmacro %}
