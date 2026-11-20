# Productie-check Stop Swiping — 20 november 2026

Wat er getest is: unit-tests (463) in de simulator, een release-build en een
debug-build op de iPhone 17 Pro (doorgelopen via een tijdelijke UI-test-driver),
een externe aanvalstest op de live Supabase-server met de publieke app-sleutel,
en een code-review van app, migraties en edge functions.

Niet getest (kon niet zonder jou): inloggen, matching, chat, pushberichten,
fotoverificatie en aankopen op het toestel. Daarvoor zijn een ingelogd account
en een tweede telefoon/account nodig. De live database is van buiten
aangevallen én van binnen gecontroleerd (alleen-lezen), zie §3.

## 1. Blokkers: niet live gaan voordat dit klaar is

| # | Probleem | Waarom het blokkeert | Wie |
|---|----------|----------------------|-----|
| B1 | De **privacyverklaring in de app is nog een sjabloon**: ~60 invulvelden zoals `[PRIVACY_EMAIL]`, `[LEGAL_ENTITY_NAME]`, `[NUMBER_OF_DAYS]`, `[PRIVACY_CONTACT]` (`Features/Privacy/PrivacyContent.swift`). Gebruikers zien dit bij het geven van toestemming. | De app verwerkt bijzondere persoonsgegevens (religie, intimiteit). Toestemming op basis van een onvolledige verklaring is onder de AVG niet geldig; App Review keurt dit ook af. Bedrijfsgegevens (naam, adres, KvK, e-mail) moeten van jou komen; de technische feiten (12 maanden bewaren, Supabase, Apple/Google, APNs) kan ik invullen. Let op: tekst wijzigen kan een bump van de consent-versie vragen, en dan moet de server mee (zie `privacy-consent-version-sync`). | jij + ik |
| B2 | **hakketjak.com/stop-swiping/privacy geeft 404** (ook /stop-swiping). | App Store Connect vereist een werkende privacy-URL; Google eist die ook voor OAuth-verificatie. | jij (website) |
| B3 | **Google-login staat nog in "Testing"** bij Google Cloud (één goedgekeurd testaccount). | Iedere echte gebruiker die op "Doorgaan met Google" tikt krijgt "toegang geblokkeerd". Publiceer de OAuth-app (na B2) of verberg de Google-knop tot dan. | jij |
| B4 | ~~Sandbox-aankopen telden als echte toegang (TestFlight → gratis lifetime in de App Store-versie).~~ **Opgelost:** `202611200001_production_hardening.sql` is op 20-11 live gezet. Toegang telt nu alleen voor productie-aankopen, en namen zijn op de server begrensd. Live tests: android_readiness 29/29, subscriptions 23/23. | — | klaar |

## 2. Beslissingen voor jou

| # | Punt | Mijn advies |
|---|------|-------------|
| D1 | **Verborgen gebaar**: 3 seconden vasthouden op de Lifetime-kaart opent het gratis early-adopter-plan opnieuw, *ook in productie* (`EarlyAccessView.swift:172`, bewust zo gedocumenteerd). | Achter `#if DEBUG` zetten. App Store-richtlijn 2.3.1 verbiedt verborgen functies, en iedereen die het ontdekt kan eindeloos gratis verlengen. |
| D2 | **De server controleert niet of iemand betaald heeft.** Toegang wordt alleen in de app gecontroleerd; met een account kan iemand via de API rechtstreeks het matching-profiel opslaan. | Voor de lancering acceptabel (vereist technische kennis). Later: `eligible()` laten kijken naar `store_entitlements`. |
| D3 | **Fotoverificatie vertrouwt de telefoon** (was al bewust gekozen voor de beta; App Attest is gebouwd maar niet op een echt toestel getest). | Voor een publieke lancering: App Attest op een toestel testen en daarna de onbewezen route afsluiten. |
| D4 | **Meldingen worden niet actief bewaakt.** Bij 3 meldingen volgt automatisch een ban, maar niemand krijgt een seintje bij een melding (bijv. "minderjarig"). | Apple (richtlijn 1.2) verwacht dat je snel reageert op meldingen en een contactadres publiceert. Een dagelijkse controle van `matching_private.overview` of een e-mailalert instellen. |
| D5 | `ITSAppUsesNonExemptEncryption` ontbreekt in Info.plist, dus bij elke upload vraagt App Store Connect naar export compliance. De chat gebruikt end-to-end-encryptie (standaard CryptoKit). | Eén keer de vragenlijst in App Store Connect invullen; daarna de sleutel toevoegen met de uitkomst. |
| D6 | "MBTI (Myers-Briggs)" is een geregistreerd handelsmerk. | Overweeg "16 types" of een eigen naam; de disclaimer "geen officiële test" staat er al. |

## 3. Server: wat goed zit

Getest van buiten met alleen de publieke sleutel die in elke app-download zit:

- Alle tabellen (`profiles`, `matches`, `encrypted_messages`, `match_cards`,
  `match_reports`, `push_devices`, `store_entitlements`, …) → `permission denied`.
- Alle RPC's (`current_match`, `chat_poll`, `delete_account`,
  `record_device_photo_verification`, `push_claim_due`, `retention_claim`, …) → `permission denied`.
- Storage: buckets en foto's niet op te vragen. OpenAPI-schema niet zichtbaar.
- Edge functions zonder login → 401.
- Login: alleen Apple en Google; e-mail en anonieme accounts staan uit.

Van binnen (live catalogus, alleen-lezen query, 20-11 08:20):

- Geen tabel in `public`/`matching_private`/`api_guard` zonder RLS; geen
  tabelrechten voor `anon`; geen functie die `anon` kan uitvoeren.
- Alle `security definer`-functies hebben een vast `search_path`.
- `authenticated` kan precies de 19 bedoelde functies aanroepen, en niets anders.
- `pgrst.db_pre_request = api_guard.check_request` staat aan; statement- en
  lock-timeout 8 s.
- Bucket `profile-photos`: privé, 2 MB, alleen JPEG; 5 storage-policies.
- 6 cron-jobs actief, laatste run steeds gelukt, 0 fouten in 24 uur.
- `question_ids()` = 50 vragen.
- Vault: `identity_hash_key`, `push_dispatch_secret`; `retention_secret` ontbreekt nog (bekend).
- De database is leeg (0 accounts, profielen, matches, aankopen); B4 is uitgerold zonder gebruikers te raken.

In de code zitten verder: limieten op profielgrootte (128 kB), foto's (12, 2 MB),
chat (32 kB, 60/min, 5 MB/dag), 120 schrijfacties/min per account, maximaal
1 meldreden per uur, één zoekactie per minuut, en een App Store-handtekeningcheck
die aan Apple's root-certificaat vastzit.

Nog open uit eerdere sessies: `retention-purge` heeft "Verify JWT" nog aan en
`RETENTION_SECRET` is nog niet gezet; de Deno-tests van de edge functions zijn
nooit gedraaid; de IAP-producten stonden op 19-11 nog op MISSING_METADATA
(screenshots voor de review ontbraken).

## 4. Vandaag gerepareerd (in de werkmap, nog niet gecommit)

| Probleem | Fix |
|----------|-----|
| **Geen privacy-manifest**: App Store Connect weigert uploads die UserDefaults/systemUptime gebruiken zonder `PrivacyInfo.xcprivacy`. | Manifest toegevoegd voor de app (CA92.1, 1C8F.1, 35F9.1) en de notificatie-extensie (1C8F.1). |
| **Camera-toestemmingstekst noemde AWS in Ierland**, terwijl AWS uit staat. Dat is misleidend en een afwijsreden. | Tekst (EN+NL) zegt nu dat de scan op de iPhone gebeurt en het camerabeeld nooit wordt geüpload (gecontroleerd: alleen het foto-ID gaat naar de server). |
| **Opstart-race**: als StoreKit iets later antwoordde dan het welkomstscherm laadde, zag een betalende gebruiker zonder account "Beginnen" (het pad naar het betaalscherm) in plaats van zijn profiel. Twee keer gezien op je telefoon. | Het welkomstscherm springt alsnog naar het profiel zodra de toegang binnenkomt. Daarna 4× herstart op het toestel: steeds goed. |
| Bij een **storing bij Supabase (5xx)** tijdens het opstarten werd een ingelogde gebruiker als uitgelogd getoond. | Alleen echt uitloggen als de server het token weigert; bij storingen blijft de lokale sessie staan. |
| De naam van een match kwam ongefilterd van de server; via de API kon iemand een naam van 100 kB zetten. | De app kort hem in tot 30 tekens; de server staat nu maximaal 400 tekens toe (live, B4). |
| **Taalkeuze-sheet** was half leeg (2 opties in een halve-schermsheet). | De sheet is nu precies zo hoog als de inhoud en groeit mee met grotere tekst. Gecontroleerd op het toestel. |
| De sluitknop van de **scanner** stond op een andere plek dan op de andere schermen (16/8 pt tegenover 20/20). | Gelijkgetrokken met "Mijn matches" en het profieloverzicht. |
| De tijdelijke debug-probe `TempSheetProbe` zat nog in de app. | Verwijderd. |
| Een lege vertaalsleutel `", %lld"` liet de vertaaltest falen. | De naam/leeftijd-tekst is nu `verbatim`; de sleutel is verwijderd. |
| 3 tests verwachtten oude teksten ("Go celebrate your birthday…", "potential partner"). | Tests bijgewerkt naar jouw nieuwe teksten. |

Testresultaat na de fixes: zie §6.

## 5. Schermen die nog aandacht verdienen

- **Mijn matches (leeg)**: kaal zwart scherm met alleen "Nog geen matches." —
  geen uitleg hoe je een match krijgt (QR-code, telefoons tegen elkaar,
  automatisch matchen) en geen actieknop. Valt uit de toon bij de rest.
- **Profieloverzicht**: vragen tonen "Jij: 4 / Partner: 4". Het eindlabel
  (bijv. "Hopeloos romantisch") zegt veel meer. De sluitknop scrollt mee
  weg, dus na een lange lijst moet je eerst terug naar boven.
- **Engelse datums** staan in Amerikaanse notatie ("November 19, 2008") terwijl
  de primaire store-taal en-GB is.
- **6 NL-teksten staan nog op "needs review"** in de vertalingen (o.a. "Minderjarigen
  niet toegestaan", de dealbreaker-koppen, "Kom over 18 jaar terug").
- Op het toestel bekeken en in orde: welkomstscherm/helix, persoonlijkheids-
  paneel, profieloverzicht, bewerkscherm van een vraag, QR-code, scanner,
  account aanmaken, de bevestiging bij "Profiel verwijderen" (geannuleerd,
  er is niets verwijderd), taalwissel EN/NL.

## 6. Tests

- Unit-tests: 463, waarvan 2 falen: `WelcomeLightEntranceTests.testTheHeadAndMaterialKeepMovingThroughHeartClosure`
  (tekensnelheid bij het sluiten van het hart) en
  `WelcomeLightMetalTests.testActualMetalRendererDrawsDistinctHeartAndCirclePoses`
  (niet alle pixels volledig dekkend). Beide horen bij de animatie die je in
  "first screens improved" hebt bijgesteld; op het toestel ziet het licht er goed
  uit. Pas de drempels aan als dit de bedoeling is, of laat het mij nakijken.
- `TmpMatchFramesTests.swift` is een tijdelijke render-test die nog in de testtarget zit.
- Opstarttijd release-build op de iPhone: ongeveer 6 s tot het welkomstscherm met helix.

## 7. Volgende stappen om de rest te testen

1. Log op de telefoon in met Apple (dat moet jij doen) → dan test ik
   profiel-upload, push-registratie en App Attest.
2. Een tweede account/telefoon voor matching en chat (of een testaccount op
   de simulator via Google, zodra B3 klaar is).
