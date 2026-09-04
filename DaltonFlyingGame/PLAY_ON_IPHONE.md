# How to get Dalton Flyer on the iPhone

**Your iPhone will never appear in GitHub.** GitHub is only a website that stores the code. It has no list of phones.

The phone shows up in **Xcode on a Mac**, after you plug it in with a cable. Look at the **top middle of the Xcode window**, not on github.com.

You cannot open Xcode from a GitHub link. Pick **one** path below.

---

## Path A — easiest if you have a Mac (real iPhone app)

### 1. Download the game onto the Mac

On the **Mac**, tap this (it downloads a zip):

https://github.com/samuelgann90-lgtm/Ideas-for-Apps/archive/refs/heads/cursor/dalton-flying-game-2645.zip

### 2. Unzip it

- Open **Downloads**
- Double-click the zip
- A folder appears named something like `Ideas-for-Apps-cursor-dalton-flying-game-2645`

### 3. Open Xcode

Go into that folder → **DaltonFlyingGame** → double-click **`Open in Xcode.command`**

If the Mac asks whether to open it, choose **Open**.

**If nothing happens / “Xcode not found”:**
1. Open the **App Store** on the Mac
2. Search **Xcode**
3. Click **Get** / **Install** (this is a large install; wait until it finishes)
4. Double-click `Open in Xcode.command` again

You can also open it by going to `DaltonFlyingGame/ios/` and double-clicking **`DaltonFlyer.xcodeproj`**.

### 4. Sign it with your Apple ID (one-time)

1. In Xcode’s left list, click **DaltonFlyer** (the blue app icon at the top)
2. Click **Signing & Capabilities**
3. Check **Automatically manage signing**
4. Next to **Team**, choose your name. If the list is empty:
   - **Add Account…**
   - Sign in with the **same Apple ID** you use on the iPhone
5. If Xcode shows a red signing error, change **Bundle Identifier** to something unique, like `com.yourname.DaltonFlyer`

### 5. Put it on the iPhone

1. Unlock the iPhone and plug it into the Mac with a cable
2. On the iPhone, tap **Trust** if it asks
3. At the **top center** of Xcode, click the device menu (it may say iPhone Simulator or DaltonFlyer) and pick **your iPhone**
4. Click the **Play** button (triangle) at the top left
5. Wait until Xcode says it finished

**First time only, the iPhone may block it:**

1. iPhone **Settings → General → VPN & Device Management** (or **Device Management**)
2. Tap your Apple ID / developer name
3. Tap **Trust**

Then open **Dalton Flyer** on the home screen. Turn the phone **sideways**. Tap **START MISSION**.

### Phone not showing in Xcode

Do these in order. Stay in **Xcode**, not GitHub.

1. Unlock the iPhone. Leave it on the home screen (not a passcode lock).
2. Use a **data** cable (the one that came with the phone). Charge-only cables will not show the phone.
3. Plug straight into the Mac, not through a hub if you can avoid it.
4. On the iPhone, if you see **Trust This Computer?** tap **Trust** and enter the passcode.
5. On the iPhone: **Settings → Privacy & Security → Developer Mode** → turn **On**, then restart the phone if it asks. (This is required on iOS 16 and later.)
6. In Xcode, click **Window → Devices and Simulators**. Wait until your iPhone name appears on the left. The first time, Xcode may sit on “Preparing device” for a few minutes.
7. Back in the main Xcode window, click the name next to the Play button (top left/middle). It might say **iPhone 16** or **Any iOS Device**. Pick **your iPhone** from that list — not a Simulator.

If it still does not appear, unplug, unlock the phone, plug back in, and wait on the Devices window. You can still play without this: AirDrop **`DaltonFlyer.html`** to the iPhone and open it in Safari.

---

## Path B — no Xcode: AirDrop one file to the iPhone

1. On the Mac, in the same unzipped folder, find **`DaltonFlyingGame/DaltonFlyer.html`**
2. **AirDrop** that one file to the iPhone (or Mail it to yourself and open the attachment)
3. On the iPhone, tap the file → **Open in Safari** if asked
4. Turn the phone sideways → **START MISSION**
5. Optional: Safari **Share** button → **Add to Home Screen** so it looks like an app

This needs internet the first time (it loads the 3D engine). Use Path A if you want a real home-screen app that does not depend on a website.
