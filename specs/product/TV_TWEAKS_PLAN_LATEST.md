# TV tweaks plan: debloat, privacy and a calmer home screen

- Status: proposed, revision 2 (2026-10-29) after a red-team review of four areas
  (Samsung Frames, Sony, LG, DNS) against outside sources. Nothing started.
- Source: the r/ClaudeAI post "I used Claude to fix my Samsung TV" and
  [victaphu/glass-home-samsung-tv](https://github.com/victaphu/glass-home-samsung-tv)
  (`docs/SAMSUNG-SETTINGS.md`, tested on one 2023 Q70C, Tizen 8).
- Rules: AGENTS.md "Never automate menus near Factory Reset, Reset Smart Hub or DNS";
  ask before any command that changes TV state; write down every setting before changing it.

## What revision 2 changed

| Area | Revision 1 said | Red team found | Now |
|---|---|---|---|
| All TVs | Menu paths from one 2023 Samsung | Tizen 9 reached 2023 Samsungs (Oct 2025); LG Re:New moved 2023 sets to webOS 24/25; paths move | P0 reads versions first; paths written from the real menus |
| All TVs | One-time checklist | Firmware updates turn ACR/promos back on (LG Live Plus, Samsung terms) | Re-check after every firmware update |
| All TVs | No guard for Big Remote | Easy toggles break LAN control and wake | "Must stay on" list per TV |
| Samsung | Glass Home optional | A Frame powers on into Art Mode, so the launcher rarely shows; certs tied to DUID, expire with firmware | Glass Home dropped for the Frames |
| Samsung | TV-only privacy | Samsung Account privacy dashboard can re-enable it by sync | Account dashboard step added |
| Sony | Generic debloat | Three easy-to-disable packages kill Big Remote's own Sony path; lists contradict; boot loop reports | Allow list + hard-coded deny list, batches with reboot and checks |
| Sony | Private DNS by IP | Needs a DoT hostname, only via ADB (no menu), strict mode = no internet if down | Router DNS preferred; ADB DNS only with explicit sign-off |
| Sony | Disable stock launcher | No Home picker on Android TV 8/9; disabling `tvlauncher` can strand the TV | Launcher only via Accessibility override, `tvlauncher` untouched |
| LG | "Dev apps expire in 50 h" | Now 1000 h with renewal; root patched on current firmware | Still not worth it; use Home Settings toggles |
| DNS | "Router covers every TV" | Android TV may use built-in 8.8.8.8; ISP IPv6 DNS leaks past a Deco DHCP change | IPv6 step, bypass caveat, smoke tests, 48 h per TV |

## What is possible on each TV

| | Frame 43" (QN43LS03D, 2024) | Frame 32" (QN32LS03C, 2023) | Sony KD-49X755F (2018) | LG 43UR7800PSA (2023) |
|---|---|---|---|---|
| Privacy/promo settings | Yes (menus) | Yes (menus) | Yes (menus) | Yes (menus) |
| Reset advertising ID | Yes (Reset PSID) | Yes | Yes (Google > Ads) | Yes (Advertisement > Reset AD ID) |
| Disable preinstalled apps | Hide from Home row | Hide | **Yes, reversible ADB, curated list** | Hide; delete home ad cards |
| Custom home screen | Dropped (Art Mode) | Dropped | Optional, Accessibility override only | Not worth it (no Home replacement without root) |
| Gain | Medium | Medium | **High** | Low-medium |

## Phases

### P0 — Read before touching (read-only, ~5 min per TV)

- Samsung: `GET :8001/api/v2/` gives model, `developerMode` (both 0 on 2026-10-29) and API 2.0.25, but
  `firmwareVersion` is "Unknown", so the Tizen/firmware version is read in Settings > Support > About.
- Sony: `getprop ro.build.version.release` once ADB is on (Android 9 expected for LATAM X755F).
- LG: Settings > Support > TV Information (webOS and firmware version).
- Router: confirm Deco BE65 vs Archer BE65 (menus differ).
Record versions in `docs/PROTOCOL.md`.

### P1 — Privacy checklist (you with the remote, ~10–15 min per TV)

`docs/TV-PRIVACY.md` (pt-BR), one section per TV: path, "before" value, how to undo. Big Remote only opens
menus; you make each change. Warn in writing: Factory data reset sits right below Start Screen Options
(Samsung), Reset Smart Hub, "Delete" in App Settings.

- Samsung (both Frames): Privacy Choices (Viewing Information Services, Interest-Based Advertisements; the
  menu may be under Support or General & Privacy), Reset PSID, Notification > Samsung Promotion, Start with
  Smart Hub Home, Autorun Smart Hub, voice/Bixby data, Samsung TV Plus autostart, Home-row tidy-up.
  Then the same toggles in the Samsung Account privacy dashboard. Interest-based ads off stops targeting,
  not the ads themselves. Art Store promos: no known switch, check on the TV only.
- LG: Live Plus and Live Promotion off; Home Settings > Home Promotion and Content Recommendation off;
  Support > Privacy & Terms > User Agreements: untick Viewing Information, Voice Information,
  Interest-Based Advertisement (keep Terms of Use and Privacy Policy, apps need them); Advertisement >
  Limit AD Tracking on and Reset AD ID; delete ad cards on the Home screen.
- Sony: Google > Ads (opt out, reset ID); Sony usage/diagnostic data and Samba Interactive TV off
  (exact names read on the TV).

**Must stay on (Big Remote)**

| TV | Keep |
|---|---|
| Samsung | Power On with Mobile, IP Remote (Network > Expert Settings), Device Connection Manager access for "Big Remote" |
| Sony | IP control, Remote start (Network > Home network) |
| LG | LG Connect Apps, Mobile TV On > Turn On via Wi-Fi, Quick Start+ |

After every firmware update: re-check P1 (updates re-enable ACR and promos).

### P2 — Ad/tracker DNS (your decision, manual by rule)

- Resolver: Control D free "HaGeZi Light" `76.76.2.37` / `76.76.10.37` (IPv6 `2606:1a40::37`,
  DoT/DoH `x-hagezi-light.freedns.controld.com`), vendor states no logs. Fallback: AdGuard DNS
  `94.140.14.14` (blocks more, breaks more). Not Quad9/Mullvad (malware only). It does not remove
  YouTube or in-stream ads.
- Router path (preferred): Deco > More > Advanced > DHCP Server, both Control D addresses. Also stop the
  ISP's IPv6 DNS (IPv6 off on the LAN, or Control D IPv6 if the firmware allows). Caveat: Android TV
  and some Samsungs fall back to built-in 8.8.8.8 or DoT and skip it; the Deco cannot force port 53.
  It applies to every device in the house.
- Per-TV path: start with the 43" Frame only. Samsung takes one DNS server (user-reported): if Control D
  is down that TV is offline; undo = DNS "Get automatically". Sony/LG manual DNS may need a static IP
  plus a DHCP reservation (Big Remote stores TVs by IP).
- Smoke test after each change, then wait 48 h before the next TV: Netflix, YouTube, Globoplay, Samsung
  TV Plus, LG Channels, the app store, "check for updates", Art Store, Google Play sign-in (Sony).
- LG: `lgtvsdp.com` and `lgappstv.com` must resolve (Content Store); `lgsmartad.com` can be blocked.

### P3 — Sony debloat over ADB (biggest gain)

Needs: Developer options (About > Build, 7 taps), network debugging, `brew install
android-platform-tools`, Local Network permission for the terminal, one "Allow" on the TV.

1. Baseline: run the pending Big Remote Sony live test first (PIN, IRCC keys, app launch, Remote start).
2. Backup to `backups/sony/` (git-ignored): `pm list packages -e` and `-d`, `getprop`, `settings list
   global|secure`, `dumpsys package` for each target.
3. `scripts/sony-debloat.sh`: disables only packages present on the TV and approved by you, with
   `pm disable-user --user 0`, in batches of ~5, then reboots. A hard-coded deny list makes it refuse:
   - Big Remote path: `com.sony.dtv.webapi.core`, `com.sony.dtv.discovery`, `com.sony.dtv.remotepairing`,
     `com.sony.dtv.remoteaccess`, `com.sony.dtv.homenetwork`, `com.sony.dtv.magicpacketnotifyservice`,
     `com.sony.dtv.keepsleepserviceforwolna`, `com.sony.dtv.seeds.iot.remotestart`, `com.sony.dtv.b2b.vendorprotocol`
   - Casting/streaming: `com.google.android.apps.mediashell`, `com.sony.dtv.dialservice`,
     `com.sony.dtv.netflixmanager`, `com.netflix.ninja`, `com.google.android.youtube.tv`
   - TV/remote/voice: `com.sony.dtv.tvx`, `com.sony.dtv.rcplayer*`, `com.sony.dtv.remotecontrolsettings`,
     `com.sony.dtv.braviabluetoothservice`, `com.android.bluetooth`, `com.google.android.tv.remote.service`,
     `com.google.android.katniss`, `*.inputmethod.*`
   - Breaks Settings/boots: `com.sony.dtv.b2b.hotelmode`, `com.sony.rvu`, `com.sony.dtv.demomode`,
     `com.google.android.gms`, `com.google.android.gsf`, `com.android.vending`, `com.android.location.fused`
   - Launcher/setup: `com.google.android.tvlauncher`, `com.google.android.leanbacklauncher`,
     `com.sony.dtv.tvlaunchercustomizer`, `com.google.android.tungsten.setupwraith`
4. Candidate list (you approve each): Sony Select/promos (`com.sony.dtv.sonyselect*`, `com.sony.dtv.promos`,
   `android.autoinstalls.config.sony.bravia`), telemetry/ACR (`com.sony.dtv.da.service`, `com.qterics.da.product`,
   `tv.samba.ssm*`, `com.sonyericsson.idd.agent`), store demo/help (`com.sony.dtv.multiscreendemo`,
   `com.sony.dtv.demosupport`, `com.sony.dtv.smarthelp`, `com.sony.dtv.imanual`), Google extras
   (`com.google.android.feedback`, `com.google.android.tv.bugreportsender`, `com.google.android.play.games`).
5. After each batch: Big Remote pairing + keys, Remote start from standby, Chromecast, Netflix, YouTube,
   HDMI, Settings. `scripts/sony-restore.sh` re-enables only what the debloat script disabled.
6. Optional launcher (separate approval, later): Projectivy via its Accessibility Home override only;
   `tvlauncher` stays enabled; keep ADB on for a few days, then decide. Watch RAM on this 2018 set.
7. DNS: prefer the router (P2). ADB Private DNS (DoT hostname, opportunistic) only with your explicit sign-off.
8. Turn network debugging off and reboot. Record results in `docs/PROTOCOL.md` § 11.5.

Risks kept in view: one boot-loop report ~9 h after debloat + launcher on another Sony (cause unproven);
a factory reset reverts everything.

### Not planned

- Glass Home on the Frames (Art Mode at power-on, DUID-bound certificates, updates can delete it).
- LG root (faultmanager/DejaVuln patched on current firmware; updates close any window) and LG dev-mode launcher.
- Replacing Samsung's Home button (CleanFrame/Arn0 rewrite undocumented settings, one TV each).
- Phone-camera feedback loop (only needed for unattended menu automation, which P1 avoids).

## What changes for the user

- Fewer promos and pop-ups; no content recognition watching HDMI inputs; new advertising IDs.
- With DNS: fewer ad tiles and tracker calls on filtered devices; YouTube ads stay.
- Sony: less running in the background, faster menus, optionally a cleaner home screen.
- Big Remote keeps working: the must-stay-on list and the Sony deny list protect it, and the Sony and LG
  live tests run along the way.
- A written record and an undo path for every change, plus a re-check after firmware updates.

## Effort

| Phase | Your time | Agent time |
|---|---|---|
| P0 | ~5 min per TV | read-only checks, record versions |
| P1 | ~10–15 min per TV, again after updates | write `docs/TV-PRIVACY.md` |
| P2 | one router change, or ~5 min per TV; 48 h test each | smoke-test checklist |
| P3 | ~45–60 min at the Sony | backup, scripts with deny list, batch checks |
