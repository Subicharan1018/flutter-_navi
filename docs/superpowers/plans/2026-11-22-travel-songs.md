# Travel Songs Implementation Plan

> **For the AI building this:** no skills or plugins are needed. Do the tasks in order, tick each `- [ ]` step as you finish it, and follow the rules in "Read this first". (If your tool has a plan-execution or test-driven-development skill, it may help, but nothing here depends on it.)

**Goal:** Pick a date and see on a map where you were (from Google Timeline) and which songs played along the way, with album covers (from Navidrome listening history).

**Architecture:** A small Python tool (standard library only) joins two local files by time: `listens.json` (made by `tool/export_listens.py`, already exists) and Google's `Timeline.json`. It writes one self-contained folder: `travel_songs.js` (all days), `viewer.html`, and the covers. The viewer is one static HTML page (vanilla JavaScript + Leaflet map) that opens by double-click. No server, no upload, no build step.

**Tech Stack:** Python 3.10+ (stdlib only), pytest for tests, Leaflet 1.9.4 from cdnjs (map), OpenStreetMap tiles, plain HTML/CSS/JS.

**Spec:** `docs/travel-songs-plan.md` (what the data looks like and why); `tool/export_listens.py` (the listening export, do not change it).

## Read this first (rules for the AI building this)

1. Do exactly what each step says. Use the exact file names, function names, parameter names and types written here. Do not rename or "improve" them: later tasks call them.
2. Work in order. Do not start a task before the previous one passes its tests.
3. Test first: write the test, run it and see it fail, then write the code, then run it and see it pass.
4. Use only the Python standard library in the tool. The only allowed outside library is `pytest` for tests.
5. Never put real personal data in the repository: tests use the invented data written in this plan. `Timeline.json`, `listens.*`, `listens_covers/` and `travel_out/` are already in `.gitignore`; add `travel_out/` to it in Task 4.
6. If something in this plan is unclear or two steps disagree, stop and ask the human instead of guessing.
7. Commit after every task with the message given.

## Global Constraints

- Python 3.10 compatible (the user has Python 3.10): no `match`-less features newer than 3.10, no `datetime.UTC`, no `from datetime import UTC`. `datetime.fromisoformat` in 3.10 does NOT accept a trailing `Z`: replace `Z` with `+00:00` first.
- All times inside the code are **epoch seconds (float, UTC)**. Local time is only used to decide which calendar day something belongs to.
- Default local time zone offset: `330` minutes (India, UTC+5:30), configurable with `--tz-offset-minutes`.
- Visual design (viewer): black background `#000`, white text `#fff`, secondary text `#8a8a8a`, hairline lines `#1f1f1f`, no cards, no boxes with borders or shadows, no colours except white and grey (the map polylines and markers are white). Font: `system-ui, sans-serif`.
- The viewer must work when opened from `file://` (no `fetch` of local files, no ES modules): data is loaded with a normal `<script src="travel_songs.js">`.
- Keep files small and single-purpose: one responsibility per file as listed below.

## File Structure

```
tool/travel_songs/
  timeline.py          # read Google Timeline.json (both formats) -> list of Segment
  locate.py            # where was I at time t?  -> (segment index, lat, lng)
  build.py             # join plays + segments per day, write travel_out/ ; CLI
  viewer.html          # the page: date picker, list of songs by trip, map
  README.md            # how to run (written in Task 6)
  tests/
    conftest.py        # puts tool/travel_songs on sys.path
    test_timeline.py
    test_locate.py
    test_build.py
    test_viewer.py     # checks the HTML has the ids the script needs
```

Data shapes used by every task (copy exactly):

```python
# timeline.py
@dataclass(frozen=True)
class Point:
    t: float      # epoch seconds UTC
    lat: float
    lng: float

@dataclass(frozen=True)
class Segment:
    kind: str                 # "visit" or "travel"
    mode: str                 # "visit", or e.g. "IN_PASSENGER_VEHICLE", "WALKING", "path", "UNKNOWN"
    start: float              # epoch seconds UTC
    end: float
    path: tuple[Point, ...]   # visit: 2 points (start and end, same place); travel: 2 or more
```

A play (one object of `listens.json`, produced by `tool/export_listens.py`) has these keys we use:
`played_at_epoch` (int), `duration_s` (int), `title`, `artist`, `album`, `cover_id` (like `al-0ppIbU600qAUPikubN7Xn`).

The viewer's data (`window.TRAVEL_DATA`), produced by `build.py`:

```json
{
  "tz_minutes": 330,
  "days": {
    "2026-11-20": {
      "date": "2026-11-20",
      "segments": [
        {"id": 0, "kind": "visit",  "mode": "visit", "start": 1795141800, "end": 1795143600, "path": [[13.0827, 80.2707]]},
        {"id": 1, "kind": "travel", "mode": "IN_PASSENGER_VEHICLE", "start": 1795143600, "end": 1795150800,
         "path": [[13.0827, 80.2707], [13.0, 79.7], [12.9165, 79.1325]]}
      ],
      "plays": [
        {"t": 1795146000, "start": 1795145712, "title": "T", "artist": "A", "album": "Al", "cover_id": "al-x",
         "duration_s": 288, "lat": 13.0, "lng": 79.7, "segment": 1}
      ],
      "summary": {"plays": 1, "minutes": 5, "top_artist": "A", "travel_km": 123.4}
    }
  }
}
```

`lat`, `lng` and `segment` are `null` when the play could not be placed. Segment `path` for a visit is a single `[lat, lng]`.

## Review Focus

- Timeline file with neither `semanticSegments` nor `timelineObjects` (wrong file): clear error message, exit code 1, nothing written.
- A day with plays but no timeline data: the day still appears, `segments` empty, every play has `null` position.
- Plays that fall exactly on a segment boundary or in a gap shorter than 10 minutes: placed on the nearest segment end, not dropped.
- A play at 00:40 local time whose UTC date is the day before: must land on the local date (tested).
- Songs with quotes, `&`, `<`, emoji or Tamil text in the title: the viewer must show them as text, never as HTML (use `textContent`, never `innerHTML` with data).

---

### Task 1: Read the new Timeline format

**Files:**
- Create: `tool/travel_songs/timeline.py`, `tool/travel_songs/tests/conftest.py`, `tool/travel_songs/tests/test_timeline.py`

**Interfaces:**
- Produces: `Point`, `Segment` (shapes above), `iso_to_epoch(text: str) -> float`, `parse_latlng(text: str) -> tuple[float, float]`, `parse_timeline(data: dict) -> list[Segment]` (sorted by `start`; raises `ValueError("not a Google Timeline export")` when neither key exists).

- [ ] **Step 1: Create `tests/conftest.py`**

```python
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
```

- [ ] **Step 2: Write the failing tests in `tests/test_timeline.py`**

```python
import pytest
from timeline import Point, Segment, iso_to_epoch, parse_latlng, parse_timeline

NEW = {
    "semanticSegments": [
        {
            "startTime": "2026-11-20T08:00:00.000+05:30",
            "endTime": "2026-11-20T08:30:00.000+05:30",
            "visit": {"probability": 0.9, "topCandidate": {
                "semanticType": "HOME", "placeLocation": {"latLng": "13.0827°, 80.2707°"}}},
        },
        {
            "startTime": "2026-11-20T08:30:00.000+05:30",
            "endTime": "2026-11-20T10:30:00.000+05:30",
            "activity": {"start": {"latLng": "13.0827°, 80.2707°"}, "end": {"latLng": "12.9165°, 79.1325°"},
                         "distanceMeters": 130000.0, "topCandidate": {"type": "IN_PASSENGER_VEHICLE"}},
        },
        {
            "startTime": "2026-11-20T08:30:00.000+05:30",
            "endTime": "2026-11-20T10:30:00.000+05:30",
            "timelinePath": [
                {"point": "13.0827°, 80.2707°", "time": "2026-11-20T08:30:00.000+05:30"},
                {"point": "13.0°, 79.7°", "time": "2026-11-20T09:30:00.000+05:30"},
                {"point": "12.9165°, 79.1325°", "time": "2026-11-20T10:30:00.000+05:30"},
            ],
        },
    ]
}


def test_iso_to_epoch_handles_offset_and_z():
    assert iso_to_epoch("2026-11-20T08:00:00.000+05:30") == iso_to_epoch("2026-11-20T02:30:00Z")


def test_parse_latlng():
    assert parse_latlng("13.0827°, 80.2707°") == (13.0827, 80.2707)
    assert parse_latlng("-12.5°, 77°") == (-12.5, 77.0)


def test_visit_becomes_two_point_segment():
    visit = parse_timeline(NEW)[0]
    assert (visit.kind, visit.mode) == ("visit", "visit")
    assert len(visit.path) == 2 and visit.path[0].lat == pytest.approx(13.0827)
    assert visit.path[0].t == visit.start and visit.path[1].t == visit.end


def test_activity_without_path_is_a_straight_line_travel_segment():
    seg = [s for s in parse_timeline(NEW) if s.mode == "IN_PASSENGER_VEHICLE"][0]
    assert seg.kind == "travel" and len(seg.path) == 2
    assert seg.path[1].lat == pytest.approx(12.9165)


def test_timeline_path_becomes_travel_segment_with_all_points():
    seg = [s for s in parse_timeline(NEW) if s.mode == "path"][0]
    assert seg.kind == "travel" and len(seg.path) == 3
    assert seg.path[1].t == iso_to_epoch("2026-11-20T09:30:00.000+05:30")


def test_sorted_by_start():
    segs = parse_timeline(NEW)
    assert [s.start for s in segs] == sorted(s.start for s in segs)


def test_wrong_file_is_rejected():
    with pytest.raises(ValueError, match="not a Google Timeline export"):
        parse_timeline({"hello": 1})
```

- [ ] **Step 3: Run `python -m pytest tool/travel_songs/tests/test_timeline.py -q`. Expected: FAIL (`ModuleNotFoundError: timeline`).**

- [ ] **Step 4: Implement `timeline.py`** with the dataclasses above and these functions:
  - `iso_to_epoch(text)`: replace a trailing `Z` with `+00:00`, `datetime.fromisoformat(...).timestamp()`.
  - `parse_latlng(text)`: `re.findall(r"-?\d+(?:\.\d+)?", text)` -> first two numbers as floats (the `°` signs are ignored).
  - `parse_timeline(data)`: if `"semanticSegments"` in data, walk it (per item: `visit` -> visit segment using `visit.topCandidate.placeLocation.latLng`; `activity` -> travel segment with mode `activity.topCandidate.type` (default `"UNKNOWN"`), path = start and end points placed at the segment's start/end times; `timelinePath` -> travel segment, mode `"path"`, one `Point` per entry using its own `time`). Items with none of the three keys are skipped (they are "raw" signals). Skip any item that raises `KeyError`/`ValueError` while parsing (one bad segment never fails the file). Old format is added in Task 2: for now, if `"timelineObjects"` is present return `[]`; if neither key is present raise `ValueError("not a Google Timeline export")`. Return the list sorted by `start`.

- [ ] **Step 5: Run the tests. Expected: all PASS.**

- [ ] **Step 6: Commit**

```bash
git add tool/travel_songs
git commit -m "feat(travel-songs): read the new Google Timeline format"
```

---

### Task 2: Read the old Timeline format

**Files:**
- Modify: `tool/travel_songs/timeline.py`
- Modify: `tool/travel_songs/tests/test_timeline.py`

**Interfaces:**
- Consumes: `Point`, `Segment`, `iso_to_epoch` from Task 1.
- Produces: `parse_timeline` now also accepts `{"timelineObjects": [...]}`.

- [ ] **Step 1: Add the failing tests to `test_timeline.py`**

```python
OLD = {
    "timelineObjects": [
        {"placeVisit": {
            "location": {"latitudeE7": 130827000, "longitudeE7": 802707000},
            "duration": {"startTimestamp": "2026-11-20T02:30:00Z", "endTimestamp": "2026-11-20T03:00:00Z"}}},
        {"activitySegment": {
            "startLocation": {"latitudeE7": 130827000, "longitudeE7": 802707000},
            "endLocation": {"latitudeE7": 129165000, "longitudeE7": 791325000},
            "duration": {"startTimestamp": "2026-11-20T03:00:00Z", "endTimestamp": "2026-11-20T05:00:00Z"},
            "activityType": "IN_PASSENGER_VEHICLE",
            "waypointPath": {"waypoints": [{"latE7": 130000000, "lngE7": 797000000}]}}},
    ]
}


def test_old_format_visit_and_activity():
    visit, drive = parse_timeline(OLD)
    assert visit.kind == "visit" and visit.path[0].lat == pytest.approx(13.0827)
    assert drive.kind == "travel" and drive.mode == "IN_PASSENGER_VEHICLE"
    assert len(drive.path) == 3                      # start, one waypoint, end
    assert drive.path[1].lat == pytest.approx(13.0)
    assert drive.path[0].t == drive.start and drive.path[-1].t == drive.end
    assert drive.start < drive.path[1].t < drive.end  # waypoint times are spread evenly between start and end
```

- [ ] **Step 2: Run it; expected FAIL (returns `[]`).**

- [ ] **Step 3: Implement** the `timelineObjects` branch of `parse_timeline`: `placeVisit` -> visit (`location.latitudeE7/1e7`, `longitudeE7/1e7`, times from `duration.startTimestamp/endTimestamp`); `activitySegment` -> travel, mode = `activityType` (default `"UNKNOWN"`), points = start location, then each `waypointPath.waypoints` entry (`latE7`, `lngE7`) with times spaced evenly between start and end, then end location. Same "skip a bad item, never fail the file" rule.

- [ ] **Step 4: Run all tests in the folder. Expected: PASS.**

- [ ] **Step 5: Commit** `git commit -am "feat(travel-songs): read the old Timeline format"`

---

### Task 3: Where was I at time t?

**Files:**
- Create: `tool/travel_songs/locate.py`, `tool/travel_songs/tests/test_locate.py`

**Interfaces:**
- Consumes: `Segment`, `Point` from `timeline.py`.
- Produces:
  - `position_at(seg: Segment, t: float) -> tuple[float, float]`: linear interpolation along `seg.path` by time; before the first point or after the last returns that end point.
  - `locate(segments: list[Segment], t: float, near_s: float = 600) -> tuple[int | None, tuple[float, float] | None]`: `(index into segments, (lat, lng))`.

- [ ] **Step 1: Write the failing tests**

```python
import pytest
from timeline import Point, Segment
from locate import locate, position_at

T0 = 1_000_000.0
HOUR = 3600.0


def drive():
    return Segment("travel", "path", T0, T0 + 2 * HOUR, (
        Point(T0, 13.0827, 80.2707), Point(T0 + HOUR, 13.0, 79.7), Point(T0 + 2 * HOUR, 12.9165, 79.1325)))


def stay():
    return Segment("visit", "visit", T0 + 2 * HOUR, T0 + 4 * HOUR, (
        Point(T0 + 2 * HOUR, 12.9165, 79.1325), Point(T0 + 4 * HOUR, 12.9165, 79.1325)))


def test_position_at_a_point_and_between_points():
    s = drive()
    assert position_at(s, T0 + HOUR) == pytest.approx((13.0, 79.7))
    assert position_at(s, T0 + HOUR / 2) == pytest.approx((13.04135, 79.98535))


def test_position_outside_is_clamped_to_the_ends():
    s = drive()
    assert position_at(s, T0 - 99) == pytest.approx((13.0827, 80.2707))
    assert position_at(s, T0 + 9 * HOUR) == pytest.approx((12.9165, 79.1325))


def test_locate_inside_a_travel_segment():
    i, pos = locate([drive(), stay()], T0 + HOUR / 2)
    assert i == 0 and pos == pytest.approx((13.04135, 79.98535))


def test_locate_inside_a_visit():
    i, pos = locate([drive(), stay()], T0 + 3 * HOUR)
    assert i == 1 and pos == pytest.approx((12.9165, 79.1325))


def test_overlap_prefers_the_segment_with_more_path_points():
    straight = Segment("travel", "IN_PASSENGER_VEHICLE", T0, T0 + 2 * HOUR, (
        Point(T0, 13.0827, 80.2707), Point(T0 + 2 * HOUR, 12.9165, 79.1325)))
    i, _ = locate([straight, drive()], T0 + HOUR)
    assert i == 1


def test_gap_within_ten_minutes_snaps_to_the_nearest_segment():
    segs = [drive(), stay()]
    i, pos = locate(segs, T0 + 4 * HOUR + 300)          # 5 min after the visit ended
    assert i == 1 and pos == pytest.approx((12.9165, 79.1325))


def test_gap_longer_than_ten_minutes_is_unplaced():
    assert locate([drive(), stay()], T0 + 4 * HOUR + 601) == (None, None)


def test_no_segments():
    assert locate([], T0) == (None, None)
```

- [ ] **Step 2: Run; expected FAIL (`ModuleNotFoundError: locate`).**

- [ ] **Step 3: Implement `position_at` and `locate`.** `position_at`: find the two consecutive path points whose times bracket `t`, interpolate with `f = (t - a.t) / (b.t - a.t)` (if `b.t == a.t` return `a`). `locate`: among segments with `start <= t <= end` choose the one with the most path points (ties: the earlier index) and return `(index, position_at(...))`. If none contains `t`, find the segment whose nearest boundary (`start` or `end`) is closest to `t`; if that distance is `<= near_s` return it with the position at that boundary, else `(None, None)`.

- [ ] **Step 4: Run; expected PASS.**

- [ ] **Step 5: Commit** `git commit -am "feat(travel-songs): locate a time on the timeline"` (use `git add tool/travel_songs` first).

---

### Task 4: Join plays and timeline per day, write the output folder

**Files:**
- Create: `tool/travel_songs/build.py`, `tool/travel_songs/tests/test_build.py`
- Modify: `.gitignore` (add the line `travel_out/`)

**Interfaces:**
- Consumes: `parse_timeline`, `Segment` from `timeline.py`; `locate` from `locate.py`.
- Produces:
  - `day_key(epoch: float, tz_minutes: int) -> str` (local date `YYYY-MM-DD`).
  - `haversine_km(a: tuple[float, float], b: tuple[float, float]) -> float`.
  - `build_days(plays: list[dict], segments: list[Segment], tz_minutes: int = 330) -> dict[str, dict]` (shape in "Data shapes": the value of `days`).
  - `write_output(days: dict, tz_minutes: int, out_dir: str, viewer_src: str, covers_dir: str | None = None) -> None` writes `travel_songs.js`, copies `viewer.html`, copies the covers folder to `out_dir/covers/`.
  - `main(argv: list[str] | None = None) -> int` with `--listens`, `--timeline`, `--out-dir` (default `travel_out`), `--covers` (optional), `--tz-offset-minutes` (default 330). Prints `N days, M plays, K placed -> <out-dir>`. Returns 1 and prints the error when the timeline file is not a Timeline export; writes nothing then.

- [ ] **Step 1: Write the failing tests**

```python
import json
import pytest
from timeline import Point, Segment
from build import build_days, day_key, haversine_km, main, write_output

T0 = 1795141800.0   # 2026-11-20 08:00 at +05:30 (02:30 UTC)
HOUR = 3600.0


def segs():
    return [
        Segment("visit", "visit", T0, T0 + 1800, (Point(T0, 13.0827, 80.2707), Point(T0 + 1800, 13.0827, 80.2707))),
        Segment("travel", "path", T0 + 1800, T0 + 1800 + 2 * HOUR, (
            Point(T0 + 1800, 13.0827, 80.2707), Point(T0 + 1800 + HOUR, 13.0, 79.7),
            Point(T0 + 1800 + 2 * HOUR, 12.9165, 79.1325))),
    ]


def play(played_at, artist="A", title="T", duration=240):
    return {"played_at_epoch": played_at, "duration_s": duration, "title": title, "artist": artist,
            "album": "Al", "cover_id": "al-x"}


def test_day_key_uses_local_time():
    assert day_key(1795115400, 330) == "2026-11-20"      # 2026-11-19 19:10 UTC is 00:40 local on the 20th
    assert day_key(1795115400, 0) == "2026-11-19"


def test_haversine_one_degree_of_latitude_is_about_111_km():
    assert haversine_km((0.0, 0.0), (1.0, 0.0)) == pytest.approx(111.19, abs=0.3)


def test_play_is_placed_by_its_midpoint():
    mid = T0 + 1800 + HOUR                       # exactly on the middle path point
    days = build_days([play(mid + 120, duration=240)], segs())   # midpoint = played_at - duration/2 = mid
    p = days["2026-11-20"]["plays"][0]
    assert (p["lat"], p["lng"]) == pytest.approx((13.0, 79.7))
    assert p["segment"] == 1 and p["start"] == mid + 120 - 240 and p["t"] == mid + 120


def test_day_without_timeline_keeps_the_plays_unplaced():
    days = build_days([play(T0 + 30 * 86400)], segs())
    day = days["2026-12-20"]
    assert day["segments"] == [] and day["plays"][0]["lat"] is None and day["plays"][0]["segment"] is None


def test_summary():
    plays = [play(T0 + 100, "A"), play(T0 + 200, "B"), play(T0 + 300, "A")]
    s = build_days(plays, segs())["2026-11-20"]["summary"]
    assert s["plays"] == 3 and s["minutes"] == 12 and s["top_artist"] == "A"
    assert s["travel_km"] == pytest.approx(
        haversine_km((13.0827, 80.2707), (13.0, 79.7)) + haversine_km((13.0, 79.7), (12.9165, 79.1325)), abs=0.01)


def test_visit_path_is_a_single_point_and_ids_are_indexes():
    segments = build_days([play(T0 + 100)], segs())["2026-11-20"]["segments"]
    assert [s["id"] for s in segments] == [0, 1]
    assert len(segments[0]["path"]) == 1 and len(segments[1]["path"]) == 3


def test_write_output_and_cli(tmp_path):
    listens = tmp_path / "listens.json"
    listens.write_text(json.dumps([play(T0 + 100)]), encoding="utf-8")
    tl = tmp_path / "Timeline.json"
    tl.write_text(json.dumps({"semanticSegments": []}), encoding="utf-8")
    viewer = tmp_path / "viewer.html"
    viewer.write_text("<html></html>", encoding="utf-8")
    out = tmp_path / "out"
    days = build_days([play(T0 + 100)], [])
    write_output(days, 330, str(out), str(viewer))
    text = (out / "travel_songs.js").read_text(encoding="utf-8")
    assert text.startswith("window.TRAVEL_DATA = ")
    data = json.loads(text[len("window.TRAVEL_DATA = "):].rstrip(";\n"))
    assert data["tz_minutes"] == 330 and "2026-11-20" in data["days"]
    assert (out / "viewer.html").exists()


def test_cli_rejects_a_wrong_timeline_and_writes_nothing(tmp_path, capsys):
    (tmp_path / "l.json").write_text("[]", encoding="utf-8")
    (tmp_path / "t.json").write_text('{"hello": 1}', encoding="utf-8")
    code = main(["--listens", str(tmp_path / "l.json"), "--timeline", str(tmp_path / "t.json"),
                 "--out-dir", str(tmp_path / "o")])
    assert code == 1 and "not a Google Timeline export" in capsys.readouterr().out
    assert not (tmp_path / "o").exists()
```

- [ ] **Step 2: Run; expected FAIL (`ModuleNotFoundError: build`).**

- [ ] **Step 3: Implement `build.py`.**
  - `day_key`: `datetime.fromtimestamp(epoch, timezone(timedelta(minutes=tz_minutes))).strftime("%Y-%m-%d")`.
  - `haversine_km`: standard formula, Earth radius 6371.0088 km.
  - `build_days`: for each play compute `start = played_at - duration_s`, `mid = played_at - duration_s / 2`, `locate(segments, mid)`. Group plays by `day_key(mid, tz)`; sort by `t`. For every day, `segments` = the input segments that overlap that local day (`seg.start < day_end and seg.end > day_start`, where day bounds are computed from the local date), re-indexed `0..n-1` as `id`; a play's `segment` is the id **inside its day's list** (look the segment up by identity; if its segment is not in that day's list, `segment` and position are `null`). Segment output: `{"id","kind","mode","start","end","path":[[lat,lng],...]}` with a visit reduced to one point. `summary`: `plays` count, `minutes = round(sum(duration_s)/60)`, `top_artist` = most frequent artist (ties: alphabetical), `travel_km` = sum of `haversine_km` between consecutive path points of that day's travel segments **that are not duplicates**: when two travel segments overlap in time, count only the one with more path points (same rule as Task 3), rounded to 1 decimal.
  - `write_output`: `os.makedirs(out_dir, exist_ok=True)`; write `window.TRAVEL_DATA = ` + `json.dumps({"tz_minutes": tz, "days": days}, ensure_ascii=False)` + `;\n` to `travel_songs.js` (UTF-8); `shutil.copyfile(viewer_src, out_dir/viewer.html)`; if `covers_dir`, `shutil.copytree(covers_dir, out_dir/covers, dirs_exist_ok=True)`.
  - `main`: load listens JSON (list), load timeline JSON, `parse_timeline` inside `try/except ValueError as e: print(e); return 1` **before** creating the out dir. `viewer_src` is `viewer.html` next to `build.py` (`Path(__file__).with_name("viewer.html")`).

- [ ] **Step 4: Add `travel_out/` to `.gitignore`. Run the tests; expected PASS. (The CLI test only needs a `viewer.html` next to `build.py`: create an empty placeholder `tool/travel_songs/viewer.html` containing `<!doctype html><title>Travel songs</title>` now; Task 5 replaces it.)**

- [ ] **Step 5: Commit** `git add tool/travel_songs .gitignore && git commit -m "feat(travel-songs): join plays and timeline per day, write the output folder"`

---

### Task 5: The viewer page

**Files:**
- Modify: `tool/travel_songs/viewer.html` (replace the placeholder)
- Create: `tool/travel_songs/tests/test_viewer.py`

**Interfaces:**
- Consumes: `window.TRAVEL_DATA` (shape in "Data shapes").
- Produces: a page that works by double-clicking `travel_out/viewer.html`.

**Required ids and behaviour (build exactly this):**

| Element | id | Behaviour |
|---|---|---|
| Date input (`<input type="date">`) | `day` | `min` and `max` are the first and last day that has data; changing it calls `showDay(date)`. Days without data show the message "No songs on this day." |
| Previous / next day buttons | `prev`, `next` | Move to the previous / next day **that has data**. Disabled at the ends. |
| Summary line | `summary` | e.g. `23 songs · 94 min · top: A. R. Rahman · 130.4 km travelled`. Hide the km part when `travel_km` is 0. |
| Song list container | `list` | See below. |
| Map container | `map` | Leaflet map filling the right side (desktop) or the top 45% of the screen (width under 800 px, list below it). |
| Message line | `message` | Used for "No songs on this day." and for "travel_songs.js not found: run build.py first." (shown when `window.TRAVEL_DATA` is undefined). |

**The list** is built from the day's plays, in time order, grouped into **trips**: a new group starts whenever `segment` changes between neighbouring plays (`null` forms its own group labelled "Elsewhere"). Each group has a header line then rows. No boxes, no borders except a 1 px `#1f1f1f` line between rows:

- Header: mode label, then local time range of the group, e.g. `Drive · 08:30–10:30`. Mode labels: `IN_PASSENGER_VEHICLE` -> "Drive", `WALKING` -> "Walk", `CYCLING` -> "Cycle", `IN_BUS` -> "Bus", `IN_TRAIN`, `IN_SUBWAY`, `IN_TRAM` -> "Train", `FLYING` -> "Flight", `MOTORCYCLING` -> "Ride", `visit` -> "Stay", any other / `path` -> "Travel". Colour `#8a8a8a`, 12 px, upper-case letter-spacing 0.08em.
- Row (height 56 px): a 44x44 cover `<img>` (`covers/<cover_id>.jpg`, `loading="lazy"`; on `error` replace with a 44x44 `#1f1f1f` square), then title (white, 15 px, one line with ellipsis), artist · album (grey, 13 px, ellipsis), and the local time `HH:MM` on the right (grey, 13 px, tabular numbers). Local time = `t + tz_minutes*60` formatted as UTC (`new Date((t + tz*60)*1000).toISOString().slice(11,16)`).
- Rows whose play has a position are clickable; hovering a row highlights its map marker (bigger, full white); clicking pans/zooms the map to it (`map.flyTo([lat,lng], 14)`) and opens its popup.

**The map** (Leaflet 1.9.4 from cdnjs: `https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.css` and `.../leaflet.min.js`; OpenStreetMap tiles `https://tile.openstreetmap.org/{z}/{x}/{y}.png` with the attribution `© OpenStreetMap contributors`):
- Dark look with CSS only: `.leaflet-tile { filter: invert(1) grayscale(1) brightness(0.85) contrast(0.9); }`, map background `#000`.
- Each travel segment: white polyline, weight 3, opacity 0.9. Each visit: a white circle (radius 8, `fillOpacity 0.15`, white 1 px outline).
- Each placed play: `L.circleMarker` radius 5, fill white, opacity 0.7; popup contains the cover (64 px), title, artist, time. **Build popup content with DOM elements and `textContent`, never `innerHTML` with data.**
- After drawing a day, `map.fitBounds` to everything drawn (padding 40). If nothing is drawn (no timeline that day), show the world at zoom 2 and keep the list.
- When showing another day, remove the old layers first (use one `L.layerGroup` and `clearLayers()`).

- [ ] **Step 1: Write the failing test `tests/test_viewer.py`**

```python
from pathlib import Path

HTML = (Path(__file__).resolve().parent.parent / "viewer.html").read_text(encoding="utf-8")


def test_has_every_required_id():
    for needed in ("id=\"day\"", "id=\"prev\"", "id=\"next\"", "id=\"summary\"", "id=\"list\"", "id=\"map\"",
                   "id=\"message\""):
        assert needed in HTML, needed


def test_loads_data_without_fetch_and_without_modules():
    assert '<script src="travel_songs.js">' in HTML
    assert "fetch(" not in HTML and 'type="module"' not in HTML


def test_pinned_leaflet_version_and_no_innerhtml_with_data():
    assert "leaflet/1.9.4/leaflet.min.js" in HTML and "leaflet/1.9.4/leaflet.min.css" in HTML
    assert "innerHTML" not in HTML


def test_design_rules():
    assert "#000" in HTML and "box-shadow" not in HTML
```

- [ ] **Step 2: Run; expected FAIL.**

- [ ] **Step 3: Write `viewer.html`** (one file: `<style>`, the body with the ids above, `<script src="travel_songs.js">` placed **before** your inline script, then your inline script). Functions to define in the inline script: `showDay(date)`, `renderSummary(day)`, `renderList(day)`, `renderMap(day)`, `modeLabel(mode)`, `localTime(t)`, `groupPlays(plays)` (returns array of `{segment, plays}`). Keep the whole file under 400 lines. Layout: CSS grid, desktop `grid-template-columns: 380px 1fr` (left column: date controls, summary, list with its own scroll; right: map); under 800 px: single column, map first (45vh), list below. Touch targets at least 44 px.

- [ ] **Step 4: Run the tests; expected PASS.**

- [ ] **Step 5: Manual check (write the result in your final report):** run the pipeline on the invented sample in Task 6, open `travel_out/viewer.html` by double-click in a browser, and confirm: date picker moves between days, the list is grouped, hovering/clicking a row highlights/flies to the marker, a title containing `<b>` and `&` shows literally.

- [ ] **Step 6: Commit** `git add tool/travel_songs && git commit -m "feat(travel-songs): viewer page with date picker, grouped songs and map"`

---

### Task 6: README, sample run, final check

**Files:**
- Create: `tool/travel_songs/README.md`, `tool/travel_songs/sample/` (invented data only: `listens.json`, `Timeline.json`)

**Interfaces:** Consumes everything above.

- [ ] **Step 1: Create invented sample data** in `tool/travel_songs/sample/`: `Timeline.json` using the `NEW` structure from Task 1's test (a visit, a drive with a 3-point `timelinePath`, a second visit) and `listens.json` with about 8 plays (invented titles, e.g. "Test Song 1", including one title `<b>Bold & "quoted"</b>` and one Tamil title `தமிழ் பாடல்`) spread across 08:00-12:00 local on 2026-11-20 and 3 plays on 2026-11-21 with no timeline data. No real songs, places or people.

- [ ] **Step 2: Run the whole pipeline on the sample**

Run: `python tool/travel_songs/build.py --listens tool/travel_songs/sample/listens.json --timeline tool/travel_songs/sample/Timeline.json --out-dir travel_out`
Expected output: `2 days, 11 plays, 8 placed -> travel_out` (adjust the numbers only if your sample differs, and say so).

- [ ] **Step 3: Write `README.md`** with these sections, short and in plain words: *What it does*; *Step 1: export your listens* (the command from `docs/travel-songs-plan.md`, with `--covers listens_covers`); *Step 2: export Timeline from the phone*; *Step 3: build* (`python tool/travel_songs/build.py --listens listens.json --timeline Timeline.json --covers listens_covers --out-dir travel_out`); *Step 4: open `travel_out/viewer.html`*; *Time zones* (default +05:30, `--tz-offset-minutes`); *Privacy* (everything stays on your computer; the map tiles are the only network use); *Limits* (a play is placed by the middle of the song; only phone plays during a trip; Timeline only has the days the phone kept).

- [ ] **Step 4: Run the full test folder**

Run: `python -m pytest tool/travel_songs/tests -q`
Expected: all tests pass (about 25).

- [ ] **Step 5: Commit** `git add tool/travel_songs && git commit -m "docs(travel-songs): README and invented sample data"`

## Final report the builder must write

State: tests run and passed (the count), the sample command output, whether the viewer was opened in a real browser (yes/no, and what was checked), and anything that differed from this plan.
