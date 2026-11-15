import Foundation

/// NL/EN privacy copy. The approval screens show short points first; the
/// sections hold the complete terms the user agrees to. Changing the meaning
/// of any approval text requires bumping `PrivacyConsentKind.version`.
enum PrivacyContent {
    struct Point: Hashable {
        let symbol: String
        let title: String
        let text: String
    }

    struct Section: Hashable {
        let title: String
        let body: String
    }

    struct Approval {
        let title: String
        let points: [Point]
        let sections: [Section]
        let acknowledgement: String
    }

    static func approval(_ kind: PrivacyConsentKind, language: AppLanguage) -> Approval {
        switch (kind, language) {
        case (.profile, .english):
            profileEN
        case (.matching, .english):
            matchingEN
        case (.profile, .dutch):
            profileNL
        case (.matching, .dutch):
            matchingNL
        }
    }

    static func policy(language: AppLanguage) -> String {
        switch language {
        case .english: policyEN
        case .dutch: policyNL
        }
    }

    // MARK: - Profile

    private static let profileEN = Approval(
        title: "Please read!",
        points: [
            Point(symbol: "iphone",
                  title: "Stored on your iPhone",
                  text: "Nobody else can see your profile until you share it yourself."),
            Point(symbol: "icloud",
                  title: "Backup is optional",
                  text: "With an account you can back up your profile to restore it later. A backup is never visible to other users."),
            Point(symbol: "arrow.left.arrow.right",
                  title: "Sharing means everything",
                  text: "In an exchange you both receive each other's full profile: all answers, importance ratings and dealbreakers. You can't hide individual answers."),
            Point(symbol: "clock.arrow.circlepath",
                  title: "Shared stays shared",
                  text: "The other person keeps the version from that moment. Later edits don't change it, and we can't recall saved copies or screenshots."),
            Point(symbol: "sparkles",
                  title: "Automatic matching is separate",
                  text: "We'll ask for your permission for that separately.")
        ],
        sections: [
            Section(title: "Storage on your device",
                    body: "Your answers, importance ratings, preferences and dealbreakers are stored on your iPhone. Depending on your settings, they may also be included in your Apple device backup, which is governed by Apple's terms."),
            Section(title: "Cloud backup",
                    body: "Only if you create an account and turn on backup do we store a copy with our cloud provider, Supabase. It is protected in transit and at rest, and access is limited to what is needed to run the service. A backup does not make your profile visible or enroll you in matching."),
            Section(title: "Profile exchange",
                    body: "An exchange only happens when both of you start or accept it. You each receive a snapshot of the other's complete profile. Login details and chats are not included."),
            Section(title: "Information already shared",
                    body: "Later edits don't change snapshots or match scores that were already shared. Recipients can save information or take screenshots; we can't remove copies kept outside the app. Requests about copies within our service are handled under the Privacy Policy."),
            Section(title: "Security",
                    body: "We use secure connections, encrypted storage and restricted access. Cloud data is not technically unreadable to every administrator. We don't sell your information or use your answers for advertising."),
            Section(title: "Chats",
                    body: "Messages are encrypted on your device and only decrypted on the recipient's. We process only what delivery requires, such as account IDs and timestamps. If you attach messages to a report yourself, we can review that content."),
            Section(title: "Your rights",
                    body: "You can edit your profile, manage your backup, and request access, correction or deletion in the app or via [PRIVACY_CONTACT]. Retention periods and all your rights are set out in the Privacy Policy."),
            Section(title: "Automatic matching",
                    body: "Automatic matching processes your complete answers on our servers. We only do this with your separate, explicit consent.")
        ],
        acknowledgement: "I understand how my profile is stored and that an exchange shares my complete profile."
    )

    private static let profileNL = Approval(
        title: "Even lezen!",
        points: [
            Point(symbol: "iphone",
                  title: "Opgeslagen op je iPhone",
                  text: "Niemand ziet je profiel tot je het zelf deelt."),
            Point(symbol: "icloud",
                  title: "Back-up is optioneel",
                  text: "Met een account kun je een back-up maken om je profiel later te herstellen. Een back-up is nooit zichtbaar voor andere gebruikers."),
            Point(symbol: "arrow.left.arrow.right",
                  title: "Delen is alles delen",
                  text: "Bij een uitwisseling krijgen jullie allebei elkaars volledige profiel: alle antwoorden, wegingen en breekpunten. Losse antwoorden verbergen kan niet."),
            Point(symbol: "clock.arrow.circlepath",
                  title: "Gedeeld blijft gedeeld",
                  text: "De ander houdt de versie van dat moment. Latere wijzigingen passen die niet aan, en opgeslagen kopieën of screenshots kunnen we niet terughalen."),
            Point(symbol: "sparkles",
                  title: "Automatisch matchen is apart",
                  text: "Daarvoor vragen we later los toestemming.")
        ],
        sections: [
            Section(title: "Opslag op je toestel",
                    body: "Je antwoorden, wegingen, voorkeuren en breekpunten worden op je iPhone opgeslagen. Afhankelijk van je instellingen kunnen ze ook in je Apple-reservekopie terechtkomen; daarvoor gelden de voorwaarden van Apple."),
            Section(title: "Cloudback-up",
                    body: "Alleen als je een account aanmaakt en back-up aanzet, bewaren we een kopie bij onze cloudverwerker Supabase. Die is beveiligd tijdens verzending en opslag, en toegang is beperkt tot wat nodig is voor de dienst. Een back-up maakt je profiel niet zichtbaar en meldt je niet aan voor matching."),
            Section(title: "Profieluitwisseling",
                    body: "Een uitwisseling gebeurt alleen als jullie die allebei starten of accepteren. Jullie ontvangen dan een momentopname van elkaars volledige profiel. Inloggegevens en chats horen daar niet bij."),
            Section(title: "Eerder gedeelde gegevens",
                    body: "Latere wijzigingen veranderen eerder gedeelde momentopnamen en matchscores niet. Een ontvanger kan gegevens bewaren of screenshots maken; kopieën buiten de app kunnen wij niet verwijderen. Verzoeken over kopieën binnen onze dienst behandelen we volgens de Privacyverklaring."),
            Section(title: "Beveiliging",
                    body: "We gebruiken beveiligde verbindingen, versleutelde opslag en beperkte toegangsrechten. Cloudgegevens zijn niet voor iedere beheerder technisch onleesbaar. We verkopen je gegevens niet en gebruiken je antwoorden niet voor advertenties."),
            Section(title: "Chats",
                    body: "Berichten worden op jouw toestel versleuteld en pas bij de ontvanger ontsleuteld. We verwerken alleen wat nodig is voor aflevering, zoals account-ID's en tijdstippen. Voeg je zelf berichten toe aan een melding, dan kunnen wij die inhoud bekijken."),
            Section(title: "Je rechten",
                    body: "Je kunt je profiel aanpassen, je back-up beheren en in de app of via [PRIVACYCONTACT] inzage, correctie of verwijdering vragen. Bewaartermijnen en al je rechten staan in de Privacyverklaring."),
            Section(title: "Automatisch matchen",
                    body: "Bij automatisch matchen worden je volledige antwoorden op onze servers verwerkt. Dat doen we alleen met je aparte, uitdrukkelijke toestemming.")
        ],
        acknowledgement: "Ik begrijp hoe mijn profiel wordt opgeslagen en dat ik bij een uitwisseling mijn volledige profiel deel."
    )

    // MARK: - Automatic matching

    private static let matchingEN = Approval(
        title: "Automatic matching",
        points: [
            Point(symbol: "server.rack",
                  title: "Processed on our servers",
                  text: "Your complete matching profile is stored and automatically compared with other participants. This includes sensitive answers about your religion, sexuality and use of alcohol, tobacco and drugs."),
            Point(symbol: "person.2",
                  title: "Shared when you match",
                  text: "When you match, you both immediately see each other's full profile and a compatibility score. You don't approve each match first."),
            Point(symbol: "pin",
                  title: "Fixed at that moment",
                  text: "The score and shared profile don't update. Your edits only count for new matches."),
            Point(symbol: "arrow.uturn.backward",
                  title: "Withdrawing consent",
                  text: "Turn matching off and you won't get new matches. Anything already shared with a match stays with that person."),
            Point(symbol: "lock",
                  title: "Private stays private",
                  text: "Chats are end-to-end encrypted. We don't sell your information or use it for advertising.")
        ],
        sections: [
            Section(title: "What we use",
                    body: "Your complete matching profile: all answers, importance ratings, preferences and dealbreakers, plus the technical data needed to compare profiles. It is stored with our cloud provider, Supabase. This includes special categories of personal data: your religion or worldview, your gender and the genders you are interested in (which reveal your sexual orientation), your preferences around sex and intimacy, and how often you use alcohol, tobacco and drugs."),
            Section(title: "How matching works",
                    body: "We first check dealbreakers and required criteria in both directions, then calculate a compatibility score from answers and importance ratings. A match is only created when the criteria are met. The score is the result of our calculation, not a prediction of relationship success."),
            Section(title: "What a match sees",
                    body: "A snapshot of your complete profile, including your name and photo if they are part of your profile. Individual answers can't be hidden. By turning on matching you agree to this in advance; we don't ask again for each match."),
            Section(title: "Fixed scores",
                    body: "When a match is created, we save the score and both profiles. Later edits don't change them, so an older score may differ from your current answers. New matches use your latest information."),
            Section(title: "Security",
                    body: "Data is protected in transit and at rest. Where possible we separate account details from matching data and restrict access. Because our servers must compare your answers, this processing is not end-to-end encrypted."),
            Section(title: "Turning matching off",
                    body: "You'll no longer be included in new matches, and your matching data is deleted or deactivated according to the retention periods in the Privacy Policy. Existing matches, shared snapshots and copies kept by others don't disappear automatically. Your cloud backup follows your backup settings."),
            Section(title: "Chats and reports",
                    body: "Chats are end-to-end encrypted. We process limited metadata for delivery, safety and support. If you add messages to a report yourself, we can review that content."),
            Section(title: "Withdrawal and your rights",
                    body: "You can withdraw your consent at any time by turning off automatic matching. This stops further processing but does not make earlier processing unlawful. You can exercise your privacy rights via [PRIVACY_CONTACT]. The service providers we use are listed in the Privacy Policy.")
        ],
        acknowledgement: "I explicitly consent to my complete matching profile, including sensitive answers about my religion, sexuality and substance use, being stored and automatically processed to find matches, and automatically shared with each match. I can withdraw this consent at any time; anything already shared stays with the recipient."
    )

    private static let matchingNL = Approval(
        title: "Automatisch matchen",
        points: [
            Point(symbol: "server.rack",
                  title: "Verwerkt op onze servers",
                  text: "Je volledige matchingprofiel wordt opgeslagen en automatisch vergeleken met andere deelnemers. Daarin staan ook gevoelige antwoorden over je geloof, seksualiteit en gebruik van alcohol, tabak en drugs."),
            Point(symbol: "person.2",
                  title: "Gedeeld bij een match",
                  text: "Bij een match zien jullie direct elkaars volledige profiel en een matchpercentage. Je keurt niet elke match vooraf goed."),
            Point(symbol: "pin",
                  title: "Vastgelegd op dat moment",
                  text: "Score en gedeeld profiel veranderen niet mee. Je wijzigingen tellen alleen voor nieuwe matches."),
            Point(symbol: "arrow.uturn.backward",
                  title: "Toestemming intrekken",
                  text: "Zet matching uit en je krijgt geen nieuwe matches meer. Wat al met een match is gedeeld, blijft bij die persoon."),
            Point(symbol: "lock",
                  title: "Privé blijft privé",
                  text: "Chats zijn end-to-end versleuteld. We verkopen je gegevens niet en gebruiken ze niet voor advertenties.")
        ],
        sections: [
            Section(title: "Welke gegevens",
                    body: "Je volledige matchingprofiel: alle antwoorden, wegingen, voorkeuren en breekpunten, plus de technische gegevens die nodig zijn om te vergelijken. We bewaren dit bij onze cloudverwerker Supabase. Daaronder vallen bijzondere persoonsgegevens: je geloof of levensovertuiging, je gender en de genders waarin je geïnteresseerd bent (waaruit je seksuele voorkeur blijkt), je wensen rond seks en intimiteit, en hoe vaak je alcohol, tabak en drugs gebruikt."),
            Section(title: "Hoe matching werkt",
                    body: "Eerst controleren we breekpunten en harde voorwaarden, in beide richtingen. Daarna berekenen we een matchpercentage op basis van antwoorden en wegingen. Alleen als aan de voorwaarden is voldaan, ontstaat een match. Het percentage is een rekenuitkomst, geen voorspelling van een geslaagde relatie."),
            Section(title: "Wat een match ziet",
                    body: "Een momentopname van je volledige profiel, inclusief naam en foto als die in je profiel staan. Losse antwoorden verbergen kan niet. Door matching aan te zetten geef je hier vooraf toestemming voor; we vragen het niet per match opnieuw."),
            Section(title: "Vaste scores",
                    body: "Bij een match leggen we de score en beide profielen vast. Latere wijzigingen passen die niet aan, dus een oude score kan afwijken van je huidige antwoorden. Nieuwe matches gebruiken je nieuwste gegevens."),
            Section(title: "Beveiliging",
                    body: "Gegevens zijn beveiligd tijdens verzending en opslag. Waar mogelijk scheiden we accountgegevens van matchinggegevens en beperken we toegang. Omdat onze servers je antwoorden moeten kunnen vergelijken, is deze verwerking niet end-to-end versleuteld."),
            Section(title: "Matching uitzetten",
                    body: "Je doet dan niet meer mee aan nieuwe matches en we verwijderen of deactiveren je matchinggegevens volgens de bewaartermijnen in de Privacyverklaring. Bestaande matches, gedeelde momentopnamen en kopieën bij anderen verdwijnen niet automatisch. Je cloudback-up volgt je eigen back-upinstellingen."),
            Section(title: "Chats en meldingen",
                    body: "Chats zijn end-to-end versleuteld. We verwerken beperkte metadata voor aflevering, veiligheid en ondersteuning. Voeg je zelf berichten toe aan een melding, dan kunnen wij die inhoud bekijken."),
            Section(title: "Intrekken en je rechten",
                    body: "Je kunt je toestemming altijd intrekken door automatisch matchen uit te zetten. Dat stopt verdere verwerking, maar maakt eerdere verwerking niet onrechtmatig. Je privacyrechten oefen je uit via [PRIVACYCONTACT]. Welke dienstverleners we gebruiken, staat in de Privacyverklaring.")
        ],
        acknowledgement: "Ik geef uitdrukkelijk toestemming om mijn volledige matchingprofiel, inclusief gevoelige antwoorden over mijn geloof, seksualiteit en middelengebruik, op te slaan en automatisch te verwerken om matches te vinden, en het automatisch te delen met iedere match. Ik kan deze toestemming altijd intrekken; wat al gedeeld is, blijft bij de ontvanger."
    )

    private static let policyEN = #"""
# Privacy Policy — [APP_NAME]

**Version:** [VERSION_NUMBER]  
**Effective date:** [DATE]  
**Last updated:** [DATE]  
**Privacy contact:** [PRIVACY_EMAIL]  
**Public URL:** [PRIVACY_POLICY_URL]


## 1. Who is responsible for your data?

[LEGAL_ENTITY_NAME], located at [POSTAL_ADDRESS], [POSTCODE_AND_CITY], [COUNTRY], registered under [COMPANY_REGISTRATION_NUMBER], is the controller of personal data processed in [APP_NAME] as described in this policy (“we”, “us”, or “the app”).

You can contact us at [GENERAL_CONTACT_EMAIL], or send privacy requests to [PRIVACY_EMAIL]. If a data protection officer has been appointed, you may contact them at [DPO_CONTACT_OR_NOT_APPLICABLE].

## 2. Who can use the app?

[APP_NAME] is intended for people aged 18 or over. Minors may not use the service. We use [AGE_ASSURANCE_APPROACH] to support this age restriction. If we discover that a minor has an account, we follow [UNDERAGE_ACCOUNT_PROCEDURE].

## 3. What personal data do we process?

The data we process depends on the features you choose.

### 3.1 Local profile
You can answer questions and build a profile on your iPhone. This can include up to [QUESTION_COUNT; INTENDED: 50] answers scored 1–5, importance ratings of 1–5, dealbreakers, preferences, and other information you provide. These data are stored locally on your device. Depending on your settings, they may also be included in an Apple device backup. Unless you enable a cloud feature or exchange profiles, we do not send your local matching profile to our matching server.

### 3.2 Account and identity data
If you create an account, we process [ACCOUNT_DATA, E.G. AUTH ID, EMAIL ADDRESS, LOGIN PROVIDER], relevant account status, and [ADDITIONAL_IDENTITY_INFORMATION]. Authentication data are handled by Supabase Auth and, where chosen, [THIRD_PARTY_SIGN_IN_PROVIDER]. Your profile name and photo may be stored separately so they can be shown to matches.

### 3.3 Optional cloud backup
If you separately enable cloud backup, we store a copy of [PRECISE_BACKUP_CONTENT] so you can restore your profile on another device. Backups do not automatically enroll you in matching and are not publicly accessible.

### 3.4 Automatic matching
If you expressly enable automatic matching, we process your complete numerical and other matching profile: answers, importance ratings, dealbreakers, preferences, profile version, matching status, and information necessary to find candidates and calculate scores. Your answers may reveal health information, religious beliefs, sexual orientation or other special-category personal data.

### 3.5 Profile exchanges, matches and snapshots
When you mutually exchange profiles or an automatic match is created, we process linked account identifiers, the match time, fixed compatibility score, algorithm/version information, and full snapshots of both profiles. Each recipient receives all answers, importance ratings, preferences and dealbreakers, plus the profile name and photo included in the exchange. There is no option to hide individual questions.

### 3.6 Chats and communications metadata
Message content is end-to-end encrypted. We process encrypted messages and, where necessary, metadata such as participating account IDs, delivery states and timestamps. We cannot read the content of messages delivered normally. If someone voluntarily submits messages with a safety report, we can process the content they have submitted.

### 3.7 Technical and safety data
To keep the service secure and available and prevent misuse, we process the necessary [IP ADDRESS, APP VERSION, DEVICE/SESSION IDENTIFIERS, ERROR AND SECURITY LOGS, REPORTS AND BLOCKS; ADJUST TO REAL USE]. We minimize log contents and do not log complete matching answers, decryption keys or readable chat content.

### 3.8 Other features
[DESCRIBE ANY ANALYTICS, CRASH REPORTING, PAYMENT PROVIDERS, SUBSCRIPTIONS, NOTIFICATIONS, LOCATION OR MARKETING, OR CONFIRM THEY ARE NOT USED]. If push notifications are enabled, the relevant platform services process a push token and delivery metadata; readable private-message content is not included in push notifications.

## 4. For what purposes and on what legal bases do we use data?

| Processing activity | Purpose | GDPR legal basis |
| --- | --- | --- |
| Local profile and core features, to the extent processed by us | Let you create and use your profile | Performance of a contract, Art. 6(1)(b), where applicable |
| Account management and sign-in | Provide and secure your account | Performance of a contract, Art. 6(1)(b) |
| Optional cloud backup | Restore your profile | [SELECT AND JUSTIFY: CONSENT ART. 6(1)(a) OR CONTRACT ART. 6(1)(b)] |
| Manual mutual profile exchange | Carry out the exchange you select | [SELECT AND JUSTIFY: ART. 6(1)(a) OR 6(1)(b)] and, if required, a relevant Art. 9 GDPR exception |
| Automatic matching and automatic full-profile sharing | Find compatible people, calculate scores and exchange profiles | Explicit consent, Art. 6(1)(a); for special-category data, Art. 9(2)(a) |
| E2EE chat and delivery | Enable communication between matches | Performance of a contract, Art. 6(1)(b) |
| Essential security and abuse investigations | Prevent and respond to incidents | Legitimate interests, Art. 6(1)(f), following a balancing test; with an additional condition for special-category data where required |
| Mandatory legal records | Comply with applicable law | Legal obligation, Art. 6(1)(c) |
| [OTHER PROCESSING] | [PURPOSE] | [LEGAL BASIS] |

Consent is voluntary, specific and withdrawable for future processing relying on it. Creating an account or enabling backup does not enable automatic matching. We assess in advance whether explicit consent and any other GDPR requirements are suitable and sufficient for processing special-category data.

## 5. How do automatic matching and compatibility percentages work?

Our matching service compares profiles of users who have enabled automatic matching. First, it checks dealbreakers and mandatory criteria in both directions. It then compares numerical answers question by question, taking each participant's importance ratings into account. The exact method for the weighted percentage is [FINAL FORMULA, NORMALIZATION, TREATMENT OF UNANSWERED QUESTIONS AND MATCH THRESHOLD].

A match is created only when the criteria are met. The compatibility score and complete profile snapshots shared with both parties are fixed at the time of matching and are not automatically changed by later edits. The percentage represents calculated overlap, not a guarantee or prediction of relationship success.

This automated assessment determines which participants qualify for matches and consequently gain access to each other's full profiles. Assess whether it can have legal or similarly significant effects: [ARTICLE 22 GDPR ASSESSMENT AND FINDING]. You can ask questions about the method or an outcome via [MATCHING_EXPLANATION_CONTACT]. Where required by the GDPR, we provide applicable rights and safeguards relating to automated decision-making.

## 6. With whom do we share personal data?

We disclose personal data only for the stated purposes:

- **Other users:** following a mutual exchange you choose or automatic matching to which you have expressly consented. They receive the full profile described above and may retain copies themselves.
- **Supabase:** to provide database hosting, authentication, storage, application functions and related technical services under applicable agreements.
- **[OTHER PROCESSORS INCLUDING PUSH, LOGGING, EMAIL, KMS OR HOSTING PROVIDERS]:** only for specified services under suitable contractual protections.
- **Competent authorities:** if legally required or otherwise supported by an applicable lawful basis.

We do not sell profile and matching information to advertisers or data brokers and do not use questionnaire answers for targeted advertising. We do not send matching answers to external AI providers for model training [VERIFY ACTUAL IMPLEMENTATION].

## 7. Where do we process data and do we transfer it outside the EEA?

The primary Supabase project region is [EXACT SUPABASE REGION, E.G. eu-central-1, FRANKFURT, GERMANY]. Locations of application functions, logs, storage/caching, support and any additional providers are [LIST OF REGIONS]. The primary database region does not necessarily mean that all processing or transfers stay within the EEA.

Where personal data are transferred outside the EEA, we use [APPLICABLE TRANSFER MECHANISM, E.G. ADEQUACY DECISION OR STANDARD CONTRACTUAL CLAUSES AND SUPPLEMENTARY MEASURES] where necessary. Information about the applicable safeguards is available through [PRIVACY_EMAIL].

## 8. How do we keep data secure?

We use appropriate technical and organizational measures, including encrypted connections, encryption at rest, access controls, separation of account and matching functions, secured authentication, restricted administrative permissions, backup management, and security reviews. Where practical, identifying data are separated from matching records and pseudonymous identifiers are used. A pseudonymous profile is not anonymous while it can be linked back to an account.

The matching service must be able to process necessary answers during scoring. Matching-profile processing is therefore not end-to-end encrypted against our entire system. Ordinary chat content is end-to-end encrypted, so our servers cannot read it. No security measure can eliminate every risk.

## 9. How long do we keep personal data?

| Data category | Retention rule |
| --- | --- |
| Local profile | Until you delete the profile or app data from your device, subject to external device backups |
| Account information | While the account is active and [NUMBER_OF_DAYS] after account deletion, except where a lawful exception applies |
| Cloud backup | Until disabled/deleted, then no more than [NUMBER_OF_DAYS] in active storage |
| Active matching profile | While matching is enabled; deleted or irreversibly deactivated within [NUMBER_OF_DAYS] after consent withdrawal |
| Match scores and server snapshots | [PERIOD AND RULES FOR UNMATCHING/BLOCKING/ACCOUNT DELETION] |
| Encrypted E2EE message content | [RETENTION OR DELETION RULE], including [RULE FOR UNDELIVERED MESSAGES] |
| Technical logs and metadata | No more than [NUMBER_OF_DAYS], except for security investigations |
| Evidence of consent | [RETENTION NEEDED FOR ACCOUNTABILITY AND LIMITATION PERIODS] |
| Safety reports and blocks | [RETENTION PERIOD AND CRITERIA] |
| Backups and deleted copies | Rotated out under [MAXIMUM_BACKUP_RETENTION AND ROTATION] |
| Mandatory tax or legal records | As required under [LEGAL RETENTION PERIOD] |

Once you disable matching, your profile is no longer used to create new matches. Snapshots already provided to recipients cannot automatically be retrieved. When you request deletion, we also assess copies retained under our control; they are not kept indefinitely without a lawful reason.

## 10. What choices and rights do you have?

You may decline or later disable matching without losing your local profile. Cloud backup can be managed separately. Under the conditions of the GDPR, you have rights of access, rectification, erasure, restriction, portability and objection, and a right to withdraw consent. Additional rights may apply to automated decision-making.

Submit a request via [IN-APP PRIVACY REQUEST PATH] or [PRIVACY_EMAIL]. We may carry out necessary verification and ordinarily respond within one month, subject to lawful extensions. Withdrawal does not affect processing that was lawful before withdrawal. We cannot guarantee deletion of copies independently kept by recipients.

If you can create an account, you can also request deletion in the app at [DELETE ACCOUNT PATH].

## 11. Minors, safety and abuse

The service is for adults aged 18 or over. Users can block another person or report inappropriate behavior at [BLOCK_AND_REPORT_PATH]. Our staff cannot normally read E2EE message contents. A reporting user may, however, voluntarily provide relevant messages for review. We handle safety reports through [SAFETY_REPORTING_PROCESS_AND_CONTACT].

## 12. Changes to this policy

We may update this policy as the app, our providers or applicable laws change. The latest version is at [PRIVACY_POLICY_URL]. We inform users of material changes through [NOTICE_METHOD]. Where new consent is required, we ask for it before the relevant processing begins.

## 13. Complaints

For questions or complaints, contact [PRIVACY_EMAIL]. You may also lodge a complaint with the Dutch Data Protection Authority (Autoriteit Persoonsgegevens) at https://autoriteitpersoonsgegevens.nl or with another competent European supervisory authority.
"""#

    private static let policyNL = #"""
# Privacyverklaring — [APPNAAM]

**Versie:** [VERSIENUMMER]  
**Ingangsdatum:** [DATUM]  
**Laatste wijziging:** [DATUM]  
**Contact:** [PRIVACY_E-MAIL]  
**Openbaar adres:** [URL_PRIVACYVERKLARING]


## 1. Wie is verantwoordelijk?

[OFFICIËLE_BEDRIJFSNAAM], gevestigd aan [POSTADRES], [POSTCODE_EN_PLAATS], [LAND], ingeschreven onder [KVK_OF_REGISTRATIENUMMER], is de verwerkingsverantwoordelijke voor de hieronder omschreven verwerking van persoonsgegevens in [APPNAAM] (hierna: “wij” of “de app”).

Je kunt ons bereiken via [ALGEMEEN_CONTACTADRES] en voor privacyverzoeken via [PRIVACY_E-MAIL]. Onze functionaris voor gegevensbescherming, indien aangesteld, is bereikbaar via [CONTACT_FG_OF_NIET_VAN_TOEPASSING].

## 2. Voor wie is de app bedoeld?

[APPNAAM] is bedoeld voor personen van 18 jaar en ouder. Personen jonger dan 18 mogen de dienst niet gebruiken. We vragen [OMSCHRIJVING_LEEFTIJDSCONTROLE] om deze leeftijdsgrens te handhaven. Wanneer we vaststellen dat een minderjarige een account heeft, handelen we volgens [PROCEDURE_MINDERJARIGEN].

## 3. Welke persoonsgegevens verwerken we?

Welke gegevens we verwerken hangt af van de functies die je gebruikt.

### 3.1 Lokaal profiel
Je kunt op je iPhone vragen beantwoorden en een profiel opbouwen. Dit kan bestaan uit maximaal [AANTAL_VRAGEN; BEOGEN: 50] antwoorden met scores van 1 tot 5, belangrijkheidswegingen van 1 tot 5, breekpunten, voorkeuren en andere door jou ingevulde profielgegevens. Deze informatie wordt lokaal op je toestel opgeslagen. Afhankelijk van je instellingen kunnen gegevens ook in een reservekopie van Apple terechtkomen. Zonder gekozen cloudfunctie of profieluitwisseling sturen we het lokale matchingprofiel niet naar onze matchingserver.

### 3.2 Account- en identiteitsgegevens
Als je een account aanmaakt, verwerken we [ACCOUNTGEGEVENS: BIJV. AUTH-ID, E-MAILADRES, INLOGPROVIDER], relevante accountstatussen en [AANVULLENDE_IDENTITEITSGEGEVENS]. Auth-gegevens worden verwerkt via Supabase Auth en, indien gekozen, [INLOGPROVIDER]. Profielnaam en profielfoto kunnen afzonderlijk worden opgeslagen voor het zichtbaar maken van matches.

### 3.3 Optionele cloudback-up
Als je afzonderlijk cloudback-up inschakelt, bewaren we een kopie van [EXACTE_BACK-UPINHOUD] om je profiel op een ander toestel te kunnen herstellen. Deze back-up is niet automatisch ingeschreven voor matching en is niet openbaar toegankelijk.

### 3.4 Automatische matching
Als je automatische matching uitdrukkelijk inschakelt, verwerken we je volledige numerieke en andere matchingprofiel: antwoorden, wegingen, breekpunten, voorkeuren, profielversie, matchingstatus en de gegevens die nodig zijn om kandidaten te vinden en scores te berekenen. De antwoorden kunnen informatie onthullen over bijvoorbeeld gezondheid, religie, seksuele oriëntatie of andere bijzondere persoonsgegevens.

### 3.5 Profieluitwisselingen, matches en snapshots
Bij een vrijwillige wederzijdse profieluitwisseling of automatische match verwerken we de gekoppelde account-ID’s, de relevante matchdatum, de vastgezette matchscore, de gebruikte methode/versie en volledige momentopnamen van beide profielen. Ontvangers krijgen de volledige snapshot inclusief antwoorden, wegingen, voorkeuren en breekpunten en de profielnaam en foto die bij de uitwisseling horen. Er is geen instelling om afzonderlijke vragen te verbergen.

### 3.6 Chats en communicatiegegevens
Chatinhoud is end-to-end versleuteld. Wij verwerken versleutelde berichten en, voor zover noodzakelijk, metadata zoals betrokken account-ID’s, afleverstatussen en tijdstippen. Wij kunnen de inhoud van normaal verzonden berichten niet lezen. Wanneer iemand chatinhoud vrijwillig bij een melding meestuurt, kunnen wij die aangeleverde inhoud wel verwerken.

### 3.7 Technische gegevens en veiligheid
Voor beveiliging, beschikbaarheid en misbruikbestrijding verwerken we voor zover nodig [IP-ADRES, APP-VERSIE, APPARAAT-/SESSIE-ID, FOUT- EN BEVEILIGINGSLOGS, MELDINGEN EN BLOKKADES; EXACT AANPASSEN]. We beperken de inhoud van logs en bewaren daarin geen volledige matchingantwoorden, decryptiesleutels of chatberichten in leesbare vorm.

### 3.8 Overige functies
[OMSCHRIJF EVENTUELE ANALYTICS, CRASHREPORTING, BETAALDIENSTEN, ABONNEMENTEN, NOTIFICATIES, LOCATIE OF MARKETING, OF VERMELD DAT DEZE NIET WORDEN GEBRUIKT]. Als pushnotificaties zijn ingeschakeld, verwerken de betrokken platformdiensten een apparaat-/pushtoken en aflevermetadata; we tonen geen leesbare privéberichtinhoud in pushberichten.

## 4. Waarom en op welke rechtsgrond verwerken we gegevens?

| Verwerking | Doel | Rechtsgrond AVG |
| --- | --- | --- |
| Lokaal profiel en basisbediening, voor zover verwerking door ons plaatsvindt | Je profiel kunnen maken en gebruiken | Uitvoering van de overeenkomst, art. 6 lid 1(b), voor zover van toepassing |
| Accountbeheer en inloggen | Je account beschikbaar houden en beveiligen | Uitvoering van de overeenkomst, art. 6 lid 1(b) |
| Optionele cloudback-up | Je profiel veilig kunnen herstellen | [KIES EN ONDERBOUW: TOESTEMMING ART. 6(1)(a) OF OVEREENKOMST ART. 6(1)(b)] |
| Handmatige, wederzijdse profieluitwisseling | De door jou gekozen uitwisseling uitvoeren | [KIES EN ONDERBOUW: ART. 6(1)(a) OF 6(1)(b)] en waar noodzakelijk een uitzondering uit art. 9 AVG |
| Automatische matching en automatische volledige profieluitwisseling | Compatibele personen vinden, scores berekenen en profielen delen | Uitdrukkelijke toestemming, art. 6 lid 1(a), en voor bijzondere persoonsgegevens art. 9 lid 2(a) |
| E2EE-chat en berichtaflevering | Communicatie tussen matches | Uitvoering van de overeenkomst, art. 6 lid 1(b) |
| Beveiliging en noodzakelijk misbruikonderzoek | Incidenten voorkomen en behandelen | Gerechtvaardigd belang, art. 6 lid 1(f), na belangenafweging; waar nodig aanvullende grondslag voor bijzondere gegevens |
| Wettelijke administratieve verplichtingen | Aan wettelijke verplichtingen voldoen | Wettelijke verplichting, art. 6 lid 1(c) |
| [EVENTUELE OVERIGE VERWERKING] | [DOEL] | [GRONDSLAG] |

Toestemming is vrijwillig, specifiek en kan voor toekomstige verwerking op die grond worden ingetrokken. Een account of cloudback-up schakelt automatische matching niet vanzelf in. Als we bijzondere persoonsgegevens gebruiken, beoordelen we vooraf of uitdrukkelijke toestemming en andere AVG-vereisten passend en voldoende zijn.

## 5. Hoe werken automatische matches en matchpercentages?

Onze matchingservice vergelijkt de profielgegevens van gebruikers die automatische matching hebben ingeschakeld. Eerst controleren we breekpunten en noodzakelijke criteria in beide richtingen. Vervolgens vergelijken we per vraag de verschillen tussen de numerieke antwoorden, rekening houdend met de opgegeven belangrijkheidswegingen. De methode voor het gewogen percentage is [OMSCHRIJVING DEFINITIEVE FORMULE, MAXIMUMAFWIJKING, OMGANG MET ONBEANTWOORDE VRAGEN EN DREMPELWAARDE].

Een match ontstaat alleen als de ingestelde criteria zijn gehaald. De score en de aan beide personen verstrekte volledige profielmomentopnamen worden op de matchdatum vastgelegd en wijzigen niet automatisch bij latere profielaanpassingen. De score is een rekenkundige overeenkomst, geen garantie of voorspelling van relatiesucces.

We gebruiken deze geautomatiseerde beoordeling om binnen de app te bepalen wie voor een match in aanmerking komt en wie elkaars volledige profiel mag zien. De beslissing heeft [BEOORDEEL OF ER SPRAKE KAN ZIJN VAN RECHTSGEVOLGEN OF VERGELIJKBAAR AANZIENLIJKE GEVOLGEN ONDER ART. 22 AVG]. Je kunt vragen stellen over de matchingmethode of een uitkomst via [CONTACT_MATCHING_UITLEG]. Waar de AVG dit vereist, bieden we de toepasselijke rechten en waarborgen bij geautomatiseerde besluitvorming.

## 6. Met wie delen we persoonsgegevens?

We delen persoonsgegevens alleen voor de hieronder omschreven doelen:

- **Andere gebruikers:** uitsluitend bij door jou gekozen wederzijdse profieluitwisseling of bij automatische matching die je uitdrukkelijk hebt ingeschakeld. Zij zien dan het volledige profiel zoals beschreven; zij kunnen zelf kopieën bewaren.
- **Supabase:** voor onze database, authenticatie, opslag, applicatiefuncties en technische dienstverlening op basis van de toepasselijke afspraken.
- **[OVERIGE VERWERKERS, INCLUSIEF PUSH-, LOG-, E-MAIL-, KMS- OF HOSTINGDIENSTEN]:** uitsluitend voor de benoemde functies en volgens passende overeenkomsten.
- **Bevoegde instanties:** indien we daartoe wettelijk verplicht zijn of op basis van een geldige rechtsgrond.

Wij verkopen je profiel- en matchinggegevens niet aan adverteerders of datahandelaren en gebruiken je matchingantwoorden niet voor gerichte advertenties. We delen je matchingantwoorden niet met externe AI-aanbieders voor modeltraining [CONTROLEER FEITELIJKE IMPLEMENTATIE].

## 7. Waar worden gegevens verwerkt en gaan ze naar buiten de EER?

De primaire Supabase-projectregio is [CONCRETE SUPABASE-REGIO, BIJV. eu-central-1, FRANKFURT, DUITSLAND]. De locatie van appfuncties, logging, opslag/caching, support en eventuele andere dienstverleners is [OVERZICHT REGIO'S]. De gekozen databaseregio betekent niet automatisch dat geen enkele verwerking of doorgifte buiten de EER plaatsvindt.

Voor eventuele doorgifte buiten de EER gebruiken we waar nodig [TOEPASSELIJK DOORGIFTEMECHANISME, BIJV. ADEQUAATHEIDSBESLUIT OF STANDAARDCONTRACTBEPALINGEN MET AANVULLENDE MAATREGELEN]. Een kopie van of informatie over deze waarborgen is verkrijgbaar via [PRIVACY_E-MAIL].

## 8. Hoe beschermen we gegevens?

We gebruiken passende technische en organisatorische maatregelen, zoals versleutelde verbindingen, encryptie van opgeslagen gegevens, toegangscontrole, gescheiden functies voor account- en matchinggegevens, beveiligde authenticatie, beperkte beheerrechten, back-upbeheer en beveiligingscontroles. Profilering- en identiteitsgegevens worden waar praktisch mogelijk gepseudonimiseerd. Een pseudoniem profiel is niet anoniem zolang het aan een account te koppelen is.

De matchingservice moet noodzakelijke antwoorden tijdens de berekening kunnen verwerken. De matchingprofielen zijn daarom niet end-to-end versleuteld ten opzichte van ons gehele systeem. De inhoud van gewone chatberichten is wél end-to-end versleuteld; onze servers kunnen die inhoud niet lezen. Geen enkele beveiligingsmaatregel kan ieder risico volledig uitsluiten.

## 9. Hoe lang bewaren we gegevens?

| Gegevens | Bewaarregel |
| --- | --- |
| Lokaal profiel | Tot je dit op je toestel verwijdert of de appgegevens wist, behoudens externe toestelback-ups |
| Accountgegevens | Gedurende gebruik en [AANTAL_DAGEN] na accountverwijdering, tenzij een geldige uitzondering geldt |
| Cloudback-up | Tot uitschakeling/verwijdering, vervolgens maximaal [AANTAL_DAGEN] voor actieve opslag |
| Actief matchingprofiel | Zolang matching aanstaat; na intrekken toestemming binnen [AANTAL_DAGEN] verwijderd/onomkeerbaar buiten gebruik gesteld |
| Matchscores en server-snapshots | [TERMIJN EN REGEL BIJ UNMATCH/BLOKKEREN/ACCOUNTVERWIJDERING] |
| E2EE-versleutelde berichtinhoud | [TERMIJN OF VERWIJDERREGEL], met [REGEL VOOR NIET-AFGELEVERDE BERICHTEN] |
| Technische logs en metadata | Maximaal [AANTAL_DAGEN], behoudens incidentonderzoek |
| Toestemmingsbewijs | [BEWAARTERMIJN TER VERANTWOORDING EN VERJARING] |
| Veiligheidsmeldingen en blokkades | [BEWAARTERMIJN EN CRITERIA] |
| Back-ups en verwijderde kopieën | Uit roulatie volgens [MAXIMALE BACK-UPRETENTIE EN ROTATIE] |
| Fiscale/andere wettelijk vereiste gegevens | Volgens [WETTELIJKE BEWAARTERMIJN] |

Als je matching uitschakelt, komen er geen nieuwe matches tot stand op basis van dat profiel. Reeds gedeelde snapshots bij ontvangers zijn niet automatisch terug te halen. Wanneer een gebruiker om verwijdering verzoekt, beoordelen we ook de kopieën die wij zelf binnen de dienst bewaren; die blijven niet zonder geldige reden onbeperkt beschikbaar.

## 10. Welke keuzes en rechten heb je?

Je kunt matching weigeren of later uitschakelen zonder je lokale profiel kwijt te raken. Je kunt cloudback-up afzonderlijk beheren. Je hebt, onder de voorwaarden van de AVG, recht op inzage, rectificatie, verwijdering, beperking, overdraagbaarheid en bezwaar; je hebt ook het recht om toestemming in te trekken. Voor geautomatiseerde besluitvorming kunnen aanvullende rechten gelden.

Dien je verzoek in via [IN-APP PAD VOOR PRIVACYVERZOEKEN] of [PRIVACY_E-MAIL]. We kunnen noodzakelijke verificatie vragen en reageren in beginsel binnen één maand, behoudens wettelijk toegestane verlenging. Intrekking verandert niets aan verwerking die vóór de intrekking rechtmatig plaatsvond. Kopieën die ontvangers buiten onze controle hebben bewaard, kunnen we niet gegarandeerd verwijderen.

Als je een account kunt aanmaken, kun je dat ook binnen de app laten verwijderen via [PAD ACCOUNT VERWIJDEREN].

## 11. Minderjarigen, veiligheid en misbruik

De app is 18+. Gebruikers kunnen een andere gebruiker blokkeren en ongewenst gedrag melden via [PAD_BLOKKEREN_EN_MELDEN]. Onze medewerkers kunnen de inhoud van normaal E2EE-verkeer niet lezen. Een gebruiker kan er wel voor kiezen relevante berichten met een melding aan te leveren. We behandelen veiligheidsmeldingen volgens [PROCEDURE_EN_CONTACTPUNT].

## 12. Wijzigingen in deze verklaring

We kunnen deze verklaring bijwerken als de app, onze dienstverleners of wetgeving veranderen. De actuele versie staat op [URL_PRIVACYVERKLARING]. We informeren gebruikers over wezenlijke wijzigingen via [MELDINGSKANAAL]. Als een wijziging nieuwe toestemming vereist, vragen we die voordat de betreffende verwerking start.

## 13. Klachten

Heb je vragen of klachten, neem dan contact op via [PRIVACY_E-MAIL]. Je kunt ook een klacht indienen bij de Autoriteit Persoonsgegevens (Nederland) via https://autoriteitpersoonsgegevens.nl of bij een andere bevoegde Europese toezichthouder.
"""#
}
