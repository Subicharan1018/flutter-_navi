---
version: 1
slug: "lib-screens-home-screen-dart"
primary_target: "lib/screens/home_screen.dart"
related_targets: ["lib/screens/search_screen.dart","lib/screens/library_screen.dart","lib/widgets/ui/artwork_page.dart","lib/screens/settings_screen.dart","lib/screens/login_screen.dart","lib/screens/stats/stats_screen.dart"]
---

# App chrome — Home, Search, Library, collection pages, Settings, Sign-in

Scope: every non-player surface of NaviVibe (Flutter, Navidrome client). Mode: Operate.
Primary target: Android phone (390×844 class); secondary: Linux/Windows desktop wide adaptation.
User: invited friends of the server owner; the server URL is prefilled and never explained. Aha moment: first song playing.
Constraints: Apple Music iOS 26, played straight; green accent (no purple/pink); opaque chrome, only artwork may fade into its page colour; 44pt+ targets; no eyebrow kickers or glows.

## Direction contract

THESIS: Apple Music's iPhone app, at full fidelity, on Android. The cover art is the only decoration; the chrome is exact, quiet and opaque. This refuses the default Android music client: a Material grey shell with cards, chips and a bottom navigation bar.

OWN-WORLD: The ground is an opaque green-black ramp (#050B07 base / #0F1D14 grouped surface / #17291D elevated / #213628 overlay), never neutral grey. The accent is systemGreen #30D158; text is #FFFFFF / #97A59C / #7E9284. Stats and dashboards have no card containers: type, space and charts carry them. Collection pages use the cover's sampled ground colour, with the artwork bleeding into it. Inter with Apple dynamic tracking, Apple-style large titles that collapse, and inset grouped lists. Shuffle and More are round; Play is a capsule. The floating capsule tab bar has a separate Search circle, and the capsule mini player sits on a solid band of the page colour.

STORY: The listener opens the app, sees Top Picks and their recent albums, taps once and music plays. They find anything with Search's coloured genre tiles, and keep their pins at the top of Library.

FIRST VIEWPORT: Home: the large title "Home" with an avatar at right; Top Picks is one tall cover-coloured card per item (cover 60% of the card, with text on a solid panel of the cover's colour), scrolling horizontally. Below it are the Recently Played shelf, and the dock is the mini player above the tab capsule. Primary action: tap a cover to play.

FORM: canon (the category standard, played straight), chosen by the user from the decision page. Seed key: 02f533ac.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

## Unresolved
- Onboarding: library sync progress honesty on first sign-in.
