# Samsung The Frame: control protocol spec (big-remote-control)

Status: research spec, written 2026-10-29. **Nothing here has been sent to the
TVs yet.** The only live data is one read-only `GET :8001/api/v2/` on the 32"
set. Treat every payload as "known to work on other Frames per the cited
code"; verify each one in the live session.

Confidence tags used below:

- **[V]** verified on our TV (read-only GET only)
- **[C]** confirmed in maintained open-source code (samsungtvws, Home
  Assistant, NickWaterton fork, homebridge-smartthings-tv, reference repo)
- **[R]** community reports only; may not work on our firmware
- **[?]** unknown / guess; test before relying on it

## 0. Target devices

> IPs, MACs and DUIDs in this document are documentation examples (`192.168.1.x`, `02:00:00:…`), not the real devices.

| | tv-samsung-32 | smarttv-samsung-43 |
|---|---|---|
| IP | 192.168.1.20 | 192.168.1.21 |
| modelName | QN32LS03CBGXZD (LS03C, 2023) | QN43LS03DAGXZD (LS03D, 2024) |
| model | 23_KSUE_FTV_T09 | 24_PTM_FTV_T09 |
| Tizen (by model year) | 7.0 [?] | 8.0 [?] |
| Panel | 1920x1080 | 4K |
| Network | wireless, wifiMac 02:00:00:00:00:20 | wired, MAC 02:00:00:00:00:21 |
| API | 2.0.25, TokenAuthSupport true, FrameTVSupport true | 2.0.25 (per task brief) |
| Locale | pt_BR, countryCode BR | pt_BR |

Live observation 2026-10-29 [V]: `.42` answered `PowerState: "on"`,
`ImeSyncedSupport: "true"`, `developerMode: "0"`, `firmwareVersion: "Unknown"`.
`.43` did **not answer** `GET :8001/api/v2/` within 4 s (it was in standby).
So in deep standby the REST API can be unreachable: the app must treat
"no answer" as `off/standby`, not as an error.

Sources:

- Reference repo: victaphu/glass-home-samsung-tv (`tools/tvremote.py`,
  `tools/wake.py`, `docs/SAMSUNG-SETTINGS.md`)
- `samsungtvws` (xchwarze/samsung-tv-ws-api, master as of 2026-09):
  `connection.py`, `remote.py`, `rest.py`, `art/art.py`, `COMMANDS.md`,
  `APPLICATIONS.md`
- NickWaterton/samsung-tv-ws-api (`samsungframetv`): `async_art.py`,
  `ipcontrol.py`, README "Art mode by model" (most up-to-date Frame notes)
- Home Assistant `components/samsungtv/bridge.py` (power-off logic) and the
  SmartThings test fixture `vd_stv_2017_k.json`
- pysmartthings `capability.py` / `command.py` / `attribute.py`
- homebridge-smartthings-tv 3.0.10 (`tvAccessory.js`, OAuth docs)
- SmartThings docs + community thread "Changes To Personal Access Tokens"

---

## 1. Discovery and device info

### 1.1 REST device info (no auth, no popup) [V]

```
GET http://<ip>:8001/api/v2/
```

Response (trimmed, real data from .42):

```json
{
  "device": {
    "FrameTVSupport": "true",
    "ImeSyncedSupport": "true",
    "Language": "pt_BR",
    "OS": "Tizen",
    "PowerState": "on",
    "TokenAuthSupport": "true",
    "countryCode": "BR",
    "developerMode": "0",
    "duid": "uuid:00000000-0000-0000-0000-000000000020",
    "id": "uuid:00000000-0000-0000-0000-000000000020",
    "ip": "192.168.1.20",
    "model": "23_KSUE_FTV_T09",
    "modelName": "QN32LS03CBGXZD",
    "name": "tv-samsung-32",
    "networkType": "wireless",
    "resolution": "1920x1080",
    "wifiMac": "02:00:00:00:00:20",
    "type": "Samsung SmartTV"
  },
  "isSupport": "{\"FrameTVSupport\":\"true\",\"remote_available\":\"true\",...}\n",
  "name": "tv-samsung-32",
  "remote": "1.0",
  "uri": "http://192.168.1.20:8001/api/v2/",
  "version": "2.0.25"
}
```

Gotchas:

- All booleans are **strings** (`"true"`/`"false"`). `isSupport` is a
  **JSON string inside JSON** (with a trailing `\n`); decode it a second time.
- `PowerState` values seen: `"on"`, `"standby"`. Home Assistant uses
  `PowerState == "on"` as its on-check [C]. Nick Waterton reports that 2025
  Frames report `standby` while in art mode [R]. Our 2023/2024 sets should
  report `on` in art mode, but **verify** on both.
- When the TV is in deep standby the request may time out (seen on .43).
  Use a short timeout (1.5-3 s) and map timeout to `unreachable`.
- `wifiMac` is the Wi-Fi MAC. A wired TV still reports `wifiMac` (the Wi-Fi
  chip's MAC); for Wake-on-LAN use the MAC of the interface actually in use
  (.43 = wired `02:00:00:00:00:21`).
- Same info is available over TLS: `GET https://<ip>:8002/api/v2/` [C].

Polling rule: `GET /api/v2/` is cheap and does not show any popup. Poll every
5-10 s for power state. Do **not** open a WebSocket only to probe power: HA
notes "on some TVs, opening a websocket turns on the TV" [C].

### 1.2 SSDP / mDNS (optional) [?]

Not needed: we know the IPs. If auto-discovery is wanted later:

- SSDP M-SEARCH to `239.255.255.250:1900` with
  `ST: urn:samsung.com:device:RemoteControlReceiver:1` (also answers
  `urn:dial-multiscreen-org:service:dial:1`). Then `GET :8001/api/v2/` on
  each responder and keep those with `"type": "Samsung SmartTV"`. [R]
- mDNS: Samsung 2018+ TVs advertise `_airplay._tcp` (AirPlay 2) and
  possibly `_samsungmsf._tcp` [?]. Not reliable for identification.
- Pragmatic approach: let the user enter the IP, or scan the /24 with a
  `GET :8001/api/v2/` probe (300 ms timeout each, concurrent).

Recommend DHCP reservations for both TVs on the router.

---

## 2. Remote control channel (WebSocket)

### 2.1 URL

```
wss://<ip>:8002/api/v2/channels/samsung.remote.control?name=<b64name>&token=<token>
```

- `name` = standard base64 of the UTF-8 client name, e.g. "Big Remote" ->
  `QmlnIFJlbW90ZQ==`. **Percent-encode** the value (`=` -> `%3D`, `+` -> `%2B`,
  `/` -> `%2F`). [C]
- Omit `&token=` on first connect. [C]
- Port 8002 = TLS with a **self-signed** cert. Accept it (pin the leaf cert
  fingerprint after first connect if you want TOFU safety). [C]
- Port 8001 `ws://` also exists but on TokenAuthSupport TVs it does not
  return/accept a token; samsungtvws only sends the token on 8002. Use 8002. [C]
- The token is bound to the TV and (in practice) the client name. Changing the
  name triggers a new Allow prompt [R]. Keep the name constant. Store **one
  token per TV** (Nick Waterton: "use a separate token file for each TV") [C].

### 2.2 Connect / pairing sequence [C]

1. Open the socket.
2. First time: TV shows "Allow <name> to connect?" on screen. User presses
   Allow with the physical remote. Wait up to 30-60 s (HA uses 31 s,
   reference tool 45 s, Nick's fork 60 s with no token).
3. Read frames until you get one of:

```json
{"event":"ms.channel.connect","data":{"id":"...","clients":[...],"token":"12345678"}}
```

-> connected. Save `data.token` if present and different from the stored one.
**Token type**: normally a numeric string, but a test fixture has it as a JSON
number (`"token": 123456789`). Decode both.

```json
{"event":"ms.channel.unauthorized"}
```

-> user pressed Deny, or the TV has the client blocked. Tell the user to go to
Settings > General > External Device Manager > Device Connection Manager >
Device List and allow it.

```json
{"event":"ms.channel.timeOut"}
```

-> token missing/stale/for another TV, or Allow not pressed in time, or TV
asleep. Clear token and re-pair.

4. Ignore at startup: `ed.edenTV.update`, `ms.voiceApp.hide` [C]. Other
events you may see any time: `ms.channel.clientConnect`,
`ms.channel.clientDisconnect`, `ms.remote.imeStart`, `ms.remote.imeEnd`,
`ms.remote.imeUpdate`, `ms.remote.touchEnable`, `ms.error`.

TV setting that controls the prompt: Settings > General > External Device
Manager > Device Connection Manager > Access Notification ("First Time Only"
recommended). [R: menu path varies by year]

TVs can forget tokens after a long power-off [R]; handle `ms.channel.timeOut`
by re-pairing, not by crashing.

### 2.3 Key press [C]

```json
{"method":"ms.remote.control","params":{
  "Cmd":"Click","DataOfCmd":"KEY_VOLUP","Option":"false","TypeOfRemote":"SendRemoteKey"}}
```

- `Cmd`: `"Click"` (press+release), `"Press"` (key down), `"Release"`
  (key up). Hold = `Press`, sleep N s, `Release`. [C]
- `Option` is the **string** `"false"`.
- No response is sent for a key. Errors come as
  `{"event":"ms.error","data":{"message":"..."}}`.
- Pace keys: libraries use 0.6-1.2 s between keys by default; 0.15-0.2 s works
  for navigation [C]. Use ~150 ms for arrow repeat, ~500 ms after HOME/MENU.
- Keep one long-lived socket per TV; the TV sends WS pings, answer with pongs
  (URLSession does this automatically).
- Reference tool note: per-read socket timeouts never fire because the TV
  pings regularly; use a hard deadline for "wait for answer" logic.

Mouse/pointer (optional) [C]:

```json
{"method":"ms.remote.control","params":{
  "Cmd":"Move","Position":{"x":10,"y":0,"Time":"0"},"TypeOfRemote":"ProcessMouseDevice"}}
```

Our TV reports `mouseWheelSupport: "false"`; pointer is browser-only. Low
priority.

### 2.4 Useful KEY_ codes

Not an official list; support varies by model [C: samsungtvws COMMANDS.md].

| Group | Keys |
|---|---|
| Power | `KEY_POWER` (see 2.5), `KEY_POWEROFF` [R: ignored by many Tizen sets] |
| Volume | `KEY_VOLUP`, `KEY_VOLDOWN`, `KEY_MUTE` |
| Navigation | `KEY_UP`, `KEY_DOWN`, `KEY_LEFT`, `KEY_RIGHT`, `KEY_ENTER`, `KEY_RETURN` (Back), `KEY_EXIT` (closes all menus) |
| Menus | `KEY_HOME` (Smart Hub), `KEY_MENU` (All Settings directly), `KEY_TOOLS`, `KEY_INFO`, `KEY_GUIDE`, `KEY_CONTENTS`, `KEY_APP_LIST` [?] |
| Source | `KEY_SOURCE` (source picker), `KEY_HDMI` (cycles HDMI), `KEY_HDMI1`..`KEY_HDMI4` [R: often ignored on Tizen], `KEY_TV`, `KEY_DTV` |
| Channel | `KEY_CHUP`, `KEY_CHDOWN`, `KEY_PRECH`, `KEY_CH_LIST`, `KEY_FAVCH` |
| Digits | `KEY_0`..`KEY_9` (channel N = digits then `KEY_ENTER`) |
| Media | `KEY_PLAY`, `KEY_PAUSE`, `KEY_STOP`, `KEY_FF`, `KEY_REWIND`, `KEY_REC` |
| Colour | `KEY_RED`, `KEY_GREEN`, `KEY_YELLOW`, `KEY_BLUE` |
| Picture | `KEY_PMODE` (picture mode cycle) [?], `KEY_PICTURE_SIZE` [?], `KEY_ASPECT` [?] |
| Frame | `KEY_AMBIENT` (listed in samsungtvws; on Frames may toggle Art Mode) [?] |
| Misc | `KEY_CAPTION` (subtitles) [?], `KEY_SLEEP` [?], `KEY_AD` (audio description) [?] |
| **Never** | `KEY_FACTORY` (service menu, can misconfigure TV). Block it in the app. |

There is no single "play/pause toggle" key that works everywhere;
`KEY_PLAY`/`KEY_PAUSE` work in most apps, `KEY_ENTER` toggles in YouTube.

### 2.5 Power semantics on The Frame (important)

Frame power states: **Off** (real standby, screen black), **Art Mode**
(screen shows art, network up), **TV** (normal).

| Action | 2023/2024 Frame behaviour |
|---|---|
| `KEY_POWER` Click while in TV | -> Art Mode (not off) [C/R] |
| `KEY_POWER` Click while in Art Mode | -> TV [R] |
| `KEY_POWER` hold 3 s (`Press`, 3 s, `Release`) | -> real Off [C: HA uses exactly this when `FrameTVSupport == "true"`] |
| 2025 Frames | hold does **not** power off (issue #29); not our models [R] |

Home Assistant `bridge.py` [C]:

```python
if self._get_device_spec("FrameTVSupport") == "true":
    await self._async_send_commands(SendRemoteKey.hold("KEY_POWER", 3))
else:
    await self._async_send_commands([SendRemoteKey.click("KEY_POWER")])
```

Power-on:

- From Art Mode: TV is awake on the network. Send `KEY_POWER` Click, or
  `set_artmode_status off` on the art channel (section 6), or SmartThings
  `switch on`.
- From real Off: WebSocket is not reachable. Use Wake-on-LAN (section 5) or
  SmartThings `switch on` (cloud can wake it if "Power On with Mobile" is on).
  After WoL the TV may come up in Art Mode or TV mode depending on its
  setting; then fix the mode via art channel.

App "power" button UX proposal: three explicit actions, "TV", "Art", "Off";
not a toggle. Determine current state before sending anything (section 6.6).

### 2.6 Alternative power/input path: Samsung IP Control (port 1516) [C/R]

Nick Waterton's fork (Oct 2026) documents **IP Control**: JSON-RPC 2.0 over
HTTPS (self-signed) on port **1516** (1515 on pre-2020 TVs). Must be enabled:
Settings > General > Network > Expert Settings > **IP Remote** [?: whether
LS03C/LS03D in Brazil have this item]. Pairing only works when the TV is on
and **not** in art mode; user presses Allow. One connection at a time.

```
POST https://<ip>:1516/   Content-Type: application/json
{"jsonrpc":"2.0","id":1,"method":"createAccessToken"}           -> result.AccessToken
{"jsonrpc":"2.0","id":1,"method":"powerControl","params":{"AccessToken":"<t>"}}   -> {"power":"powerOn"|"powerOff"}
{"jsonrpc":"2.0","id":1,"method":"powerControl","params":{"AccessToken":"<t>","power":"powerOff"}}  (powerOn | powerOff | reboot)
{"jsonrpc":"2.0","id":1,"method":"artModeControl","params":{"AccessToken":"<t>","artMode":"artModeOn"}}
{"jsonrpc":"2.0","id":1,"method":"getTVStates","params":{"AccessToken":"<t>"}}
   -> {"speakerSelect","volume","mute","pictureSize","pictureMode","soundMode","inputSource"}
{"jsonrpc":"2.0","id":1,"method":"inputSourceControl","params":{"AccessToken":"<t>","inputSource":"HDMI2"}}
{"jsonrpc":"2.0","id":1,"method":"directVolumeControl","params":{"AccessToken":"<t>","volume":12}}
{"jsonrpc":"2.0","id":1,"method":"muteControl","params":{"AccessToken":"<t>","mute":"muteOn"}}
{"jsonrpc":"2.0","id":1,"method":"getVideoStates","params":{"AccessToken":"<t>"}}  -> contrast, sharpness, brightness, color, tint
```

Errors: `-32601` method not found (or not available in current state, e.g.
input/volume in art mode), `-32010` unauthorized, `-32700` stale token.
Notes: art flag is stale in standby; check `powerControl` first. Older TVs
need `SECLEVEL=0` ciphers (small DH key). This is **local** direct volume,
direct input, and real power-off: if our TVs support it, it removes most of
the need for SmartThings. Treat as phase-2, test in the live session.

---

## 3. Apps

### 3.1 REST (port 8001, no token on our firmware [?]) [C]

| Method | URL | Meaning |
|---|---|---|
| GET | `http://<ip>:8001/api/v2/applications/<appId>` | status: `{"id","name","running":bool,"version","visible":bool}`; 404 if not installed |
| POST | same | launch app |
| DELETE | same | close app (Tizen may ignore for some apps) |
| PUT | same | open install page in store (do not use) |

Gotchas:

- GET status is the **only reliable way to test if an app is installed** on
  Tizen 7/8 (see 3.2). It is read-only and safe; use it to build the app
  grid from a candidate list.
- `visible: true` = app is in the foreground. The reference tool uses this to
  confirm a launch.
- Some firmwares reject REST POST without token or return 404 for web apps
  [R]; fall back to WS launch.

### 3.2 WebSocket (remote channel)

Launch [C]:

```json
{"method":"ms.channel.emit","params":{
  "event":"ed.apps.launch","to":"host",
  "data":{"appId":"3201907018807","action_type":"DEEP_LINK","metaTag":""}}}
```

- `action_type`: `"DEEP_LINK"` for store apps (app_type 2), `"NATIVE_LAUNCH"`
  for native apps (e.g. `org.tizen.browser`). Unknown type -> try DEEP_LINK,
  poll REST status for `visible`, then NATIVE_LAUNCH (reference tool does
  exactly this, 16 polls x 0.5 s).
- Reply: `{"event":"ed.apps.launch","data":200,"from":"host"}` [C fixture].
- `metaTag` = deep-link payload (app-specific). Browser:
  `appId:"org.tizen.browser"`, `action_type:"NATIVE_LAUNCH"`,
  `metaTag:"https://example.com"` [C]. YouTube: `metaTag` such as
  `"v=dQw4w9WgXcQ"` [R].

Installed apps list:

```json
{"method":"ms.channel.emit","params":{"event":"ed.installedApp.get","to":"host"}}
```

Reply `{"event":"ed.installedApp.get","data":{"data":[{"appId","name","app_type","icon","is_lock"}...]}}`.
**Samsung removed this on newer firmware**: reference tool says "On Tizen 8
the apps command gets no answer"; samsungtvws says "not available on all
TVs". Expect no reply on both our TVs. Use a 5 s timeout and fall back to
probing candidate IDs via REST GET.

### 3.3 App ID table

IDs from samsungtvws APPLICATIONS.md (community list). For 2020+ TVs try the
right-most ID first. All need live verification with REST GET.

| App | ID(s) to try (first = preferred for 2023/24) | Confidence |
|---|---|---|
| Netflix | `3201907018807`, `11101200001` | [C] widely used |
| YouTube | `111299001912` | [C] |
| Prime Video | `3201910019365`, `3201512006785` | [C] |
| Disney+ | `3202204027038`, `3202009021709`, `3201901017640` | [R] which one is BR? |
| Globoplay | `3201908019022` | [R] |
| Spotify | `3201606009684` | [C] |
| Apple TV | `3201807016597` | [C] |
| Max (HBO) | `3202301029760`, `3201601007230` (HBO Max) | [R] BR store ID may differ |
| Paramount+ | `3202110025305`, `3201710014981` | [R] |
| Pluto TV | `3201808016802` | [R] |
| Twitch | `3202203026841` | [R] |
| Xbox | `3202203026799` | [R] |
| Plex | `3201512006963` | [C] |
| Internet (Browser) | `org.tizen.browser` (NATIVE_LAUNCH), `3202010022079`, `3201907018784` | [C] |
| SmartThings | `3201910019378`, `3201710015016` | [R] |
| Privacy Choices | `3201909019271` | [R] useful for tweaks (section 8) |
| Gallery | `3201710015037` | [R] |
| Samsung TV Plus | unknown, discover on TV | [?] |
| Telecine (BR) | `3201604009182` | [R] |
| DAZN | `3201806016390` | [R] |
| TikTok | `3202008021577` | [R] |
| Art Mode / Art Store | not an app ID; use art channel | - |

Extra discovery: Samsung's web app store pages expose `data-app-id`
attributes; Tizen Studio "Installed Web App List" needs developer mode
(off on ours, do not enable for this).

---

## 4. Text input

The TV shows its on-screen keyboard (IME) when a text field is focused. The
remote channel emits `ms.remote.imeStart` when that happens and
`ms.remote.imeEnd` when it closes. `ImeSyncedSupport: "true"` on .42 [V].

Send text [C]:

```json
{"method":"ms.channel.emit","params":{"event":"custom.remote.textReceived","to":"broadcast"}}
```

(once per IME session, "some TVs require this broadcast before accepting
text", samsungtvws) then

```json
{"method":"ms.remote.control","params":{
  "Cmd":"<base64 of UTF-8 text>","DataOfCmd":"base64","TypeOfRemote":"SendInputString"}}
```

then, to submit/close:

```json
{"method":"ms.remote.control","params":{"TypeOfRemote":"SendInputEnd"}}
```

- `SendInputString` **replaces** the field content on most TVs (not append)
  [R]. For live typing send the whole current string each time (debounce
  ~250 ms).
- Reference tool waits 0.5 s between text and `SendInputEnd`.
- Password fields: samsungtvws has `POST http://<ip>:8001/api/v2/remoteControl/imeInput/<b64>?token=<token>` [C, untested]. Avoid (we do
  not type passwords for the user anyway).
- Accents (pt_BR: ç, ã, é) should work through UTF-8 base64 [?]; verify.

---

## 5. Wake-on-LAN

Packet [C]: 6 x `0xFF` + MAC (6 bytes) x 16 = 102 bytes, UDP.

Reference `wake.py`: send to `255.255.255.255` **and** the TV's unicast IP,
ports **9 and 7**, **3 rounds** 300 ms apart ("some Samsung sets ignore a
single packet"). Also send to the subnet broadcast `192.168.1.255` (more
reliable than limited broadcast on macOS with several interfaces) [R].

| TV | MAC for WoL |
|---|---|
| .42 (wireless) | `02:00:00:00:00:20` |
| .43 (wired) | `02:00:00:00:00:21` |

Prerequisites / gotchas:

- TV setting: Settings > General > Network > Expert Settings > **Power On
  with Mobile** = On (reference doc path: Settings > Connection > Network >
  Expert Settings) [C]. Verify both TVs in the live session.
- Wi-Fi WoL is less reliable: after long standby the Wi-Fi radio may sleep
  and unicast to `.42` fails because ARP can't resolve; broadcast is needed
  [R]. Wired (.43) should be solid.
- Unicast to the IP only works while the router still has the ARP entry.
- After WoL, wait for `GET /api/v2/` to answer (poll 1 s, up to ~20 s), then
  open the WebSocket.
- From Art Mode WoL is not needed (TV is already on the network).
- macOS: sending to broadcast needs `SO_BROADCAST`. On macOS 15+ the app needs
  Local Network permission (`NSLocalNetworkUsageDescription`); whether
  broadcast also needs the `com.apple.developer.networking.multicast`
  entitlement on macOS is uncertain [?] (it is required on iOS). Test.
  Network.framework `NWConnection` UDP to a broadcast address is awkward; a
  BSD socket (`socket/setsockopt/sendto`) is simpler.

---

## 6. The Frame art channel

### 6.1 URL and handshake [C]

```
wss://<ip>:8002/api/v2/channels/com.samsung.art-app?name=<b64name>&token=<token>
```

- Same name/token rules as the remote channel. **2024 Frames (our .43) do not
  show the Allow prompt on the art channel**: pair on
  `samsung.remote.control` first, then reuse that token here (Nick Waterton)
  [C]. Do this for both TVs.
- Handshake: wait for `ms.channel.connect` (same as remote), **then** wait for
  `{"event":"ms.channel.ready","data":{}}`. Only send requests after `ready`.

### 6.2 Request envelope [C]

Every art request is a `ms.channel.emit` whose `data` is a **JSON-encoded
string** (double-encoded):

```json
{"method":"ms.channel.emit","params":{
  "event":"art_app_request","to":"host",
  "data":"{\"request\":\"get_artmode_status\",\"id\":\"<uuid>\",\"request_id\":\"<uuid>\"}"}}
```

Set both `id` and `request_id` to the same fresh UUID (samsungtvws does this
for correlation).

### 6.3 Response envelope [C]

```json
{"event":"d2d_service_message","from":"<client uuid>",
 "data":"{\"id\":\"<uuid>\",\"request_id\":\"<uuid>\",\"event\":\"artmode_status\",\"value\":\"on\",\"target_client_id\":\"...\"}"}
```

- `data` is again a **JSON string**; parse it.
- Match on `request_id` (fall back to `id`).
- Inner `event` = sub-event name. `"error"` means failure; then
  `error_code` and `request_data` (JSON string with the original request).
- Unsolicited sub-events (push, no request_id match) [C: async_art.py]:
  - `art_mode_changed` with `status: "on"|"off"` (user pressed power on remote)
  - `artmode_status` with `value` (API 5.x may use `status` instead)
  - `go_to_standby` (TV going to real off)
  - `*wakeup*` (TV woke; re-query art mode)
  - `image_selected`, `favorite_changed`, `image_added`, `image_deleted` [R]
  Keep the art socket open and listen: this is the cheapest way to track
  Art/TV state live.
- Frames may carry a **binary tail** after the JSON (old API 0.97
  thumbnails). Not relevant for 2023/24.

### 6.4 Requests

| Purpose | request JSON (inside `data`) | reply sub-event / key fields |
|---|---|---|
| API version | `{"request":"api_version"}` (fallback `get_api_version`) | `version` e.g. `"4.3.4.0"` (2022); 2023/24 likely 4.x-5.x [?] |
| Art mode status | `{"request":"get_artmode_status"}` | `artmode_status`, `value: "on"/"off"` |
| Art mode on/off | `{"request":"set_artmode_status","value":"on"}` | ack / `art_mode_changed` |
| Current artwork | `{"request":"get_current_artwork"}` | `content_id`, `category_id`, `matte_id`, ... |
| Content list | `{"request":"get_content_list","category":null}` | `content_list` = **JSON string** array of `{content_id, category_id, width, height, matte_id}` |
| Select image | `{"request":"select_image","content_id":"MY_F0003","category_id":null,"show":true}` | `image_selected` |
| Settings (API >= 4.3.4.0) | `{"request":"get_artmode_settings"}` | `data` = JSON string list of `{item, value, ...}`; items include `brightness`, `color_temperature`, `motion_timer`, `motion_sensitivity`, `brightness_sensor_setting` |
| Brightness get (old) | `{"request":"get_brightness"}` | `value` |
| Brightness set | `{"request":"set_brightness","value":5}` | range 1-10 typical [R]; "maybe `brightness` on 4.x" (TODO in code) [?] |
| Colour temperature | `{"request":"set_color_temperature","value":0}` | range ~ -5..5 [?] |
| Brightness sensor | `{"request":"set_brightness_sensor_setting","value":"on"}` | |
| Slideshow get | `{"request":"get_slideshow_status"}` (API < 4.3.4: `get_auto_rotation_status`) | `value`, `category_id`, `type` |
| Slideshow set | `{"request":"set_slideshow_status","value":"15","category_id":"MY-C0002","type":"shuffleslideshow"}` | `value`: minutes as string, or `"off"`; `type`: `slideshow` / `shuffleslideshow` |
| Motion timer | `{"request":"set_motion_timer","value":"15"}` | `off`,`5`,`15`,`30`,`60`,`120`,`240` |
| Motion sensitivity | `{"request":"set_motion_sensitivity","value":"2"}` | `1`-`3` |
| Favourite | `{"request":"change_favorite","content_id":"SAM-F0206","status":"on"}` | `favorite_changed` |
| Matte list | `{"request":"get_matte_list"}` | `matte_type_list` (or `matte_list`), `matte_color_list` (JSON strings) |
| Change matte | `{"request":"change_matte","content_id":"MY_F0003","matte_id":"shadowbox_polar"}` | |
| Photo filters | `{"request":"get_photo_filter_list"}` / `set_photo_filter` | |
| Rotation | `{"request":"get_current_rotation"}` | `current_rotation_status` |
| Delete own photos | `{"request":"delete_image_list","content_id_list":[{"content_id":"MY_F0020"}]}` | **destructive, needs user confirm** |

Category IDs: `MY-C0002` = My Photos, `MY-C0004` = Favourites,
`MY-C0008` = Art Store (per samsungtvws docstring); `MY-C0003` also appears in
fixtures [?]. Content IDs: own photos `MY_F0001...`, store art `SAM-F0206...`.

Upload and thumbnails use a side **D2D TCP socket** (`conn_info` with `ip`,
`port`, `key`, `secured`) and a 4-byte big-endian header length + JSON header
+ bytes. Out of scope for v1; see `samsungtvws/art/art.py` `upload()` and
`get_thumbnail_list()` if needed later. API >= 4.3.4.0 uses
`get_thumbnail_list` (not `get_thumbnail`).

### 6.5 Firmware differences and known problems

- Art API names changed: `auto_rotation` (<= 2.03) -> `slideshow`
  (>= 4.3.4.0). Try `slideshow` first on our sets, fall back. [C]
- `get_artmode_settings` exists only from 4.3.4.0; older uses one request per
  setting. [C]
- 2023/2024 (LS03C/LS03D): "reported working by users. 2024 models pair on the
  remote channel first." [C, not tested by maintainer]
- The art service can stop answering while the TV is otherwise fine (2022).
  Nick's fork: after 3 unanswered requests close the socket and back off
  30 s, doubling to 4 min. Copy this. Use a 5-10 s per-request timeout. [C]
- With the TV in real Off/standby the art channel does not answer.

### 6.6 Power state algorithm (recommended)

```
1. GET :8001/api/v2/ (timeout 2 s)
   - no answer            -> OFF (unreachable)
   - PowerState=standby   -> STANDBY (2025 caveat irrelevant for our models; still query art if socket opens)
   - PowerState=on        -> go to 2
2. art channel get_artmode_status (timeout 5 s)
   - value=on  -> ART
   - value=off -> TV
   - no answer -> ON (mode unknown)
3. Keep art socket open; update on art_mode_changed / go_to_standby / wakeup.
4. If IP Control is paired: powerControl + artModeControl is the most reliable source.
```

Transitions:

| From -> To | Command |
|---|---|
| TV -> ART | `set_artmode_status on` (or `KEY_POWER` Click) |
| ART -> TV | `set_artmode_status off` (or `KEY_POWER` Click) |
| TV/ART -> OFF | `KEY_POWER` Press, 3 s, Release (or IP Control `powerOff`, or SmartThings `switch off` [?: may go to art]) |
| OFF -> TV/ART | WoL, wait for REST, then set art mode as wanted (or SmartThings `switch on`) |

---

## 7. SmartThings REST (cloud)

Base: `https://api.smartthings.com/v1`. Header
`Authorization: Bearer <token>`, `Content-Type: application/json`.
Needs the TVs added to the user's SmartThings account (SmartThings app on the
phone) [assumed; verify].

### 7.1 Auth

- **PAT** (https://account.smartthings.com/tokens): since **30 Dec 2024**
  new PATs are valid **24 hours** only. PATs created before then keep their
  original expiry (up to 50 years), though some users report old ones also
  stopped. -> PAT is OK for a quick test only.
- **OAuth-In app** (recommended for a long-lived app): create with the
  SmartThings CLI (`brew install smartthingscommunity/smartthings/smartthings`,
  `smartthings apps:create` -> "OAuth-In App"), scopes `r:devices:*`,
  `w:devices:*`, `x:devices:*` (add `r:locations:*` if needed), a redirect URI.
  Save the client ID/secret (shown once).
  - Authorize: `https://api.smartthings.com/oauth/authorize?client_id=...&response_type=code&redirect_uri=...&scope=r:devices:* x:devices:*`
  - Token: `POST https://api.smartthings.com/oauth/token` (HTTP Basic
    client_id:client_secret, form `grant_type=authorization_code&code=...&redirect_uri=...`)
  - Refresh: same endpoint, `grant_type=refresh_token&refresh_token=...`.
    Access token lives ~24 h; refresh tokens rotate (store the new one each
    time) [R].
  - For a macOS app: use `ASWebAuthenticationSession` with a custom-scheme or
    loopback redirect, if SmartThings accepts it [?]; homebridge uses
    `https://httpbin.org/get` and the user copies the code.
- Store tokens in the Keychain.

### 7.2 Endpoints [C]

```
GET  /v1/devices                       -> {"items":[{deviceId,label,name,deviceTypeName,ocf:{...},components:[...]}],"_links":{"next":...}}
GET  /v1/devices/{deviceId}/status     -> {"components":{"main":{"<capability>":{"<attr>":{"value":...}}}}}
GET  /v1/devices/{deviceId}/components/main/capabilities/{capabilityId}/status
POST /v1/devices/{deviceId}/commands   body {"commands":[{"component":"main","capability":"switch","command":"on","arguments":[]}]}
```

Match a SmartThings device to a LAN TV by `ocf.mnmo` (model, e.g.
`QN32LS03CBGXZD`?) or label; the OCF `di` is not the LAN `duid` [?].
Paginate `GET /devices` via `_links.next.href`.

### 7.3 Capabilities on Samsung TVs

From HA fixture `vd_stv_2017_k` and pysmartthings maps [C]; Frame-specific
availability [?] until we read `GET /devices/{id}` for our sets. Always check
`custom.disabledCapabilities.disabledCapabilities` before offering a feature.

| Capability | Commands (arguments) | Attributes |
|---|---|---|
| `switch` | `on`, `off` | `switch` |
| `audioVolume` | `setVolume` ([0-100]), `volumeUp`, `volumeDown` | `volume` |
| `audioMute` | `mute`, `unmute`, `setMute` (["muted"/"unmuted"]) | `mute` ("muted"/"unmuted") |
| `mediaInputSource` | `setInputSource` (["HDMI1"\|"digitalTv"...]) | `inputSource`, `supportedInputSources` |
| `samsungvd.mediaInputSource` | `setInputSource` ([id from map, e.g. "HDMI2"]) | `inputSource`, `supportedInputSourcesMap` `[{id,name}]` (name = user label / CEC name, e.g. "PlayStation 4") |
| `tvChannel` / `samsungvd.tvChannel` | `channelUp`, `channelDown`, `setTvChannel` (["7"]), `setTvChannelName` | `tvChannel`, `tvChannelName` |
| `mediaPlayback` | `play`, `pause`, `stop`, `fastForward`, `rewind` | `playbackStatus`, `supportedPlaybackCommands` |
| `mediaTrackControl` | `nextTrack`, `previousTrack` | |
| `custom.picturemode` | `setPictureMode` (["Movie"]; use `name` from map) | `pictureMode`, `supportedPictureModes`, `supportedPictureModesMap` `[{id:"modeMovie",name:"Movie"}]` |
| `custom.soundmode` | `setSoundMode` (["Standard"]) | `soundMode`, `supportedSoundModes(Map)` |
| `samsungvd.pictureMode` / `samsungvd.soundMode` | `setPictureMode` / `setSoundMode` (newer variants) [?] | same pattern |
| `custom.launchapp` | `launchApp` ([appId], optional [appId, appName]) | none |
| `samsungvd.remoteControl` | `send` ([keyValue]); enum includes `UP`,`DOWN`,`LEFT`,`RIGHT`,`OK`,`BACK`,`HOME`,`MENU` [C homebridge] | |
| `samsungvd.ambient` | `setAmbientOn` (no args) -> Ambient/Art mode; `sendData` [?] | `info` |
| `samsungvd.ambientContent` | `setAmbientContent` ([app from `supportedAmbientApps`]) [C homebridge] | `supportedAmbientApps` |
| `samsungvd.art` | `setArtOn` (args unknown) [?] | |
| `samsungvd.supportsPowerOnByOcf` | - | `supportsPowerOnByOcf` (can cloud power it on) |
| `execute` | `execute` ([href, payload]) raw OCF; undocumented [?] | `data` |
| `ocf` | - | `mnmo` model, `mnfv` firmware, `n` name |
| `refresh` | `refresh` | |

Example: set picture mode

```json
POST /v1/devices/{id}/commands
{"commands":[{"component":"main","capability":"custom.picturemode","command":"setPictureMode","arguments":["Movie"]}]}
```

Example: input by name

```json
{"commands":[{"component":"main","capability":"samsungvd.mediaInputSource","command":"setInputSource","arguments":["HDMI2"]}]}
```

Gotchas:

- Commands return `{"results":[{"id","status":"ACCEPTED"}]}`; ACCEPTED does
  not mean done. Re-read status after ~1-2 s.
- Status attributes can be stale while the TV is off/art; the cloud updates
  them only when the TV is online.
- `switch off` on a Frame may go to Art Mode rather than real off [?].
- Picture/sound mode names in the map are localised? On pt_BR TVs the
  `name` may be Portuguese [?]; always use values from
  `supported*Map`, never hard-coded strings.
- Rate limits: SmartThings documents per-token limits (roughly tens of
  requests/minute per device) [?]; poll status no faster than every 30 s.
- Latency 0.5-3 s; use the local WebSocket for anything interactive (keys,
  volume steps).

### 7.4 What only SmartThings (or IP Control) can do

| Feature | Local WS | IP Control (if available) | SmartThings |
|---|---|---|---|
| Set picture mode directly | no (only `KEY_PMODE` cycle / menu navigation) | read only (`getTVStates`) [C] | **yes** `custom.picturemode` |
| Set sound mode directly | no | read only | **yes** `custom.soundmode` |
| Input by name / direct HDMIn | `KEY_SOURCE` + navigation; `KEY_HDMIx` unreliable | **yes** `inputSourceControl` | **yes** `samsungvd.mediaInputSource` |
| Absolute volume (set to 15) / read volume | no (only steps) | **yes** | **yes** `audioVolume` |
| Read mute state | no | yes | yes |
| Read current input | no | yes | yes |
| Power on from real off | WoL only | `powerOn` [?: only if TV keeps 1516 alive in standby] | **yes** if `supportsPowerOnByOcf` |
| Direct channel set | digits + ENTER | no | `setTvChannel` |
| Read volume/picture values | no | `getVideoStates` (brightness, contrast...) | partial |

---

## 8. Tweaks catalogue (from reference SAMSUNG-SETTINGS.md)

The reference doc was written for a 2023 Q70C on Tizen 8; menu paths on our
Frames may differ. "Scriptable" here means: as a **key macro** (blind
sequence of KEY_ presses; there is no screenshot API, so each step must be
checked by eye) unless a direct API exists. None of these settings has a
known direct API (local or SmartThings).

| Tweak | Where (reference doc) | Direct API | Macro-able | Notes |
|---|---|---|---|---|
| Turn off Viewing Information Services (ACR) | Privacy Choices > Terms & Conditions, Privacy Policy > untick | none | partial: can open Privacy Choices app (`3201909019271` [R]) and navigate; the checklist position varies | Manual with guidance recommended |
| Turn off Interest-Based Ads | same screen | none | partial | manual |
| Reset advertising ID (PSID) | All Settings > General & Privacy > Terms & Privacy > Reset PSID | none | risky | irreversible (harmless); manual |
| Turn off Samsung Promotion notifications | Settings > Notification > gear > untick | none | partial | manual |
| Start with Smart Hub Home off | All Settings > General & Privacy > Start Screen Options | none | partial | **Factory Data Reset is the item just below**: never macro this area |
| Autoplay Sound off (Home previews) | Home > For You > bottom > Media Options | none | no (content-dependent layout) | manual |
| Tidy Home row (Remove tile) | hold OK on tile > Remove | none | no | manual; App Settings > Delete **uninstalls** |
| Custom DNS (e.g. 76.76.2.37 Control D) | All Settings > Connection > Network > Network Status > IP Settings > DNS Setting | none | no: on-screen keypad only, remote digits did not fill boxes | manual; if TV loses internet set DNS back to automatic |
| Power On with Mobile (needed for WoL) | General > Network > Expert Settings | none | manual | required setup step |
| IP Remote (needed for IP Control) | General > Network > Expert Settings | none | manual | [?] presence on our models |
| Device Connection Manager Access Notification | General > External Device Manager | none | manual | set "First Time Only" |
| Picture mode / sound mode | - | SmartThings yes | - | see 7.4 |
| Art Mode brightness, sleep-after (motion timer), slideshow | - | **art channel yes** | - | section 6.4 |
| Not changeable at all | New & Trending rows, banner, left menu, what Home opens | - | - | per reference doc |

Safe helpers the app can offer: open All Settings directly (`KEY_MENU`),
close all menus (`KEY_EXIT`), open Privacy Choices app, and a checklist UI
telling the user what to change. Do not automate anything near Factory Reset,
Reset Smart Hub, App Delete, or DNS.

---

## 9. macOS implementation notes

- **WebSocket**: `URLSessionWebSocketTask` with a session delegate that
  accepts the TV's self-signed cert in
  `urlSession(_:didReceive:completionHandler:)` (only for the known TV IPs,
  `.useCredential` with `URLCredential(trust:)`). Set
  `task.maximumMessageSize` high (e.g. 16 MB): art `content_list` replies can
  exceed the 1 MB default. URLSession answers TV pings automatically.
- Alternative: Network.framework `NWProtocolWebSocket` + `sec_protocol_options_set_verify_block`.
- **ATS**: plain `http://192.168.1.x:8001` - add `NSAllowsLocalNetworking` (and
  test; ATS may not apply to bare IPs anyway).
- **Sandbox**: `com.apple.security.network.client` entitlement.
- **Local Network privacy** (macOS 15+): `NSLocalNetworkUsageDescription`;
  first LAN access shows a system prompt.
- One actor per TV owning: REST poller, remote socket, art socket, token
  (Keychain, keyed by TV `duid`).
- Reconnect with backoff; on `ms.channel.timeOut`/`unauthorized` go to a
  "Pair" UI state that tells the user to press Allow on the TV.
- Never send `KEY_FACTORY`. Rate-limit key repeats.

## 10. Open questions for the live session

1. Does `PowerState` read `on` while in Art Mode on both sets?
2. `KEY_POWER` click and 3 s hold behaviour on LS03C (.42) and LS03D (.43).
3. Does `.43` show Allow on the remote channel and accept that token on the
   art channel?
4. Art API version on each TV; does `get_artmode_settings` work?
5. Does `ed.installedApp.get` answer? (expected: no)
6. Which IDs answer REST GET for Netflix/YouTube/Prime/Disney+/Globoplay/Max.
7. Does REST POST launch work without token, or only WS `ed.apps.launch`?
8. Is "Power On with Mobile" on? Does WoL wake .42 over Wi-Fi after > 1 h off?
9. Is "IP Remote" present? If yes, test port 1516 pairing.
10. SmartThings: are both TVs in the account? Which capabilities are listed
    and which are in `custom.disabledCapabilities`? Picture mode names in pt_BR.
11. Does `SendInputString` handle pt_BR accents?

## Resultados do teste ao vivo (Frame 43" QN43LS03D, 2024, 29/10/2026)

| Item | Resultado |
|---|---|
| Pareamento | Funciona. O aviso na TV some rápido: aceite logo. Token salvo por TV. |
| Teclas (`ms.remote.control` Click) | Funcionam (volume confirmado na tela). |
| Modo Arte (`get_artmode_status`) | Funciona, reaproveita o token do canal remoto. |
| Abrir app via `ed.apps.launch` (WS) | **Ignorado**: sem resposta, app fica `running` mas `visible:false`. |
| Abrir app via `POST /api/v2/applications/<id>` | **Funciona** (`visible:true`). O app usa este primeiro. |
| `ed.installedApp.get` | A TV fecha a conexão. Use `GET /api/v2/applications/<id>` por ID. |
| `KEY_POWER` Press/Release (3 s ou 5 s) | Age como clique: alterna TV ↔ Arte. Não desliga. |
| `KEY_POWEROFF` | Ignorado. |
| IP Control (porta 1516) | Fechada. |
| Desligar de verdade | Só pelo controle físico ou SmartThings `switch off`. |
| `PowerState` no REST | `on` em TV e em Arte; `standby` quando desligada. |
| Wake-on-LAN (cabo) | Não acordou em 30 s. |
| `KEY_POWER` Click em standby | **Liga a TV** (~6 s). O app tenta isto antes do WOL. |
| IDs confirmados | Netflix 3201907018807, YouTube 111299001912, Prime 3201910019365, Disney+ 3201901017640, HBO Max 3202301029760, Spotify 3201606009684, Apple TV 3201807016597, Browser 3202010022079. Globoplay 3201908019022 = 404. |
