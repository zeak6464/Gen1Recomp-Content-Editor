-- Shared hover text for form authoring controls. Describes implemented behavior.
local M={}
M.mechanics={
  none="No special battle mechanic. Other form selection and battle rules still apply.",
  mega="Press SELECT in the move menu, then choose a move. One Mega Evolution per side per battle; persists through switching and reverts when battle ends.",
  primal="Automatically changes form on battle entry when prerequisites match. Reverts at battle end. Harsh weather is not supplied by this setting.",
  ultra="Press SELECT in the move menu to activate Ultra Burst. A fused form can be the required starting form. Reverts at battle end; the fusion partner is retained.",
  dynamax="Press SELECT to activate for three turns. Scales HP and converts moves to Max moves; status moves become Max Guard. Ends on switching or battle end. Shares its once-per-side limit with Gigantamax.",
  gigantamax="Dynamax HP and duration, plus this form's artwork and a configured G-Max move. The chosen move must already have a working effect in your project.",
  tera="Press SELECT to activate. Changes defensive typing while retaining original-type attack bonuses. Stellar keeps original defensive types and boosts each attack type once. Party healing recharges the player's Tera use.",
  disguise="Absorbs the first direct damaging hit and changes to this form. Does not protect a substitute. Choose no HP cost or a cost of one eighth maximum HP.",
  ice_face="Absorbs a direct physical hit and changes to this form. Restores the original form when hail newly starts or on entry into hail. Special attacks are not blocked.",
  gulp="The chosen move loads this form, subject to its HP condition. Taking direct move damage unloads it, damages the attacker by one quarter maximum HP and applies the chosen effect. Loading occurs before hit resolution.",
  power_construct="At turn end, changes form when HP meets the threshold. Adds the difference in maximum HP to current HP. Temporary HP and stats are restored at battle end.",
  boss="An HP-triggered battle phase with this form's stats and maximum HP. Checked at turn end; restored at battle end. Does not create a raid or cinematic sequence.",
}
M.advanced={
  from="The Pokemon must currently be in this form to activate. For fusion followed by Ultra Burst, choose the fused form.",
  item="Optional held-item requirement. Leave empty to allow activation without a particular held item; this does not consume the item.",
  keyItem="Optional item required in the player's Bag. It is not consumed. Give this item to the player through an event.",
  teraType="Defensive type after Terastallization. Original types retain their attack bonuses. Stellar keeps original defensive typing and grants per-type attack boosts.",
  teraBlast="Optional move to behave as Tera Blast while transformed: uses the Tera type and the stronger attacking stat. Stellar also lowers Attack and Special Attack after dealing damage.",
  move="Using this move loads the selected Gulp form before the attack resolves, even if it later misses.",
  payload="After unloading, the attacker loses one quarter maximum HP, then loses one Defense stage or is paralyzed.",
  hpCondition="Select which side of half HP loads this form. Exactly half HP counts as At or below. Use separate forms for different payloads.",
  percent="Activate at turn end when current HP is at or below this percentage of maximum HP. A fainted Pokemon cannot activate.",
  maxType="While Gigantamaxed, attacks of this type use the configured G-Max move. Other types use generic Max moves.",
  maxMove="Choose an existing move whose effect implements the desired G-Max attack. Original move-slot PP is spent. A name alone does not create a new effect.",
  disguiseCost="Choose Generation 7's zero HP cost or the later one-eighth maximum HP cost when Disguise breaks.",
  swapFrom="Replace this known move while transformed. Other moves and existing slot PP are retained.",
  swapTo="Temporary replacement for the original move. Restored when the transformation ends, provided the slot still contains this replacement.",
  ability="Optional required ability ID, such as DISGUISE. Leave blank for any ability. This checks eligibility; it does not implement a missing ability effect.",
}
M.fieldKinds={
  none="No field selection rule for this form.",map="Use this form on a specific map. The original form is used when no field rule matches.",
  hour="Select by the computer's local hour. Ranges can cross midnight. Start is inclusive; end is exclusive. Equal hours mean all day.",
  season="Seasons change monthly: January is Spring, February Summer, March Autumn, April Winter, then repeat.",
  nature="Select by the individual's nature ID, derived from personality. This selects appearance; it does not add an evolution method.",
  personality="Select when personality divided by the divisor leaves the chosen remainder. A divisor of 100 gives approximately one in 100 for each remainder.",
  flag="Use this form while the configured story flag is set. Clearing the flag allows fallback to the original form.",
  tag="Select by a saved individual variant tag. The tag can be inherited from the breeding parent. Giving this named variant establishes its tag.",
  grooming="Using a reusable item selects this appearance for a number of real-time days. The expiry survives saving; appearance refreshes on world updates or stat calculation.",
}
M.field={map="Exact map ID used by the project, not the displayed location name.",startHour="Local start hour, 0 to 23, inclusive. Use 20 to 6 for an overnight range.",endHour="Local end hour, 0 to 23, exclusive. Matching the start hour means all day.",season="Monthly four-season cycle, not the real-world three-month seasons. Scripts can override the environment.",nature="Nature ID from 0 to 24. The individual's personality determines its nature.",modulus="Positive whole-number divisor for the personality value. Larger values make each remainder rarer.",remainder="Required remainder after division. Must be zero or greater and smaller than the divisor.",flag="Numeric story-flag ID. The form applies while this flag is set.",tag="Saved variant tag shared by matching forms and inherited offspring, such as REGIONAL_NORTH.",item="Reusable item used on the Pokemon from the Bag to apply this appearance.",days="Positive duration in real-time days. Offline time counts toward expiry; appearance refreshes when the Pokemon is processed."}
M.rules={trigger="The event that attempts this transformation. Rules run in order; only the first matching rule runs for each event.",from="Only activate while in this form, or choose Any form. Known-move selection requires Any form.",move="Move used by this condition. Move-used runs before the effect; move-hit requires HP damage to a Pokemon and excludes substitutes. Known-move selection updates outside battle.",weather="Required effective battle weather. Add another rule if you want to return when weather changes.",percent="HP threshold checked on entry and at turn end. At or below includes the boundary; Above excludes it.",minLevel="The individual must be at least this level for the rule to match.",consume="Reusable leaves the item in the Bag. Consume removes one item after a successful field transformation.",duration="Revert on switching ends the form when withdrawn. Keep until battle ends preserves it when returning to battle. Both clean up at battle end.",item="Item used in the Bag for an item-use rule, or held by the Pokemon for a battle-held-item rule."}
return M
