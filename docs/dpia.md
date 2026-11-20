# DPIA Stop Swiping (concept, 20 november 2026)

Gegevensbeschermingseffectbeoordeling volgens artikel 35 AVG. Concept op basis
van de code en de live configuratie op 20 november 2026. Wat tussen
`[haken]` staat, moet de verwerkingsverantwoordelijke zelf invullen of
beslissen. Laat het geheel vóór de lancering nalezen door iemand met
juridische kennis.

## 1. Waarom een DPIA verplicht is

De app verwerkt bijzondere persoonsgegevens (art. 9 AVG): religie of
levensovertuiging, seksuele voorkeuren en relatievorm, en gebruik van alcohol,
tabak en drugs (gezondheid). Daarnaast profileert en matcht hij mensen
automatisch, met locatie. Volgens de lijst van de Autoriteit Persoonsgegevens
(AP) en de EDPB-criteria (gevoelige gegevens, profilering, nieuwe technologie,
koppeling van gegevens) is een DPIA verplicht.

## 2. De verwerking

| | |
| --- | --- |
| Verwerkingsverantwoordelijke | [OFFICIËLE NAAM, ADRES, KVK] |
| Contact privacy | [E-MAIL] |
| Betrokkenen | Volwassen gebruikers (18+, gecontroleerd via geboortedatum) en de mensen met wie zij matchen |
| Verwerkers | Supabase Inc. (database, opslag, authenticatie, functies; regio West EU, Ierland), Apple (inloggen, pushberichten, App Store, App Attest, iCloud), Google (inloggen; later pushberichten en Play) |
| Doorgifte buiten de EER | Supabase, Apple en Google zijn Amerikaanse bedrijven. [CONTROLEER: EU-VS Data Privacy Framework-certificering en SCC's in de verwerkersovereenkomsten] |

### Wat waar staat

| Gegevens | Waar | Wie kan het lezen | Bewaartermijn |
| --- | --- | --- | --- |
| Volledig profiel, antwoorden, foto's | Telefoon | Gebruiker | Tot verwijderen |
| Back-up profiel en opgeslagen matches | iCloud van de gebruiker, versleutelde velden | Alleen de gebruiker | Tot verwijderen |
| Matchingprofiel incl. bijzondere gegevens, locatie ~1 km | Supabase `profiles` | Server/beheerder, gebruiker zelf | Alleen zolang automatisch matchen aan staat; 12 mnd inactief → weg |
| Matchingfoto | Supabase Storage, privé | Gebruiker; match alleen tijdens de match | Idem |
| Chatberichten | Supabase, end-to-end versleuteld (HPKE) | Alleen de twee telefoons | 12 maanden |
| Match (ID's, scores, data) en identiteitshashes (HMAC) | Supabase | Deelnemers / alleen server | 5 jaar na einde match |
| Meldingen | Supabase | Beheerder | Toelichting 12 mnd; melding 5 jaar |
| Account (Apple/Google-ID, e-mail van provider) | Supabase Auth | Beheerder | Tot accountverwijdering |
| Aankopen (transactie-ID, product) | Supabase | Beheerder, gebruiker | Met het account |
| Pushtoken, taal, tijdzone | Supabase | Beheerder | 12 mnd inactief of ingetrokken token |

## 3. Doelen en grondslagen

| Doel | Gegevens | Grondslag |
| --- | --- | --- |
| Profiel maken en lokaal vergelijken (QR, telefoons tegen elkaar) | Alle antwoorden, lokaal | Art. 6(1)(b); art. 9(2)(a) uitdrukkelijke toestemming (profieltoestemming) |
| Automatisch matchen op de server | Matchingprofiel, foto, locatie ~1 km | Art. 6(1)(b); art. 9(2)(a) uitdrukkelijke toestemming (matchingtoestemming, apart) |
| Chat tussen matches | Versleutelde berichten, metadata | Art. 6(1)(b) |
| Veiligheid: meldingen, blokkades, ban-ontwijking | Meldingen, identiteitshashes | Art. 6(1)(f) gerechtvaardigd belang (veiligheid van gebruikers) [AFWEGING VASTLEGGEN] |
| Aankopen en toegang | Transacties | Art. 6(1)(b) |
| Fotoverificatie | Alleen foto-ID; de scan blijft op de telefoon | Art. 6(1)(b); geen biometrische verwerking op de server |

Toestemming is per versie vastgelegd (receipt met versienummer). De server laat
niemand in de matchingpool zonder beide actuele toestemmingen. Intrekken kan
door automatisch matchen uit te zetten (profiel en foto gaan direct van de
server) of door het profiel te verwijderen.

## 4. Noodzaak en evenredigheid

- **Minimalisatie.** Locatie wordt vóór uploaden afgerond (~1 km). Foto's
  worden verkleind (1080 px). Alleen wie automatisch matchen aanzet, heeft een
  profiel op de server; zet je het uit, dan gaat het profiel direct weg.
- **Geen losse antwoorden zichtbaar.** Een match toont scores per categorie,
  nooit antwoorden op losse vragen.
- **Lokaal waar het kan.** Handmatig matchen gebeurt helemaal op de
  telefoons. De gezichtsscan blijft op de telefoon; de server krijgt alleen
  een door Apple bewezen melding (App Attest) dat de scan klopte.
- **Bekend punt.** Het matchingprofiel staat dubbel op de server (`profile` en
  `backup`). [TERUGBRENGEN NAAR ÉÉN KOPIE vóór grote groei]

## 5. Risico's voor betrokkenen

| # | Risico | Kans | Ernst | Maatregelen | Rest |
| --- | --- | --- | --- | --- | --- |
| R1 | Datalek van de server toont religie, seksuele voorkeur en middelengebruik | Laag | Hoog | RLS op alle tabellen, geen anonieme toegang, ingelogde gebruikers kunnen alleen de bedoelde functies aanroepen, versleuteling op schijf en tijdens transport, gegevens alleen bij automatisch matchen, bewaartermijnen, EU-regio. [MFA OP HET SUPABASE-ACCOUNT, NOG IN TE STELLEN] | Middel |
| R2 | Misbruik door iemand met beheertoegang | Laag | Hoog | Eén beheerder, beheerdersoverzicht alleen in de SQL-editor, chatinhoud end-to-end versleuteld | Middel |
| R3 | Iemand leest via de app andermans antwoorden | Laag | Middel | Verzegelde profielcode, alleen categoriescores op scherm, QR verloopt na 24 uur. Wie de app ontleedt kan codes openen (uitgelegd in de privacyverklaring) | Laag |
| R4 | Nepprofielen of catfishing | Middel | Middel | Fotoverificatie op de telefoon, bewezen met App Attest; meldingen met waarschuwing, blokkade en ban, ook bij een nieuw account | Laag |
| R5 | Minderjarigen | Laag | Hoog | Leeftijdsslot in de app, server laat alleen 18+ toe, meldreden "minderjarig" met directe push naar de beheerder | Laag |
| R6 | Chatberichten worden gelezen | Laag | Hoog | HPKE end-to-end; sleutels alleen op het toestel. Geen forward secrecy (uitgelegd in de privacyverklaring) | Laag |
| R7 | Heridentificatie via identiteitshashes | Laag | Laag | HMAC-SHA256 met geheime sleutel in Vault; termijn 5 jaar | Laag |
| R8 | Profilering leidt tot uitsluiting | Middel | Laag | Gebruiker kiest eigen eisen en minimumscore; geen beslissing met rechtsgevolg (art. 22 niet van toepassing) | Laag |
| R9 | Doorgifte naar de VS | Middel | Middel | [DPF/SCC CONTROLEREN]; Apple en Google zien pushberichten zonder naam of inhoud | [INVULLEN] |

## 6. Rechten van betrokkenen

- Inzage en overdraagbaarheid: [PROCES EN TERMIJN, bijv. export via de app of op verzoek per e-mail]
- Verwijderen: in de app (profiel verwijderen wist account, server, foto's, iCloud en telefoon; Apple-tokens worden ingetrokken)
- Bezwaar en intrekken van toestemming: automatisch matchen uit, of verwijderen
- Klacht: Autoriteit Persoonsgegevens

## 7. Nog te doen vóór de lancering

1. Bedrijfsgegevens en contact in de privacyverklaring; privacy-URL online.
2. Verwerkersovereenkomst (DPA) met Supabase ondertekenen (dashboard → Organization → Legal documents) en de doorgifte (DPF/SCC) vastleggen.
3. MFA op het Supabase-account.
4. Belangenafweging voor de veiligheidsverwerking (R4/R5, art. 6(1)(f)) vastleggen.
5. Procedure voor meldingen: reactietermijn, wie beoordeelt, wanneer melden bij politie (minderjarigen).
6. Datalekprocedure (72 uur bij de AP).
7. Deze DPIA laten nalezen en ondertekenen; herzien bij elke grote wijziging.

Ondertekend: [NAAM, DATUM]
