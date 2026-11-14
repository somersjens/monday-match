import Foundation

/// Supplied NL/EN copy. Keep the approval summaries separate from the full policy.
/// Placeholders in the supplied policy are intentionally retained for editorial review.
enum PrivacyContent {
    struct Approval {
        let title: String
        let summary: String
        let details: String
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
        language == .dutch ? policyNL : policyEN
    }

    private static let profileEN = Approval(
        title: #"""
Your Profile, Your Privacy
"""#,
        summary: #"""
- Your profile is stored on your iPhone.
- You can optionally create an account and enable cloud backup to restore your profile if your device is lost or replaced.
- Creating your profile or making a backup does not automatically make it visible to other users.
- When you exchange profiles with someone, you both receive a complete snapshot of each other's profile, including all answers, importance ratings and dealbreakers.
- Changes you make later do not update profiles you have already shared.
- Messages in the app are end-to-end encrypted, so we cannot read their contents.
- Automatic matching is a separate, optional service for which we will ask for your permission later.
"""#,
        details: #"""
#### 1. Your profile on your device

Your answers, importance ratings, preferences and dealbreakers are stored on your iPhone. You can create and edit your profile without enabling automatic matching. Depending on your iPhone settings, app data may also be included in an Apple device backup. Apple's settings and safeguards also apply to such backups.

#### 2. Optional cloud backup

You may choose to create an account and enable cloud backup. A copy of your profile is then stored through our cloud infrastructure, provided by Supabase, so you can restore it if your device is lost or replaced. The data is protected in transit and at rest, and access is restricted to the systems and authorized functions needed to provide the service.

Cloud backup is not automatic matching. A backup does not make your profile visible to other users or enroll you in matching. You can manage your backup settings separately.

#### 3. Exchanging complete profiles

When you and another person choose to exchange profiles, each of you receives a complete snapshot of the other's profile at that moment. This includes all answers, importance ratings, preferences and dealbreakers, as well as the profile information included in the exchange. Individual answers cannot be hidden. Login credentials and private conversations are not included.

A manual profile exchange takes place only after both people initiate or accept that exchange. Automatic matching has its own separate consent screen.

#### 4. Information already shared

Each exchange fixes the profile content shared at that time. Later edits do not change previously shared snapshots or existing match scores. Recipients may save information or take screenshots. We cannot guarantee the removal of copies saved outside the app. Requests concerning copies stored within our service are handled under our Privacy Policy.

#### 5. Security and access

We use secure connections, encrypted storage, restricted access and authorization checks. Our cloud provider and strictly authorized systems may process information to provide the functions you enable. We do not promise that cloud information is technically unreadable to every administrator. We do not sell profile information or use your questionnaire answers for targeted advertising.

#### 6. Private conversations

Chat messages are end-to-end encrypted. Their contents are encrypted on the sending device and decrypted on the recipient's device. Our servers cannot read the message contents. We may process limited data needed for delivery, such as participating account identifiers and send or delivery times. If you choose to attach messages to a report, the reported content may be reviewed.

#### 7. Your choices and rights

You can edit your profile, manage cloud backup, and request access, correction or deletion through the app or [PRIVACY_CONTACT]. Copies already received by other people may not be recoverable. Retention periods and your rights are explained in the Privacy Policy.

#### 8. Automatic matching is separate

You can create a profile without using automatic matching. Automatic matching involves processing your complete answers and importance ratings on our servers. We ask for separate, explicit consent, including permission to automatically share your full profile when a match is created.
"""#,
        acknowledgement: #"""
I have read and understood how my profile is stored and what happens when I exchange my complete profile with another person.
"""#
    )

    private static let matchingEN = Approval(
        title: #"""
Automatic Matching & Your Data
"""#,
        summary: #"""
- Automatic matching is optional and is turned off by default.
- If you enable it, your complete matching profile is securely stored and processed on our servers.
- The system compares all your answers, importance ratings and dealbreakers with those of other participating users.
- When a match is created, you both automatically receive each other's complete profile and a calculated compatibility score, without approving each match individually.
- Compatibility scores and shared profile snapshots stay fixed; later changes are used only for future matches.
- You can disable automatic matching at any time, but previously shared profiles cannot automatically be recalled.
- Chat messages are end-to-end encrypted and cannot be read by us.
- We do not sell your matching information or use your answers for targeted advertising.
"""#,
        details: #"""
#### 1. What information do we use?

When you enable automatic matching, we upload your complete matching profile to our cloud infrastructure provided by Supabase. This includes all questionnaire answers, importance ratings, preferences and dealbreakers, together with technical information required to compare profiles. The information may contain or reveal sensitive details, including information about health, religion or sexual orientation.

#### 2. How does matching work?

The system first checks dealbreakers and other mandatory criteria in both directions. It then compares answers and importance ratings to calculate a compatibility percentage. An automatic match is created only when the matching requirements are met. The score represents our calculation method, not a prediction or guarantee of relationship success.

#### 3. What can a match see?

When a match is created, both people gain access to a complete snapshot of the other's profile. It includes all matching answers, importance ratings, preferences and dealbreakers. Your profile name and photograph are also visible to that match if they form part of your profile. Individual answers cannot be hidden from matches.

By enabling automatic matching, you agree in advance to this automatic sharing with future matches. We do not ask you to approve each individual match before your complete profile snapshot becomes visible.

#### 4. Fixed scores and snapshots

At match creation, we save the calculated score and complete exchanged profile snapshots. Edits to your current profile do not change existing scores or previously shared snapshots. As a result, an older score may not reflect your current answers. New matches use your latest synchronized profile information.

#### 5. How is the information secured?

Information is protected in transit and at rest. Where practical, we separate identifying account information from numerical matching data and restrict access through authentication, authorization and technical safeguards. The matching service must process your answers to calculate scores, so matching-profile processing is not end-to-end encrypted. Administrative and system access are restricted as far as practicable. Our Privacy Policy outlines our security approach.

#### 6. What happens when you turn matching off?

After you disable matching, your profile is no longer considered for new automatic matches. Active matching data is deleted or deactivated according to the retention periods in our Privacy Policy. Existing matches, shared snapshots and copies kept by other users do not automatically disappear. Separately enabled cloud backup remains controlled by your backup settings.

#### 7. Messages and reports

Chats between matches are end-to-end encrypted, so our servers cannot read their contents. We still process limited metadata for delivery, safety and support. If users voluntarily submit message content with a report, we may review that submitted content.

#### 8. Service providers and your rights

Supabase and any other service providers listed in our Privacy Policy help operate and secure the app. We do not sell your answers. You can withdraw your consent to automatic matching in Privacy Settings. This stops future processing based on that consent but does not reverse earlier lawful processing or recall copies already provided to another person. You can also exercise your legal privacy rights through [PRIVACY_CONTACT].
"""#,
        acknowledgement: #"""
I explicitly consent to the storage and automated processing of my complete matching profile, including any sensitive personal data it contains, to find compatible people. I also consent to my complete profile being automatically shown to each user with whom a match is created. I understand that I will not approve each match individually and that I may withdraw consent later, without automatically recalling previously shared copies.
"""#
    )

    private static let profileNL = Approval(
        title: #"""
Jouw profiel, jouw privacy
"""#,
        summary: #"""
- Je profiel wordt opgeslagen op je iPhone.
- Je kunt vrijwillig een account aanmaken en cloudback-up inschakelen om je profiel te herstellen als je van toestel wisselt of je toestel verliest.
- Je profiel wordt niet automatisch zichtbaar voor anderen wanneer je het invult of een back-up maakt.
- Als je met iemand profielen uitwisselt, ontvangen jullie allebei een volledige momentopname van elkaars profiel, inclusief alle antwoorden, belangrijkheidswegingen en breekpunten.
- Wijzigingen die je later aanbrengt, veranderen eerder gedeelde profielen niet.
- Berichten in de app zijn end-to-end versleuteld, zodat wij de inhoud niet kunnen lezen.
- Automatische matching is een afzonderlijke, vrijwillige dienst waarvoor wij later apart toestemming vragen.
"""#,
        details: #"""
#### 1. Je profiel op je toestel

Je antwoorden, belangrijkheidswegingen, voorkeuren en breekpunten worden op je iPhone opgeslagen. Je kunt je profiel opbouwen en aanpassen zonder automatische matching in te schakelen. Afhankelijk van je iPhone-instellingen kunnen appgegevens ook onderdeel zijn van een reservekopie van Apple. Voor de beveiliging en het beheer van die reservekopie gelden mede de instellingen van Apple.

#### 2. Vrijwillige cloudback-up

Je kunt ervoor kiezen een account aan te maken en cloudback-up in te schakelen. Dan wordt een kopie van je profiel opgeslagen via onze cloudinfrastructuur van Supabase, zodat je je profiel kunt herstellen bij verlies of vervanging van je toestel. Deze gegevens worden beveiligd tijdens verzending en opslag. De toegang is beperkt tot de systemen en bevoegde functies die nodig zijn voor deze dienst.

Cloudback-up is niet hetzelfde als automatische matching. Een back-up maakt je profiel niet zichtbaar voor andere gebruikers en schrijft je niet in voor automatische matching. Je kunt de instellingen voor je back-up afzonderlijk beheren.

#### 3. Een volledig profiel uitwisselen

Als jij en een andere persoon besluiten profielen uit te wisselen, krijgen jullie allebei een volledige momentopname van elkaars profiel zoals dat op dat moment is. Daarin staan alle antwoorden, belangrijkheidswegingen, voorkeuren en breekpunten, naast de profielgegevens die bij de uitwisseling horen. Je kunt niet per vraag bepalen wat je verbergt. Je inloggegevens en privégesprekken maken geen deel uit van de profieluitwisseling.

Een profieluitwisseling vindt alleen plaats nadat de betreffende uitwisseling door beide personen is gestart of geaccepteerd. Bij automatische matching geldt het afzonderlijke toestemmingsscherm van die dienst.

#### 4. Eerder gedeelde gegevens

Elke uitwisseling legt de gedeelde profielinhoud op dat moment vast. Wanneer je later iets in je profiel wijzigt, verandert dat eerder gedeelde momentopnamen en bestaande matchscores niet. Een ontvanger kan gegevens bewaren of schermafbeeldingen maken. Wij kunnen niet garanderen dat kopieën die iemand buiten de app heeft opgeslagen worden verwijderd. Verwijderverzoeken voor kopieën die wij binnen de dienst beheren worden volgens onze Privacyverklaring behandeld.

#### 5. Beveiliging en toegang

We gebruiken beveiligde verbindingen, versleutelde opslag, beperkte toegangsrechten en controles op wie gegevens mag opvragen. De cloudverwerker en strikt bevoegde systemen kunnen gegevens verwerken voor de functies die je hebt ingeschakeld. Wij beloven niet dat cloudgegevens technisch voor iedere beheerder onleesbaar zijn. We verkopen je profielgegevens niet en gebruiken je vragenantwoorden niet voor gerichte advertenties.

#### 6. Privégesprekken

Chatberichten zijn end-to-end versleuteld. De inhoud wordt op het verzendende toestel versleuteld en op het toestel van de ontvanger ontsleuteld. Onze servers kunnen de berichtinhoud niet lezen. We kunnen wel beperkte gegevens verwerken die nodig zijn voor het afleveren van berichten, zoals betrokken account-ID’s en verzend- of aflevermomenten. Als je zelf een bericht bij een melding meestuurt, kan de gemelde inhoud worden beoordeeld.

#### 7. Je keuzes en rechten

Je kunt je profiel aanpassen, cloudback-up beheren en via de app of [PRIVACYCONTACT] verzoeken indienen voor inzage, correctie of verwijdering. Eerder ontvangen kopieën bij andere personen kunnen niet altijd worden teruggehaald. De precieze bewaartermijnen en je rechten staan in de Privacyverklaring.

#### 8. Automatische matching is apart

Je kunt een profiel maken zonder automatische matching. Voor automatische matching worden je volledige antwoorden en wegingen verwerkt op onze servers. Daarvoor vragen we op een afzonderlijk scherm uitdrukkelijk toestemming, inclusief toestemming voor automatische uitwisseling van je volledige profiel bij een match.
"""#,
        acknowledgement: #"""
Ik heb gelezen en begrepen hoe mijn profiel wordt opgeslagen en wat er gebeurt wanneer ik mijn volledige profiel met iemand uitwissel.
"""#
    )

    private static let matchingNL = Approval(
        title: #"""
Automatische matching en jouw gegevens
"""#,
        summary: #"""
- Automatische matching is vrijwillig en staat standaard uit.
- Als je deze dienst inschakelt, wordt je volledige matchingprofiel veilig opgeslagen en verwerkt op onze servers.
- Het systeem vergelijkt alle antwoorden, wegingen en breekpunten met die van andere deelnemende gebruikers.
- Wanneer een match ontstaat, krijgen jullie automatisch elkaars volledige profiel en een berekend matchpercentage te zien, zonder dat je elke match vooraf afzonderlijk goedkeurt.
- Het matchpercentage en de uitgewisselde profielmomentopnamen blijven vaststaan; latere wijzigingen worden alleen gebruikt voor toekomstige matches.
- Je kunt automatische matching op elk moment uitschakelen; eerder gedeelde profielen zijn daarmee niet automatisch teruggehaald.
- Chatberichten zijn end-to-end versleuteld en kunnen niet door ons worden gelezen.
- We verkopen je matchinggegevens niet en gebruiken je antwoorden niet voor gerichte advertenties.
"""#,
        details: #"""
#### 1. Welke gegevens gebruiken we?

Wanneer je automatische matching inschakelt, sturen we je volledige matchingprofiel naar onze cloudinfrastructuur van Supabase. Dat omvat alle vragenantwoorden, belangrijkheidswegingen, voorkeuren en breekpunten en de noodzakelijke technische gegevens om profielen te vergelijken. Ook gegevens die gevoelig zijn of iets kunnen onthullen over bijvoorbeeld gezondheid, geloof of seksuele voorkeuren kunnen hierin voorkomen.

#### 2. Hoe werkt matching?

Het systeem controleert eerst de ingestelde breekpunten en andere noodzakelijke voorwaarden in beide richtingen. Daarna vergelijkt het de antwoorden en wegingen om een compatibiliteitspercentage te berekenen. Alleen als aan de ingestelde voorwaarden wordt voldaan, ontstaat een automatische match. De score is een uitkomst van onze rekenmethode, geen voorspelling of garantie dat een relatie zal slagen.

#### 3. Wat ziet een match?

Op het moment dat een match ontstaat, krijgen beide personen toegang tot een volledige momentopname van het profiel van de ander. Daarin zitten alle matchingantwoorden, belangrijkheidswegingen, voorkeuren en breekpunten. Ook je profielnaam en profielfoto worden zichtbaar voor die match, als deze onderdeel zijn van je profiel. Er is geen mogelijkheid om afzonderlijke antwoorden voor matches te verbergen.

Door automatische matching in te schakelen, geef je vooraf toestemming voor dit automatisch delen met toekomstige matches. We vragen je niet bij elke afzonderlijke match opnieuw om toestemming voordat de volledige profielmomentopname zichtbaar wordt.

#### 4. Vastgezette scores en momentopnamen

Bij het aanmaken van een match slaan we de berekende score en de volledige uitgewisselde profielmomentopnamen vast op. Veranderingen aan je actuele profiel wijzigen bestaande scores en eerder gedeelde momentopnamen niet. Daardoor kan een oude matchscore afwijken van je huidige antwoorden. Voor nieuwe matches gebruiken we de nieuwste gesynchroniseerde profielgegevens.

#### 5. Hoe worden gegevens beveiligd?

De informatie wordt beveiligd tijdens verzending en opslag. We scheiden identificerende accountinformatie waar mogelijk van numerieke matchinggegevens en beperken toegang met authenticatie, autorisatie en technische controles. De matchingservice moet je gegevens wel kunnen verwerken om scores te berekenen; daarom is dit geen end-to-end versleutelde verwerking van de profielantwoorden. Beheerders- en systeemrechten worden zoveel mogelijk beperkt. Onze volledige beveiligingsaanpak staat op hoofdlijnen in de Privacyverklaring.

#### 6. Wat gebeurt er als je matching uitschakelt?

Na uitschakeling word je niet meer meegenomen in nieuwe automatische matches en worden je actieve matchinggegevens verwijderd of buiten gebruik gesteld volgens de bewaartermijnen in onze Privacyverklaring. Eerder ontstane matches, gedeelde profielmomentopnamen en opgeslagen kopieën bij andere gebruikers verdwijnen niet automatisch. Een apart ingeschakelde cloudback-up blijft onder je eigen back-upinstellingen vallen.

#### 7. Berichten en meldingen

Chats tussen matches zijn end-to-end versleuteld, zodat onze servers de inhoud niet kunnen lezen. We verwerken wel beperkte metadata voor aflevering, veiligheid en ondersteuning. Als gebruikers zelf inhoud toevoegen aan een melding, kan die inhoud door ons worden beoordeeld.

#### 8. Derden en je rechten

Supabase en eventueel andere in de Privacyverklaring genoemde dienstverleners ondersteunen de werking en beveiliging van de app. We verkopen je antwoorden niet. Je kunt je toestemming voor automatische matching intrekken in Privacyinstellingen. Dit stopt toekomstige verwerking op basis van die toestemming, maar draait eerdere rechtmatige verwerking of de verstrekking van kopieën aan andere personen niet terug. Je kunt ook je wettelijke privacyrechten uitoefenen via [PRIVACYCONTACT].
"""#,
        acknowledgement: #"""
Ik geef uitdrukkelijk toestemming voor het opslaan en automatisch verwerken van mijn volledige matchingprofiel, inclusief eventuele gevoelige persoonsgegevens, om compatibele personen te vinden. Ik geef ook toestemming om mijn volledige profiel automatisch zichtbaar te maken aan iedere gebruiker met wie een match ontstaat. Ik begrijp dat ik niet iedere match vooraf afzonderlijk goedkeur en dat ik mijn toestemming later kan intrekken, zonder eerder gedeelde kopieën automatisch terug te halen.
"""#
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
