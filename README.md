# Tesla Trek — iOS / TestFlight shell

Capacitor wrapper. Bundle id: `com.lvlltd.teslatrek`.

**Sep 13, 2026:** `server.url` was removed so the app loads the bundled TRON prototype in `native-shell/index.html` instead of https://www.tesla-trek.com.

## Windows (PowerShell)
```powershell
cd $HOME\Documents
git clone https://github.com/omgawdmadeit1/tesla-trek-app.git
cd tesla-trek-app
Start-Process native-shell\index.html
```

To restore the live-site wrapper later, put this back in `capacitor.config.json`:
```json
"server": { "url": "https://www.tesla-trek.com" }
```

## Cloud Mac / TestFlight
```bash
npm install
npx cap add ios
npx cap sync ios
npx cap open ios
```
Then Archive → TestFlight.

Related kit: https://github.com/omgawdmadeit1/tesla-trek-tron-handoff
