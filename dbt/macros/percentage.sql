{#
    percentage(num, denom) 
    returns percentage with two decimal places, or null if denom is zero or either term is null

#}
{% macro percentage(num, denom) %}
    case
        when {{ num }} is null or {{ denom }} is null or {{ denom }} = 0 then null
        else round(100.0 * {{ num }} / {{ denom }}, 2)
    end
    -- TODO: implement classification logic
{% endmacro %}
