"""
cross-device-v1: start a queue on ANY of a user's devices, even one that is not playing.

Adds the proto-3 command `playOn` to navivibe/session.py with exact-match,
idempotent edits: each edit is applied only if its old text is there exactly
once, and skipped if its new text is already there. Anything else stops the
run with nothing written.

    python -I patch_session.py /opt/shuffle-server/navivibe/session.py
"""

import sys

PATCHES = [
    # 1 a transfer may carry the queue that is to start on the target
    (
        "cmd: Optional[tuple] = None, play: Optional[bool] = None, legacy_ws=None):\n",
        "cmd: Optional[tuple] = None, play: Optional[bool] = None, legacy_ws=None,\n"
        "                        load: Optional[Dict[str, Any]] = None):   # cross-device-v1\n",
    ),
    # 2 the target is told to prepare THAT queue; the room itself changes only at commit,
    #   so a timeout or a dropped target leaves everything exactly as it was
    (
        "            for tws in list(target.sockets):\n"
        "                await self._send(tws, prepare)\n"
        "            return \"pending\", None\n",
        "            if load:                                          # cross-device-v1\n"
        "                prepare.update(position_ms=load[\"position_ms\"], track_id=load[\"track_id\"],\n"
        "                               queue=load[\"queue\"], queue_index=load[\"queue_index\"], play=True)\n"
        "                room.pending[\"load\"] = load\n"
        "            for tws in list(target.sockets):\n"
        "                await self._send(tws, prepare)\n"
        "            return \"pending\", None\n",
    ),
    # 3 nobody plays (or the host is gone): the target takes the queue at once
    (
        "        await self._commit_transfer(room, target, by_name, force=force, sender=sender)\n"
        "        return \"ok\", None\n",
        "        await self._commit_transfer(room, target, by_name, force=force, sender=sender, load=load)\n"
        "        return \"ok\", None\n",
    ),
    # 4 at commit the room takes on the queue that was loaded
    (
        "    async def _commit_transfer(self, room: Room, target: Device, by_name: str, *, force: bool = False,\n"
        "                               sender: Optional[Device] = None) -> None:\n",
        "    async def _commit_transfer(self, room: Room, target: Device, by_name: str, *, force: bool = False,\n"
        "                               sender: Optional[Device] = None, load: Optional[Dict[str, Any]] = None) -> None:\n",
    ),
    (
        "        room.pending = None\n"
        "        s[\"position_ms\"] = self._projected_position(room)       # hand the playhead over\n",
        "        room.pending = None\n"
        "        load = load or (pending or {}).get(\"load\")              # cross-device-v1\n"
        "        if load:\n"
        "            for k in (\"track_id\", \"queue\", \"queue_index\", \"track_title\", \"artist\", \"album\", \"cover_art_id\", \"duration_s\"):\n"
        "                s[k] = load[k]\n"
        "            s[\"position_ms\"], s[\"is_playing\"], s[\"updated_at\"] = load[\"position_ms\"], True, now\n"
        "        s[\"position_ms\"] = self._projected_position(room)       # hand the playhead over\n",
    ),
    # 5 the command
    (
        "        action = self._CMD_TYPES.get(kind)\n"
        "        if action is None:\n",
        "        if kind == \"playOn\":                  # cross-device-v1\n"
        "            status, reason = await self._play_on(room, ws, dev, cmd_id, args)\n"
        "            if status == \"pending\":\n"
        "                ack = await self._ack(room, ws, cmd_id, \"ok\", pending=True)\n"
        "            else:\n"
        "                ack = await self._ack(room, ws, cmd_id, status, reason)\n"
        "            room.cmds[cmd_id] = (self._clock(), ack)\n"
        "            return\n"
        "        action = self._CMD_TYPES.get(kind)\n"
        "        if action is None:\n",
    ),
    # 6 the work
    (
        "    async def _transfer(self, room: Room, sender: Device, target_id: str, *, force: bool = False,\n",
        "    # ── cross-device-v1: start a queue on any device ─────────────────────────\n"
        "\n"
        "    async def _play_on(self, room: Room, ws, sender: Device, cmd_id: str, args: Dict[str, Any]):\n"
        "        \"\"\"playOn{toDeviceId, queue, index, track_title?, artist?, album?, cover_art_id?, duration_s?}.\n"
        "        The target loads the queue first; the current host keeps playing until it says ready, then\n"
        "        the target takes over (one epoch bump, never two devices at once). If the target already\n"
        "        plays, it is simply told to start the queue. Returns (status, reason): ok | pending | rejected.\"\"\"\n"
        "        ids = args.get(\"queue\")\n"
        "        index = args.get(\"index\", 0)\n"
        "        if (not isinstance(ids, list) or not ids or len(ids) > MAX_QUEUE\n"
        "                or not all(isinstance(t, str) and 0 < len(t) <= 64 for t in ids)\n"
        "                or not isinstance(index, int) or isinstance(index, bool) or not 0 <= index < len(ids)):\n"
        "            return \"rejected\", \"bad_args\"\n"
        "        target = room.devices.get(str(args.get(\"toDeviceId\") or \"\"))\n"
        "        if target is None or not target.sockets:\n"
        "            return \"rejected\", \"device_offline\"\n"
        "        if target.proto < 3:\n"
        "            return \"rejected\", \"device_too_old\"\n"
        "        if room.state[\"active_device\"] == target.id:\n"
        "            ok, reason = await self._command(\n"
        "                room, ws, sender, {\"action\": \"set_queue\", \"queue\": ids, \"index\": index, \"target\": target.id}, reply=False)\n"
        "            return (\"ok\", None) if ok else (\"rejected\", reason)\n"
        "\n"
        "        def text(key: str, n: int = 200) -> Optional[str]:\n"
        "            v = args.get(key)\n"
        "            return v[:n] if isinstance(v, str) and v else None\n"
        "\n"
        "        dur = args.get(\"duration_s\")\n"
        "        load = {\"track_id\": ids[index], \"queue\": list(ids), \"queue_index\": index, \"position_ms\": 0,\n"
        "                \"track_title\": text(\"track_title\"), \"artist\": text(\"artist\"), \"album\": text(\"album\"),\n"
        "                \"cover_art_id\": text(\"cover_art_id\", 64),\n"
        "                \"duration_s\": float(dur) if isinstance(dur, (int, float)) and not isinstance(dur, bool) and dur >= 0 else 0.0}\n"
        "        # A person's gesture: it overrides the hysteresis, and an old epoch does not matter (the\n"
        "        # intent is absolute: this queue, on that device).\n"
        "        return await self._transfer(room, sender, target.id, force=True, cmd=(ws, cmd_id), play=True, load=load)\n"
        "\n"
        "    async def _transfer(self, room: Room, sender: Device, target_id: str, *, force: bool = False,\n",
    ),
]


def patch(path: str) -> int:
    with open(path, encoding="utf-8") as f:
        src = f.read()
    changed = 0
    for i, (old, new) in enumerate(PATCHES, 1):
        if new in src:
            continue
        n = src.count(old)
        if n != 1:
            print(f"!! cross-device-v1 edit {i}: expected its anchor once in {path}, found {n}; nothing written")
            return 1
        src = src.replace(old, new)
        changed += 1
    if changed:
        compile(src, path, "exec")
        with open(path, "w", encoding="utf-8") as f:
            f.write(src)
    print(f"   {path}: {changed} edit(s) applied, {len(PATCHES) - changed} already there")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(patch(sys.argv[1]))
