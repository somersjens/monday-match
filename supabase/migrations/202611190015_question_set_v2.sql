-- Stop Swiping: fourteen compatibility questions replaced, new order.
--
-- Runs after 202611190014_subscription_auto_renew.sql (independent of it).
--
-- The app retired calling, discussingFeelings, leisureTime, exPartnerContact,
-- futurePlanning, diningOut, sharedHobbies, conversationDepth,
-- expressingAppreciation, travel, socialMediaSharing, sharedResponsibilities,
-- disagreements and relationshipConversations, and asks humor, setbacks,
-- competitiveness, othersOpinion, cooking, boundaries, pride, optimism,
-- patience, perfectionism, headOrHeart, rules, emotionalExpression and makingUp
-- instead. Still 50 questions, listed in the app's new order.
--
-- Nobody has answered the new questions yet, so every pool entry is now
-- ineligible and holds answers in the old order. The pool is emptied; each
-- person re-enters on their next profile save, once they answered the new
-- questions in an app build that asks them.
begin;

create or replace function matching_private.question_ids() returns text[]
language sql immutable set search_path = '' as $$
    select array['dailyRhythm','cityOrNature','screenTime','exercise','nightlife','competitiveness',
    'travelStyle','hostingGuests','cooking','pets','homeTidiness','foodChoices','spendingMoney',
    'familyRole','socialPlans','currentAffairs','celebrations','othersOpinion','talkativeness',
    'humor','texting','communicationStyle','punctuality','newExperiences','perfectionism',
    'takingInitiative','decisionMaking','workAmbition','rules','pride','weeklyPlanning',
    'personalStyle','headOrHeart','patience','spirituality','boundaries','optimism','stressContact',
    'debating','setbacks','listeningAndSolutions','makingUp','emotionalExpression','aloneTime',
    'publicAffection','partnerSocializing','physicalAffection','relationshipPrivacy',
    'sexualIntimacy','romanticGestures']::text[];
$$;

do $$
begin
    -- The same lock matching, breaking and moderation take.
    perform pg_catalog.pg_advisory_xact_lock(724310261114::bigint);
    delete from matching_private.pool;
end;
$$;

commit;
