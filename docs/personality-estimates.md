# Personality estimates

Tapping the helix opens ten personality models, estimated from the 57
compatibility questions (`PersonalityEstimator.swift`). None of these questions
was written for these tests, so every dimension combines the answers that
describe the same behaviour. The app always labels the result as an estimate.

## Scoring

- Each own answer (1–5) becomes −1…1. Every question has two meaningful ends,
  so answering 5 means "the right-hand label", not "agree".
- A dimension is the weighted mean of its questions, divided by
  `answered weight + 0.6`. That pulls thin evidence toward the middle: one
  question alone gives at most ±0.62, and only answers that all point the same
  way come near the ends. Nothing is stretched afterwards.
- Unanswered questions are left out.

Two kinds of percentages follow from that score:

| Kind | Models | Meaning |
|---|---|---|
| Normative | MBTI, 16Personalities, PI, Big Five, HEXACO | 50% is the middle of the scale. Spectra show how strongly the winning pole wins (50–100%). |
| Relative | Belbin, TMA, Enneagram | Each role or drive against the person's own average, in standard deviations around 50% (z × 22%, at most 96%). These tests rank preferences, so there is always a top role, but rarely more than two above 90%. |
| Shares | DISC, Insights | Two axes give four quarters; each quarter is the mean of its two axis directions, shown as shares of 100%. |

`PersonalityEstimatorTests.testRandomProfilesSpreadOverEveryOutcome` scores
4,000 random profiles: every MBTI letter splits about 50/50, every type,
style, role and drive is reachable, and none dominates.
`testOutspokenAnswersNeverSaturateACharts` checks that answering only 1s and 5s
never fills a chart with 100%s.

## Per model

- **MBTI**: four spectra. E/I from talkativeness, social plans, nightlife,
  going out, guests and (negatively) time alone. S/N from conversation depth,
  new experiences, spirituality, travel. T/F from listening against solutions,
  sharing feelings, and (negatively) directness and debate. J/P from weekly
  planning, punctuality, tidiness, saving and planning ahead.
- **16Personalities**: the MBTI axes plus Assertive/Turbulent, from taking the
  lead and quick decisions against seeking reassurance, texting, jealousy-like
  answers (ex contact, sharing phones) and frequent relationship talks.
- **DISC**: pace (initiative, talkativeness, quick decisions, debate) and
  people against task orientation (listening, feelings, appreciation against
  ambition, directness, punctuality). D = fast + task, I = fast + people,
  S = steady + people, C = steady + task. Two letters (e.g. "Di") when the
  second style is within 85% of the first.
- **Insights Discovery**: the MBTI extraversion and feeling axes, the Jungian
  basis of the four colours.
- **Big Five**: openness, conscientiousness, extraversion and agreeableness
  from their behaviour questions. Neuroticism only shows through reassurance
  and jealousy in relationships, so it is held 25% closer to the middle.
- **HEXACO**: Big Five plus Honesty-Humility (modest style, simple travel,
  private relationship, little status spending) and Emotionality (seeking
  support, sharing feelings, family closeness).
- **Enneagram**: nine type scores, the highest is the type, the stronger
  neighbour is the wing.
- **Belbin**: nine role scores, each from three to seven questions, with
  opposing questions (a Teamworker keeps the peace, a Shaper debates).
- **Predictive Index**: dominance, extraversion, patience and formality, then
  the reference profile whose pattern points the same way (cosine
  similarity); "Adapter" when no factor reaches ±0.15.
- **TMA**: eight drives (achievement, status, leadership, social contact,
  helping, structure, change, autonomy).
