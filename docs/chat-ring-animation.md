# Matchhart naar chatcirkels — 15 november 2026

De chat gebruikt nu de cirkelbeweging van het welkomstscherm, met behoud van het tekenvlak en de schouders van het matchhart.

## Onderzoek

De vergelijking is gemaakt tussen `WelcomeLightGeometry.Frame`, de Metal-functies `ribbonPoint` en `matchPointAt`, de chatklok, de transformatie in `WelcomeView` en het scrollmasker in `MatchChatPanel`.

De vorige chatanimatie week op vier punten af:

- Een eigen rotatie van acht seconden draaide twee gekantelde ringen als één stijf object. Het welkomstscherm gebruikt een doorlopende fase met snelheidscompensatie, bewegende linten, lokale vertraging, diepte en perspectief.
- De chat verkleinde het complete tekenvlak naar 72% en verschoof het omhoog. Daardoor konden cirkels de positie en het formaat van het hart niet behouden, ongeacht de shadergeometrie.
- De eigen straal van 0,47 en afstand van 0,38 tot het midden sloten niet aan op de oorspronkelijke hartbogen. Inclusief de verkleining was de halve breedte ongeveer 0,61, tegenover 0,97 voor het hart.
- De sluiting vervormde de draaduiteinden met een niet-periodieke weefbeweging. Een vervagende overlap maskeerde de uiteinden, maar garandeerde geen overeenkomstige positie, raaklijn en diepte.

Daarnaast bleek dat een opnieuw geopende chat al gevormde cirkels kon aanvragen terwijl de onderliggende match nog op tijdstip nul stond. Het zichtbaarheidsvenster van de entree kon de cirkels daardoor verbergen.

## Implementatie

`circleRibbonPoint` is de gedeelde Metal-geometrie voor de ronde fase van het welkomstscherm en de chat. Beide gebruiken dezelfde lintgolven, breedtevariatie, diepte, lokale rotatievertraging, perspectief en kanteling. De bestaande hart- en entreeroutes blijven hun eigen vormen gebruiken.

De chat start op `WelcomeLightGeometry.circleTime`. De voortgaande klok loopt via dezelfde `WelcomeLightMotionClock` en dezelfde rotatiecurve als het welkomstscherm. De overgang trekt de punt en de uitlopers van het hart naar de ringen. De snelheid loopt geleidelijk op; na het opstarten duurt een omwenteling dezelfde 6,042 seconden als op het welkomstscherm. De vorm blijft rond terwijl de rotatie en lichtdraden doorgaan.

De cirkels sluiten aan op de oorspronkelijke schouders:

- Bovenkant: −0,88 in de bestaande genormaliseerde coördinaten.
- Buitenste breedte: x = ±0,97.
- Verticaal middelpunt: −0,30; verticale straal: 0,58.
- Geen aanvullende schaalverandering of verplaatsing van het tekenvlak wanneer de chat opent.

De oorspronkelijke linker- en rechterboog blijven bij hun eigen cirkel tijdens het sluiten. Het weefpatroon is periodiek over één ring, zodat de overlappende uiteinden dezelfde geometrie hebben. Zodra de overgang klaar is, slaat de shader de berekening van de onzichtbare hartgeometrie over.

Het berichtenmasker gebruikt de positie van datzelfde tekenvlak en reserveert ruimte voor de cirkels en hun gloed. Bij een klein venster met toetsenbord verkort het masker de transparante zone en de vervaging, zodat de nieuwste berichten leesbaar blijven zonder de cirkels te verplaatsen. Heropende chats krijgen direct een voltooid onderliggend hart, zowel voor een nieuwe als een opgeslagen match.

Bij Verminder beweging worden de volledige cirkels stil getoond. De toepassing van deze systeemvoorkeur volgt [Apples documentatie over accessibilityReduceMotion](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityReduceMotion).

## Verificatie

De controles gebruiken de echte Metal-renderpipeline en GPU-computefuncties, naast de bestaande geometrie-, klok- en chatcontroles. Dat controleert ook de runtimecompilatie van de shader; zie [Apples documentatie over Metal-shadercontrole](https://developer.apple.com/documentation/xcode/validating-your-apps-metal-shader-usage).

Nieuwe regressiecontroles dekken de gedeelde welkomstklok, het oorspronkelijke formaat, de ringnaad inclusief diepte, eindige posities, vloeiende tussenstappen, heropende chats, Verminder beweging, nieuwe en opgeslagen matches en de chatindeling op compacte en normale schermen.

Renderresultaten staan in `outputs/chat-rings`: een animatie uit de daadwerkelijke renderer en een overzicht van de overgang voor beide matchroutes. De gerichte suite voor chat, geometrie en Metal is geslaagd: **29 tests, nul fouten**. Na de laatste aanpassing van het berichtenmasker zijn de vijf chatanimatie- en indelingscontroles opnieuw geslaagd. Simulatorcontroles bewijzen geen prestaties op een fysieke iPhone.

## Doorlopende sluiting met rustigere eerste draai

De ronde vorm is al zichtbaar voordat de morphklok op 2,6 seconden eindigt. De vorige aanloop (2,2–2,6 seconden) wachtte daardoor visueel nog steeds en versnelde vervolgens te sterk. De draai begint nu geleidelijk vanaf 1,3 seconden en bereikt de normale klok op 2,9 seconden. De vormverandering en de draai overlappen met een brede, vloeiende versnelling.

Een meting van de hoekbeweging tot de eerste kruising laat zien dat de aanvankelijke pieksnelheid afneemt van ongeveer 1,39 naar 0,99 rad/s, en de hoogste versnelling van 6,93 naar 1,56 rad/s². Zodra de cirkels visueel rond worden, bewegen ze al. De volgende rondes behouden de beweging van het welkomstscherm; positie en formaat blijven behouden.

De regressiecontrole bewaakt zichtbare beweging vóór het technische einde van de sluiting, begrenst de eerste snelheids- en versnellingspiek en vergelijkt de kruising met de volgende rondes. `chat-first-turn-comparison.gif` toont de vorige korte aanloop naast de geleidelijke overgang op 24 beelden per seconde.

Verificatie: **12 gerichte simulatorcontroles geslaagd, nul fouten**, inclusief de pieksnelheid en versnelling over de hele aanloop, de aansluiting op de volgende rondes en de Metal-renderbeelden.
