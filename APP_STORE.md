# TestFlight checklist — Tesla Trek

1. Confirm https://www.tesla-trek.com shows the new companion + /car HUD
2. `npm install && npx cap add ios && npx cap sync ios` (first time only)
3. Open Xcode → set Team / bundle id matching your existing TestFlight app if updating
4. Archive → Upload → TestFlight **only if native shell / permissions changed**
5. Internal testing group: open app → Connect Tesla (Demo) → Claim cache → Car HUD

**Content updates** (UI, quests, HUD): ship web to tesla-trek.com — TestFlight picks them up on next launch. No new binary required.

Privacy: Location optional (GPS claims). No account required for demo mode.
