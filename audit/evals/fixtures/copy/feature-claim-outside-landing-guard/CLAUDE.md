# reportly, CLAUDE.md

## Landing-Content, Produktaussagen

Was in `resources/landing/**/*.md` ueber reportly behauptet wird, muss der Code decken. Real sind
CSV-Export und der woechentliche E-Mail-Digest. NICHT real ist jede Form von automatischem
PDF-Export, das ist noch nicht gebaut. `LandingProductClaimsTest` erzwingt das, deckt aber nur
`resources/landing/**/*.md` ab, nicht `lang/*.php`.
