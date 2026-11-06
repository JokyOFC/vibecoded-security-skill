---
paths:
  - "app.json"
  - "app.config.{js,ts}"
  - "eas.json"
  - "ios/**"
  - "android/**"
  - "**/*.{swift,kt,kts}"
---
<!-- Managed by vibecoded-security. Re-run /vibecoded-security:guardrails to update; local edits are overwritten. -->

# Mobile security rules

- Everything shipped in the app is public: `EXPO_PUBLIC_*`, `extra` in `app.config`, bundled JSON, native config. Only public keys (e.g. Supabase anon/publishable) may live there; never service keys or LLM provider keys.
- Tokens go to the Keychain/Keystore (`expo-secure-store`), never AsyncStorage or SharedPreferences in plain text.
- No cleartext traffic: no broad ATS exceptions, no `usesCleartextTraffic`, no staging URLs or debug flags in production builds.
- Deep links and universal links validate every parameter and never open protected screens without a session.
- No `console.log` of user data, tokens or API responses.
- OTA updates use code signing and the correct channel/runtime version.
- API changes must keep older app versions in the field working until they are retired.
- Health and biometric data (HealthKit, Health Connect, wearables): explicit consent, minimum data, nothing sent that the feature does not need.
