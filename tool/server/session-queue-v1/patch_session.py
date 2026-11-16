"""
session-queue-v1: small queue edits from any of a user's devices (protocol 4).

Patches navivibe/session.py in place with exact-match, idempotent edits:
each edit is applied only if its old text is there exactly once, and skipped
if its new text is already there. Anything else stops the run unchanged.

    python -I patch_session.py /opt/shuffle-server/navivibe/session.py
"""

import sys

MARK = "# session-queue-v1"

PATCHES = [
    # 1 the protocol notes at the top of the file
    (
        "Clients that don't send proto=2 only ever receive `state` and `pong`, so older\n"
        "app builds keep working unchanged.\n",
        "Clients that don't send proto=2 only ever receive `state` and `pong`, so older\n"
        "app builds keep working unchanged.\n"
        "\n"
        "Protocol 4 (session-queue-v1): any device edits the host's queue with small\n"
        "acked commands, cmd{cmdType, args, baseVersion}:\n"
        "  queue_insert          {track_ids, position: \"next\"|\"end\"|int, after_id?}\n"
        "  queue_remove          {index, track_id}\n"
        "  queue_move            {from, to, track_id}\n"
        "  queue_clear_upcoming  {}\n"
        "The server checks each edit against the host's queue. An edit made on an\n"
        "older view (baseVersion behind) is rebased by its track ids; one that can't\n"
        "be placed any more is answered `stale`. The room's queue changes at once\n"
        "(every device sees it), and the host gets a `command` with the resolved\n"
        "indices to apply to its player. A host that reports `queue_locked` (its\n"
        "queue follows a Jam) refuses edits with `queue_locked`. set_queue stays.\n",
    ),
    # 2 protocol 4 is the one that speaks queue edits
    (
        "MAX_PROTO = 3\n",
        "MAX_PROTO = 4\n"
        "QUEUE_PROTO = 4                      # " + "session-queue-v1: a host must speak this to take queue edits\n"
        "MAX_QUEUE_INSERT = 200               # songs one queue_insert may add\n",
    ),
    # 3 the host says when its queue follows a Jam
    (
        '    "duration_s", "position_ms", "is_playing", "queue", "queue_index",\n}\n',
        '    "duration_s", "position_ms", "is_playing", "queue", "queue_index",\n'
        '    "queue_locked",                   # session-queue-v1: the host\'s queue follows a Jam\n}\n'
        "QUEUE_CMD_TYPES = {                  # session-queue-v1\n"
        '    "queue_insert": "queue_insert", "queueInsert": "queue_insert",\n'
        '    "queue_remove": "queue_remove", "queueRemove": "queue_remove",\n'
        '    "queue_move": "queue_move", "queueMove": "queue_move",\n'
        '    "queue_clear_upcoming": "queue_clear_upcoming", "queueClearUpcoming": "queue_clear_upcoming",\n'
        "}\n",
    ),
    (
        '        "queue_index": 0,\n        "updated_at": None,\n    }\n',
        '        "queue_index": 0,\n        "queue_locked": None,\n        "updated_at": None,\n    }\n',
    ),
    # 4 queue commands are routed before the play/pause table
    (
        "        action = self._CMD_TYPES.get(kind)\n"
        "        if action is None:\n",
        "        if kind in QUEUE_CMD_TYPES:          # " + "session-queue-v1\n"
        "            base = data.get(\"baseVersion\", args.get(\"baseVersion\"))\n"
        "            status, reason, extra = await self._queue_edit(\n"
        "                room, dev, QUEUE_CMD_TYPES[kind], args, base if isinstance(base, int) and not isinstance(base, bool) else None, cmd_id)\n"
        "            ack = await self._ack(room, ws, cmd_id, status, reason, **extra)\n"
        "            room.cmds[cmd_id] = (self._clock(), ack)\n"
        "            return\n"
        "        action = self._CMD_TYPES.get(kind)\n"
        "        if action is None:\n",
    ),
    # 5 the edit itself
    (
        "    async def _transfer(self, room: Room, sender: Device, target_id: str, *, force: bool = False,\n",
        "    # ── proto 4: queue edits from any device (" + "session-queue-v1) ─────────\n"
        "\n"
        "    @staticmethod\n"
        "    def _int(v) -> Optional[int]:\n"
        "        return v if isinstance(v, int) and not isinstance(v, bool) else None\n"
        "\n"
        "    @staticmethod\n"
        "    def _locate(queue: List[Any], index: Optional[int], track_id: Any) -> Optional[int]:\n"
        "        \"\"\"Where `track_id` is now: at `index` if it is still there, else its one\n"
        "        place in the queue. None when it is gone or there twice (can't tell which).\"\"\"\n"
        "        if not isinstance(track_id, str) or not track_id:\n"
        "            return None\n"
        "        if index is not None and 0 <= index < len(queue) and queue[index] == track_id:\n"
        "            return index\n"
        "        found = [i for i, t in enumerate(queue) if t == track_id]\n"
        "        return found[0] if len(found) == 1 else None\n"
        "\n"
        "    async def _queue_edit(self, room: Room, sender: Device, action: str, args: Dict[str, Any],\n"
        "                          base_version: Optional[int], cmd_id: str = \"\"):\n"
        "        \"\"\"Check one queue edit against the host's queue, rebase it if the sender saw an\n"
        "        older one, apply it to the room, send it to the host, broadcast. Returns\n"
        "        (status, reason, ack extras): ok | stale | rejected.\"\"\"\n"
        "        s = room.state\n"
        "        host_id = s[\"active_device\"]\n"
        "        if not host_id:\n"
        "            return \"rejected\", \"no_active_device\", {}\n"
        "        host = room.devices.get(host_id)\n"
        "        if host is None or not host.sockets:\n"
        "            return \"rejected\", \"device_offline\", {}\n"
        "        if host.proto < QUEUE_PROTO:\n"
        "            return \"rejected\", \"device_too_old\", {}\n"
        "        if s.get(\"queue_locked\"):\n"
        "            return \"rejected\", \"queue_locked\", {}\n"
        "        queue = [str(t) for t in (s[\"queue\"] or [])]\n"
        "        cur = self._int(s[\"queue_index\"]) or 0\n"
        "        cur = min(max(cur, 0), max(len(queue) - 1, 0))\n"
        "        fresh = base_version is not None and base_version == room.version\n"
        "        out: Dict[str, Any] = {\"type\": \"command\", \"action\": action,\n"
        "                               \"from_device\": sender.id, \"from_name\": sender.name}\n"
        "\n"
        "        if action == \"queue_insert\":\n"
        "            ids = args.get(\"track_ids\")\n"
        "            if (not isinstance(ids, list) or not ids or len(ids) > MAX_QUEUE_INSERT\n"
        "                    or not all(isinstance(t, str) and 0 < len(t) <= 64 for t in ids)):\n"
        "                return \"rejected\", \"bad_args\", {}\n"
        "            if len(queue) + len(ids) > MAX_QUEUE:\n"
        "                return \"rejected\", \"queue_full\", {}\n"
        "            pos = args.get(\"position\", \"end\")\n"
        "            if pos == \"next\":\n"
        "                at = cur + 1 if queue else 0\n"
        "            elif pos == \"end\":\n"
        "                at = len(queue)\n"
        "            elif self._int(pos) is not None:\n"
        "                # The song the drop landed under (none: the very top) places it best;\n"
        "                # the bare index is trusted only on the version the sender saw.\n"
        "                after = args.get(\"after_id\")\n"
        "                i = self._locate(queue, pos - 1, after) if after is not None else None\n"
        "                if \"after_id\" in args and after is None:\n"
        "                    at = 0\n"
        "                elif i is not None:\n"
        "                    at = i + 1\n"
        "                elif fresh:\n"
        "                    at = pos\n"
        "                else:\n"
        "                    return \"stale\", \"queue_changed\", {}\n"
        "                if not 0 <= at <= len(queue):\n"
        "                    return \"rejected\", \"bad_args\", {}\n"
        "            else:\n"
        "                return \"rejected\", \"bad_args\", {}\n"
        "            queue[at:at] = ids\n"
        "            if len(queue) > len(ids) and at <= cur:\n"
        "                cur += len(ids)\n"
        "            out.update(track_ids=ids, index=at)\n"
        "\n"
        "        elif action == \"queue_remove\":\n"
        "            i = self._locate(queue, self._int(args.get(\"index\")), args.get(\"track_id\"))\n"
        "            if i is None:\n"
        "                return \"stale\", \"queue_changed\", {}\n"
        "            if i == cur:\n"
        "                return \"rejected\", \"is_current\", {}\n"
        "            del queue[i]\n"
        "            if i < cur:\n"
        "                cur -= 1\n"
        "            out.update(index=i, track_id=args[\"track_id\"])\n"
        "\n"
        "        elif action == \"queue_move\":\n"
        "            to = self._int(args.get(\"to\"))\n"
        "            if to is None:\n"
        "                return \"rejected\", \"bad_args\", {}\n"
        "            i = self._locate(queue, self._int(args.get(\"from\")), args.get(\"track_id\"))\n"
        "            if i is None:\n"
        "                return \"stale\", \"queue_changed\", {}\n"
        "            if not 0 <= to < len(queue):\n"
        "                if fresh:\n"
        "                    return \"rejected\", \"bad_args\", {}\n"
        "                to = min(max(to, 0), len(queue) - 1)   # the queue shrank meanwhile\n"
        "            if i == to:\n"
        "                return \"ok\", None, {}\n"
        "            queue.insert(to, queue.pop(i))\n"
        "            if i == cur:\n"
        "                cur = to\n"
        "            elif i < cur <= to:\n"
        "                cur -= 1\n"
        "            elif to <= cur < i:\n"
        "                cur += 1\n"
        "            out.update(**{\"from\": i, \"to\": to, \"track_id\": args[\"track_id\"]})\n"
        "\n"
        "        elif action == \"queue_clear_upcoming\":\n"
        "            if cur + 1 >= len(queue):\n"
        "                return \"ok\", None, {}\n"
        "            out.update(index=cur, track_id=queue[cur])\n"
        "            queue = queue[:cur + 1]\n"
        "\n"
        "        else:\n"
        "            return \"rejected\", \"unknown_type\", {}\n"
        "\n"
        "        s[\"queue\"] = queue\n"
        "        s[\"queue_index\"] = cur\n"
        "        for tws in list(host.sockets):\n"
        "            await self._send(tws, out)\n"
        "        # cmdId lets the sender retire its optimistic copy of this edit with this very state.\n"
        "        await self.broadcast_state(room, caused_by={\"deviceId\": sender.id, \"cmdId\": cmd_id})\n"
        "        return \"ok\", None, {}\n"
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
            print(f"!! session-queue-v1 edit {i}: expected its anchor once in {path}, found {n}; nothing written")
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
