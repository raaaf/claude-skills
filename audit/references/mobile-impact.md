# Mobile App Impact Matrix

Only relevant when `bin/detect-mobile.sh` detects a mobile app in the repo.

| Change | Mobile Relevance | Rating |
|----------|-----------------|------------|
| API endpoints changed/removed | Breaking change — app must be updated | Important |
| API response format changed | Breaking change — app parsing breaks | Important |
| New API fields added | Not a breaking change, but the app won't use them without an update | Minor |
| Auth flow changed | Breaking change — login in the app breaks | Important |
| Push notification payload changed | App receives wrong data | Important |
| Deep link routes changed | App navigation breaks | Important |
| Shared code changed (monorepo) | Directly affected — check whether the app build still works | Important |
| Only frontend/web changed | No mobile impact (except WebView/Capacitor) | — |

Rate findings as **Important** when breaking changes are detected, as **Minor** when only new fields/endpoints are added.
