--- Stacking Bosses, by NickTG. v1.0.0.
--- Every boss blind you beat stays for the rest of the run. Its effect applies to
--- every blind after it, Small and Big included, stacking with every other boss
--- you've beaten. Works on any deck; switch it off in the mod's config.
---
--- How: every vanilla boss effect is a name check inside the methods of the one
--- G.GAME.blind (dump/blind.lua). For each beaten boss the mod runs the same vanilla
--- logic again, as a "staying" boss, at the same points the real blind does. Bosses
--- are not changed.
---
--- Line numbers point into the game code as it runs (the lovely dump, "dump/") and
--- Steamodded 1.0.0~BETA-1620a ("smods/").

local THIS_MOD = SMODS.current_mod          -- must be captured at load time
local cfg      = THIS_MOD.config
if cfg.enabled == nil then cfg.enabled = true end

local SB = {}
StackingBosses = SB                         -- the mod's namespace
local function log(msg) sendInfoMessage(msg, 'StackingBosses') end

----------------------------------------------------------------------
-- State. G.GAME.ntgsb is saved with the run, so it survives Continue.
--   on       the switch, read at run start
--   beaten   boss key -> times beaten
--   order    boss keys in the order first beaten
--   st       boss key -> per-blind memory (Eye's hands, Mouth's hand, Water/Needle
--            amounts, Fish/Crimson prepped, Verdant disabled)
--   off      true while staying bosses are off for this blind (Chicot)
--   factor   size multiplier applied to the current blind
--   manacle  the Manacle's permanent -1 hand size is applied
--   triggered  a staying boss triggered this hand (Matador)
----------------------------------------------------------------------
local function S() return G.GAME and G.GAME.ntgsb end
function SB.on() local s = S(); return s and s.on or false end
function SB.st(key) local s = S(); s.st[key] = s.st[key] or {}; return s.st[key] end

-- Vanilla bosses only: modded bosses keep their own code paths, which this mod
-- can't re-run safely. They are still counted as beaten.
local VANILLA = {
    bl_ox = true, bl_hook = true, bl_mouth = true, bl_fish = true, bl_club = true, bl_manacle = true,
    bl_tooth = true, bl_wall = true, bl_house = true, bl_mark = true, bl_wheel = true, bl_arm = true,
    bl_psychic = true, bl_goad = true, bl_water = true, bl_eye = true, bl_plant = true, bl_needle = true,
    bl_head = true, bl_window = true, bl_serpent = true, bl_pillar = true, bl_flint = true,
    bl_final_bell = true, bl_final_leaf = true, bl_final_vessel = true, bl_final_acorn = true, bl_final_heart = true,
}
SB.VANILLA = VANILLA

local function in_blind()
    return G.GAME and G.GAME.blind and G.GAME.blind.name and G.GAME.blind.name ~= ''
end

-- The staying bosses that act right now: in a blind, not switched off by Chicot,
-- and not the same boss as the current blind (a repeat is already active as itself).
function SB.active()
    local s = S()
    if not (s and s.on) or s.off or not in_blind() then return {} end
    local out = {}
    for _, key in ipairs(s.order) do
        local P = G.P_BLINDS[key]
        if VANILLA[key] and P and P.name ~= G.GAME.blind.name then out[#out + 1] = key end
    end
    return out
end
function SB.is_active(key)
    for _, k in ipairs(SB.active()) do if k == key then return true end end
    return false
end

-- exclude: a Chicot on his way out; include: a Chicot on his way in (set_debuff calls
-- add_to_deck before it clears .debuff, dump/card.lua:719-721).
function SB.chicot_owned(exclude, include)
    if include then return true end
    if not G.jokers then return false end
    for _, c in ipairs(G.jokers.cards) do
        if c ~= exclude and c.ability and c.ability.name == 'Chicot' and not c.debuff then return true end
    end
    return false
end

-- Size: a boss's mult over a normal boss's 2. The Wall 4 -> x2, Violet Vessel 6 -> x3,
-- The Needle 1 -> x0.5 (dump/game.lua:272-300). Everything else is x1.
local function size_of(key)
    local P = G.P_BLINDS[key]
    return (P and P.mult and P.mult > 0) and (P.mult / 2) or 1
end
-- Factor for a blind named `name` (the blind select screen asks before the blind is set).
function SB.factor_for(name)
    local s = S()
    if not (s and s.on) or SB.chicot_owned() then return 1 end
    local f = 1
    for _, key in ipairs(s.order) do
        local P = G.P_BLINDS[key]
        if VANILLA[key] and P and P.name ~= name then f = f * size_of(key) end
    end
    return f
end

-- A boss's description values, as Blind:set_text gets them (dump/blind.lua:56-67):
-- Steamodded gives The Wheel its odds through loc_vars.
local function boss_vars(P)
    if P.name == 'The Ox' and G.GAME and G.GAME.current_round then
        return { localize(G.GAME.current_round.most_played_poker_hand, 'poker_hands') }
    end
    if type(P.loc_vars) == 'function' then
        local ok, res = pcall(P.loc_vars, P)
        if ok and type(res) == 'table' and res.vars then return res.vars end
    end
    return P.vars
end

-- The text shown when a staying boss blocks a hand: "The Psychic: Must play 5 cards"
function SB.debuff_text(key)
    local P = G.P_BLINDS[key]
    local lines = localize { type = 'raw_descriptions', key = key, set = 'Blind', vars = boss_vars(P) } or {}
    local text = ''
    for i, v in ipairs(type(lines) == 'table' and lines or {}) do text = text .. v .. (i < #lines and ' ' or '') end
    if P.name == 'The Mouth' then
        local only = SB.st(key).only_hand
        if only then text = text .. ' [' .. localize(only, 'poker_hands') .. ']' end
    end
    return localize { type = 'name_text', key = key, set = 'Blind' } .. ': ' .. text
end

----------------------------------------------------------------------
-- The Manacle stays as one permanent -1 hand size (a per-blind -1/+1 could leak a
-- card if a +1 is ever missed). Off while Chicot is owned; off for the rest of a blind
-- where staying bosses were switched off; off while the current blind is a real
-- Manacle, which does its own -1 (blind.lua:214/378), the same rule as any repeat.
----------------------------------------------------------------------
function SB.sync_manacle(exclude, blind_over, include)
    local s = S()
    if not (s and s.on) or not G.hand then return end
    local now = not blind_over and in_blind()
    local real = now and G.GAME.blind.name == 'The Manacle'
    local want = (s.beaten.bl_manacle or 0) > 0 and not SB.chicot_owned(exclude, include) and not real
        and not (now and s.off)
    if want ~= (s.manacle and true or false) then
        G.hand:change_size(want and -1 or 1)
        s.manacle = want
        log('Manacle ' .. (want and 'on: -1 hand size' or 'off: hand size back'))
    end
end

----------------------------------------------------------------------
-- A boss is beaten: it stays. A repeat only raises its count.
----------------------------------------------------------------------
function SB.add_beaten(key)
    local s = S()
    s.beaten[key] = (s.beaten[key] or 0) + 1
    if s.beaten[key] == 1 then
        s.order[#s.order + 1] = key
        log('Stays: ' .. key .. ' (' .. #s.order .. ' stacked)' .. (VANILLA[key] and '' or ' [modded boss: counted, not applied]'))
    else
        log('Beaten again: ' .. key .. ' x' .. s.beaten[key] .. ' (no change)')
    end
    SB.sync_manacle(nil, true)
end

----------------------------------------------------------------------
-- New run: read the switch. Continue: the saved state comes back with G.GAME.
-- A run started before the mod was installed has no state and plays as vanilla.
----------------------------------------------------------------------
local start_run_ref = Game.start_run
function Game:start_run(args)
    start_run_ref(self, args)
    if SB.text_set then SMODS.debuff_text = nil; SB.text_set = nil end
    if not (args and args.savetext) then
        G.GAME.ntgsb = { on = cfg.enabled and true or false, beaten = {}, order = {}, st = {}, factor = 1, manacle = false }
        log('New run, ' .. (G.GAME.ntgsb.on and 'ON' or 'OFF'))
    elseif G.GAME.ntgsb then
        local s = G.GAME.ntgsb
        s.beaten, s.order, s.st, s.factor = s.beaten or {}, s.order or {}, s.st or {}, s.factor or 1
        log('Continue, ' .. (G.GAME.ntgsb.on and 'ON' or 'OFF') .. ', ' .. #G.GAME.ntgsb.order .. ' stacked')
    end
end

----------------------------------------------------------------------
-- The boss draw only offers bosses you haven't beaten yet; once every eligible one
-- is beaten, the least-beaten come back. Vanilla keeps the eligible
-- bosses with the lowest G.GAME.bosses_used and picks one (dump/functions/
-- common_events.lua:2690-2752; min_use starts at 100, so values stay under it).
-- For the call, bosses_used holds beaten count first and times drawn second.
----------------------------------------------------------------------
local get_new_boss_ref = get_new_boss
function get_new_boss(...)
    local s = S()
    if not (s and s.on) or not G.GAME.bosses_used then return get_new_boss_ref(...) end
    local real = G.GAME.bosses_used
    local low = math.huge
    for _, v in pairs(real) do if v < low then low = v end end
    if low == math.huge then low = 0 end
    local tmp = {}
    for k, v in pairs(real) do
        tmp[k] = math.min(s.beaten[k] or 0, 8) * 11 + math.min(math.max(v - low, 0), 10)
    end
    G.GAME.bosses_used = tmp
    local ok, boss = pcall(get_new_boss_ref, ...)
    G.GAME.bosses_used = real
    if not ok then error(boss, 0) end
    if boss then real[boss] = (real[boss] or 0) + 1 end
    log('Boss drawn: ' .. tostring(boss) .. ((s.beaten[boss] or 0) > 0 and ' (repeat)' or ''))
    return boss
end

----------------------------------------------------------------------
-- Blind select shows the requirement with staying sizes included
-- (dump/functions/UI_definitions.lua:1697 multiplies by ante_scaling).
----------------------------------------------------------------------
local blind_choice_ref = create_UIBox_blind_choice
function create_UIBox_blind_choice(type, run_info)
    local key = G.GAME and G.GAME.round_resets and G.GAME.round_resets.blind_choices
        and G.GAME.round_resets.blind_choices[type or 'Small']
    local P = key and G.P_BLINDS[key]
    local f = P and SB.factor_for(P.name) or 1
    if f == 1 then return blind_choice_ref(type, run_info) end
    local sp = G.GAME.starting_params
    local old = sp.ante_scaling
    sp.ante_scaling = old * f
    local ok, ret = pcall(blind_choice_ref, type, run_info)
    sp.ante_scaling = old
    if not ok then error(ret, 0) end
    return ret
end

----------------------------------------------------------------------
-- set_blind: per-blind setup for each staying boss (dump/blind.lua:188-223), then
-- the size. Debuffs come from THIS_MOD.set_debuff below, which set_blind's own
-- debuff pass already calls for every card.
----------------------------------------------------------------------
local set_blind_ref = Blind.set_blind
function Blind:set_blind(blind, reset, silent)
    local s = S()
    local fresh = s and s.on and blind and not reset and self == G.GAME.blind
    if fresh then
        if SB.text_set then SMODS.debuff_text = nil; SB.text_set = nil end
        s.off = SB.chicot_owned()
        s.triggered = false
        s.factor = 1
        for _, key in ipairs(s.order) do
            local st = SB.st(key)
            st.disabled, st.hands, st.only_hand, st.discards_sub, st.hands_sub = nil, nil, nil, nil, nil
            st.prepped = true                            -- as every blind does (blind.lua:116)
        end
    end
    set_blind_ref(self, blind, reset, silent)
    if not fresh then return end

    local active = SB.active()
    for _, key in ipairs(active) do
        local name, st = G.P_BLINDS[key].name, SB.st(key)
        if name == 'The Eye' then
            st.hands = {}
        elseif name == 'The Mouth' then
            st.only_hand = false
        elseif name == 'The Fish' then
            st.prepped = nil
        elseif name == 'The Water' then
            st.discards_sub = G.GAME.current_round.discards_left
            ease_discard(-st.discards_sub)
        elseif name == 'The Needle' then
            st.hands_sub = G.GAME.round_resets.hands - 1
            ease_hands_played(-st.hands_sub)
        elseif name == 'Amber Acorn' and #G.jokers.cards > 0 then
            G.jokers:unhighlight_all()
            for _, v in ipairs(G.jokers.cards) do v:flip() end
            if #G.jokers.cards > 1 then
                G.E_MANAGER:add_event(Event({ trigger = 'after', delay = 0.2, func = function()
                    G.E_MANAGER:add_event(Event({ func = function() G.jokers:shuffle('aajk'); play_sound('cardSlide1', 0.85); return true end }))
                    delay(0.15)
                    G.E_MANAGER:add_event(Event({ func = function() G.jokers:shuffle('aajk'); play_sound('cardSlide1', 1.15); return true end }))
                    delay(0.15)
                    G.E_MANAGER:add_event(Event({ func = function() G.jokers:shuffle('aajk'); play_sound('cardSlide1', 1); return true end }))
                    delay(0.5)
                    return true end }))
            end
        end
    end
    local f = 1
    for _, key in ipairs(active) do f = f * size_of(key) end
    if f ~= 1 then
        self.chips = self.chips * f
        self.chip_text = number_format(self.chips)
        s.factor = f
    end
    SB.sync_manacle()
    if #s.order > 0 then
        log('Blind ' .. tostring(self.name) .. ': ' .. #active .. ' staying' .. (s.off and ' (off: Chicot)' or '')
            .. (f ~= 1 and (', size x' .. f) or ''))
    end
end

----------------------------------------------------------------------
-- Debuffs. Card:set_debuff asks every mod's set_debuff (dump/card.lua:687-700) and
-- ORs the answer in, so this covers every place the game recalculates debuffs.
-- Same checks as Blind:debuff_card (dump/blind.lua:682-737).
----------------------------------------------------------------------
THIS_MOD.set_debuff = function(card)
    local active = SB.active()
    if not active[1] then return end
    for _, key in ipairs(active) do
        local P = G.P_BLINDS[key]
        local d = P.debuff or {}
        if card.playing_card then
            if d.suit and card:is_suit(d.suit, true) then return true end
            if d.is_face == 'face' and card:is_face(true) then return true end
            if P.name == 'The Pillar' and card.ability.played_this_ante then return true end
            if d.value and d.value == card.base.value then return true end
            if d.nominal and d.nominal == card.base.nominal then return true end
            if P.name == 'Verdant Leaf' and not SB.st(key).disabled then return true end
        end
        if P.name == 'Crimson Heart' and card.area == G.jokers and card.ability.crimson_heart_chosen then return true end
    end
end

----------------------------------------------------------------------
-- Hands: same checks as Blind:debuff_hand (dump/blind.lua:557-610). Staying bosses
-- that block the hand are checked first and change nothing; only a hand that is
-- allowed records The Eye / The Mouth and runs The Arm / The Ox, as in vanilla.
----------------------------------------------------------------------
local debuff_hand_ref = Blind.debuff_hand
function Blind:debuff_hand(cards, hand, handname, check)
    local s = S()
    if not (s and s.on) or self ~= G.GAME.blind then return debuff_hand_ref(self, cards, hand, handname, check) end
    s.triggered = false                              -- as vanilla clears it here (blind.lua:563-564)
    local active = SB.active()
    for _, key in ipairs(active) do
        local P = G.P_BLINDS[key]
        local d, st = P.debuff or {}, SB.st(key)
        local hit = (d.hand and hand[d.hand] and next(hand[d.hand]))
            or (d.h_size_ge and #cards < d.h_size_ge)
            or (d.h_size_le and #cards > d.h_size_le)
            or (P.name == 'The Eye' and st.hands and st.hands[handname])
            or (P.name == 'The Mouth' and st.only_hand and st.only_hand ~= handname)
        if hit then
            s.triggered = true
            SMODS.debuff_text = SB.debuff_text(key)
            SB.text_set = true
            return true
        end
    end
    local ret = debuff_hand_ref(self, cards, hand, handname, check)
    if ret then return ret end
    if SB.text_set then SMODS.debuff_text = nil; SB.text_set = nil end
    for _, key in ipairs(active) do
        local name, st = G.P_BLINDS[key].name, SB.st(key)
        if name == 'The Eye' then
            if not check then st.hands = st.hands or {}; st.hands[handname] = true end
        elseif name == 'The Mouth' then
            if not check then st.only_hand = handname end
        elseif name == 'The Arm' then
            if G.GAME.hands[handname].level > 1 then
                s.triggered = true
                if not check then
                    level_up_hand(self.children.animatedSprite, handname, nil, -1)
                    self:wiggle()
                end
            end
        elseif name == 'The Ox' then
            if handname == G.GAME.current_round.most_played_poker_hand then
                s.triggered = true
                if not check then
                    ease_dollars(-G.GAME.dollars, true)
                    self:wiggle()
                end
            end
        end
    end
    return ret
end

-- No cards selected: clear a staying boss's "not allowed" text (the game only
-- refreshes it while a hand is selected).
local parse_ref = CardArea.parse_highlighted
function CardArea:parse_highlighted(...)
    if SB.text_set and self == G.hand and #self.highlighted == 0 then SMODS.debuff_text = nil; SB.text_set = nil end
    return parse_ref(self, ...)
end

----------------------------------------------------------------------
-- Playing a hand: The Hook, The Tooth, Crimson Heart, The Fish (dump/blind.lua:499-543).
----------------------------------------------------------------------
local press_play_ref = Blind.press_play
function Blind:press_play()
    local ret = press_play_ref(self)
    local s = S()
    if not (s and s.on) or self ~= G.GAME.blind then return ret end
    s.triggered = false
    for _, key in ipairs(SB.active()) do
        local name, st = G.P_BLINDS[key].name, SB.st(key)
        if name == 'The Hook' then
            G.E_MANAGER:add_event(Event({ func = function()
                local any_selected = nil
                local _cards = {}
                for _, v in ipairs(G.hand.cards) do _cards[#_cards + 1] = v end
                for i = 1, 2 do
                    if G.hand.cards[i] then
                        local selected_card, card_key = pseudorandom_element(_cards, pseudoseed('hook'))
                        G.hand:add_to_highlighted(selected_card, true)
                        table.remove(_cards, card_key)
                        any_selected = true
                        play_sound('card1', 1)
                    end
                end
                if any_selected then G.FUNCS.discard_cards_from_highlighted(nil, true) end
                return true end }))
            s.triggered = true
            delay(0.7)
            ret = true
        elseif name == 'Crimson Heart' then
            if G.jokers.cards[1] then s.triggered = true; st.prepped = true end
        elseif name == 'The Fish' then
            st.prepped = true
        elseif name == 'The Tooth' then
            G.E_MANAGER:add_event(Event({ trigger = 'after', delay = 0.2, func = function()
                for i = 1, #G.play.cards do
                    G.E_MANAGER:add_event(Event({ func = function() G.play.cards[i]:juice_up(); return true end }))
                    ease_dollars(-1)
                    delay(0.23)
                end
                return true end }))
            s.triggered = true
            ret = true
        end
    end
    return ret
end

----------------------------------------------------------------------
-- The Flint (dump/blind.lua:545-555).
----------------------------------------------------------------------
local modify_hand_ref = Blind.modify_hand
function Blind:modify_hand(cards, poker_hands, text, mult, hand_chips, scoring_hand)
    local m, c, modded = modify_hand_ref(self, cards, poker_hands, text, mult, hand_chips, scoring_hand)
    local s = S()
    if not (s and s.on) or self ~= G.GAME.blind then return m, c, modded end
    if SB.is_active('bl_flint') then
        s.triggered = true
        m = math.max(math.floor(m * 0.5 + 0.5), 1)
        c = math.max(math.floor(c * 0.5 + 0.5), 0)
        modded = true
    end
    return m, c, modded
end

----------------------------------------------------------------------
-- Cards drawn face down: The Wheel, The House, The Mark, The Fish (dump/blind.lua:662-680).
----------------------------------------------------------------------
local stay_flipped_ref = Blind.stay_flipped
function Blind:stay_flipped(area, card, from_area)
    local ret = stay_flipped_ref(self, area, card, from_area)
    if ret or area ~= G.hand then return ret end
    local s = S()
    if not (s and s.on) or self ~= G.GAME.blind then return ret end
    for _, key in ipairs(SB.active()) do
        local name = G.P_BLINDS[key].name
        if name == 'The Wheel' and SMODS.pseudorandom_probability(self, pseudoseed('wheel'), 1, 7, 'wheel') then
            return true
        elseif name == 'The House' and G.GAME.current_round.hands_played == 0 and G.GAME.current_round.discards_used == 0 then
            return true
        elseif name == 'The Mark' and card:is_face(true) then
            return true
        elseif name == 'The Fish' and SB.st(key).prepped then
            return true
        end
    end
    return ret
end

----------------------------------------------------------------------
-- After the draw: Cerulean Bell, Crimson Heart (dump/blind.lua:612-660).
----------------------------------------------------------------------
local drawn_ref = Blind.drawn_to_hand
function Blind:drawn_to_hand()
    drawn_ref(self)
    local s = S()
    if not (s and s.on) or self ~= G.GAME.blind then return end
    for _, key in ipairs(SB.active()) do
        local name, st = G.P_BLINDS[key].name, SB.st(key)
        if name == 'Cerulean Bell' then
            local any_forced = nil
            for _, v in ipairs(G.hand.cards) do if v.ability.forced_selection then any_forced = true end end
            if not any_forced and G.hand.cards[1] then
                G.hand:unhighlight_all()
                local forced_card = pseudorandom_element(G.hand.cards, pseudoseed('cerulean_bell'))
                forced_card.ability.forced_selection = true
                G.hand:add_to_highlighted(forced_card)
            end
        elseif name == 'Crimson Heart' and st.prepped and G.jokers.cards[1] then
            local prev_chosen_set, fallback_jokers, jokers = {}, {}, {}
            for i = 1, #G.jokers.cards do
                if G.jokers.cards[i].ability.crimson_heart_chosen then
                    prev_chosen_set[G.jokers.cards[i]] = true
                    G.jokers.cards[i].ability.crimson_heart_chosen = nil
                    if G.jokers.cards[i].debuff then SMODS.recalc_debuff(G.jokers.cards[i]) end
                end
            end
            for i = 1, #G.jokers.cards do
                if not G.jokers.cards[i].debuff then
                    if not prev_chosen_set[G.jokers.cards[i]] then jokers[#jokers + 1] = G.jokers.cards[i] end
                    table.insert(fallback_jokers, G.jokers.cards[i])
                end
            end
            if #jokers == 0 then jokers = fallback_jokers end
            local _card = pseudorandom_element(jokers, pseudoseed('crimson_heart'))
            if _card then
                _card.ability.crimson_heart_chosen = true
                SMODS.recalc_debuff(_card)
                _card:juice_up()
                self:wiggle()
            end
        end
    end
    for _, key in ipairs(s.order) do SB.st(key).prepped = nil end
end

----------------------------------------------------------------------
-- Turning staying bosses off mid-blind (Chicot arrives), the way Blind:disable
-- undoes each boss (dump/blind.lua:393-450).
----------------------------------------------------------------------
function SB.switch_off()
    local s = S()
    if not (s and s.on) or s.off or not in_blind() then return end
    local active = SB.active()
    local blind = G.GAME.blind
    for _, v in ipairs(G.jokers.cards) do if v.facing == 'back' then v:flip() end end
    for _, key in ipairs(active) do
        local name, st = G.P_BLINDS[key].name, SB.st(key)
        if name == 'The Water' and st.discards_sub then
            ease_discard(st.discards_sub)
        elseif name == 'The Needle' and st.hands_sub then
            ease_hands_played(st.hands_sub)
        elseif name == 'The Wheel' or name == 'The House' or name == 'The Mark' or name == 'The Fish' then
            for i = 1, #G.hand.cards do if G.hand.cards[i].facing == 'back' then G.hand.cards[i]:flip() end end
            for _, v in pairs(G.playing_cards) do v.ability.wheel_flipped = nil end
        elseif name == 'Cerulean Bell' then
            for _, v in ipairs(G.playing_cards) do v.ability.forced_selection = nil end
        elseif name == 'Crimson Heart' then
            for _, v in ipairs(G.jokers.cards) do v.ability.crimson_heart_chosen = nil end
        end
    end
    if s.factor and s.factor ~= 1 then
        blind.chips = blind.chips / s.factor
        blind.chip_text = number_format(blind.chips)
        s.factor = 1
    end
    s.off = true
    for _, v in ipairs(G.playing_cards) do SMODS.recalc_debuff(v) end
    for _, v in ipairs(G.jokers.cards) do SMODS.recalc_debuff(v) end
    log('Staying bosses off for this blind (Chicot)')
    G.E_MANAGER:add_event(Event({ trigger = 'immediate', func = function()
        if G.GAME.blind and G.GAME.blind.chips and G.GAME.chips - G.GAME.blind.chips >= 0
            and G.STATE == G.STATES.SELECTING_HAND then
            G.STATE = G.STATES.NEW_ROUND
            G.STATE_COMPLETE = false
        end
        return true end }))
end

-- Chicot gained or lost (also when a debuff turns him off and on: set_debuff calls
-- remove_from_deck / add_to_deck, dump/card.lua:714-722).
local add_to_deck_ref = Card.add_to_deck
function Card:add_to_deck(from_debuff)
    local was = self.added_to_deck
    add_to_deck_ref(self, from_debuff)
    if not was and self.ability and self.ability.name == 'Chicot' and SB.on() then
        SB.switch_off()
        SB.sync_manacle(nil, nil, self)
    end
end
local remove_from_deck_ref = Card.remove_from_deck
function Card:remove_from_deck(from_debuff)
    local was = self.added_to_deck
    remove_from_deck_ref(self, from_debuff)
    if was and self.ability and self.ability.name == 'Chicot' and SB.on() then SB.sync_manacle(self) end
end

-- Disabling the current blind (Luchador, Chicot, a real Verdant Leaf) flips every
-- face-down Joker up, and hand cards too for Wheel/House/Mark/Fish (dump/blind.lua:
-- 395-415). Cards a staying Amber Acorn or staying flip boss turned down stay down.
-- Then re-check the Manacle.
local disable_ref = Blind.disable
function Blind:disable()
    local s = S()
    local keep_j, keep_h = {}, {}
    if s and s.on and not s.off and self == G.GAME.blind and in_blind() then
        if SB.is_active('bl_final_acorn') then
            for _, c in ipairs(G.jokers.cards) do if c.facing == 'back' then keep_j[#keep_j + 1] = c end end
        end
        if SB.is_active('bl_wheel') or SB.is_active('bl_house') or SB.is_active('bl_mark') or SB.is_active('bl_fish') then
            for _, c in ipairs(G.hand.cards) do if c.facing == 'back' then keep_h[#keep_h + 1] = c end end
        end
    end
    disable_ref(self)
    for _, c in ipairs(keep_j) do if c.facing == 'front' then c:flip() end end
    for _, c in ipairs(keep_h) do
        if c.facing == 'front' then c:flip() end
        c.ability.wheel_flipped = true
    end
    if self == G.GAME.blind and SB.on() then SB.sync_manacle() end
end

----------------------------------------------------------------------
-- A boss is beaten: Blind:defeat runs at the round's cash out (dump/functions/
-- state_events.lua:997). Mr. Bones saving the run counts too, as vanilla marks
-- that boss Defeated.
----------------------------------------------------------------------
local defeat_ref = Blind.defeat
function Blind:defeat(silent)
    local s = S()
    local key = self.config and self.config.blind and self.config.blind.key
    local was_boss = self:get_type() == 'Boss'
    local heart = s and s.on and SB.is_active('bl_final_heart')
    defeat_ref(self, silent)
    if not (s and s.on) or self ~= G.GAME.blind then return end
    if heart then for _, v in ipairs(G.jokers.cards) do v.ability.crimson_heart_chosen = nil end end
    if was_boss and key and G.P_BLINDS[key] then SB.add_beaten(key) end
    SB.sync_manacle(nil, true)
end

----------------------------------------------------------------------
-- Verdant Leaf: selling a Joker during the blind turns it off for that blind
-- (vanilla does this for the current boss, dump/card.lua:1956).
----------------------------------------------------------------------
local sell_ref = Card.sell_card
function Card:sell_card()
    local leaf = self.ability and self.ability.set == 'Joker' and SB.is_active('bl_final_leaf')
        and not SB.st('bl_final_leaf').disabled
    sell_ref(self)
    if leaf then
        G.E_MANAGER:add_event(Event({ trigger = 'immediate', func = function()
            SB.st('bl_final_leaf').disabled = true
            for _, v in ipairs(G.playing_cards) do SMODS.recalc_debuff(v) end
            log('Verdant Leaf off for this blind (Joker sold)')
            return true end }))
    end
end

----------------------------------------------------------------------
-- The Serpent: its draw-3 lives in the draw function (dump/functions/state_events.lua:
-- 329-335) and reads G.GAME.blind.name. For that call only, the blind answers to
-- The Serpent. The draw itself is queued as events, which run after the name is back.
----------------------------------------------------------------------
local draw_ref = G.FUNCS.draw_from_deck_to_hand
G.FUNCS.draw_from_deck_to_hand = function(e)
    local b = G.GAME and G.GAME.blind
    if b and b.name ~= 'The Serpent' and SB.is_active('bl_serpent') then
        local name, disabled = b.name, b.disabled
        b.name, b.disabled = 'The Serpent', false
        local ok, r = pcall(draw_ref, e)
        b.name, b.disabled = name, disabled
        if not ok then error(r, 0) end
        return r
    end
    return draw_ref(e)
end

-- Steamodded tops the hand back up after a draw unless the blind "modifies the draw"
-- (smods/src/utils.lua:3568, 3634). The Serpent is listed by key, so a staying
-- Serpent has to answer too, or the hand refills straight after its draw-3.
local modifies_draw_ref = SMODS.blind_modifies_draw
function SMODS.blind_modifies_draw(key)
    if modifies_draw_ref(key) then return true end
    if SB.is_active('bl_serpent') then return true end
end

----------------------------------------------------------------------
-- Matador pays when the current boss triggered (dump/card.lua:3168, 4182). Here it
-- also pays when a staying boss triggered this hand.
----------------------------------------------------------------------
local calc_joker_ref = Card.calculate_joker
function Card:calculate_joker(context)
    if self.ability and self.ability.name == 'Matador' then
        local s = S()
        local b = G.GAME and G.GAME.blind
        if s and s.on and s.triggered and b and not b.triggered then
            b.triggered = true
            local r = { pcall(calc_joker_ref, self, context) }
            b.triggered = false
            if not r[1] then error(r[2], 0) end
            return unpack(r, 2, table.maxn(r))
        end
    end
    return calc_joker_ref(self, context)
end

-- Other mods asking whether a boss is active (smods/src/utils.lua:3629).
local is_active_blind_ref = SMODS.is_active_blind
function SMODS.is_active_blind(key, ignore_disabled)
    if is_active_blind_ref(key, ignore_disabled) then return true end
    for _, k in ipairs(SB.active()) do
        if k == key or G.P_BLINDS[k].name == key then return true end
    end
    return false
end

----------------------------------------------------------------------
-- RUN INFO: a "Bosses" tab after Vouchers. Every boss stacked this run, in the order
-- beaten, with its chip, name, effect and how many times it was beaten. Added while
-- Run Info builds its tabs (dump/functions/UI_definitions.lua:3305-3327), as
-- BossBounties does, so other mods' tabs survive.
----------------------------------------------------------------------
local function bosses_tab()
    local s = S()
    local list = {}
    for _, key in ipairs((s and s.order) or {}) do
        if G.P_BLINDS[key] then list[#list + 1] = key end
    end
    if not list[1] then
        return { n = G.UIT.ROOT, config = { align = 'cm', colour = G.C.CLEAR, padding = 0.2, minh = 4 }, nodes = {
            { n = G.UIT.T, config = { text = (s and s.on) and 'No bosses yet' or 'Stacking Bosses is off for this run',
                scale = 0.6, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
        } }
    end
    local per_row = #list > 12 and 4 or 3
    local small = #list > 16
    local rows, row = {}, nil
    for i, key in ipairs(list) do
        if (i - 1) % per_row == 0 then
            row = { n = G.UIT.R, config = { align = 'cm', padding = 0.05 }, nodes = {} }
            rows[#rows + 1] = row
        end
        local P = G.P_BLINDS[key]
        local chip = SMODS.create_sprite(0, 0, small and 0.55 or 0.75, small and 0.55 or 0.75,
            SMODS.get_atlas(P.atlas) or 'blind_chips', P.pos)
        chip:define_draw_steps({ { shader = 'dissolve', shadow_height = 0.05 }, { shader = 'dissolve' } })
        local desc = localize { type = 'raw_descriptions', key = key, set = 'Blind', vars = boss_vars(P) } or {}
        local text = ''
        for j, v in ipairs(type(desc) == 'table' and desc or {}) do text = text .. v .. (j < #desc and ' ' or '') end
        local n = s.beaten[key] or 1
        local col = get_blind_main_colour and get_blind_main_colour(key) or G.C.RED
        row.nodes[#row.nodes + 1] = { n = G.UIT.C, config = { align = 'cm', padding = 0.06, r = 0.1,
            colour = G.C.BLACK, minw = small and 2.6 or 3.4, maxw = small and 2.6 or 3.4 }, nodes = {
            { n = G.UIT.C, config = { align = 'cm' }, nodes = { { n = G.UIT.O, config = { object = chip } } } },
            { n = G.UIT.C, config = { align = 'cl', padding = 0.03 }, nodes = {
                { n = G.UIT.R, config = { align = 'cl' }, nodes = {
                    { n = G.UIT.T, config = { text = localize { type = 'name_text', key = key, set = 'Blind' },
                        scale = small and 0.3 or 0.36, colour = G.C.WHITE, shadow = true } },
                    n > 1 and { n = G.UIT.T, config = { text = '  x' .. n, scale = small and 0.3 or 0.36, colour = col, shadow = true } } or nil,
                } },
                { n = G.UIT.R, config = { align = 'cl' }, nodes = {
                    { n = G.UIT.O, config = { object = DynaText({ string = { text }, colours = { G.C.UI.TEXT_LIGHT },
                        scale = small and 0.22 or 0.27, maxw = small and 1.8 or 2.5, silent = true }) } },
                } },
            } },
        } }
    end
    local total = #list
    local nodes = {
        { n = G.UIT.R, config = { align = 'cm', padding = 0.05 }, nodes = {
            { n = G.UIT.T, config = { text = total .. (total == 1 and ' boss' or ' bosses') .. ' stacked',
                scale = 0.45, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
        } },
    }
    if s.off and in_blind() then
        nodes[#nodes + 1] = { n = G.UIT.R, config = { align = 'cm' }, nodes = {
            { n = G.UIT.T, config = { text = 'Off this blind (Chicot)', scale = 0.32, colour = G.C.GREEN, shadow = true } } } }
    end
    for _, r in ipairs(rows) do nodes[#nodes + 1] = r end
    return { n = G.UIT.ROOT, config = { align = 'cm', colour = G.C.CLEAR, padding = 0.1 }, nodes = nodes }
end
SB.bosses_tab = bosses_tab

local building_run_info = false
local run_info_ref = G.UIDEF.run_info
function G.UIDEF.run_info(...)
    building_run_info = true
    local ok, ret = pcall(run_info_ref, ...)
    building_run_info = false
    if not ok then error(ret, 0) end
    return ret
end

local create_tabs_ref = create_tabs
function create_tabs(args)
    if building_run_info and args and type(args.tabs) == 'table' then
        building_run_info = false
        local s = S()
        if s then
            local at = #args.tabs + 1
            local vouchers = localize('b_vouchers')
            for i, t in ipairs(args.tabs) do if t and t.label == vouchers then at = i + 1 end end
            table.insert(args.tabs, at, { label = 'Bosses', tab_definition_function = bosses_tab })
        end
    end
    return create_tabs_ref(args)
end

----------------------------------------------------------------------
-- Config: the switch. Read at run start, so it applies to the next new run.
----------------------------------------------------------------------
THIS_MOD.config_tab = function()
    return {
        n = G.UIT.ROOT, config = { align = 'cm', padding = 0.1, colour = G.C.CLEAR },
        nodes = {
            { n = G.UIT.R, config = { align = 'cm', padding = 0.05 }, nodes = {
                create_toggle({ label = 'Stacking Bosses on', ref_table = cfg, ref_value = 'enabled' }) } },
            { n = G.UIT.R, config = { align = 'cm', padding = 0.05 }, nodes = {
                { n = G.UIT.T, config = { text = 'Applies to new runs', scale = 0.32, colour = G.C.UI.TEXT_LIGHT } } } },
        },
    }
end

log('Loaded v1.0.0, ' .. (cfg.enabled and 'on' or 'off') .. ' for new runs')
