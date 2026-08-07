#!/usr/bin/env python3
"""
CAEP ELL Student Journey - local aggregate extraction
=====================================================

WHAT THIS IS
    Reads the student-level flat file on a machine authorized under the
    Chancellor's Office data-sharing MOU and writes a folder of aggregate
    tables. Only the aggregate folder is ever shared outside that machine.
    No student-level record, identifier, date, or college name leaves here.

WHAT IT GUARANTEES
    1. Output is counts and percentages only. Never a row per student.
    2. Any cell built on fewer than MIN_CELL students is suppressed and
       replaced with the string "suppressed".
    3. Colleges appear only as the three structural groups already used in
       the study. No college name, code, or district appears in any output.
    4. No dates. Terms appear as position in a student's own sequence or as
       entry cohort year, never as a calendar date.
    5. A manifest records what was written, so the contents are auditable.

KNOWN PIPELINE ITEMS THIS SCRIPT WORKS AROUND
    F2  Never reads lowest_cb21_level_adjusted_a_f_only_collapsed_by_terms.
        That variant folds levels 7 and 8 below transfer into level 6.
        Uses the "all" and "all_credit_types" variants instead.
    F3  Derives credit status from the per-term ESL sequences rather than
        from always_noncredit_esl / always_credit_esl / both_credit_noncredit_esl,
        which disagree with the sequences for roughly 850 students.
    F6  Cannot produce anything calendar-based. Sequence position is the
        order of a student's enrolled terms, not elapsed time.

USAGE
    python3 extract_aggregates.py --input eeaao_64.csv --outdir aggregates

REVIEW NOTES FOR RENEE
    Please check: the credit-status derivation (derive_groups), the pathway
    classifier (classify) and its priority order, and whether MIN_CELL of 11
    is the right threshold for this agreement.
"""

import argparse, json, os, sys, hashlib
from datetime import datetime
import pandas as pd
import numpy as np

MIN_CELL = 11          # cells built on fewer students than this are suppressed
ENTRY_COHORTS = ['2017-2018', '2018-2019', '2019-2020', '2020-2021', '2021-2022']
CENSORED_COHORT = '2022-2023'

SEQ_COLS = [
    'any_esl_enrollment_by_terms',
    'any_noncredit_esl_enrollment_by_terms',
    'any_credit_esl_enrollment_by_terms',
    'lowest_cb21_level_adjusted_all_by_terms',
    'lowest_cb21_level_adjusted_all_credit_types_by_terms',
    'any_493084_course_enrollment_by_terms',
    'any_493085_course_enrollment_by_terms',
    'any_493086_course_enrollment_by_terms',
    'any_493087_course_enrollment_by_terms',
]

# CB21 letter -> levels below transfer. A = 1 below ... H = 8 below.
LEVEL_RANK = {c: i + 1 for i, c in enumerate('ABCDEFGH')}
LEVEL_LABEL = {i: f'{i} below transfer' for i in range(1, 9)}

STRUCTURE_LABEL = {
    'CONFIRMED CC - 6 LEVELS': 'six levels',
    'CONFIRMED CC - A/B':      'top two combined',
    'CONFIRMED CC - E/F':      'two beginning combined',
}

CITIZENSHIP = {'1': 'US citizen', '2': 'Permanent resident', '3': 'Temporary resident',
               '4': 'Refugee or asylee', '5': 'Student visa', '6': 'Other status',
               'X': 'Unknown'}
GOAL = {'A': 'Degree and transfer', 'B': 'Transfer without degree',
        'C': 'Degree without transfer', 'E': 'Vocational certificate',
        'F': 'Discover career interests', 'G': 'Prepare for a new career',
        'H': 'Advance in current job', 'J': 'Educational development',
        'K': 'Improve basic skills in English', 'L': 'High school credits or GED',
        'M': 'Undecided', 'N': 'Move from noncredit to credit', 'X': 'Not reported'}

RACE_FLAGS = [('latin_american', 'Latin American'), ('aapi', 'AAPI'),
              ('white', 'White'), ('black', 'Black'),
              ('indigenous_american', 'Indigenous American'),
              ('no_data', 'No race data recorded')]

MANIFEST = []


# ----------------------------------------------------------------------
# safety
# ----------------------------------------------------------------------
def suppress(df, count_cols, min_cell=MIN_CELL):
    """Blank out any row whose count column falls below the threshold.

    Numeric columns are cast to object first so the sentinel can be written
    without a dtype error. Rows with a zero count are left alone: a zero is
    not disclosive and is often a finding in itself.
    """
    if not count_cols:
        return df.copy()
    out = df.copy()
    mask = pd.Series(False, index=out.index)
    for c in count_cols:
        v = pd.to_numeric(out[c], errors='coerce').fillna(0)
        mask |= (v > 0) & (v < min_cell)
    if not mask.any():
        return out
    for c in out.columns:
        if c in count_cols or out[c].dtype.kind in 'if':
            out[c] = out[c].astype(object)
            out.loc[mask, c] = 'suppressed'
    return out


BANNED_SUBSTRINGS = ['uuid', 'sb00', 'ssn', 'name', 'birth', 'address',
                     'date', 'college_id', 'district', 'gi01']


def write(df, outdir, filename, count_cols, note=''):
    """Suppress small cells, sanity-check for identifiers, then write."""
    df = suppress(df, count_cols)
    for col in df.columns:
        low = str(col).lower()
        for bad in BANNED_SUBSTRINGS:
            if bad in low:
                sys.exit(f'ABORT: column "{col}" in {filename} looks like an identifier.')
    path = os.path.join(outdir, filename)
    df.to_csv(path, index=False)
    MANIFEST.append({'file': filename, 'rows': int(len(df)),
                     'columns': list(map(str, df.columns)), 'note': note})
    print(f'  wrote {filename:52s} {len(df):>4} rows')


# ----------------------------------------------------------------------
# derivation
# ----------------------------------------------------------------------
def derive_groups(df):
    """Credit status from the per-term sequences, not the summary flags (F3)."""
    nc = df['any_noncredit_esl_enrollment_by_terms'].str.contains('1', na=False)
    cr = df['any_credit_esl_enrollment_by_terms'].str.contains('1', na=False)
    g = pd.Series('mixed', index=df.index)
    g[nc & ~cr] = 'noncredit only'
    g[~nc & cr] = 'credit only'
    g[~nc & ~cr] = 'no ESL recorded'
    return g


def sequence_features(row):
    esl = row['any_esl_enrollment_by_terms']
    lev = row['level_seq']
    idx = [i for i, ch in enumerate(esl) if ch == '1']
    n = len(idx)
    levels = [LEVEL_RANK.get(lev[i]) if i < len(lev) else None for i in idx]
    graded = [x for x in levels if x]
    gaps = 0
    if n > 1:
        run = 0
        for i in range(idx[0], idx[-1] + 1):
            if esl[i] == '0':
                run += 1
            else:
                if run:
                    gaps += 1
                run = 0
    slipped = False
    if graded:
        best = graded[0]
        for x in graded[1:]:
            if x > best:
                slipped = True
            best = min(best, x)
    return pd.Series({
        'esl_terms': n,
        'enrolled_terms': len(esl),
        'graded_terms': len(graded),
        'entry_level': levels[0] if levels else None,
        'exit_level': graded[-1] if graded else None,
        'best_level': min(graded) if graded else None,
        'net_levels_gained': (graded[0] - graded[-1]) if graded else 0,
        'ever_slipped_back': slipped,
        'gap_terms': gaps,
        'esl_first_term': idx[0] == 0 if idx else False,
        'nothing_after_last_esl': idx[-1] == len(esl) - 1 if idx else False,
        'levels_in_first_term': None,
    })


def classify(r):
    """Pathway typology. Priority order matters; a student is counted once."""
    if r['esl_terms'] == 1:
        return '1 One term, then gone'
    if r['graded_terms'] == 0:
        return 'Not classified'
    if r['best_level'] == 1:
        return '5 Reaches the top level'
    if r['gap_terms'] > 0:
        return '4 Moves up and down the levels'
    if r['net_levels_gained'] > 0 and not r['ever_slipped_back']:
        return '3 Moves up steadily'
    if r['net_levels_gained'] > 0 and r['ever_slipped_back']:
        return '4 Moves up and down the levels'
    if r['net_levels_gained'] == 0:
        return '2 Returns, finishes at the level they started'
    return '4 Moves up and down the levels'


def pct(part, whole):
    return round(part / whole * 100, 1) if whole else None


# ----------------------------------------------------------------------
# tables
# ----------------------------------------------------------------------
def crosstab_table(d, by, label, outdir, prefix):
    """Pathway distribution across one grouping variable."""
    rows = []
    for val, sub in d.groupby(by, dropna=False, observed=True):
        if pd.isna(val):
            continue
        tot = len(sub)
        for path, cnt in sub['pathway'].value_counts().items():
            rows.append({label: val, 'pathway': path, 'students': int(cnt),
                         'group_total': int(tot), 'pct_of_group': pct(cnt, tot)})
    if rows:
        write(pd.DataFrame(rows), outdir, f'{prefix}.csv', ['students'],
              f'pathway by {label}')


def run(args):
    outdir = args.outdir
    os.makedirs(outdir, exist_ok=True)

    print('reading flat file ...')
    dtypes = {c: str for c in SEQ_COLS}
    df = pd.read_csv(args.input, low_memory=False, dtype=dtypes)
    src_rows = len(df)

    for c in SEQ_COLS:
        if c not in df.columns:
            sys.exit(f'ABORT: expected column {c} not found. '
                     'Has the flat file changed shape?')

    df['group'] = derive_groups(df)
    df['level_seq'] = np.where(df['group'].eq('credit only'),
                               df['lowest_cb21_level_adjusted_all_credit_types_by_terms'],
                               df['lowest_cb21_level_adjusted_all_by_terms'])

    print('deriving sequence features ...')
    feats = df.apply(sequence_features, axis=1)
    d = pd.concat([df.reset_index(drop=True), feats.reset_index(drop=True)], axis=1)
    d['pathway'] = d.apply(classify, axis=1)

    d['age'] = d['age_at_first_term'].where(
        (d['age_at_first_term'] >= 14) & (d['age_at_first_term'] <= 99))
    d['age_band'] = pd.cut(d['age'], [13, 24, 44, 54, 99],
                           labels=['18 to 24', '25 to 44', '45 to 54', '55 and over'])
    d['gender_label'] = d['gender'].map({'F': 'Female', 'M': 'Male'}).fillna('Unreported')
    d['structure'] = d['first_college_group'].map(STRUCTURE_LABEL).fillna('other')
    d['citizenship'] = d['citizenship_earliest'].map(CITIZENSHIP).fillna('Unknown')
    d['goal'] = d['sb14_student_ed_goal'].map(GOAL).fillna('Not reported')
    d['entry_level_label'] = d['entry_level'].map(LEVEL_LABEL)
    d['cohort'] = d['first_academic_year']

    elig = d[d['cohort'].isin(ENTRY_COHORTS)]

    # ---------------- 00 provenance ----------------
    write(pd.DataFrame([{
        'source_rows': src_rows,
        'students_in_eligible_cohorts': int(len(elig)),
        'eligible_cohorts': ', '.join(ENTRY_COHORTS),
        'censored_cohort_reported_separately': CENSORED_COHORT,
        'min_cell_suppression': MIN_CELL,
        'level_variant_used': 'all / all_credit_types (NOT the collapsed variant)',
        'credit_status_source': 'derived from per-term ESL sequences',
        'generated': datetime.now().strftime('%Y-%m-%d'),
    }]), outdir, '00_provenance.csv', [], 'run parameters')

    # ---------------- 01 composition ----------------
    comp = (d.groupby(['group', 'cohort'], observed=True).size()
              .reset_index(name='students'))
    write(comp, outdir, '01_composition_by_group_and_cohort.csv', ['students'],
          'students by credit status and entry cohort')

    # ---------------- 02 pathway totals ----------------
    for grp in ['noncredit only', 'credit only']:
        sub = elig[elig['group'] == grp]
        t = sub['pathway'].value_counts().reset_index()
        t.columns = ['pathway', 'students']
        t['group_total'] = len(sub)
        t['pct_of_group'] = t['students'].apply(lambda x: pct(x, len(sub)))
        tag = grp.split()[0]
        write(t, outdir, f'02_pathway_totals_{tag}.csv', ['students'],
              f'pathway totals, {grp}')

    # ---------------- 03-08 pathway by margin ----------------
    margins = [('entry_level_label', 'entry_level', '03_pathway_by_entry_level'),
               ('cohort', 'cohort', '04_pathway_by_cohort'),
               ('structure', 'structure', '05_pathway_by_college_structure'),
               ('age_band', 'age_band', '06_pathway_by_age'),
               ('gender_label', 'gender', '07_pathway_by_gender'),
               ('goal', 'goal', '08_pathway_by_goal')]
    for grp in ['noncredit only', 'credit only']:
        sub = elig[elig['group'] == grp]
        tag = grp.split()[0]
        for by, label, prefix in margins:
            crosstab_table(sub, by, label, outdir, f'{prefix}_{tag}')

    # ---------------- 09 pathway by race flag ----------------
    rows = []
    for grp in ['noncredit only', 'credit only']:
        sub = elig[elig['group'] == grp]
        for col, label in RACE_FLAGS:
            s = sub[sub[col] == True]
            if len(s) == 0:
                continue
            for path, cnt in s['pathway'].value_counts().items():
                rows.append({'group': grp, 'race_flag': label, 'pathway': path,
                             'students': int(cnt), 'group_total': int(len(s)),
                             'pct_of_group': pct(cnt, len(s))})
    write(pd.DataFrame(rows), outdir, '09_pathway_by_race_flag.csv', ['students'],
          'race flags are not mutually exclusive')

    # ---------------- 10 term counts within pathway ----------------
    rows = []
    for grp in ['noncredit only', 'credit only']:
        sub = elig[elig['group'] == grp]
        for path, s in sub.groupby('pathway', observed=True):
            vc = s['esl_terms'].clip(upper=10).value_counts().sort_index()
            for terms, cnt in vc.items():
                rows.append({'group': grp, 'pathway': path,
                             'esl_terms': f'{int(terms)}+' if terms == 10 else int(terms),
                             'students': int(cnt), 'pathway_total': int(len(s)),
                             'median_esl_terms': float(s['esl_terms'].median()),
                             'mean_esl_terms': round(float(s['esl_terms'].mean()), 2)})
    write(pd.DataFrame(rows), outdir, '10_terms_within_pathway.csv', ['students'],
          'ESL term counts, capped at 10 or more')

    # ---------------- 11 entry level distribution ----------------
    rows = []
    for grp in ['noncredit only', 'credit only']:
        sub = elig[elig['group'] == grp]
        for lvl, s in sub.groupby('entry_level', observed=True):
            rows.append({'group': grp, 'levels_below_transfer': int(lvl),
                         'students': int(len(s)), 'group_total': int(len(sub)),
                         'pct_of_group': pct(len(s), len(sub))})
        y = sub[sub['level_seq'].str[0] == '1'] if 'level_seq' in sub else sub.iloc[0:0]
        rows.append({'group': grp, 'levels_below_transfer': 'at or above transfer',
                     'students': int(len(y)), 'group_total': int(len(sub)),
                     'pct_of_group': pct(len(y), len(sub))})
    write(pd.DataFrame(rows), outdir, '11_entry_level_distribution.csv', ['students'],
          'level at first ESL term')

    # ---------------- 12 advancement, six-level colleges only ----------------
    six = elig[(elig['group'] == 'noncredit only') &
               (elig['first_college_group'] == 'CONFIRMED CC - 6 LEVELS')]
    rows = []
    for lvl in range(1, 9):
        at = returned = next_lvl = any_higher = 0
        for seq in six['level_seq']:
            g = [LEVEL_RANK[ch] for ch in seq if ch in LEVEL_RANK]
            if lvl not in g:
                continue
            at += 1
            pos = g.index(lvl)
            later = g[pos + 1:]
            if not later:
                continue
            returned += 1
            if (lvl - 1) in later:
                next_lvl += 1
            if any(x < lvl for x in later):
                any_higher += 1
        if at:
            rows.append({'levels_below_transfer': lvl, 'students_at_level': at,
                         'returned_for_later_esl_term': returned,
                         'pct_returned': pct(returned, at),
                         'reached_next_level': next_lvl,
                         'pct_of_returners_next_level': pct(next_lvl, returned),
                         'reached_any_higher_level': any_higher,
                         'pct_of_returners_any_higher': pct(any_higher, returned)})
    write(pd.DataFrame(rows), outdir, '12_advancement_by_level_six_level_colleges.csv',
          ['students_at_level', 'returned_for_later_esl_term'],
          'a student is counted at every level they appear at; rows are not exclusive')

    # ---------------- 13 arrival and what followed ----------------
    rows = []
    for grp in ['noncredit only', 'credit only']:
        sub = elig[elig['group'] == grp]
        for path, s in sub.groupby('pathway', observed=True):
            rows.append({'group': grp, 'pathway': path, 'students': int(len(s)),
                         'esl_was_first_enrollment': int(s['esl_first_term'].sum()),
                         'nothing_after_last_esl_term': int(s['nothing_after_last_esl'].sum()),
                         'any_non_esl_enrolled_term': int((s['enrolled_terms'] > s['esl_terms']).sum()),
                         'ever_slipped_back_a_level': int(s['ever_slipped_back'].sum())})
    write(pd.DataFrame(rows), outdir, '13_arrival_and_what_followed.csv',
          ['students'], 'counts within each pathway')

    # ---------------- 14 awards by TOP code family ----------------
    if 'earliest_degree_topcode' in d.columns:
        ESL_TOP = {493084, 493085, 493086, 493087, 493090}
        VESL = {493100}
        OTHER_BS = {493009, 493010, 493011, 493012, 493013, 493014,
                    493030, 493031, 493032, 493033, 493060, 493062, 493072}
        LIB = {490100, 490110, 490200, 490300, 490310, 490330, 499900}

        def family(t):
            if pd.isna(t):
                return None
            t = int(t)
            if t in ESL_TOP:  return 'ESL basic skills'
            if t in VESL:     return 'Vocational ESL'
            if t in OTHER_BS: return 'Other basic skills'
            if t in LIB:      return 'Liberal arts or transfer studies'
            return 'Career-technical or academic discipline'

        d2 = elig.copy()
        d2['award_family'] = d2['earliest_degree_topcode'].map(family)
        rows = []
        for grp in ['noncredit only', 'credit only']:
            sub = d2[d2['group'] == grp]
            for path, s in sub.groupby('pathway', observed=True):
                for fam, cnt in s['award_family'].value_counts().items():
                    rows.append({'group': grp, 'pathway': path, 'award_family': fam,
                                 'students': int(cnt), 'pathway_total': int(len(s))})
        write(pd.DataFrame(rows), outdir, '14_awards_by_top_code_family.csv',
              ['students'], 'first award only; for RQ3')

    # ---------------- manifest ----------------
    h = hashlib.sha256(open(args.input, 'rb').read(1 << 20)).hexdigest()[:16]
    with open(os.path.join(outdir, 'MANIFEST.json'), 'w') as f:
        json.dump({'generated': datetime.now().isoformat(timespec='seconds'),
                   'input_file': os.path.basename(args.input),
                   'input_first_1mb_sha256': h,
                   'source_rows': src_rows,
                   'min_cell_suppression': MIN_CELL,
                   'files': MANIFEST}, f, indent=2)
    print(f'\ndone. {len(MANIFEST)} files in {outdir}/')
    print('Review the folder before sharing it. It should contain no student-level rows.')


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--input', required=True, help='path to the student-level flat file')
    ap.add_argument('--outdir', default='aggregates')
    run(ap.parse_args())
