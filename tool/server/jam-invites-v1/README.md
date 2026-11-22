# jam-invites-v1: invite a friend to a Jam from the app

For `/opt/shuffle-server` (the social v3 server). Install: `bash install.sh` on the server, then `sudo systemctl restart navivibe`.
Without it the app still works: the Invite button hides itself while the server answers 404, and the share link stays.

| Where | What |
|---|---|
| new | `navivibe/jam_invites.py`: in-memory invites next to the in-memory rooms, plus the three routes |
| 1 anchored patch | `navivibe/social.py` registers the routes (`patch_social.py`, idempotent) |

## HTTP contract (signed in)

    POST /social/jam/<code>/invite          {"to": "bob"}   -> {"invited": "Bob"}
    GET  /social/jam/invites                                -> {"invites": [{code, from, mode, members, at, expires_at}]}
    POST /social/jam/<code>/invite/decline                  -> {"declined": true}

Accepting is the existing `POST /social/jam/join {"code"}`; it also clears the invite.

Errors: 400 no friend / yourself, 403 you are not in the room or social is off for you, 404 friend not on social, 409 already
inside or room full, 410 room ended, 429 throttled (one invite per pair per 5 s, 40 an hour per sender, 10 waiting per friend).
An invite lives 30 min or until the room ends. Any member can invite (they all see the code anyway).

## Tests

`navivibe/tests/test_jam_invites_v1.py`: 13 tests (delivery, join clears it, membership/privacy, opt-in rules, full room,
expiry and room end, decline, throttles, auth, route order). Run on a copy of the live v3 code: 13 passed; with the existing
social suites (test_social, test_jam_roles, test_social_v2, test_jam_extras, test_social_v3, test_discover) 108 + 13 pass.
