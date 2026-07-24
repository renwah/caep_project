from __future__ import annotations

import argparse
from pathlib import Path

import pandas as pd
from dash import Dash, Input, Output, dcc, html
import plotly.graph_objects as go


CSV_PATH = Path("sample_cohort.csv")

COLOR_SEQUENCE = ["#1f4e79", "#f97316", "#15803d", "#dc2626", "#0f766e"]

VENN_COLS = ["first_term_noncredit", "first_term_credit"]
_VENN_LABELS = {
    "first_term_noncredit": "Noncredit First Term",
    "first_term_credit":    "Credit First Term",
}
_VENN_CIRCLE_STYLES = [
    ((-0.50,  0.30), "rgba(76,120,168,0.25)",  "#4C78A8"),
    (( 0.50,  0.30), "rgba(245,133,24,0.25)",  "#F58518"),
]
# (region key, x, y) — positions verified to sit inside exactly the right circles
# Circles: A(-0.5,0.3) B(0.5,0.3) C(0,-0.4), r=0.6
_REGION_POINTS = [
    ("A",   -0.75,  0.45),
    ("B",    0.75,  0.45),
    ("AB",   0.00,  0.60),
]


def _normalize_bool(series: pd.Series) -> pd.Series:
    return series.fillna("").astype(str).str.strip().str.upper().isin({"Y", "YES", "TRUE", "1"})


def load_data(csv_path: Path) -> pd.DataFrame:
    df = pd.read_csv(csv_path)
    df = df.loc[:, ~df.columns.duplicated()]
    bool_cols = [
        "first_term_noncredit", "first_term_credit", "incorrect_first_term",
        "ever_credit_esl", "always_noncredit_esl",
        "six_terms_attended", "twelve_terms_attended",
    ]
    for col in bool_cols:
        if col in df.columns:
            df[col] = _normalize_bool(df[col])
    return df


def blank_figure(title: str, message: str) -> go.Figure:
    fig = go.Figure()
    fig.update_layout(
        template="plotly_white",
        title=title,
        annotations=[{
            "text": message, "xref": "paper", "yref": "paper",
            "x": 0.5, "y": 0.5, "showarrow": False,
            "font": {"size": 14, "color": "#475569"},
        }],
        xaxis={"visible": False},
        yaxis={"visible": False},
        margin={"l": 24, "r": 24, "t": 50, "b": 24},
        height=420,
    )
    return fig


def venn3_figure(df: pd.DataFrame) -> go.Figure:
    """Interactive 2-set Venn diagram: invisible scatter markers carry the tooltips,
    visible text shows the count for each region."""
    available = [c for c in VENN_COLS if c in df.columns]
    if len(available) < 2:
        return blank_figure("Category Overlap", "Not enough category columns in data.")

    total = len(df)
    sets = [
        df[c] if c in df.columns else pd.Series(False, index=df.index)
        for c in VENN_COLS
    ]
    a, b = sets

    region_counts = {
        "A":   int((a & ~b).sum()),
        "B":   int((~a & b).sum()),
        "AB":  int((a & b).sum()),
    }

    la = _VENN_LABELS[VENN_COLS[0]]
    lb = _VENN_LABELS[VENN_COLS[1]]
    region_hover_labels = {
        "A":   f"<b>{la} only</b>",
        "B":   f"<b>{lb} only</b>",
        "AB":  f"<b>{la}</b> ∩ <b>{lb}</b>",

    }

    def pct(n: int) -> str:
        return f"{n / total * 100:.1f}%" if total > 0 else "0.0%"

    fig = go.Figure()

    r = 0.60
    for (cx, cy), fill, stroke in _VENN_CIRCLE_STYLES:
        fig.add_shape(
            type="circle", xref="x", yref="y",
            x0=cx - r, y0=cy - r, x1=cx + r, y1=cy + r,
            fillcolor=fill, line_color=stroke, line_width=2,
        )

    for key, px, py in _REGION_POINTS:
        n = region_counts[key]
        fig.add_trace(go.Scatter(
            x=[px], y=[py],
            mode="markers+text",
            marker=dict(size=55, color="rgba(0,0,0,0)", line=dict(width=0)),
            text=[f"<b>{n:,}</b>"],
            textposition="middle center",
            textfont=dict(size=11, color="#0f172a"),
            hovertemplate=(
                f"{region_hover_labels[key]}<br>"
                f"Count: <b>{n:,}</b><br>"
                f"Share of total: <b>{pct(n)}</b>"
                "<extra></extra>"
            ),
            showlegend=False,
        ))

    fig.update_layout(
        template="plotly_white",
        title="Enrollment Category Overlap",
        xaxis=dict(range=[-1.5, 1.5], visible=False, fixedrange=True),
        yaxis=dict(range=[-1.35, 1.25], visible=False, scaleanchor="x", fixedrange=True),
        annotations=[
            dict(x=-0.50, y=1.00, text=f"<b>{la}</b>", showarrow=False,
                 font=dict(size=11, color="#4C78A8"), align="center"),
            dict(x= 0.50, y=1.00, text=f"<b>{lb}</b>", showarrow=False,
                 font=dict(size=11, color="#F58518"), align="center"),
        ],
        margin=dict(l=10, r=10, t=50, b=10),
        height=460,
        showlegend=False,
        hovermode="closest",
    )
    return fig


def retention_bar(df: pd.DataFrame) -> go.Figure:
    """Grouped bar chart with one group per (academic_year, cohort) combination.

    Each group shows three bars: Total students, 6 Terms Attended, 12 Terms Attended.
    """
    year_col, cohort_col = "first_academic_year", "cohort"
    six_col, twelve_col = "six_terms_attended", "twelve_terms_attended"

    has_year = year_col in df.columns
    has_cohort = cohort_col in df.columns

    if not has_year and not has_cohort:
        return blank_figure("Term Retention", "No grouping columns found in data.")
    if six_col not in df.columns and twelve_col not in df.columns:
        return blank_figure("Term Retention", "No retention columns found in data.")

    df_work = df.copy()
    if has_year:
        df_work["_year"] = df_work[year_col].fillna("Unknown").astype(str)
    if has_cohort:
        df_work["_cohort"] = df_work[cohort_col].fillna("Unknown").astype(str)

    if has_year and has_cohort:
        df_work["_group"] = df_work["_year"] + " / " + df_work["_cohort"]
        sort_cols = ["_year", "_cohort"]
        xlabel = "Academic Year / Cohort"
    elif has_year:
        df_work["_group"] = df_work["_year"]
        sort_cols = ["_year"]
        xlabel = "Academic Year"
    else:
        df_work["_group"] = df_work["_cohort"]
        sort_cols = ["_cohort"]
        xlabel = "Cohort"

    group_order = (
        df_work[sort_cols + ["_group"]]
        .drop_duplicates()
        .sort_values(sort_cols)["_group"]
        .tolist()
    )

    fig = go.Figure()

    totals = [len(df_work[df_work["_group"] == g]) for g in group_order]
    fig.add_trace(go.Bar(
        name="Total Students",
        x=group_order, y=totals,
        marker_color=COLOR_SEQUENCE[2],
        text=totals, textposition="outside",
        hovertemplate="%{x}<br>Total: %{y:,}<extra></extra>",
    ))

    if six_col in df.columns:
        counts = [int(df_work[df_work["_group"] == g][six_col].sum()) for g in group_order]
        fig.add_trace(go.Bar(
            name="6 Terms Attended",
            x=group_order, y=counts,
            marker_color=COLOR_SEQUENCE[0],
            text=counts, textposition="outside",
            hovertemplate="%{x}<br>6 Terms: %{y:,}<extra></extra>",
        ))

    if twelve_col in df.columns:
        counts = [int(df_work[df_work["_group"] == g][twelve_col].sum()) for g in group_order]
        fig.add_trace(go.Bar(
            name="12 Terms Attended",
            x=group_order, y=counts,
            marker_color=COLOR_SEQUENCE[1],
            text=counts, textposition="outside",
            hovertemplate="%{x}<br>12 Terms: %{y:,}<extra></extra>",
        ))

    fig.update_layout(
        template="plotly_white",
        title="Term Retention by Academic Year & Cohort",
        xaxis_title=xlabel,
        yaxis_title="Students",
        barmode="group",
        margin={"l": 24, "r": 24, "t": 60, "b": 130},
        height=460,
        legend={"orientation": "h", "yanchor": "bottom", "y": 1.02, "xanchor": "right", "x": 1},
    )
    fig.update_xaxes(tickangle=-40, automargin=True)
    fig.update_yaxes(automargin=True, rangemode="tozero")
    return fig


_SANKEY_LEFT = [
    ("first_term_credit",    "Credit First Term",    "#F58518", "rgba(245,133,24,0.35)"),
    ("first_term_noncredit", "Noncredit First Term", "#4C78A8", "rgba(76,120,168,0.35)"),
]
_SANKEY_RIGHT = [
    ("ever_credit_esl",      "Ever Credit ESL",      "#54A24B"),
    ("always_noncredit_esl", "Always Noncredit ESL", "#dc2626"),
]


def sankey_figure(df: pd.DataFrame) -> go.Figure:
    node_labels = [lbl for _, lbl, *_ in _SANKEY_LEFT] + [lbl for _, lbl, _ in _SANKEY_RIGHT]
    node_colors = [col for _, _, col, _ in _SANKEY_LEFT] + [col for _, _, col in _SANKEY_RIGHT]

    sources, targets, values, link_colors = [], [], [], []
    for i, (left_col, _, _, link_color) in enumerate(_SANKEY_LEFT):
        if left_col not in df.columns:
            continue
        for j, (right_col, _, _) in enumerate(_SANKEY_RIGHT):
            if right_col not in df.columns:
                continue
            count = int((df[left_col] & df[right_col]).sum())
            if count == 0:
                continue
            sources.append(i)
            targets.append(len(_SANKEY_LEFT) + j)
            values.append(count)
            link_colors.append(link_color)

    if not sources:
        return blank_figure("Enrollment Pathways", "No overlapping records found between selected categories.")

    fig = go.Figure(go.Sankey(
        arrangement="snap",
        node=dict(
            pad=25,
            thickness=20,
            line=dict(color="white", width=0.5),
            label=node_labels,
            color=node_colors,
        ),
        link=dict(
            source=sources,
            target=targets,
            value=values,
            color=link_colors,
        ),
    ))
    fig.update_layout(
        template="plotly_white",
        title="Enrollment Pathways: First Term → ESL Trajectory",
        margin=dict(l=20, r=20, t=60, b=20),
        height=380,
        font=dict(size=12, color="#0f172a"),
    )
    return fig


def summary_cards(df: pd.DataFrame) -> list[html.Div]:
    def _sum(col: str) -> str:
        return f"{int(df[col].sum()):,}" if col in df.columns else "N/A"

    cards = [
        ("Total Students",    f"{len(df):,}"),
        ("6 Terms Attended",  _sum("six_terms_attended")),
        ("12 Terms Attended", _sum("twelve_terms_attended")),
        ("Started Credit",    _sum("first_term_credit")),
        ("Started Noncredit", _sum("first_term_noncredit")),
    ]
    return [
        html.Div(
            [html.Div(label, className="summary-card__label"),
             html.Div(value, className="summary-card__value")],
            className="summary-card",
        )
        for label, value in cards
    ]


def build_layout(df: pd.DataFrame) -> html.Div:
    def _options(col: str, all_label: str) -> list[dict]:
        if col not in df.columns:
            return [{"label": all_label, "value": ""}]
        return (
            [{"label": all_label, "value": ""}]
            + [{"label": str(v), "value": str(v)}
               for v in sorted(df[col].dropna().unique(), key=str)]
        )

    return html.Div(
        className="app-shell",
        children=[
            html.Div(
                className="hero",
                children=[
                    html.Div("Cohort Dashboard", className="hero__eyebrow"),
                    html.H1("CAEP Cohort Progression", className="hero__title"),
                    html.P(
                        "Explore enrollment category overlaps and term retention across cohorts and academic years.",
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
                            html.Label("Cohort", className="control-label"),
                            dcc.Dropdown(
                                id="cohort-filter",
                                options=_options("cohort", "All cohorts"),
                                value="",
                                clearable=False,
                                searchable=True,
                                className="control-input",
                            ),
                        ],
                    ),
                    html.Div(
                        className="control-group control-group--wide",
                        children=[
                            html.Label("Academic Year", className="control-label"),
                            dcc.Dropdown(
                                id="year-filter",
                                options=_options("first_academic_year", "All years"),
                                value="",
                                clearable=False,
                                searchable=True,
                                className="control-input",
                            ),
                        ],
                    ),
                ],
            ),
            html.Div(id="cohort-summary-cards", className="summary-grid"),
            html.Div(
                className="chart-grid",
                children=[
                    html.Div(
                        dcc.Graph(id="venn-graph", config={"displayModeBar": False}),
                        className="chart-card",
                    ),
                    html.Div(
                        dcc.Graph(id="retention-bar", config={"displayModeBar": False}),
                        className="chart-card",
                    ),
                ],
            ),
            html.Div(
                dcc.Graph(id="sankey-graph", config={"displayModeBar": False}),
                className="chart-card chart-card--full",
            ),
        ],
    )


def create_app(csv_path: Path) -> Dash:
    df_full = load_data(csv_path)

    app = Dash(__name__, title="Cohort Dashboard")
    app.layout = build_layout(df_full)

    @app.callback(
        Output("venn-graph", "figure"),
        Output("retention-bar", "figure"),
        Output("sankey-graph", "figure"),
        Output("cohort-summary-cards", "children"),
        Input("cohort-filter", "value"),
        Input("year-filter", "value"),
    )
    def update(cohort_val: str, year_val: str):
        df = df_full.copy()
        if cohort_val and "cohort" in df.columns:
            df = df[df["cohort"].astype(str) == cohort_val]
        if year_val and "first_academic_year" in df.columns:
            df = df[df["first_academic_year"].astype(str) == year_val]

        return venn3_figure(df), retention_bar(df), sankey_figure(df), summary_cards(df)

    return app


def main() -> None:
    parser = argparse.ArgumentParser(description="Launch the cohort progression dashboard.")
    parser.add_argument("--csv", type=Path, default=CSV_PATH, help="Path to cohort CSV file.")
    parser.add_argument("--debug", action="store_true")
    args = parser.parse_args()

    app = create_app(args.csv)
    app.run(debug=args.debug)


if __name__ == "__main__":
    main()
