from __future__ import annotations

import argparse
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd


def _normalize_yes_no(series: pd.Series) -> pd.Series:
	values = series.fillna("Unknown").astype(str).str.strip().str.upper()
	return values.replace({"": "Unknown"})


def _map_gender(series: pd.Series) -> pd.Series:
	values = _normalize_yes_no(series)
	mapping = {
		"F": "Female",
		"M": "Male",
		"X": "Nonbinary/Unknown",
		"U": "Unknown",
		"": "Unknown",
	}
	return values.map(lambda value: mapping.get(value, "Unknown"))


def _map_hispanic(series: pd.Series) -> pd.Series:
	values = _normalize_yes_no(series)
	mapping = {"Y": "Hispanic/Latino", "N": "Not Hispanic/Latino", "X": "Unknown"}
	return values.map(lambda value: mapping.get(value, "Unknown"))


def _coerce_age(series: pd.Series) -> pd.Series:
	return pd.to_numeric(series, errors="coerce")


def _plot_count_series(counts: pd.Series, title: str, output_path: Path, color: str) -> None:
	fig, ax = plt.subplots(figsize=(10, 6))
	counts.plot(kind="bar", ax=ax, color=color)
	ax.set_title(title)
	ax.set_xlabel("")
	ax.set_ylabel("Student Count")
	ax.tick_params(axis="x", rotation=30)
	ax.bar_label(ax.containers[0], fmt="%.0f", padding=3)
	fig.tight_layout()
	fig.savefig(output_path, dpi=200)
	plt.close(fig)


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


def create_demographic_graphs(csv_path: Path, output_dir: Path) -> list[Path]:
	df = pd.read_csv(csv_path)
	df = df.loc[:, ~df.columns.duplicated()]

	output_dir.mkdir(parents=True, exist_ok=True)
	saved_files: list[Path] = []

	gender_counts = _map_gender(df["gender"]).value_counts().reindex(
		["Female", "Male", "Nonbinary/Unknown", "Unknown"], fill_value=0
	)
	gender_path = output_dir / "gender_distribution.png"
	_plot_count_series(gender_counts, "Gender Distribution", gender_path, "#4C78A8")
	saved_files.append(gender_path)

	hispanic_counts = _map_hispanic(df["hispanic_non_hispanic"]).value_counts().reindex(
		["Hispanic/Latino", "Not Hispanic/Latino", "Unknown"], fill_value=0
	)
	hispanic_path = output_dir / "hispanic_ethnicity_distribution.png"
	_plot_count_series(
		hispanic_counts,
		"Hispanic / Latino Ethnicity Distribution",
		hispanic_path,
		"#F58518",
	)
	saved_files.append(hispanic_path)

	race_columns = {
		"latin_american": "Latin American",
		"aapi": "AAPI",
		"black": "Black",
		"indigenous_american": "Indigenous American",
		"white": "White",
		"no_data": "No Data",
	}
	race_counts = pd.Series(
		{
			label: (_normalize_yes_no(df[column]) == "Y").sum()
			for column, label in race_columns.items()
			if column in df.columns
		}
	).sort_values(ascending=False)
	race_path = output_dir / "race_indicator_distribution.png"
	_plot_count_series(race_counts, "Race Indicator Distribution", race_path, "#54A24B")
	saved_files.append(race_path)

	age = _coerce_age(df["age_at_first_term"])
	age_buckets = pd.cut(
		age,
		bins=[float("-inf"), 24, 50, float("inf")],
		labels=["Under 24", "25 to 50", "Over 50"],
		right=True,
	)
	age_bucket_counts = age_buckets.value_counts().reindex(["Under 24", "25 to 50", "Over 50"], fill_value=0)
	age_path = output_dir / "age_at_first_term_buckets.png"
	_plot_count_series(age_bucket_counts, "Age at First Term Buckets", age_path, "#E45756")
	saved_files.append(age_path)

	campus_counts = (
		df["main_campus_name"].fillna("Unknown").astype(str).str.strip().replace("", "Unknown").value_counts().head(10)
	)
	campus_path = output_dir / "top10_main_campuses.png"
	_plot_count_series(campus_counts, "Top 10 Main Campuses", campus_path, "#72B7B2")
	saved_files.append(campus_path)

	efl_pivot = summarize_efl_scores_pivot(df)
	efl_pivot_path = output_dir / "efl_score_pivot_table.csv"
	efl_pivot.to_csv(efl_pivot_path)
	saved_files.append(efl_pivot_path)

	return saved_files


def main() -> None:
	parser = argparse.ArgumentParser(description="Generate demographic graphs from a demographics CSV.")
	parser.add_argument(
		"--csv",
		type=Path,
		default=Path("sample_pop_demos.csv"),
		help="Path to the demographics CSV file.",
	)
	parser.add_argument(
		"--output-dir",
		type=Path,
		default=Path("outputs/demographic_graphs"),
		help="Directory where graph image files will be written.",
	)
	args = parser.parse_args()

	saved_files = create_demographic_graphs(args.csv, args.output_dir)
	print("Saved graphs:")
	for path in saved_files:
		print(path)


if __name__ == "__main__":
	main()
