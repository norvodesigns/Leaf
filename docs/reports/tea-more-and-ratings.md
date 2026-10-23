# More teas, rating teas, and Make it yours on You

Asked by Matt before App Store review: more teas, and make the place to personalise Leaf and rate teas easier to find.

## What changed

- **Catalog: 38 teas (was 19).** Assam, Ceylon, Keemun; Dragon Well, Gyokuro, Moroccan Mint, Kukicha; Matcha Latte;
  White Peony; Tieguanyin, Oriental Beauty; Lavender, Golden Turmeric, Elderflower, Linden Blossom; Vanilla Rooibos,
  Rooibos Chai; Pumpkin Spice Chai, Ginger Chai. Steep times, temperatures, caffeine and the hours they're offered
  follow the catalog rules (and its tests). Late night and the small hours now have 11 caffeine-free teas. The new teas
  are named in the book pairings they suit (poetry, science fiction, romance, history, younger reads, travel,
  feel-good, rainy days, winter, food, short and long books), each with its own line.
- **Ratings count.** A tea's leaves (on its tin, or from the new page) lean Today's tea and the ritual toward it:
  five leaves about as far as a liked kind, one leaf nearly out of the running, three neutral
  (`TeaPreferences.ratingWeight`). A tin keeps its synced rating, which wins over the page's (`TeaShelf.rating`).
- **"Teas you like" flavours work now.** Most flavour chips never matched a tea: notes say "malt" and "pine smoke",
  the chips "malty" and "smoky". `TastingAroma.cues` maps each chip to the words tins use; every chip now finds teas.
- **Rate your teas** (`TeaRatingsView`): every tea on one page with tap-to-rate leaves, no forms. Teas you've read with
  first, then the cabinet, then Leaf's by kind; chips for All, Rated and each kind.
- **You: Make it yours.** Four tiles right under the streak, each saying where it stands: Rate your teas ("4 teas
  rated"), Teas you like ("Green and Herbal · floral"), Tea cabinet ("5 in, 1 run out"), Settings. The old More card
  at the bottom is now "Look back" (reading log, numbers, year, quotes, tea history). The You first-use tip names
  the new section.
- Rate your teas and Teas you like are also linked from Settings > Tea, the cabinet, and each other.
- Screenshots: 115-tea-ratings, 116-tea-preferences, lt-115-tea-ratings, lt-c5-you (C5-you shows the tiles).

## NEEDS FROM ENGINE

- Ratings of teas the reader doesn't keep a tin of live in `TeaPreferences` on this device (like "Teas you like"),
  so they don't sync. Tin ratings do. If preferences ever sync, ratings come along with no other change.

## Next package you recommend

Tea detail sheet: tap a tea anywhere (ritual, pairing, ratings page) for its notes, temperature, caffeine, your
leaves and a one-tap "add to cabinet".
