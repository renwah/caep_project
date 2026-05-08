from __future__ import annotations

import argparse
from functools import lru_cache
from pathlib import Path
from typing import Any, cast

from google.cloud import bigquery

import pandas as pd
import io
from dash import Dash, Input, Output, dash_table, dcc, html
from plotly.colors import sample_colorscale
import plotly.graph_objects as go

from metrics_graphs import (
    _coerce_age,
    _map_gender,
    _map_hispanic,
    _normalize_yes_no,
    summarize_efl_scores_pivot,
)

client = bigquery.Client()

def fetch_data():
    query = "SELECT * EXCEPT (uuid, zip_code, residence_aggregated) FROM `endel-ell-study.caep_data_dashboard.sample_pop_demos`"
    return client.query(query).to_dataframe()

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


@lru_cache(maxsize=1)


def field_options_from_csv() -> list[dict]:
    df = fetch_data()
    return [
        {"label": col.replace("_", " ").title(), "value": col}
        for col in df.columns
        if col != "uuid"
    ]


def starting_year_options() -> list[dict]:
    df = fetch_data()
    if "sample_first_term" not in df.columns:
        return []
    years = (
        df["sample_first_term"]
        .dropna()
        .astype(str)
        .str[:2]
        .unique()
    )
    sorted_years = sorted(years)
    return [{"label": f"20{y}", "value": y} for y in sorted_years]


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


def normalize_binary(series: pd.Series) -> pd.Series:
    values = series.fillna("Unknown").astype(str).str.strip().str.upper()
    mapping = {
        "Y": "Yes",
        "YES": "Yes",
        "TRUE": "Yes",
        "1": "Yes",
        "N": "No",
        "NO": "No",
        "FALSE": "No",
        "0": "No",
    }
    return values.map(
        lambda value: mapping.get(
            str(value),
            "Unknown" if str(value) in {"", "NAN", "NONE"} else str(value).title(),
        )
    )


def summarize_column(series: pd.Series) -> pd.Series:
    values = series.fillna("Unknown").astype(str).str.strip().replace({"": "Unknown"})
    return values.value_counts().sort_values(ascending=False)


def race_indicator_counts(df: pd.DataFrame) -> pd.Series:
    labels = {
        "latin_american": "Latin American",
        "aapi": "AAPI",
        "black": "Black",
        "indigenous_american": "Indigenous American",
        "white": "White",
        "no_data": "No Data",
    }
    values = {
        label: (_normalize_yes_no(df[column]) == "Y").sum()
        for column, label in labels.items()
        if column in df.columns
    }
    return pd.Series(values).sort_values(ascending=False)


def age_bucket_counts(df: pd.DataFrame) -> pd.Series:
    if "age_at_first_term" not in df.columns:
        return pd.Series(dtype=int)

    age = _coerce_age(df["age_at_first_term"])
    buckets = pd.cut(
        age,
        bins=[float("-inf"), 24, 50, float("inf")],
        labels=["Under 24", "25 to 50", "Over 50"],
        right=True,
    )
    return buckets.value_counts().reindex(["Under 24", "25 to 50", "Over 50"], fill_value=0)


def top_campus_counts(df: pd.DataFrame) -> pd.Series:
    if "main_campus_name" not in df.columns:
        return pd.Series(dtype=int)

    values = (
        df["main_campus_name"]
        .fillna("Unknown")
        .astype(str)
        .str.strip()
        .replace({"": "Unknown"})
        .value_counts()
        .head(10)
    )
    return values


def categorical_counts(df: pd.DataFrame, column: str) -> pd.Series:
    if column not in df.columns:
        return pd.Series(dtype=int)

    if column == "gender":
        return _map_gender(df[column]).value_counts().reindex(
            ["Female", "Male", "Nonbinary/Unknown", "Unknown"], fill_value=0
        )

    if column == "hispanic_non_hispanic":
        return _map_hispanic(df[column]).value_counts().reindex(
            ["Hispanic/Latino", "Not Hispanic/Latino", "Unknown"], fill_value=0
        )

    if column in BINARY_FIELDS:
        return normalize_binary(df[column]).value_counts().reindex(["Yes", "No", "Unknown"], fill_value=0)

    return summarize_column(df[column])


def exploratory_figure(df: pd.DataFrame, x_column: str | None, y_column: str | None) -> go.Figure:
    if not x_column or x_column not in df.columns:
        return blank_figure("Explore the Data", "Choose a field to create an additional chart.")

    x_counts = categorical_counts(df, x_column)
    if y_column and y_column in df.columns:
        x_values = df[x_column].fillna("Unknown").astype(str).str.strip().replace({"": "Unknown"})
        y_values = df[y_column].fillna("Unknown").astype(str).str.strip().replace({"": "Unknown"})

        x_top = x_values.value_counts().head(12).index
        y_top = y_values.value_counts().head(12).index

        table = pd.crosstab(
            x_values.where(x_values.isin(x_top), other="Other"),
            y_values.where(y_values.isin(y_top), other="Other"),
        )
        return heatmap_figure(table, f"{x_column} by {y_column}")

    return bar_figure(x_counts.head(15), f"Distribution of {x_column}", COLOR_SEQUENCE[0])


def summary_cards(df: pd.DataFrame) -> list[html.Div]:
    total_students = len(df)
    with_efl = 0
    if {"earliest_efl_score", "latest_efl_score"}.issubset(df.columns):
        with_efl = df[["earliest_efl_score", "latest_efl_score"]].notna().all(axis=1).sum()

    with_campus = df["main_campus_name"].notna().sum() if "main_campus_name" in df.columns else 0
    median_age = "N/A"
    if "age_at_first_term" in df.columns:
        age = _coerce_age(df["age_at_first_term"])
        if age.notna().any():
            median_age = f"{age.median():.0f}"

    unique_campuses = (
        df["main_campus_name"].fillna("Unknown").astype(str).str.strip().replace({"": "Unknown"}).nunique()
        if "main_campus_name" in df.columns
        else 0
    )

    cards = [
        ("Students", f"{total_students:,}"),
        ("With EFL Scores", f"{with_efl:,}"),
        ("With Campus", f"{with_campus:,}"),
        ("Median Age", median_age),
        ("Campuses", f"{unique_campuses:,}"),
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


def efl_heatmap(df: pd.DataFrame, x_col: str = "first_level") -> go.Figure:
    for col in (x_col, "highest_level"):
        if col not in df.columns:
            return blank_figure("EFL Level Progression", f"Column '{col}' not found in data.")

    x_vals = pd.to_numeric(df[x_col], errors="coerce").dropna()
    y_vals = pd.to_numeric(df["highest_level"], errors="coerce").dropna()
    valid = df[[x_col, "highest_level"]].apply(pd.to_numeric, errors="coerce").dropna()

    if valid.empty:
        return blank_figure("EFL Level Progression", "No level data available.")

    levels = list(range(1, 9))
    table = pd.crosstab(
        valid["highest_level"].astype(int),
        valid[x_col].astype(int),
    ).reindex(index=levels, columns=levels, fill_value=0)

    x_label = "First Level" if x_col == "first_level" else "Lowest Level"
    title = f"{x_label} vs Highest Level"

    fig = heatmap_figure(table, title)
    fig.update_layout(
        xaxis_title=x_label,
        yaxis_title="Highest Level",
    )
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
    df = fetch_data()
    if selected_years:
        year_prefix = df["sample_first_term"].astype(str).str[:2]
        df = df[year_prefix.isin(selected_years)]

    gender_counts = categorical_counts(df, "gender")
    hispanic_counts = categorical_counts(df, "hispanic_non_hispanic")
    race_counts = race_indicator_counts(df)
    age_counts = age_bucket_counts(df)
    campus_counts = top_campus_counts(df)

    figures = (
        bar_figure(gender_counts, "Gender Distribution", COLOR_SEQUENCE[0]),
        bar_figure(hispanic_counts, "Hispanic / Latino Ethnicity Distribution", COLOR_SEQUENCE[1]),
        bar_figure(race_counts, "Race Indicator Distribution", COLOR_SEQUENCE[2]),
        bar_figure(age_counts, "Age at First Term Buckets", COLOR_SEQUENCE[3]),
        bar_figure(campus_counts, "Top 10 Main Campuses", COLOR_SEQUENCE[4]),
        efl_heatmap(df, efl_x_col),
        exploratory_figure(df, x_field, y_field or None),
    )

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

    def _field_bar(col: str, color: str, sort_by: str) -> go.Figure:
        if not col or col not in df.columns:
            return blank_figure("", "No field selected.")
        title = col.replace("_", " ").title()
        counts = categorical_counts(df, col)
        if sort_by == "count":
            counts = counts.sort_values(ascending=False)
        else:
            counts = counts.reindex(sorted(counts.index.astype(str), key=_sort_key))
        counts.index = [_fmt_label(v) for v in counts.index]
        n = len(counts)
        fig = bar_figure(counts, title, color)
        fig.update_layout(autosize=False, width=max(n * 55, 550))
        return fig

    x_fig = _field_bar(x_field, COLOR_SEQUENCE[0], x_sort)
    y_fig = _field_bar(y_field, COLOR_SEQUENCE[1], y_sort)

    return (*figures, x_fig, y_fig, summary_cards(df))


def main() -> None:
    parser = argparse.ArgumentParser(description="Launch the Plotly Dash demographics dashboard.")
    parser.add_argument("--host", default="127.0.0.1", help="Host to bind the dashboard to.")
    parser.add_argument("--port", type=int, default=8080, help="Port to bind the dashboard to.")
    parser.add_argument("--debug", action="store_true", help="Run the Dash development server in debug mode.")
    args = parser.parse_args()

    app.run(debug=args.debug, host=args.host, port=args.port)


if __name__ == "__main__":
    main()
