# Stacking Bosses

Every Boss Blind you beat in Balatro stays for the rest of the run.

## What it does

Beat a boss and its effect keeps applying on every blind after it, Small and Big Blinds included, stacked with every other boss you've beaten. Beat The Club and Clubs stay debuffed. Beat The Needle and every blind after it gives you one hand.

Every boss works exactly as it does in the normal game. None is changed, toned down or left out.

## How it plays

- **Blind sizes stack too.** The Wall doubles every blind after it, Violet Vessel triples them, and The Needle halves them. Beat more than one and they multiply.
- **The Manacle** takes 1 hand size away for the rest of the run.
- **You only meet bosses you haven't beaten yet.** The game picks each Boss Blind from the ones you haven't beaten. Once you've beaten every boss that can show up at that ante, they can all come back. Showdown bosses work the same way.
- **Rerolling** with Director's Cut or Retcon draws from the same unbeaten bosses, so you can put a boss off, but it comes back until you beat it.
- **A boss you've already beaten adds nothing** if it comes round again. Its effect is only on once.
- **Beaten means the blind was won**, including when Luchador or Chicot disabled it, and when Mr. Bones saved you.
- **Chicot switches off every staying boss** on every blind for as long as you own him, sizes and The Manacle included. Sell him and they all come back.
- **Luchador** disables the current boss only, as normal. That boss still stays once you beat it.
- **Matador** also pays when a staying boss triggers.
- **Verdant Leaf** staying works like the real one: sell a Joker to switch it off for that blind.

**The HUD only shows the current blind.** Run Info has a **Bosses tab** listing every boss you've stacked, with what it does.

## Installation

1. Install [Steamodded](https://github.com/Steamodded/smods) 1.0.0~BETA-1620a or newer.
2. Download the latest release, unzip it, and put the folder in your `Mods` folder:

```
Mods/
  StackingBosses/
    StackingBosses.lua
    StackingBosses.json
```

### Config

- **Stacking Bosses on** (on by default). Works on any deck and stake. The setting is read when a run starts, so changing it applies to your next new run.

## Compatibility

- Not tested alongside BossBounties or BossRewards.
- JokerDisplay's hints only know about the current boss, not the ones that stay.

## Credits

- Idea from comments by **@Sernik28** and **@badmanjones179**.
- The Bosses tab draws the boss chips from the game's own files while it runs. No game art is included in this mod.

## License

MIT
