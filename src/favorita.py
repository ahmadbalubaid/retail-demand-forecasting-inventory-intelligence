"""
favorita.py  -  shared helpers for the "Retail Demand Forecasting & Inventory Intelligence" project
(Corporacion Favorita Store Sales dataset).

Both notebooks (01_EDA, 02_Feature_Engineering) import this module so that the cleaning rules,
masks, holiday calendar and feature logic are defined ONCE and are identical in EDA and in the
modelling table.

Conventions
-----------
* Everything is stored as dense 3-D numpy arrays  [time, store, family]  on a *complete daily calendar*
  (train + test period), so that "lag k" always means "k calendar days earlier" and missing days
  (25-Dec) are NaN - never 0.
* `A`  raw sales (NaN where no row exists: 25-Dec and the test period)
* `C`  "clean" sales = A with NaN wherever a zero is NOT a demand signal
        (store not yet open, store closed, family not recorded chain-wide)
* Nothing here looks at the future: every feature function receives an origin index `t` and only reads
  index <= t of history arrays (see `origin_features` and the truncation test in notebook 02).
"""
from __future__ import annotations

import re
import warnings
from pathlib import Path

import numpy as np
import pandas as pd

warnings.filterwarnings("ignore", category=RuntimeWarning)

# --------------------------------------------------------------------------------------
# Plot style (dataviz skill: one blue + one orange, quiet grid, insight titles)
# --------------------------------------------------------------------------------------
BLUE, ORANGE, AQUA, YELLOW, MAGENTA, GREEN, VIOLET, RED = (
    "#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300", "#4a3aa7", "#e34948")
INK, INK2, MUTED, GRID, SURFACE = "#0b0b0b", "#52514e", "#898781", "#e1e0d9", "#fcfcfb"
SEQ_BLUES = ["#cde2fb", "#9ec5f4", "#6da7ec", "#3987e5", "#256abf", "#184f95", "#0d366b"]


def set_style():
    import matplotlib as mpl
    mpl.rcParams.update({
        "figure.facecolor": SURFACE, "axes.facecolor": SURFACE, "savefig.facecolor": SURFACE,
        "axes.edgecolor": GRID, "axes.labelcolor": INK2, "axes.titlecolor": INK,
        "axes.titlesize": 12.5, "axes.titleweight": "bold", "axes.titlelocation": "left",
        "axes.spines.top": False, "axes.spines.right": False, "axes.spines.left": False,
        "axes.grid": True, "axes.grid.axis": "y", "grid.color": GRID, "grid.linewidth": 0.8,
        "axes.axisbelow": True, "xtick.color": MUTED, "ytick.color": MUTED,
        "xtick.bottom": False, "ytick.left": False, "text.color": INK,
        "font.family": "DejaVu Sans", "font.size": 10, "legend.frameon": False,
        "lines.linewidth": 2, "figure.dpi": 110, "figure.figsize": (9.5, 4.2),
    })


# --------------------------------------------------------------------------------------
# Loading
# --------------------------------------------------------------------------------------
def load_raw(data_dir="data"):
    d = Path(data_dir)
    parts = sorted(d.glob("train_part_*.csv"), key=lambda p: int(re.findall(r"\d+", p.stem)[0]))
    train = pd.concat([pd.read_csv(p, parse_dates=["date"]) for p in parts], ignore_index=True)
    out = dict(
        train=train,
        test=pd.read_csv(d / "test.csv", parse_dates=["date"]),
        sample=pd.read_csv(d / "sample_submission.csv"),
        stores=pd.read_csv(d / "stores.csv"),
        trans=pd.read_csv(d / "transactions.csv", parse_dates=["date"]),
        hol=pd.read_csv(d / "holidays_events.csv", parse_dates=["date"]),
        oil=pd.read_csv(d / "oil.csv", parse_dates=["date"]),
    )
    return out


# --------------------------------------------------------------------------------------
# Panel construction
# --------------------------------------------------------------------------------------
class Panel:
    """Dense [time, store, family] representation of the whole project dataset."""

    def __init__(self, raw: dict):
        tr, te, st = raw["train"], raw["test"], raw["stores"].sort_values("store_nbr").reset_index(drop=True)
        self.stores_df = st
        self.stores = st.store_nbr.tolist()
        self.fams = sorted(tr.family.unique())
        self.dates = pd.date_range(tr.date.min(), te.date.max())
        self.last_train = tr.date.max()
        self.n_train_days = int((self.last_train - self.dates[0]).days) + 1
        T, S, F = len(self.dates), len(self.stores), len(self.fams)
        self.shape = (T, S, F)
        sidx = {s: i for i, s in enumerate(self.stores)}
        fidx = {f: i for i, f in enumerate(self.fams)}
        self.sidx, self.fidx = sidx, fidx

        def ix(df):
            return ((df.date - self.dates[0]).dt.days.values, df.store_nbr.map(sidx).values,
                    df.family.map(fidx).values)

        self.A = np.full((T, S, F), np.nan)
        self.P = np.full((T, S, F), np.nan)
        ti, si, fi = ix(tr)
        self.A[ti, si, fi] = tr.sales.values
        self.P[ti, si, fi] = tr.onpromotion.values
        ti, si, fi = ix(te)
        self.P[ti, si, fi] = te.onpromotion.values

        # transactions [T,S] (NaN = no record)
        tx = raw["trans"]
        self.TX = np.full((T, S), np.nan)
        self.TX[(tx.date - self.dates[0]).dt.days.values, tx.store_nbr.map(sidx).values] = tx.transactions.values

        # oil: complete daily calendar, forward-filled (only PAST values are used to fill a gap)
        oil = raw["oil"].set_index("date").dcoilwtico.reindex(self.dates)
        self.oil_raw = oil.copy()
        self.oil = oil.ffill().bfill().values  # bfill only touches 2013-01-01 (first row is null)

        self.dec25 = np.zeros(T, bool)
        tr_days = np.arange(self.n_train_days)
        present = np.zeros(T, bool)
        present[(tr.date.drop_duplicates() - self.dates[0]).dt.days.values] = True
        self.dec25[tr_days] = ~present[tr_days]           # calendar days inside the train span with no rows
        self.build_masks()

    # ---------------------------------------------------------------- masks
    def build_masks(self, outage_min_run=7):
        T, S, F = self.shape
        Tt = self.n_train_days
        A = self.A
        tot = np.nansum(A, axis=2)                       # [T,S] store total
        tot[self.dec25] = np.nan
        self.store_total_raw = tot
        sold = np.nan_to_num(tot) > 0
        open_idx = np.array([np.argmax(sold[:Tt, i]) for i in range(S)])
        self.open_idx = open_idx
        pre_open = np.zeros((T, S), bool)
        for i in range(S):
            pre_open[:open_idx[i], i] = True
        jan1 = np.array([(d.month == 1 and d.day == 1) for d in self.dates]) & (np.arange(T) < Tt)
        closed = (tot == 0) & ~pre_open                   # zero on ALL 33 families after opening
        self.pre_open = pre_open
        self.jan1 = jan1
        self.closed_jan1 = closed & jan1[:, None]
        self.closed_ext = closed & ~jan1[:, None]         # extended / unplanned closures
        # chain-wide family outage: chain total exactly 0 for >= outage_min_run consecutive days
        fam_tot = np.nansum(A, axis=1)                    # [T,F]
        z = (fam_tot == 0)
        z[self.dec25] = False
        z[Tt:] = False
        out = np.zeros((T, F), bool)
        for j in range(F):
            x, t = z[:, j], 0
            while t < Tt:
                if x[t]:
                    k = t
                    while k < Tt and (x[k] or self.dec25[k]):
                        k += 1
                    if k - t >= outage_min_run:
                        out[t:k, j] = True
                    t = k
                else:
                    t += 1
        self.outage = out
        # ---- recording regimes -------------------------------------------------------------------------------
        # In some months (2013, Feb/Apr-Jun/Aug 2014, Jan-May 2015) >= 5 families vanish from the data at the same
        # time.  Families that are still present but change level between "off" and "on" months (BEVERAGES ~x0.5,
        # PRODUCE ~x0.002) are not comparable across regimes -> masked on the "off" days as well.
        self.off_regime = (out.sum(axis=1) >= 5)
        span = (np.arange(T) >= 365) & (np.arange(T) < 365 * 3)           # 2014-01-01 .. 2015-12-31
        on_, off_ = span & ~self.off_regime & ~self.dec25, span & self.off_regime & ~self.dec25
        med_on, med_off = np.median(fam_tot[on_], axis=0), np.median(fam_tot[off_], axis=0)      # medians: robust to the December spike
        ratio = np.where(med_on > 0, med_off / np.maximum(med_on, 1e-9), np.nan)
        self.regime_ratio = ratio
        self.regime_fams = np.where(ratio < 0.55)[0]
        regime = np.zeros((T, F), bool)
        regime[np.ix_(np.where(self.off_regime)[0], self.regime_fams)] = True
        self.regime = regime & ~out
        self.outage_all = out | self.regime
        # family launch = first day with chain sales > 0
        self.fam_launch = np.array([np.argmax(fam_tot[:Tt, j] > 0) for j in range(F)])
        # clean series
        C = A.copy()
        C[pre_open | closed] = np.nan
        C[np.broadcast_to(self.outage_all[:, None, :], C.shape)] = np.nan
        self.C = C
        self.stable_fams = np.where(~self.outage_all.any(axis=0))[0]
        Cs = C[:, :, self.stable_fams]
        self.tot_stable = np.where(np.isnan(Cs).all(axis=2), np.nan, np.nansum(Cs, axis=2))       # [T,S]
        self.tot_clean = np.where(np.isnan(C).all(axis=2), np.nan, np.nansum(C, axis=2))          # [T,S] (all families)
        self.fam_clean = np.where(np.isnan(C).all(axis=1), np.nan, np.nansum(C, axis=1))          # [T,F]

    # ---------------------------------------------------------------- helpers
    def date_idx(self, d):
        return int((pd.Timestamp(d) - self.dates[0]).days)

    def long_frame(self, arr, name):
        """[T,S,F] -> long DataFrame (date, store_nbr, family, value)"""
        T, S, F = arr.shape
        return pd.DataFrame({
            "date": np.repeat(self.dates.values, S * F),
            "store_nbr": np.tile(np.repeat(self.stores, F), T),
            "family": np.tile(self.fams, T * S),
            name: arr.reshape(-1)})


# --------------------------------------------------------------------------------------
# Holiday / event calendar per store
# --------------------------------------------------------------------------------------
EVENT_CODES = {"none": 0, "mothers_day": 1, "black_friday": 2, "cyber_monday": 3, "world_cup": 4, "earthquake": 5}
HOL_TYPE_CODES = {"none": 0, "Holiday": 1, "Transfer": 2, "Bridge": 3, "Additional": 4, "Work Day": 5}


def event_name(desc: str) -> str:
    d = desc.lower()
    if "dia de la madre" in d: return "mothers_day"
    if "black friday" in d: return "black_friday"
    if "cyber monday" in d: return "cyber_monday"
    if "mundial" in d: return "world_cup"
    if "terremoto" in d: return "earthquake"
    return "other_event"


def holiday_calendar(hol: pd.DataFrame, panel: Panel) -> dict:
    """
    Effective holiday calendar for each (date, store).
    Rules (documented in notebook 01):
      * Holiday with transferred==True is NOT celebrated on its nominal date; the matching 'Transfer' row is.
      * Bridge / Additional are extra non-working / shopping days, Work Day is a make-up working day.
      * Event rows (Mother's Day, Black Friday, World Cup, earthquake ...) are demand events, not days off.
      * Locale matching: National -> every store; Regional -> store.state == locale_name; Local -> store.city == locale_name.
    """
    T, S = len(panel.dates), len(panel.stores)
    st = panel.stores_df
    city_of = st.city.values
    state_of = st.state.values
    z = lambda: np.zeros((T, S), np.int8)
    out = {k: z() for k in ["hol_national", "hol_regional", "hol_local", "bridge", "additional", "work_day"]}
    out["hol_type"] = z()
    out["event"] = z()
    out["quake_day"] = np.full((T, S), np.nan)
    d0 = panel.dates[0]
    for r in hol.itertuples():
        t = (r.date - d0).days
        if t < 0 or t >= T:
            continue
        if r.locale == "National":
            m = np.ones(S, bool)
        elif r.locale == "Regional":
            m = state_of == r.locale_name
        else:
            m = city_of == r.locale_name
        typ = r.type
        if typ == "Event":
            ev = event_name(r.description)
            if ev in EVENT_CODES:
                out["event"][t, m] = EVENT_CODES[ev]
            if ev == "earthquake":
                mm = re.search(r"\+(\d+)", r.description)
                out["quake_day"][t, m] = int(mm.group(1)) if mm else 0
            continue
        if typ == "Holiday" and r.transferred:
            continue                                        # moved to its Transfer row
        if typ in ("Holiday", "Transfer"):
            key = {"National": "hol_national", "Regional": "hol_regional", "Local": "hol_local"}[r.locale]
            out[key][t, m] = 1
            out["hol_type"][t, m] = HOL_TYPE_CODES[typ]
        elif typ == "Bridge":
            out["bridge"][t, m] = 1
            out["hol_type"][t, m] = np.maximum(out["hol_type"][t, m], HOL_TYPE_CODES["Bridge"])
        elif typ == "Additional":
            out["additional"][t, m] = 1
            out["hol_type"][t, m] = np.maximum(out["hol_type"][t, m], HOL_TYPE_CODES["Additional"])
        elif typ == "Work Day":
            out["work_day"][t, m] = 1
            out["hol_type"][t, m] = np.maximum(out["hol_type"][t, m], HOL_TYPE_CODES["Work Day"])
    out["hol_any"] = ((out["hol_national"] + out["hol_regional"] + out["hol_local"]) > 0).astype(np.int8)
    # distance to previous / next holiday for that store (calendar days, capped)
    nxt = np.full((T, S), 30.0)
    prv = np.full((T, S), 30.0)
    h = out["hol_any"].astype(bool)
    for s in range(S):
        idx = np.where(h[:, s])[0]
        if len(idx) == 0:
            continue
        pos = np.searchsorted(idx, np.arange(T))
        nx = np.where(pos < len(idx), idx[np.minimum(pos, len(idx) - 1)] - np.arange(T), 30)
        pv_pos = np.searchsorted(idx, np.arange(T), side="right") - 1
        pv = np.where(pv_pos >= 0, np.arange(T) - idx[np.maximum(pv_pos, 0)], 30)
        nxt[:, s] = np.minimum(nx, 30)
        prv[:, s] = np.minimum(pv, 30)
    out["days_to_hol"] = nxt
    out["days_since_hol"] = prv
    return out


def calendar_frame(dates: pd.DatetimeIndex) -> pd.DataFrame:
    d = pd.DataFrame({"date": dates})
    d["year"] = d.date.dt.year
    d["month"] = d.date.dt.month
    d["week_of_year"] = d.date.dt.isocalendar().week.astype(int)
    d["day_of_month"] = d.date.dt.day
    d["dow"] = d.date.dt.dayofweek
    d["is_weekend"] = (d.dow >= 5).astype(int)
    dim = d.date.dt.days_in_month
    d["is_payday"] = ((d.day_of_month == 15) | (d.day_of_month == dim)).astype(int)   # public-sector pay days
    d["days_to_payday"] = np.where(d.day_of_month <= 15, 15 - d.day_of_month, dim - d.day_of_month)
    d["days_since_payday"] = np.where(d.day_of_month < 15, d.day_of_month, np.where(d.day_of_month == dim, 0, d.day_of_month - 15))
    return d


# --------------------------------------------------------------------------------------
# Dormant / inactive rule (as of origin t)
# --------------------------------------------------------------------------------------
DORMANT_WINDOW = 90
DORMANT_MIN_VALID = 45
SEASONAL_EXEMPT = ["SCHOOL AND OFFICE SUPPLIES"]      # back-to-school peak sits exactly in the test window


def dormant_flag(panel: Panel, t: int, window=DORMANT_WINDOW, min_valid=DORMANT_MIN_VALID):
    """[S,F] bool: zero VALID sales in the last `window` days (with >= min_valid valid days) as of origin t."""
    past = panel.C[max(0, t - window + 1): t + 1]
    nv = np.sum(~np.isnan(past), axis=0)
    s = np.nansum(past, axis=0)
    flag = (s == 0) & (nv >= min_valid)
    for f in SEASONAL_EXEMPT:
        flag[:, panel.fidx[f]] = False
    return flag


# --------------------------------------------------------------------------------------
# Feature engineering for one forecast origin
# --------------------------------------------------------------------------------------
HORIZON = 16


INT8_COLS = ["store_type", "store_cluster", "city_id", "state_id", "hol_national", "hol_regional", "hol_local", "hol_any",
             "bridge", "additional", "work_day", "hol_type", "event", "promo_flag", "pre_holiday", "post_holiday",
             "is_weekend", "is_payday", "rule_zero"]
INT16_COLS = ["horizon", "store_nbr", "family_id", "year", "month", "week_of_year", "day_of_month", "dow",
              "days_to_payday", "days_since_payday", "days_to_holiday", "days_since_holiday", "onpromotion"]


def finalize_dtypes(df: pd.DataFrame) -> pd.DataFrame:
    """Compact dtypes (flags -> int8, counters -> int16).  NaN in an integer column is only possible for rows that are
    never kept (25-Dec targets), so they are filled with 0 first."""
    for c in INT8_COLS:
        if c in df: df[c] = df[c].fillna(0).astype(np.int8)
    for c in INT16_COLS:
        if c in df: df[c] = df[c].fillna(0).astype(np.int16)
    return df


# validation design: forecast origins (all Tuesdays, like the real 2017-08-15 origin); each fold validates on the 16 days after
FOLD_ORIGINS = {"F1_seasonal_twin": "2016-08-16",     # same season one year earlier (back-to-school peak)
                "F2_holiday_heavy": "2017-04-04",     # window contains Good Friday
                "F3_mid_2017": "2017-05-30",
                "F4_recent": "2017-07-11",
                "F5_latest": "2017-07-25"}            # the last window whose 16 targets are fully observed


def split_fold(df: pd.DataFrame, val_origin, train_start="2015-07-01", embargo_days=HORIZON):
    """Boolean masks (train, valid) for one time-based fold.
    valid  = rows whose forecast origin is exactly `val_origin` (16 targets after it)
    train  = rows with origin >= train_start and origin <= val_origin - embargo  ->  their targets end BEFORE val_origin,
             so no validation label (and no information newer than the validation origin) is ever seen in training."""
    vo = pd.Timestamp(val_origin)
    tr = (df.origin_date >= pd.Timestamp(train_start)) & (df.origin_date <= vo - pd.Timedelta(days=embargo_days))
    va = (df.origin_date == vo)
    return tr.values, va.values


class Prefix:
    """Prefix sums of a NaN-aware array along axis 0 -> O(1) window mean / std / zero-rate."""

    def __init__(self, X):
        v = ~np.isnan(X)
        x0 = np.where(v, X, 0.0)
        pad = lambda a: np.concatenate([np.zeros((1,) + a.shape[1:]), np.cumsum(a, axis=0)])
        self.s, self.s2, self.n = pad(x0), pad(x0 ** 2), pad(v.astype(float))
        self.z = pad((v & (X == 0)).astype(float))

    def _w(self, arr, t, w):
        lo = max(0, t + 1 - w)
        return arr[t + 1] - arr[lo]

    def mean(self, t, w):
        n = self._w(self.n, t, w)
        return np.where(n > 0, self._w(self.s, t, w) / np.maximum(n, 1), np.nan)

    def std(self, t, w):
        n = self._w(self.n, t, w)
        m = self._w(self.s, t, w) / np.maximum(n, 1)
        var = self._w(self.s2, t, w) / np.maximum(n, 1) - m ** 2
        return np.where(n > 1, np.sqrt(np.maximum(var, 0)), np.nan)

    def zero_rate(self, t, w):
        n = self._w(self.n, t, w)
        return np.where(n > 0, self._w(self.z, t, w) / np.maximum(n, 1), np.nan)

    def count(self, t, w):
        return self._w(self.n, t, w)

    def mean_all(self, t):
        return self.mean(t, 10 ** 9)

    def zero_rate_all(self, t):
        return self.zero_rate(t, 10 ** 9)


class FeatureBuilder:
    """Pre-computes prefix sums once; `origin_features(t)` then reads ONLY index <= t of history arrays."""

    def __init__(self, panel: Panel, hol: dict, raw_stores: pd.DataFrame):
        self.p = panel
        T, S, F = panel.shape
        self.pf = Prefix(panel.C)
        self.pf_store = Prefix(panel.tot_stable)
        self.pf_fam = Prefix(panel.fam_clean)
        self.pf_tx = Prefix(panel.TX)
        self.pf_promo = Prefix(np.where(np.isnan(panel.C), np.nan, panel.P))  # promo on valid days only
        idx = np.arange(T)[:, None, None]
        pos = np.where(np.nan_to_num(panel.C, nan=0) > 0, idx, -1)
        self.last_pos = np.maximum.accumulate(pos, axis=0)          # last day (<= t) with sales > 0
        first = np.where(pos >= 0, idx, 10 ** 9).min(axis=0)         # first day with sales>0 (used only if <= t)
        self.first_pos = first
        self.hol = hol
        self.cal = calendar_frame(panel.dates)
        st = panel.stores_df
        self.type_code = st.type.map({k: i for i, k in enumerate(sorted(st.type.unique()))}).values
        self.cluster = st.cluster.values
        self.city_code = pd.factorize(st.city, sort=True)[0]
        self.state_code = pd.factorize(st.state, sort=True)[0]
        self.T, self.S, self.F = T, S, F

    # ------------------------------------------------------------------
    def history_features(self, t):
        """Everything that is known at the END of day t. Returns dict name -> [S,F] array."""
        p, C = self.p, self.p.C
        S, F = self.S, self.F
        f = {}
        for k, name in [(1, "lag_1d"), (7, "lag_7d"), (14, "lag_14d"), (28, "lag_28d")]:
            f[name] = C[t - k + 1]                                          # k days before the FIRST forecast day
        for w in (7, 14, 28, 56):
            f[f"roll_mean_{w}d"] = self.pf.mean(t, w)
        for w in (7, 14, 28, 91):
            f[f"roll_std_{w}d"] = self.pf.std(t, w)
        f["roll_median_28d"] = np.nanmedian(C[t - 27: t + 1], axis=0)          # robust to one-off spikes
        f["roll_zero_rate_28d"] = self.pf.zero_rate(t, 28)
        f["roll_zero_rate_91d"] = self.pf.zero_rate(t, 91)
        f["valid_days_28d"] = self.pf.count(t, 28)
        lp = self.last_pos[t]
        f["days_since_last_sale"] = np.where(lp >= 0, t - lp, np.nan)
        # growth / trend
        m7, m28, m91 = f["roll_mean_7d"], f["roll_mean_28d"], self.pf.mean(t, 91)
        prev28 = (self.pf.s[t - 27] - self.pf.s[max(0, t - 55)]) / np.maximum(self.pf.n[t - 27] - self.pf.n[max(0, t - 55)], 1)
        f["growth_7_vs_28"] = np.where(m28 > 0, m7 / m28, np.nan)
        f["growth_28_vs_prev28"] = np.where(prev28 > 0, m28 / prev28, np.nan)
        f["growth_28_vs_91"] = np.where(m91 > 0, m28 / m91, np.nan)
        # volatility
        f["cv_28d"] = np.where(m28 > 0, f["roll_std_28d"] / m28, np.nan)
        f["cv_91d"] = np.where(m91 > 0, f["roll_std_91d"] / m91, np.nan)
        # store x family history
        f["sf_mean_91d"] = m91
        f["sf_mean_all"] = self.pf.mean_all(t)
        f["sf_zero_rate_all"] = self.pf.zero_rate_all(t)
        fs = self.first_pos
        f["sf_age_days"] = np.where(fs <= t, t - fs, np.nan)
        # store-level (aggregated over families)
        sm7, sm28 = self.pf_store.mean(t, 7), self.pf_store.mean(t, 28)
        sm7, sm28, sm91 = sm7[:, None], sm28[:, None], self.pf_store.mean(t, 91)[:, None]
        one = np.ones((1, F))
        f["store_mean_7d"], f["store_mean_28d"] = sm7 * one, sm28 * one
        f["store_growth_7_vs_28"] = np.where(sm28 > 0, sm7 / sm28, np.nan) * one
        f["store_growth_28_vs_91"] = np.where(sm91 > 0, sm28 / sm91, np.nan) * one
        f["store_age_days"] = np.where(p.open_idx <= t, t - p.open_idx, np.nan)[:, None] * one
        # transactions (only up to t!)
        tx7, tx28 = self.pf_tx.mean(t, 7), self.pf_tx.mean(t, 28)
        f["store_tx_mean_7d"], f["store_tx_mean_28d"] = tx7[:, None] * one, tx28[:, None] * one
        f["store_tx_growth_7_vs_28"] = np.where(tx28 > 0, tx7 / tx28, np.nan)[:, None] * one
        f["store_sales_per_tx_28d"] = np.where(tx28 > 0, sm28[:, 0] / tx28, np.nan)[:, None] * one
        # family-level (chain)
        fm7, fm28 = self.pf_fam.mean(t, 7), self.pf_fam.mean(t, 28)
        fone = np.ones((S, 1))
        f["fam_mean_7d"], f["fam_mean_28d"] = fone * fm7[None, :], fone * fm28[None, :]
        f["fam_growth_7_vs_28"] = fone * np.where(fm28 > 0, fm7 / fm28, np.nan)[None, :]
        f["sf_share_of_family_28d"] = np.where(fm28[None, :] > 0, m28 / fm28[None, :], np.nan)
        # promo history
        f["promo_mean_28d"] = self.pf_promo.mean(t, 28)
        f["promo_days_share_28d"] = np.where(self.pf.count(t, 28) > 0, self._promo_days(t, 28), np.nan)
        # oil (price known at t)
        f["oil_price"] = np.full((S, F), p.oil[t])
        f["oil_pct_chg_28d"] = np.full((S, F), p.oil[t] / p.oil[t - 28] - 1)
        return f

    def _promo_days(self, t, w):
        seg = self.p.P[max(0, t - w + 1): t + 1]
        cv = ~np.isnan(self.p.C[max(0, t - w + 1): t + 1])
        return np.nansum((seg > 0) & cv, axis=0) / np.maximum(cv.sum(axis=0), 1)

    # ------------------------------------------------------------------
    def horizon_features(self, t, h, hist):
        """Features for target day D=t+h that use (a) history <= t, aligned to D's weekday / year-ago, and
        (b) information KNOWN IN ADVANCE for D (calendar, holidays, promotions in the test file)."""
        p, C, P = self.p, self.p.C, self.p.P
        D = t + h
        S, F = self.S, self.F
        f = {}
        k0 = -(-h // 7)                                   # ceil(h/7): weeks back to the latest same-weekday obs <= t
        sd = [C[D - 7 * (k0 + k)] for k in range(8)]      # most recent same-weekday observations
        for k in range(4):
            f[f"sd_lag_{k + 1}"] = sd[k]
        stack4, stack8 = np.stack(sd[:4]), np.stack(sd)
        f["sd_mean_4"] = np.nanmean(stack4, axis=0)
        f["sd_mean_8"] = np.nanmean(stack8, axis=0)
        f["dow_ratio_8"] = np.where(hist["sf_mean_91d"] > 0, f["sd_mean_8"] / hist["sf_mean_91d"], np.nan)
        f["yoy_lag_364"] = C[D - 364] if D - 364 >= 0 else np.full((S, F), np.nan)
        lo = max(0, D - 371)
        f["yoy_mean_15d"] = np.nanmean(C[lo: D - 356], axis=0) if D - 364 >= 0 else np.full((S, F), np.nan)
        # year-ago same 28 days vs now  (trend vs last year)
        if t - 364 - 27 >= 0:
            ya = self.pf.mean(t - 364, 28)
            f["yoy_trend_28d"] = np.where(ya > 0, hist["roll_mean_28d"] / ya, np.nan)
        else:
            f["yoy_trend_28d"] = np.full((S, F), np.nan)
        # promotion on D (known in advance: it is a column of test.csv)
        pd_ = P[D]
        f["onpromotion"] = pd_
        f["promo_flag"] = (pd_ > 0).astype(float)
        f["promo_vs_28d"] = pd_ - np.nan_to_num(hist["promo_mean_28d"])
        f["promo_ratio_28d"] = pd_ / (np.nan_to_num(hist["promo_mean_28d"]) + 1.0)
        f["fam_promo_share_D"] = np.tile((pd_ > 0).mean(axis=0), (S, 1))
        f["store_promo_share_D"] = np.tile((pd_ > 0).mean(axis=1)[:, None], (1, F))
        # store-specific calendar for D (all known in advance)
        one = np.ones((1, F))
        H = self.hol
        for name in ["hol_national", "hol_regional", "hol_local", "hol_any", "bridge", "additional", "work_day",
                     "hol_type", "event"]:
            f[name] = H[name][D][:, None] * one
        f["days_to_holiday"] = H["days_to_hol"][D][:, None] * one
        f["days_since_holiday"] = H["days_since_hol"][D][:, None] * one
        f["pre_holiday"] = (H["days_to_hol"][D] == 1).astype(float)[:, None] * one
        f["post_holiday"] = (H["days_since_hol"][D] == 1).astype(float)[:, None] * one
        return f

    # ------------------------------------------------------------------
    def origin_table(self, t, horizons=range(1, HORIZON + 1)):
        """DataFrame with one row per (horizon, store, family) for forecast origin t (features known at end of day t)."""
        p = self.p
        S, F = self.S, self.F
        hist = self.history_features(t)
        hn = list(hist.keys())
        cols = {}
        n = S * F
        H = len(list(horizons))
        cols["origin_date"] = np.full(H * n, p.dates[t].to_datetime64())
        hs = np.repeat(np.array(list(horizons)), n)
        cols["horizon"] = hs.astype(np.int16)
        cols["target_date"] = (p.dates[t] + pd.to_timedelta(hs, unit="D")).values
        cols["store_nbr"] = np.tile(np.repeat(p.stores, F), H).astype(np.int16)
        cols["family_id"] = np.tile(np.tile(np.arange(F), S), H).astype(np.int16)
        # static store attributes
        cols["store_type"] = np.tile(np.repeat(self.type_code, F), H).astype(np.int8)
        cols["store_cluster"] = np.tile(np.repeat(self.cluster, F), H).astype(np.int8)
        cols["city_id"] = np.tile(np.repeat(self.city_code, F), H).astype(np.int8)
        cols["state_id"] = np.tile(np.repeat(self.state_code, F), H).astype(np.int8)
        for k in hn:
            cols[k] = np.tile(hist[k].reshape(-1), H).astype(np.float32)
        hz = [self.horizon_features(t, h, hist) for h in horizons]
        for k in hz[0].keys():
            cols[k] = np.concatenate([x[k].reshape(-1) for x in hz]).astype(np.float32)
        # target-day calendar (identical for every store)
        cal = self.cal.iloc[t + np.array(list(horizons))].reset_index(drop=True)
        for c in ["year", "month", "week_of_year", "day_of_month", "dow", "is_weekend", "is_payday", "days_to_payday", "days_since_payday"]:
            cols[c] = np.repeat(cal[c].values, n).astype(np.int16)
        # target (NaN for the test period and for masked days)
        D = t + np.array(list(horizons))
        y = np.concatenate([p.C[d].reshape(-1) if d < p.n_train_days else np.full(n, np.nan) for d in D])
        cols["y"] = y.astype(np.float32)
        cols["y_log1p"] = np.log1p(y).astype(np.float32)
        # activity rule as known at the origin: zero for 90 days, or never sold so far  ->  forecast 0 by rule
        rz = dormant_flag(p, t) | (self.first_pos > t)
        cols["rule_zero"] = np.tile(rz.reshape(-1), H).astype(np.int8)
        return finalize_dtypes(pd.DataFrame(cols))
