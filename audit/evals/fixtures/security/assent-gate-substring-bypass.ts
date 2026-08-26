// Chat route fragment: the model may override a declared allergy only after
// the user explicitly confirmed it in their reply. The gate below is meant to
// verify that confirmation before honoring the override.

interface OverrideRequest {
  term: string; // allergy term the model claims the user confirmed, e.g. "Ei"
  reply: string; // the user's latest reply text
  declaredAllergies: string[];
}

// BUG 1: prefix/substring matching instead of word boundaries. "Ei" matches
// "eine", "Nuss" matches "Nussbaum", so an override for "Ei" passes on the
// reply "mach eine Suppe" although the user never mentioned eggs.
// BUG 2: term presence is treated as assent. There is no affirmative-token
// check and no negation check, so "nein, bitte ohne Ei" and "bitte eifrei"
// both "confirm" the override (the term occurs, negation ignored; the
// -frei suffix even matches via startsWith).
function replyConfirmsTerm(req: OverrideRequest): boolean {
  const reply = req.reply.toLowerCase();
  const term = req.term.toLowerCase();
  return reply.split(/\s+/).some((word) => word.startsWith(term));
}

// BUG 3: scope. A single confirmed term drops EVERY allergy that shares its
// trigger class ("Ei" confirmed -> Mayonnaise, Eiklar and all other egg
// triggers are exempted, and unrelated class members are filtered with it).
function effectiveAllergies(req: OverrideRequest): string[] {
  if (!replyConfirmsTerm(req)) return req.declaredAllergies;
  const cls = triggerClassOf(req.term); // e.g. "egg" -> [ei, eiklar, mayonnaise, ...]
  return req.declaredAllergies.filter((a) => !cls.includes(a.toLowerCase()));
}

export function applyOverride(req: OverrideRequest): string[] {
  return effectiveAllergies(req);
}

declare function triggerClassOf(term: string): string[];
