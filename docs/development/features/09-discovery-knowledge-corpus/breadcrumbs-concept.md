# Breadcrumbs Concept — Parked for Later

Extracted from the depth analysis document. We want to first fix the depth problem WITHOUT breadcrumbs and see if the model naturally plants hints when telling a deep story. If it does, we don't need explicit breadcrumb instructions (which would add complexity to an already dense prompt).

---

## The Concept

A **breadcrumb** is a single sentence woven into the narrative that hints at a fascinating angle you are deliberately NOT developing in this discovery. Its purpose is to create curiosity — to make the listener think "wait, tell me more about that" — so they take another photo.

## Rules for breadcrumbs (if we add them later):
- Maximum 1-2 per discovery. More than that and the narrative feels scattered.
- A breadcrumb is ONE sentence. Not a paragraph. Not two sentences.
- It must be woven naturally into the main narrative — not tacked on as a separate thought.
- It should hint at something genuinely interesting that you COULD develop if the user returns.
- It should NOT feel like a cliffhanger or a sales pitch. It should feel like a guide casually mentioning something fascinating in passing.

## Good breadcrumbs (natural, tantalizing, one sentence):
- "The sculptor who carved this was later exiled for insulting the king."
- "Behind that door, the Council of Ten kept a loaded armory — but that is another story."
- "This painting was finished just twenty years before Napoleon dissolved the Republic forever."
- "The real mystery is why the builders carved a face into the underside of the arch where nobody could see it."

## Bad breadcrumbs (cliffhangers, sales pitches, or too much):
- "But the most fascinating part of this building's history is what happened next..." (cliffhanger)
- "There is so much more to discover about this place!" (sales pitch)
- "The sculptor was exiled for insulting the king. He fled to Rome where he built three churches and married a countess." (too much — that's development, not a breadcrumb)

## When the user returns:
If `recentFullDiscoveries` contains a breadcrumb about the current subject, you should pick it up as your primary thread. The user came back because they were curious — reward that curiosity with depth.

## Multi-photo progression model (if breadcrumbs are added):

**Photo 1 (cold start):**
- Go deep on the most obvious, strongest thread
- Weave in 1-2 breadcrumbs — single sentences that hint at other fascinating angles
- Breadcrumbs should make the listener think "wait, what about...?"

**Photo 2 (same subject):**
- Check `recentFullDiscoveries` for breadcrumbs planted in photo 1
- Pick up one breadcrumb as the new deep thread
- Can plant new breadcrumbs from the current angle

**Photo 3+ (same subject):**
- Continue the pattern: previous breadcrumbs become deep threads
- Can return to the original thread from a completely different angle

**Example:**
> Subject: Doge's Palace, Venice
>
> **Photo 1** (exterior): Deep thread = how the palace's pink-and-white facade was designed to intimidate foreign ambassadors arriving by sea. Breadcrumb: "Behind these walls, the Council of Ten kept loaded firearms in a secret armory."
>
> **Photo 2** (secret armory): Deep thread = picks up the breadcrumb. The Council of Ten maintained this cache to prevent noble families from building private armies. Develops: who the Ten were, how they operated, what they feared. Breadcrumb: "One floor above, the Great Council chamber held two thousand nobles who elected the Doge — with one portrait covered by a black veil."
>
> **Photo 3** (Great Council chamber): Deep thread = the black veil. Marin Faliero tried to seize total power in 1355. Develops: the plot, the betrayal, the execution, and why Venice kept the black mark visible for 600 years as a warning.

---

## Why we're parking this

The depth problem is the priority. Adding breadcrumb instructions on top of a prompt that already pulls the model toward breadth could make things worse — giving it yet another thing to juggle. Fix depth first, evaluate, then consider breadcrumbs as an enhancement.
