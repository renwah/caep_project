from __future__ import annotations

from functools import lru_cache
from typing import Any, cast

from google.cloud import bigquery

import pandas as pd
from dash import Dash, Input, Output, dash_table, dcc, html
from plotly.colors import sample_colorscale
import plotly.graph_objects as go


client = bigquery.Client()

TABLE = "`endel-ell-study.caep_data_dashboard.sample_pop_demos`"

BINARY_FIELDS = {
    "latin_american",
    "aapi",
    "black",
    "indigenous_american",
    "white",
    "no_data",
    "english_or_math_enrollment",
    "special_admit_dual_enrollment",
    "prior_non_success",
}

COLOR_SEQUENCE = ["#1f4e79", "#f97316", "#15803d", "#dc2626", "#0f766e"]


def _year_conditions(years: list[str] | None) -> list[str]:
    if not years:
        return []
    quoted = ", ".join(f"'{y}'" for y in years)
    return [f"SUBSTR(CAST(sample_first_term AS STRING), 1, 2) IN ({quoted})"]


def _where(conditions: list[str]) -> str:
    return ("WHERE " + " AND ".join(conditions)) if conditions else ""


@lru_cache(maxsize=1)
def field_options_from_csv() -> list[dict]:
    query = f"SELECT * EXCEPT (uuid, zip_code, residence_aggregated) FROM {TABLE} LIMIT 0"
    schema = client.query(query).result().schema
    return [
        {"label": field.name.replace("_", " ").title(), "value": field.name}
        for field in schema
    ]


def starting_year_options() -> list[dict]:
    query = f"""
        SELECT DISTINCT SUBSTR(CAST(sample_first_term AS STRING), 1, 2) AS yr
        FROM {TABLE}
        WHERE sample_first_term IS NOT NULL
        ORDER BY yr
    """
    return [{"label": f"20{row.yr}", "value": row.yr} for row in client.query(query).result()]


def fetch_summary_counts(years: list[str] | None) -> dict:
    where = _where(_year_conditions(years))
    query = f"""
        SELECT
            COUNT(*) AS total_students,
            COUNTIF(earliest_efl_score IS NOT NULL AND latest_efl_score IS NOT NULL) AS with_efl,
            COUNTIF(main_campus_name IS NOT NULL) AS with_campus,
            APPROX_QUANTILES(SAFE_CAST(age_at_first_term AS FLOAT64), 2)[OFFSET(1)] AS median_age,
            COUNT(DISTINCT main_campus_name) AS unique_campuses
        FROM {TABLE}
        {where}
    """
    row = next(client.query(query).result())
    return {
        "total_students": row.total_students,
        "with_efl": row.with_efl,
        "with_campus": row.with_campus,
        "median_age": row.median_age,
        "unique_campuses": row.unique_campuses,
    }


def fetch_gender_counts(years: list[str] | None) -> pd.Series:
    where = _where(_year_conditions(years))
    query = f"""
        SELECT
            CASE UPPER(TRIM(COALESCE(CAST(gender AS STRING), '')))
                WHEN 'F' THEN 'Female'
                WHEN 'M' THEN 'Male'
                WHEN 'X' THEN 'Nonbinary/Unknown'
                ELSE 'Unknown'
            END AS gender_label,
            COUNT(*) AS cnt
        FROM {TABLE}
        {where}
        GROUP BY gender_label
    """
    data = {row.gender_label: row.cnt for row in client.query(query).result()}
    return pd.Series(data).reindex(["Female", "Male", "Nonbinary/Unknown", "Unknown"], fill_value=0)


def fetch_hispanic_counts(years: list[str] | None) -> pd.Series:
    where = _where(_year_conditions(years))
    query = f"""
        SELECT
            CASE UPPER(TRIM(COALESCE(CAST(hispanic_non_hispanic AS STRING), '')))
                WHEN 'Y' THEN 'Hispanic/Latino'
                WHEN 'N' THEN 'Not Hispanic/Latino'
                ELSE 'Unknown'
            END AS hispanic_label,
            COUNT(*) AS cnt
        FROM {TABLE}
        {where}
        GROUP BY hispanic_label
    """
    data = {row.hispanic_label: row.cnt for row in client.query(query).result()}
    return pd.Series(data).reindex(["Hispanic/Latino", "Not Hispanic/Latino", "Unknown"], fill_value=0)


def fetch_race_counts(years: list[str] | None) -> pd.Series:
    where = _where(_year_conditions(years))
    race_cols = {
        "latin_american": "Latin American",
        "aapi": "AAPI",
        "black": "Black",
        "indigenous_american": "Indigenous American",
        "white": "White",
        "no_data": "No Data",
    }
    selects = ",\n            ".join(
        f"COUNTIF(UPPER(TRIM(CAST({col} AS STRING))) = 'Y') AS {col}"
        for col in race_cols
    )
    query = f"SELECT {selects} FROM {TABLE} {where}"
    row = next(client.query(query).result())
    data = {label: getattr(row, col) for col, label in race_cols.items()}
    return pd.Series(data).sort_values(ascending=False)


def fetch_age_bucket_counts(years: list[str] | None) -> pd.Series:
    where = _where(_year_conditions(years))
    query = f"""
        SELECT
            CASE
                WHEN SAFE_CAST(age_at_first_term AS FLOAT64) <= 24 THEN 'Under 24'
                WHEN SAFE_CAST(age_at_first_term AS FLOAT64) <= 50 THEN '25 to 50'
                WHEN SAFE_CAST(age_at_first_term AS FLOAT64) > 50 THEN 'Over 50'
            END AS age_bucket,
            COUNT(*) AS cnt
        FROM {TABLE}
        {where}
        GROUP BY age_bucket
        HAVING age_bucket IS NOT NULL
    """
    data = {row.age_bucket: row.cnt for row in client.query(query).result()}
    return pd.Series(data).reindex(["Under 24", "25 to 50", "Over 50"], fill_value=0)


def fetch_top_campus_counts(years: list[str] | None) -> pd.Series:
    where = _where(_year_conditions(years))
    query = f"""
        SELECT
            COALESCE(NULLIF(TRIM(main_campus_name), ''), 'Unknown') AS campus,
            COUNT(*) AS cnt
        FROM {TABLE}
        {where}
        GROUP BY campus
        ORDER BY cnt DESC
        LIMIT 10
    """
    data = {row.campus: row.cnt for row in client.query(query).result()}
    return pd.Series(data)


def fetch_efl_heatmap_data(x_col: str, years: list[str] | None) -> pd.DataFrame:
    conditions = _year_conditions(years) + [f"{x_col} IS NOT NULL", "highest_level IS NOT NULL"]
    where = _where(conditions)
    query = f"""
        SELECT
            SAFE_CAST({x_col} AS INT64) AS x_val,
            SAFE_CAST(highest_level AS INT64) AS y_val,
            COUNT(*) AS cnt
        FROM {TABLE}
        {where}
        GROUP BY x_val, y_val
        HAVING x_val IS NOT NULL AND y_val IS NOT NULL
    """
    rows = list(client.query(query).result())
    if not rows:
        return pd.DataFrame()
    data = pd.DataFrame([(r.x_val, r.y_val, r.cnt) for r in rows], columns=["x_val", "y_val", "cnt"])
    levels = list(range(1, 9))
    return (
        data.pivot_table(index="y_val", columns="x_val", values="cnt", aggfunc="sum", fill_value=0)
        .reindex(index=levels, columns=levels, fill_value=0)
    )


def fetch_binary_counts(column: str, years: list[str] | None) -> pd.Series:
    where = _where(_year_conditions(years))
    query = f"""
        SELECT
            CASE
                WHEN UPPER(TRIM(CAST({column} AS STRING))) IN ('Y', 'YES', 'TRUE', '1') THEN 'Yes'
                WHEN UPPER(TRIM(CAST({column} AS STRING))) IN ('N', 'NO', 'FALSE', '0') THEN 'No'
                ELSE 'Unknown'
            END AS val,
            COUNT(*) AS cnt
        FROM {TABLE}
        {where}
        GROUP BY val
    """
    data = {row.val: row.cnt for row in client.query(query).result()}
    return pd.Series(data).reindex(["Yes", "No", "Unknown"], fill_value=0)


def fetch_field_counts(column: str, years: list[str] | None) -> pd.Series:
    where = _where(_year_conditions(years))
    query = f"""
        SELECT
            COALESCE(NULLIF(TRIM(CAST({column} AS STRING)), ''), 'Unknown') AS val,
            COUNT(*) AS cnt
        FROM {TABLE}
        {where}
        GROUP BY val
        ORDER BY cnt DESC
    """
    data = {row.val: row.cnt for row in client.query(query).result()}
    return pd.Series(data)


def fetch_categorical_counts(column: str, years: list[str] | None) -> pd.Series:
    if column == "gender":
        return fetch_gender_counts(years)
    if column == "hispanic_non_hispanic":
        return fetch_hispanic_counts(years)
    if column in BINARY_FIELDS:
        return fetch_binary_counts(column, years)
    return fetch_field_counts(column, years)


def fetch_crosstab(x_col: str, y_col: str, years: list[str] | None) -> pd.DataFrame:
    where = _where(_year_conditions(years))
    query = f"""
        SELECT
            COALESCE(NULLIF(TRIM(CAST({x_col} AS STRING)), ''), 'Unknown') AS x_val,
            COALESCE(NULLIF(TRIM(CAST({y_col} AS STRING)), ''), 'Unknown') AS y_val,
            COUNT(*) AS cnt
        FROM {TABLE}
        {where}
        GROUP BY x_val, y_val
    """
    rows = list(client.query(query).result())
    if not rows:
        return pd.DataFrame()
    data = pd.DataFrame([(r.x_val, r.y_val, r.cnt) for r in rows], columns=["x_val", "y_val", "cnt"])
    x_top = data.groupby("x_val")["cnt"].sum().nlargest(12).index
    y_top = data.groupby("y_val")["cnt"].sum().nlargest(12).index
    data["x_val"] = data["x_val"].where(data["x_val"].isin(x_top), other="Other")
    data["y_val"] = data["y_val"].where(data["y_val"].isin(y_top), other="Other")
    return data.pivot_table(index="x_val", columns="y_val", values="cnt", aggfunc="sum", fill_value=0)


def blank_figure(title: str, message: str) -> go.Figure:
    figure = go.Figure()
    figure.update_layout(
        template="plotly_white",
        title=title,
        annotations=[
            {
                "text": message,
                "xref": "paper",
                "yref": "paper",
                "x": 0.5,
                "y": 0.5,
                "showarrow": False,
                "font": {"size": 15, "color": "#475569"},
            }
        ],
        xaxis={"visible": False},
        yaxis={"visible": False},
        margin={"l": 24, "r": 24, "t": 60, "b": 24},
        height=360,
    )
    return figure


def bar_figure(counts: pd.Series, title: str, color: str, y_label: str = "Student Count") -> go.Figure:
    if counts.empty:
        return blank_figure(title, "No data available for this chart.")

    figure = go.Figure(
        data=[
            go.Bar(
                x=counts.index.astype(str),
                y=counts.values,
                marker_color=color,
                text=counts.values,
                textposition="outside",
                hovertemplate="%{x}<br>Count: %{y}<extra></extra>",
            )
        ]
    )
    figure.update_layout(
        template="plotly_white",
        title=title,
        xaxis_title="",
        yaxis_title=y_label,
        margin={"l": 24, "r": 24, "t": 60, "b": 90},
        height=360,
        showlegend=False,
    )
    figure.update_xaxes(tickangle=-25, automargin=True)
    figure.update_yaxes(automargin=True, rangemode="tozero")
    return figure


def heatmap_figure(table: pd.DataFrame, title: str) -> go.Figure:
    if table.empty:
        return blank_figure(title, "No data available for this chart.")

    figure = go.Figure(
        data=[
            go.Heatmap(
                z=table.values,
                x=table.columns.astype(str),
                y=table.index.astype(str),
                colorscale="Blues",
                hovertemplate="%{y} x %{x}<br>Count: %{z}<extra></extra>",
                colorbar={"title": "Count"},
                text=table.values,
                texttemplate="%{text:,}",
                textfont={"size": 11},
            )
        ]
    )
    figure.update_layout(
        template="plotly_white",
        title=title,
        xaxis_title="",
        yaxis_title="",
        margin={"l": 24, "r": 24, "t": 60, "b": 70},
        height=420,
    )
    return figure


def efl_heatmap(pivot_table: pd.DataFrame, x_col: str) -> go.Figure:
    if pivot_table.empty:
        return blank_figure("EFL Level Progression", "No level data available.")
    x_label = "First Level" if x_col == "first_level" else "Lowest Level"
    fig = heatmap_figure(pivot_table, f"{x_label} vs Highest Level")
    fig.update_layout(xaxis_title=x_label, yaxis_title="Highest Level")
    return fig


def efl_pivot_gradient_styles(table_df: pd.DataFrame) -> list[dict[str, Any]]:
    if table_df.empty:
        return []

    numeric_columns = [
        column for column in table_df.columns
        if pd.api.types.is_numeric_dtype(table_df[column])
    ]
    if not numeric_columns:
        return []

    values = pd.to_numeric(table_df[numeric_columns].to_numpy().ravel(), errors="coerce")
    valid_values = values[~pd.isna(values)]
    if len(valid_values) == 0:
        return []

    min_value = float(valid_values.min())
    max_value = float(valid_values.max())
    value_range = max_value - min_value

    styles: list[dict[str, Any]] = []
    for column in numeric_columns:
        unique_values = sorted(table_df[column].dropna().unique())
        for value in unique_values:
            normalized = 0.5 if value_range == 0 else (float(value) - min_value) / value_range
            background = sample_colorscale("Blues", [normalized])[0]
            styles.append(
                {
                    "if": {"column_id": column, "filter_query": f"{{{column}}} = {value}"},
                    "backgroundColor": background,
                    "color": "#0f172a",
                }
            )

    return styles


def efl_pivot_table_component(df: pd.DataFrame) -> dash_table.DataTable | html.Div:
    try:
        pivot_table = summarize_efl_scores_pivot(df)
    except ValueError as exc:
        return html.Div(str(exc), className="empty-state")

    pivot_display = pivot_table.reset_index()
    gradient_styles = cast(list[dict[str, Any]], efl_pivot_gradient_styles(pivot_display))
    pivot_records = cast(list[dict[str, Any]], pivot_display.to_dict("records"))

    return dash_table.DataTable(
        columns=[{"name": str(column), "id": str(column)} for column in pivot_display.columns],
        data=pivot_records,  # type: ignore[arg-type]
        style_table={"overflowX": "auto"},
        style_cell={
            "backgroundColor": "#ffffff",
            "color": "#0f172a",
            "fontFamily": "Aptos, Segoe UI, sans-serif",
            "fontSize": 13,
            "padding": "8px",
            "whiteSpace": "nowrap",
        },
        style_header={
            "backgroundColor": "#0f172a",
            "color": "#ffffff",
            "fontWeight": "600",
            "border": "none",
        },
        style_data={"border": "1px solid #e2e8f0"},
        style_data_conditional=gradient_styles,  # type: ignore[arg-type]
    )

def summarize_efl_scores_pivot(df: pd.DataFrame) -> pd.DataFrame:
	required_columns = ["earliest_efl_score", "latest_efl_score"]
	missing_columns = [column for column in required_columns if column not in df.columns]
	if missing_columns:
		raise ValueError(
			"Missing required EFL score columns: " + ", ".join(missing_columns)
		)

	earliest = (
		df["earliest_efl_score"]
		.fillna("Missing")
		.astype(str)
		.str.strip()
		.replace("", "Missing")
	)
	latest = (
		df["latest_efl_score"]
		.fillna("Missing")
		.astype(str)
		.str.strip()
		.replace("", "Missing")
	)

	pivot_table = pd.crosstab(
		index=earliest,
		columns=latest,
		margins=True,
		margins_name="Total",
	)
	pivot_table.index.name = "earliest_efl_score"
	pivot_table.columns.name = "latest_efl_score"
	return pivot_table

def summary_cards(counts: dict) -> list[html.Div]:
    median_age_raw = counts.get("median_age")
    median_age = f"{median_age_raw:.0f}" if median_age_raw is not None else "N/A"

    cards = [
        ("Students", f"{counts['total_students']:,}"),
        ("With EFL Scores", f"{counts['with_efl']:,}"),
        ("With Campus", f"{counts['with_campus']:,}"),
        ("Median Age", median_age),
        ("Campuses", f"{counts['unique_campuses']:,}"),
    ]
    return [
        html.Div(
            [
                html.Div(label, className="summary-card__label"),
                html.Div(value, className="summary-card__value"),
            ],
            className="summary-card",
        )
        for label, value in cards
    ]


def _fmt_label(v: str) -> str:
    try:
        f = float(v)
        return str(int(f)) if f == int(f) else v
    except (ValueError, TypeError):
        return v


def _sort_key(v: str):
    lower = v.lower()
    if lower in ("unknown", "missing"):
        return (2, 0.0, lower)
    try:
        return (0, float(v), "")
    except (ValueError, TypeError):
        return (1, 0.0, lower)


def build_layout() -> html.Div:
    field_options = field_options_from_csv()
    year_options = starting_year_options()

    return html.Div(
        className="app-shell",
        children=[
            html.Div(
                className="hero",
                children=[
                    html.Div("Demographics Dashboard", className="hero__eyebrow"),
                    html.H1("CAEP Sample Demographics", className="hero__title"),
                    html.P(
                        "Filter by student starting year, then explore demographic distributions in an interactive layout.",
                        className="hero__subtitle",
                    ),
                ],
            ),
            html.Div(
                className="panel",
                children=[
                    html.Div(
                        className="control-group control-group--wide",
                        children=[
                            html.Label("Starting Year", className="control-label"),
                            dcc.Dropdown(
                                id="year-dropdown",
                                options=year_options,
                                value=None,
                                multi=True,
                                placeholder="All years",
                                searchable=False,
                                className="control-input",
                            ),
                        ],
                    ),
                    html.Div(
                        className="control-group control-group--wide",
                        children=[
                            html.Label("Explore field", className="control-label"),
                            dcc.Dropdown(
                                id="x-field-dropdown",
                                options=field_options,
                                value="gender",
                                clearable=False,
                                searchable=True,
                                className="control-input",
                            ),
                        ],
                    ),
                    html.Div(
                        className="control-group control-group--wide",
                        children=[
                            html.Label("Compare with", className="control-label"),
                            dcc.Dropdown(
                                id="y-field-dropdown",
                                options=[{"label": "None", "value": ""}] + field_options,
                                value="main_campus_name",
                                clearable=False,
                                searchable=True,
                                className="control-input",
                            ),
                        ],
                    ),
                ],
            ),
            html.Div(id="summary-cards", className="summary-grid"),
            html.Div(
                className="chart-grid",
                children=[
                    html.Div(
                        className="chart-card",
                        style={"overflowX": "auto"},
                        children=[
                            html.Div(
                                dcc.RadioItems(
                                    id="x-sort-toggle",
                                    options=[
                                        {"label": "Sort by value", "value": "value"},
                                        {"label": "Sort by count", "value": "count"},
                                    ],
                                    value="value",
                                    inline=True,
                                    className="efl-toggle",
                                ),
                                className="efl-toggle-bar",
                            ),
                            dcc.Graph(id="x-field-graph", config={"displayModeBar": False}),
                        ],
                    ),
                    html.Div(
                        className="chart-card",
                        style={"overflowX": "auto"},
                        children=[
                            html.Div(
                                dcc.RadioItems(
                                    id="y-sort-toggle",
                                    options=[
                                        {"label": "Sort by value", "value": "value"},
                                        {"label": "Sort by count", "value": "count"},
                                    ],
                                    value="value",
                                    inline=True,
                                    className="efl-toggle",
                                ),
                                className="efl-toggle-bar",
                            ),
                            dcc.Graph(id="y-field-graph", config={"displayModeBar": False}),
                        ],
                    ),
                ],
            ),
            html.Div(
                className="panel panel--stacked",
                children=[
                    html.Div(
                        [
                            html.H2("Explore two dimensions", className="section-title"),
                            html.P(
                                "Pick one field for a distribution or pair two fields for a cross-tab heatmap.",
                                className="section-copy",
                            ),
                        ]
                    ),
                    html.Div(dcc.Graph(id="explore-graph", config={"displayModeBar": False}), className="chart-card chart-card--full"),
                ],
            ),
            html.Div(
                className="chart-grid",
                children=[
                    html.Div(dcc.Graph(id="gender-graph", config={"displayModeBar": False}), className="chart-card"),
                    html.Div(dcc.Graph(id="hispanic-graph", config={"displayModeBar": False}), className="chart-card"),
                    html.Div(dcc.Graph(id="race-graph", config={"displayModeBar": False}), className="chart-card"),
                    html.Div(dcc.Graph(id="age-graph", config={"displayModeBar": False}), className="chart-card"),
                    html.Div(dcc.Graph(id="campus-graph", config={"displayModeBar": False}), className="chart-card"),
                    html.Div(
                        className="chart-card chart-card--wide",
                        children=[
                            html.Div(
                                dcc.RadioItems(
                                    id="efl-x-toggle",
                                    options=[
                                        {"label": "First Level", "value": "first_level"},
                                        {"label": "Lowest Level", "value": "lowest_level"},
                                    ],
                                    value="first_level",
                                    inline=True,
                                    className="efl-toggle",
                                ),
                                className="efl-toggle-bar",
                            ),
                            dcc.Graph(id="efl-graph", config={"displayModeBar": False}),
                        ],
                    ),
                ],
            ),
        ],
    )


app = Dash(__name__, title="Demographics Dashboard")
app.layout = build_layout()
server = app.server


@app.callback(
    Output("gender-graph", "figure"),
    Output("hispanic-graph", "figure"),
    Output("race-graph", "figure"),
    Output("age-graph", "figure"),
    Output("campus-graph", "figure"),
    Output("efl-graph", "figure"),
    Output("explore-graph", "figure"),
    Output("x-field-graph", "figure"),
    Output("y-field-graph", "figure"),
    Output("summary-cards", "children"),
    Input("year-dropdown", "value"),
    Input("x-field-dropdown", "value"),
    Input("y-field-dropdown", "value"),
    Input("efl-x-toggle", "value"),
    Input("x-sort-toggle", "value"),
    Input("y-sort-toggle", "value"),
)
def update_dashboard(selected_years: list[str] | None, x_field: str, y_field: str, efl_x_col: str, x_sort: str, y_sort: str):
    gender_counts = fetch_gender_counts(selected_years)
    hispanic_counts = fetch_hispanic_counts(selected_years)
    race_counts = fetch_race_counts(selected_years)
    age_counts = fetch_age_bucket_counts(selected_years)
    campus_counts = fetch_top_campus_counts(selected_years)
    efl_table = fetch_efl_heatmap_data(efl_x_col, selected_years)
    counts = fetch_summary_counts(selected_years)

    if x_field and y_field:
        crosstab = fetch_crosstab(x_field, y_field, selected_years)
        explore_fig = heatmap_figure(crosstab, f"{x_field} by {y_field}")
    elif x_field:
        x_explore_counts = fetch_categorical_counts(x_field, selected_years)
        explore_fig = bar_figure(x_explore_counts.head(15), f"Distribution of {x_field}", COLOR_SEQUENCE[0])
    else:
        explore_fig = blank_figure("Explore the Data", "Choose a field to create an additional chart.")

    def _field_bar(col: str, color: str, sort_by: str) -> go.Figure:
        if not col:
            return blank_figure("", "No field selected.")
        title = col.replace("_", " ").title()
        field_counts = fetch_categorical_counts(col, selected_years)
        if sort_by == "count":
            field_counts = field_counts.sort_values(ascending=False)
        else:
            field_counts = field_counts.reindex(sorted(field_counts.index.astype(str), key=_sort_key))
        field_counts.index = [_fmt_label(v) for v in field_counts.index]
        n = len(field_counts)
        fig = bar_figure(field_counts, title, color)
        fig.update_layout(autosize=False, width=max(n * 55, 550))
        return fig

    x_fig = _field_bar(x_field, COLOR_SEQUENCE[0], x_sort)
    y_fig = _field_bar(y_field, COLOR_SEQUENCE[1], y_sort)

    return (
        bar_figure(gender_counts, "Gender Distribution", COLOR_SEQUENCE[0]),
        bar_figure(hispanic_counts, "Hispanic / Latino Ethnicity Distribution", COLOR_SEQUENCE[1]),
        bar_figure(race_counts, "Race Indicator Distribution", COLOR_SEQUENCE[2]),
        bar_figure(age_counts, "Age at First Term Buckets", COLOR_SEQUENCE[3]),
        bar_figure(campus_counts, "Top 10 Main Campuses", COLOR_SEQUENCE[4]),
        efl_heatmap(efl_table, efl_x_col),
        explore_fig,
        x_fig,
        y_fig,
        summary_cards(counts),
    )


if __name__ == "__main__":
    app.run(debug=False)
