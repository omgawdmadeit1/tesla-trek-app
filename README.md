# Tesla Trek — iOS / TestFlight shell

Capacitor wrapper that loads **https://www.tesla-trek.com** live (same pattern as Hu-ManForge).

When you ship a new web build to `tesla-trek.com`, TestFlight testers get it on next app open — no App Store resubmit required for content.

## Live (Aug 2026)
- Production: [https://www.tesla-trek.com](https://www.tesla-trek.com)
- Car HUD: [https://www.tesla-trek.com/car](https://www.tesla-trek.com/car)
- Companion: Hunt the Drive · Fund the Cyberbeast (TanStack Start)

## Requirements
- macOS + Xcode 16+
- Apple Developer team (LVL LTD / your team)
- CocoaPods / bundler if you use Fastlane

## Bootstrap (once)
```bash
npm install
npx cap add ios
npx cap sync ios
npx cap open ios
```

In Xcode:
1. Set Team + bundle id `com.lvlltd.teslatrek` (or your existing TestFlight id)
2. Signing & Capabilities → Automatic
3. Product → Archive → Distribute → TestFlight

## Config
Live URL is in `capacitor.config.json` → `server.url`.

Allowed hosts include `tesla-trek.com`, Vercel, and CDN asset hosts used by the companion.

## Note
This is the **live web shell**. The archived native SwiftUI prototype lives at `tesla-trek-ios`.
