import json
import os
import secrets
import time
import urllib.parse
import urllib.request
from collections import deque

from flask import Flask, render_template, request, send_from_directory
from flask_socketio import SocketIO, join_room, leave_room, emit

app = Flask(__name__)
app.config["SECRET_KEY"] = os.environ.get("LOCO_SECRET_KEY") or secrets.token_hex(32)

socketio = SocketIO(app, cors_allowed_origins=[])

# Rooms stored in memory
rooms = {}
sid_rooms = {}

# ---- Chat limits (Phase One) ----
CHAT_MAX_LENGTH = 200      # characters per message
CHAT_RATE_LIMIT = 5        # messages ...
CHAT_RATE_WINDOW = 5.0     # ... per this many seconds
chat_times = {}            # sid -> deque of recent send times

WIN_LINES = [
    [0, 1, 2],
    [3, 4, 5],
    [6, 7, 8],
    [0, 3, 6],
    [1, 4, 7],
    [2, 5, 8],
    [0, 4, 8],
    [2, 4, 6]
]


def check_winner(board):
    for a, b, c in WIN_LINES:
        if board[a] and board[a] == board[b] == board[c]:
            return board[a]

    if "" not in board:
        return "draw"

    return None


def winning_line(board):
    """Cells of the winning line (used by the UI to highlight it)."""
    for a, b, c in WIN_LINES:
        if board[a] and board[a] == board[b] == board[c]:
            return [a, b, c]
    return []


def player_role(room, sid):
    return "X" if room["players"].index(sid) == 0 else "O"


def reset_board(room):
    room.pop("restart", None)
    room["board"] = [""] * 9
    room["turn"] = "X"
    room["winner"] = None


def room_data(code):
    room = rooms[code]

    return {
        "code": code,
        "board": room["board"],
        "turn": room["turn"],
        "winner": room["winner"],
        "line": winning_line(room["board"]),
        "players": len(room["players"]),
        "started": len(room["players"]) == 2
    }


def update_room(code, send_roles=False):
    if code not in rooms:
        return

    room = rooms[code]

    # Roles come from join order. When someone joins or leaves, the remaining
    # player's role can change (O becomes X), so tell every player again.
    if send_roles:
        for sid in room["players"]:
            socketio.emit(
                "your_role",
                {"role": player_role(room, sid)},
                to=sid
            )

    socketio.emit(
        "room_update",
        room_data(code),
        to=code
    )


def send_error(code, message):
    # "message" is kept for compatibility; "code" lets the UI translate it.
    emit("error_message", {"code": code, "message": message})


@app.route("/")
def home():
    return render_template("index.html")


@app.route("/favicon.ico")
def favicon():
    # Many browsers (and link previews) ask for /favicon.ico at the site root
    return send_from_directory(
        os.path.join(app.static_folder, "img"), "favicon.ico",
        mimetype="image/vnd.microsoft.icon", max_age=86400
    )


@socketio.on("join_game")
def handle_join(data):
    sid = request.sid

    if not isinstance(data, dict):
        send_error("invalid_code", "Invalid room code")
        return

    code = str(data.get("code", "")).upper().strip()

    if not code or len(code) > 12 or not (code.isascii() and code.isalnum()):
        send_error("invalid_code", "Invalid room code")
        return

    # Leave previous room if necessary
    old_code = sid_rooms.get(sid)
    if old_code and old_code != code:
        leave_old_room(old_code)

    if code not in rooms:
        rooms[code] = {
            "players": [],
            "board": [""] * 9,
            "turn": "X",
            "winner": None
        }

    room = rooms[code]

    if sid not in room["players"]:
        if len(room["players"]) >= 2:
            send_error("room_full", "This room is full!")
            return

        room["players"].append(sid)

    sid_rooms[sid] = code

    join_room(code)

    # Sends "your_role" to every player in the room, then "room_update"
    update_room(code, send_roles=True)


def leave_old_room(code):
    sid = request.sid
    leave_room(code)
    sid_rooms.pop(sid, None)
    chat_times.pop(sid, None)
    signal_times.pop(sid, None)

    room = rooms.get(code)
    if not room:
        return

    if sid in room["players"]:
        end_call(room, notify_sid=other_player(room, sid))
        room["players"].remove(sid)
        reset_board(room)

    if room["players"]:
        update_room(code, send_roles=True)
    else:
        del rooms[code]


@socketio.on("leave_game")
def handle_leave(data=None):
    """Return to lobby without reloading the page (keeps the music playing)."""
    code = sid_rooms.get(request.sid)

    if code:
        leave_old_room(code)


@socketio.on("make_move")
def handle_move(data):
    sid = request.sid
    code = sid_rooms.get(sid)

    if not code or code not in rooms:
        return

    room = rooms[code]

    if len(room["players"]) != 2:
        return

    if room["winner"]:
        return

    if sid not in room["players"]:
        return

    role = player_role(room, sid)

    if role != room["turn"]:
        return

    if not isinstance(data, dict):
        return

    try:
        index = int(data.get("index"))
    except (TypeError, ValueError):
        return

    if index < 0 or index > 8:
        return

    if room["board"][index] != "":
        return

    room["board"][index] = role

    result = check_winner(room["board"])

    if result:
        room["winner"] = result
    else:
        room["turn"] = "O" if role == "X" else "X"

    update_room(code)


# ---------- Restart needs the opponent's consent ----------
RESTART_TTL = 30.0         # seconds a restart request stays valid
RESTART_MIN_GAP = 3.0      # seconds between requests from the same player
restart_times = {}         # sid -> time of last request


@socketio.on("restart_request")
def handle_restart_request(data=None):
    sid = request.sid
    code = sid_rooms.get(sid)
    room = rooms.get(code) if code else None

    if not room or sid not in room["players"] or len(room["players"]) != 2:
        return

    # Nothing to restart on an empty board
    if all(cell == "" for cell in room["board"]):
        return

    now = time.monotonic()
    pending = room.get("restart")
    if pending and now - pending["at"] < RESTART_TTL:
        return

    if now - restart_times.get(sid, -RESTART_MIN_GAP) < RESTART_MIN_GAP:
        return
    restart_times[sid] = now

    room["restart"] = {"by": sid, "at": now}
    socketio.emit("restart_requested", {}, to=other_player(room, sid))


@socketio.on("restart_response")
def handle_restart_response(data):
    sid = request.sid
    code = sid_rooms.get(sid)
    room = rooms.get(code) if code else None

    if not room or sid not in room["players"] or not isinstance(data, dict):
        return

    pending = room.get("restart")
    if not pending or pending["by"] == sid:
        return                       # only the OTHER player may answer
    if time.monotonic() - pending["at"] >= RESTART_TTL:
        room.pop("restart", None)
        return

    requester = pending["by"]
    room.pop("restart", None)

    if data.get("accept") is True:
        reset_board(room)
        update_room(code)
    else:
        socketio.emit("restart_declined", {}, to=requester)


# ---- Voice chat (Phase Two) ----
# ICE servers are configured with environment variables (see README.md):
#   LOCO_STUN_URLS        comma separated, default: stun:stun.l.google.com:19302
#   LOCO_TURN_URLS        comma separated, e.g. turn:turn.example.com:3478,turns:turn.example.com:5349
#   LOCO_TURN_USERNAME / LOCO_TURN_CREDENTIAL
SIGNAL_MAX_SDP = 20000     # characters
SIGNAL_MAX_ICE = 2000      # characters of one ICE candidate
SIGNAL_RATE_LIMIT = 120    # signaling events ...
SIGNAL_RATE_WINDOW = 10.0  # ... per this many seconds
signal_times = {}          # sid -> deque of recent signaling times


ICE_CACHE_SECONDS = 3000      # managed TURN credentials are valid for 24 h
ICE_RETRY_SECONDS = 30        # after a provider error, try again soon
_ice_cache = {"servers": None, "until": 0.0}


def _get_json(req, timeout=3):
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def fetch_cloudflare_turn():
    """Cloudflare Realtime TURN: short-lived credentials minted by the server."""
    key_id = os.environ.get("LOCO_CF_TURN_KEY_ID", "").strip()
    token = os.environ.get("LOCO_CF_TURN_API_TOKEN", "").strip()
    if not key_id or not token:
        return []

    req = urllib.request.Request(
        "https://rtc.live.cloudflare.com/v1/turn/keys/%s/credentials/generate-ice-servers"
        % urllib.parse.quote(key_id, safe=""),
        data=json.dumps({"ttl": 86400}).encode("utf-8"),
        headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"},
        method="POST"
    )
    data = _get_json(req)

    servers = data.get("iceServers") if isinstance(data, dict) else None
    if isinstance(servers, dict):
        servers = [servers]

    clean = []
    for entry in servers or []:
        urls = entry.get("urls")
        if isinstance(urls, str):
            urls = [urls]
        # Browsers block port 53, so skip those URLs
        urls = [u for u in (urls or []) if isinstance(u, str) and ":53" not in u]
        if not urls:
            continue
        item = {"urls": urls}
        if entry.get("username"):
            item["username"] = entry["username"]
            item["credential"] = entry.get("credential", "")
        clean.append(item)
    return clean


def fetch_metered_turn():
    """Metered.ca TURN: the API key stays on the server."""
    domain = os.environ.get("LOCO_METERED_DOMAIN", "").strip()
    api_key = os.environ.get("LOCO_METERED_API_KEY", "").strip()
    if not domain or not api_key:
        return []

    domain = domain.replace("https://", "").replace("http://", "").strip("/")
    url = "https://%s/api/v1/turn/credentials?apiKey=%s" % (domain, urllib.parse.quote(api_key, safe=""))
    data = _get_json(urllib.request.Request(url))

    return [e for e in data if isinstance(e, dict) and e.get("urls")] if isinstance(data, list) else []


def ice_servers():
    now = time.monotonic()
    if _ice_cache["servers"] is not None and now < _ice_cache["until"]:
        return _ice_cache["servers"]

    stun = os.environ.get(
        "LOCO_STUN_URLS",
        "stun:stun.l.google.com:19302,stun:stun.cloudflare.com:3478"
    )
    servers = []

    stun_urls = [u.strip() for u in stun.split(",") if u.strip()]
    if stun_urls:
        servers.append({"urls": stun_urls})

    failed = False
    for fetcher in (fetch_cloudflare_turn, fetch_metered_turn):
        try:
            servers.extend(fetcher())
        except Exception as exc:       # network error, bad key, ...
            failed = True
            app.logger.warning("TURN provider %s failed: %s", fetcher.__name__, exc)

    turn_urls = [u.strip() for u in os.environ.get("LOCO_TURN_URLS", "").split(",") if u.strip()]
    if turn_urls:
        servers.append({
            "urls": turn_urls,
            "username": os.environ.get("LOCO_TURN_USERNAME", ""),
            "credential": os.environ.get("LOCO_TURN_CREDENTIAL", "")
        })

    _ice_cache["servers"] = servers
    _ice_cache["until"] = now + (ICE_RETRY_SECONDS if failed else ICE_CACHE_SECONDS)
    return servers


def has_turn(servers):
    for entry in servers:
        urls = entry.get("urls", [])
        if isinstance(urls, str):
            urls = [urls]
        if any(u.startswith(("turn:", "turns:")) for u in urls):
            return True
    return False


def other_player(room, sid):
    for other in room["players"]:
        if other != sid:
            return other
    return None


def end_call(room, notify_sid=None):
    """Forget the call of a room; optionally tell one player it ended."""
    had_call = room.pop("call", None) is not None
    if had_call and notify_sid:
        socketio.emit("voice_ended", {}, to=notify_sid)


def voice_context(sid, need_call=False):
    """Return (room, other_sid) if sid is a player in a 2-player room, else None."""
    code = sid_rooms.get(sid)
    room = rooms.get(code) if code else None

    if not room or sid not in room["players"] or len(room["players"]) != 2:
        return None
    # Count every signaling event first, so spam is limited even without a call
    now = time.monotonic()
    times = signal_times.setdefault(sid, deque())
    while times and now - times[0] > SIGNAL_RATE_WINDOW:
        times.popleft()
    if len(times) >= SIGNAL_RATE_LIMIT:
        return None
    times.append(now)

    if need_call and not room.get("call"):
        return None

    return room, other_player(room, sid)


@socketio.on("chat_message")
def handle_chat(data):
    sid = request.sid
    code = sid_rooms.get(sid)

    # Only a player who is really inside this room may chat in it
    if not code or code not in rooms or sid not in rooms[code]["players"]:
        send_error("not_in_room", "You are not in a room")
        return

    if not isinstance(data, dict):
        return

    text = data.get("text")

    if not isinstance(text, str):
        return

    # Remove control characters, trim, collapse line breaks into spaces
    text = "".join(ch if ch.isprintable() else " " for ch in text)
    text = " ".join(text.split())

    if not text:
        return

    if len(text) > CHAT_MAX_LENGTH:
        send_error("chat_too_long", "Message is too long")
        return

    # Rate limit: at most CHAT_RATE_LIMIT messages per CHAT_RATE_WINDOW seconds
    now = time.monotonic()
    times = chat_times.setdefault(sid, deque())

    while times and now - times[0] > CHAT_RATE_WINDOW:
        times.popleft()

    if len(times) >= CHAT_RATE_LIMIT:
        send_error("chat_rate", "You are sending messages too fast")
        return

    times.append(now)

    # The sender's symbol comes from the server, never from the client
    socketio.emit(
        "chat_message",
        {
            "role": player_role(rooms[code], sid),
            "text": text,
            "ts": int(time.time() * 1000)
        },
        to=code
    )


# ---------- Voice signaling (WebRTC). The server only relays; audio never touches it. ----------
@socketio.on("voice_config")
def handle_voice_config(data=None):
    ctx = voice_context(request.sid)
    if not ctx:
        return {"ok": False}
    servers = ice_servers()
    return {"ok": True, "iceServers": servers, "hasTurn": has_turn(servers)}


@socketio.on("voice_invite")
def handle_voice_invite(data=None):
    ctx = voice_context(request.sid)
    if not ctx:
        return
    room, other = ctx
    if room.get("call"):
        return

    room["call"] = {"caller": request.sid, "state": "ringing"}
    socketio.emit("voice_incoming", {}, to=other)


@socketio.on("voice_accept")
def handle_voice_accept(data=None):
    ctx = voice_context(request.sid, need_call=True)
    if not ctx:
        return
    room, other = ctx
    call = room["call"]

    # Only the invited player can accept, and only while it is ringing
    if call["state"] != "ringing" or call["caller"] == request.sid:
        return

    call["state"] = "active"
    socketio.emit("voice_accepted", {}, to=other)


@socketio.on("voice_reject")
def handle_voice_reject(data=None):
    ctx = voice_context(request.sid, need_call=True)
    if not ctx:
        return
    room, other = ctx
    call = room["call"]

    if call["state"] != "ringing" or call["caller"] == request.sid:
        return

    end_call(room)
    socketio.emit("voice_rejected", {}, to=other)


@socketio.on("voice_end")
def handle_voice_end(data=None):
    ctx = voice_context(request.sid, need_call=True)
    if not ctx:
        return
    room, other = ctx
    end_call(room, notify_sid=other)


def relay_description(event, data, expected_type, from_caller):
    ctx = voice_context(request.sid, need_call=True)
    if not ctx:
        return
    room, other = ctx
    call = room["call"]

    if call["state"] != "active":
        return
    if (call["caller"] == request.sid) != from_caller:
        return

    if not isinstance(data, dict) or not isinstance(data.get("sdp"), dict):
        return
    sdp = data["sdp"]
    if sdp.get("type") != expected_type or not isinstance(sdp.get("sdp"), str):
        return
    if len(sdp["sdp"]) > SIGNAL_MAX_SDP:
        return

    socketio.emit(event, {"sdp": {"type": expected_type, "sdp": sdp["sdp"]}}, to=other)


@socketio.on("voice_offer")
def handle_voice_offer(data):
    relay_description("voice_offer", data, "offer", from_caller=True)


@socketio.on("voice_answer")
def handle_voice_answer(data):
    relay_description("voice_answer", data, "answer", from_caller=False)


@socketio.on("voice_ice")
def handle_voice_ice(data):
    ctx = voice_context(request.sid, need_call=True)
    if not ctx:
        return
    room, other = ctx

    if room["call"]["state"] != "active":
        return
    if not isinstance(data, dict):
        return

    cand = data.get("candidate")
    if cand is not None:
        if not isinstance(cand, dict) or not isinstance(cand.get("candidate"), str):
            return
        if len(cand["candidate"]) > SIGNAL_MAX_ICE:
            return
        clean = {"candidate": cand["candidate"]}
        if isinstance(cand.get("sdpMid"), str):
            clean["sdpMid"] = cand["sdpMid"][:64]
        if isinstance(cand.get("sdpMLineIndex"), int):
            clean["sdpMLineIndex"] = cand["sdpMLineIndex"]
        cand = clean

    socketio.emit("voice_ice", {"candidate": cand}, to=other)


@socketio.on("disconnect")
def handle_disconnect():
    sid = request.sid
    code = sid_rooms.pop(sid, None)
    chat_times.pop(sid, None)
    signal_times.pop(sid, None)
    restart_times.pop(sid, None)

    if not code or code not in rooms:
        return

    room = rooms[code]

    if sid in room["players"]:
        end_call(room, notify_sid=other_player(room, sid))
        room["players"].remove(sid)

    reset_board(room)

    update_room(code, send_roles=True)

    if not room["players"]:
        del rooms[code]


if __name__ == "__main__":
    # Optional HTTPS (needed for the microphone when not on localhost):
    #   LOCO_SSL_CERT=cert.pem LOCO_SSL_KEY=key.pem python app.py
    # For real deployments, put the app behind an HTTPS reverse proxy (see README.md).
    cert = os.environ.get("LOCO_SSL_CERT")
    key = os.environ.get("LOCO_SSL_KEY")
    extra = {"ssl_context": (cert, key)} if cert and key else {}

    socketio.run(
        app,
        host=os.environ.get("LOCO_HOST", "0.0.0.0"),
        port=int(os.environ.get("LOCO_PORT", "5000")),
        debug=os.environ.get("LOCO_DEBUG", "1") == "1",
        allow_unsafe_werkzeug=True,
        **extra
    )
