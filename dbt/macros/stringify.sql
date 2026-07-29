{#
 stringify_terms(table, column) - returns a string combining the values of a column in a table, ordered by term, with no separator
#}

{% macro stringify_terms(table, column) %}
                    string_agg(
                {{ table }}.{{ column }}::varchar, '' order by {{ table }}.term
            ) as {{ column }}_by_terms
{% endmacro %}