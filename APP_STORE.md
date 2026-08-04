# TestFlight checklist — Tesla Trek

1. Confirm https://www.tesla-trek.com shows the new companion + /car HUD
2. `npm install && npx cap add ios && npx cap sync ios`
3. Open Xcode → set Team / bundle id matching your existing TestFlight app if updating
4. Archive → Upload → TestFlight
5. Internal testing group: open app → Connect Tesla (Demo) → Claim cache → Car HUD

Privacy: Location optional (GPS claims). No account required for demo mode.
