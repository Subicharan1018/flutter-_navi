"""
navivibe/catalog/spotify_evidence.py   (exportify-v1)
─────────────────────────────────────────────────────
A second opinion for the mood rules (mood_quality.ruled_out), from Spotify's own valence and energy for
the songs an Exportify CSV matched. It only ever agrees with or breaks a tie for evidence the rules already
use, and it can only keep or drop a label the labeller gave: it never creates a label on its own. A song
with no Spotify row is judged exactly as before. Admin labels and "Not this mood" marks are applied after
these rules and beat them.

  veto       a rule dropped a mood, but Spotify clearly says the opposite: the mood stays.
               sad     dropped as "sounds happy / loud and bright", Spotify valence < 0.35
               calm    dropped as "too loud / fast", Spotify energy < 0.45
               happy   dropped as "sounds sad", Spotify valence >= 0.65
               angry   dropped as "bright and gentle", Spotify energy < 0.5 and valence < 0.35
  tie-break  the audio model is one step short of dropping it and Spotify agrees: the mood goes.
               sad     lyrics don't say sad, audio valence >= 0.5, happy beats sad by 0.1, Spotify
                       valence >= 0.65 and energy >= 0.5
               calm    audio energy >= 0.55, Spotify energy >= 0.75

Measured 21 Nov 2026 on the 54-song reference sample (22 of them have a Spotify row): 49 right, 3 wrong,
2 unlabelled before and after, so accuracy is unchanged there; across the 1,032 owned songs a CSV matched,
18 change (17 lose a label, 1 gets one back). Switch it off with NAVIVIBE_SPOTIFY_MOODS=0.
"""

import os

VETO_SAD_V = 0.35
VETO_CALM_E = 0.45
VETO_HAPPY_V = 0.65
VETO_ANGRY_E, VETO_ANGRY_V = 0.5, 0.35
TIE_SAD_SP_V, TIE_SAD_SP_E, TIE_SAD_AUDIO_V, TIE_SAD_GAP = 0.65, 0.5, 0.5, 0.1
TIE_CALM_SP_E, TIE_CALM_AUDIO_E = 0.75, 0.55


def enabled() -> bool:
    return os.getenv("NAVIVIBE_SPOTIFY_MOODS", "1").strip() != "0"


def facts_for(song_id) -> dict:
    """{'sp_valence', 'sp_energy'} for a song with a Spotify row, else {} (the rules then ignore Spotify)."""
    from navivibe import spotify_details
    d = spotify_details.get(song_id) if song_id else None
    if not d or d.get("valence") is None or d.get("energy") is None:
        return {}
    return {"sp_valence": float(d["valence"]), "sp_energy": float(d["energy"])}


def second_opinion(mood: str, f: dict, base) -> str | None:
    """`base(mood, f)` is the existing rule check (the reason a mood is ruled out, or None); this answers the
    same question with Spotify's numbers taken into account."""
    why = base(mood, f)
    v, e = f.get("sp_valence"), f.get("sp_energy")
    if v is None or e is None or not enabled():
        return why
    if why:
        if mood == "sad" and v < VETO_SAD_V:
            return None
        if mood == "calm" and e < VETO_CALM_E:
            return None
        if mood == "happy" and v >= VETO_HAPPY_V:
            return None
        if mood == "angry" and e < VETO_ANGRY_E and v < VETO_ANGRY_V:
            return None
        return why
    a = f.get("audio") or {}
    happy, sad = a.get("happy"), a.get("sad")
    audio_e, audio_v = f.get("energy"), f.get("valence")
    if (mood == "sad" and f.get("sad_words", 0) < 2 and f.get("has_lyrics") and v >= TIE_SAD_SP_V and e >= TIE_SAD_SP_E
            and audio_v is not None and audio_v >= TIE_SAD_AUDIO_V
            and happy is not None and sad is not None and happy - sad >= TIE_SAD_GAP):
        return "sounds happy (Spotify agrees)"
    if mood == "calm" and e >= TIE_CALM_SP_E and audio_e is not None and audio_e >= TIE_CALM_AUDIO_E:
        return "too loud for calm (Spotify agrees)"
    return None
