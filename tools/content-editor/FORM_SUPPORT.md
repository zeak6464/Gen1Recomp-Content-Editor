# Gen 3 form support

The editor targets the Gen1Recomp FireRed/LeafGreen runtime. These features do
not patch an original GBA ROM. Reviewed against the
[form-differences reference](https://bulbapedia.bulbagarden.net/wiki/List_of_Pok%C3%A9mon_with_form_differences).
Species, artwork, abilities and custom move effects still need project data.
This report distinguishes implemented mechanisms from exact species-specific parity.

## Implemented authoring and runtime mechanisms

| Mechanism | Available behavior |
| --- | --- |
| Fixed / regional / cosmetic / gender | Separate artwork, stats, types and learnsets; fixed, gender and personality selection. |
| Held item / item use / known move | Reversible held-item selection, reusable or consumed transformation items, and learning/forgetting updates. |
| General battle rules | Move use, HP damage, damage taken, knockout, HP/level, weather, held item, entry, switch-out and turn-end triggers; source and duration conditions. |
| Mega Evolution / Ultra Burst | SELECT activation before action ordering, optional held/key item and ability prerequisites, one use per side per mechanic, persistence through switching and cleanup before battle writeback. |
| Primal Reversion | Automatic entry transformation with prerequisites, new stats and ability, and battle-end restoration. |
| Dynamax / Gigantamax | Three turns, Dynamax-level HP scaling, switch/end cleanup, Max attacks and Max Guard, original-slot PP consumption, generic Max weather/stage/terrain effects. G-Max uses an authored move effect. |
| Terastallization | Selected defensive type, original and Tera STAB, same-type boost, eligible low-power boost, optional Tera Blast move, Stellar per-type boosts and Blast stat drops. Player charge persists in session metadata and recharges on party healing. |
| Disguise / Ice Face | Hit interception, substitute and ability-bypass checks; configurable Disguise HP cost; physical-only Ice Face protection and restoration on newly starting hail or entry into hail. |
| Gulp Missile | Configured loading move and half-HP condition, quarter-HP retaliation plus Defense loss or paralysis; unloading on switch. |
| Power Construct / boss phase | HP threshold transformation with changed maximum HP; HP and stats restored before completion callbacks. |
| Field / individual rules | Map, local hour, monthly season, nature, personality remainder, story flag, inherited tag and timed grooming selection. |
| Fusion plus transformation | Multiple partner recipes, reversible individual storage, additional battle rules and advanced transformations on a fused form. |
| Form-specific moves | Multiple reversible move replacements and move-type overrides, including fusion signature moves. Existing slot PP is retained. |
| Expanded species | Export schema and editor allocation allow species indices through 65535; index 2048 is covered by export/reload tests. |

## Configure and use

Open **Pokemon > Forms**, add the required variants and edit their artwork and
species records. Each form has a **Special form mechanic** picker, an optional
**Field / individual form selection** rule and **form-specific move changes**.
Additional battle rules can also be enabled on a fusion family.

For a manually activated battle mechanic, choose its required starting form and
optional prerequisites. In the battle move menu, press **SELECT** to cycle through
available transformations and off, then select the move. Opponents automatically
use the first eligible manual mechanic. Each mechanic has its own per-side limit;
Dynamax and Gigantamax share a limit. Link battles and Safari battles are excluded.

For fusion followed by Ultra Burst, keep the partner recipe on the fused form.
Add a separate Ultra form, choose Ultra Burst, and select the fused form as its
starting form. Leave the Ultra form's fusion partner empty. Splitting restores
the original individual and partner; temporary signature substitutions revert.

For a move toggle, add a move-hit rule to each target form with the other form
as its required source. Use move-used for a change before the attack effect.
Choose reversion on switching or at battle end. Rules run in order, with one
matching rule per event. General rules preserve maximum HP; use the dedicated
HP-changing mechanics when the form needs different maximum HP.

Field rules use the first match, otherwise the original form. Hours use the
computer's local clock, start inclusive/end exclusive, and can cross midnight;
equal hours mean all day. Seasons cycle Spring/Summer/Autumn/Winter each month.
Grooming uses a reusable item and expires after the configured real-time days.
Selection refreshes on world steps, map/flag events and stat calculation.
Stored PC appearances are refreshed when those individuals are processed.
Scripts can override `session.editorFormEnvironment` with `map`, `hour`,
`season` and `now`, and invoke the `editor.gen3.forms.environment` runtime hook.
Inherited tags follow the breeding parent; this does not infer every regional
breeding rule or evolution-history condition from a species name.

## Remaining fidelity boundaries

These mechanisms are functional, but this is not full Generation 4–9 battle
compatibility or a completed preset for every entry in the reference list:

- Primal harsh weather and its move cancellation, Ogerpon mask abilities,
  Terapagos-specific exceptions, and other later-generation abilities require
  dedicated implementations. Choosing an ability ID does not create its effect.
- G-Max signature effects must be authored using supported move effects. Native
  Z-Moves, raids, riding, spin-off systems and cinematic animations are not added.
- Gulp loading currently occurs on the move-used event, before hit resolution;
  original Surf/Dive timing exceptions are not fully reproduced.
- Giant forms block native OHKO, weight-based and forced-switch move effects,
  ignore flinching, and support Protect/Max Guard interactions. Every later-gen
  trapping, copy, item and forced-switch interaction has not been reproduced.
- Move swaps preserve existing PP, rather than converting PP maxima between
  moves. Interactive move-choice continuations and every copied-move interaction
  have not been audited for the advanced adapters.
- Expanded indices are for local runtime mods. Original GBA save/ROM formats,
  link synchronization and a full modern-Pokedex content pack are not validated.

## Verification

The advanced, form-rule, fusion and dynamic-form suites export and reload real
mods against both FireRed and LeafGreen caches. Tests exercise native battle
resolution, activation, Max PP/protection, Stellar boosts, Tera typing/STAB,
shield interception, Gulp retaliation, HP restoration, fusion plus Ultra Burst,
signature move restoration, field conditions, grooming save/reload/expiry,
expanded species loading, invalid settings and pre-completion cleanup.
The advanced suite also renders the editor controls for visual inspection.

Run the matching `tests/content-editor/run-*-checks.ps1` scripts with
`-Runtime <Gen1Recomp checkout> -Game firered` or `-Game leafgreen`.
