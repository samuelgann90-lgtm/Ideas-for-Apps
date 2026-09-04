# Dalton Flyer

WW2 first-person air combat for iPhone. You fly a **P-51 Mustang** with a gunsight view, easy on-screen **GUNS** and **ROCKETS** buttons, and three kinds of targets:

- Enemy fighter planes
- Rail cars on a coastal line
- Boats in the harbor

The P-51 is a piston fighter (not a jet) — this mission is set on the 1944 Western Front with a Red Tail Mustang.

## Play on iPhone (two ways)

### 1. Native app (Xcode)

1. On a Mac, open `ios/DaltonFlyer.xcodeproj` in Xcode.
2. Select the **DaltonFlyer** target → **Signing & Capabilities** → choose your Apple ID / Team.
3. Plug in the iPhone, pick it as the run destination, press **Run**.
4. Rotate the phone to **landscape**. Drag the left **STEER** pad to fly. Hold **GUNS** to shoot. Tap **ROCKETS** for trains and ships.

iOS 17+, portrait is playable but landscape is intended.

### 2. Safari / Home Screen

The game is a full-screen web app in `web/`.

1. Host the `web` folder (AirDrop the folder, GitHub Pages, or a local server).
2. Open `index.html` in Safari on the iPhone.
3. Share → **Add to Home Screen** for an app icon.

Keyboard on a computer: **WASD / arrows** steer, **space** guns, **F** rockets.

## Mission

Destroy every bandit, rail car, and boat. Machine guns work on all targets. Rockets hit much harder against trains and ships. A light aim-assist pulls shots toward anything near the gunsight so the buttons stay easy.

## Project layout

| Path | Purpose |
|------|---------|
| `web/` | The 3D game (Three.js, runs in Safari and in the iOS app) |
| `ios/DaltonFlyer.xcodeproj` | Xcode wrapper that loads the game full-screen |
| `ios/DaltonFlyer/` | SwiftUI + WKWebView shell |

No extra SDKs or API keys. The 3D engine is vendored in `web/js/three.min.js` (MIT).
