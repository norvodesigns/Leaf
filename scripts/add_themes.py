"""Adds a `th` (themes) list to every book in Leaf/Resources/books.json.

Genres (32 of them) are too coarse to say why two books feel alike. Themes are the specific things a book is about:
"dragons", "found family", "books about books", "world war ii", "the harry potter universe".

Raw Open Library subjects are far too noisy to use directly (foreign-language words, library metadata, a dozen
spellings of the same idea). So themes come from a **curated lexicon**: about 150 canonical themes, each defined by
patterns over the cleaned subject strings. The same lexicon works at any catalog size, which matters for the 250k build.

    python3 -I scripts/add_themes.py

Reads cached subjects from scripts/.cache (no network). Safe to re-run: it only rewrites the `th` key.
"""
import glob
import importlib.util
import json
import os
import re
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
CATALOG = os.path.join(HERE, "..", "Leaf", "Resources", "books.json")
CACHE = os.path.join(HERE, ".cache")

spec = importlib.util.spec_from_file_location("build_catalog", os.path.join(HERE, "build_catalog.py"))
bc = importlib.util.module_from_spec(spec)
sys.modules["build_catalog"] = bc
spec.loader.exec_module(bc)

# (canonical theme, regex over the cleaned subject, hidden)
# `hidden` themes help similarity but are never shown as row titles or "because" reasons.
LEXICON = [
    # --- plot and premise ---
    ("adventure", r"adventure|quests?\b|treasure|buried treasure|treasure troves|explorers?|exploration|expeditions?", False),
    ("murder", r"murder|homicide|serial (killers|murders)|trials \(murder\)", False),
    ("detectives", r"detective|private investigators|ex-police officers|police|investigat|sleuth|whodunit", False),
    ("missing persons", r"missing (persons|children|girls)|disappearances?|kidnap", False),
    ("crime", r"\bcrime|criminals|organized crime|gangs|thieves|theft|heists?|burglars?|fugitives|corrupt practices|prisons?|prisoners", False),
    ("true crime", r"true crime", False),
    ("legal drama", r"lawyers|trials|courts?\b|legal|judges|attorneys", False),
    ("spies", r"spies|espionage|intelligence officers|secret agents?|cold war|secret service", False),
    ("heists & cons", r"swindlers|confidence (men|game)|con artists|heists?", False),
    ("secrets", r"secrets|secrecy|family secrets|conspirac|cover-?ups?", False),
    ("revenge", r"revenge|vengeance|vendetta", False),
    ("betrayal", r"betrayal|treason|infidelity|jealousy", False),
    ("survival", r"survival|shipwrecks|wilderness|castaways|stranded|desert island", False),
    ("war", r"\bwar\b|wars\b|soldiers|veterans|battles?|military|combat|resistance movements|insurgency|terroris", False),
    ("world war ii", r"world war, 1939|world war ii|second world war|holocaust|nazis?|concentration camps|jewish.*1939", False),
    ("world war i", r"world war, 1914|world war i\b|first world war", False),
    ("historical europe", r"middle ages|medieval|renaissance|tudor|victorian|regency|napoleonic|georgian|elizabethan", False),
    ("ancient world", r"ancient|rome\b|roman empire|egypt|greece\b|greeks|bible|biblical|trojan war", False),
    ("pirates & the sea", r"\bpirates?\b|sea stories|\bsailors?\b|\bships?\b|\bnaval\b|\boceans?\b|seafaring|\bwhaling\b|\bat sea\b|\bsea\b", False),
    ("westerns", r"westerns?|cowboys|frontier and pioneer|west \(u\.s\.\)|gold rush|wild west|outlaws", False),
    ("road trips", r"road trips?|journeys|pilgrim", False),
    ("class & society", r"social classes|social class|rich people|aristocracy|upper class|nobility|wealth|poverty|poor\b|working class", False),
    ("politics & power", r"politic|government|presidents|elections|power \(social|totalitarian|dictators|revolution", False),
    ("slavery", r"slavery|slaves|abolition|civil war|reconstruction", False),
    ("immigration", r"immigrants|emigration and immigration|refugees|assimilation|diaspora", False),
    ("race & identity", r"african americans?|afro-americans|blacks\b|racism|race relations|racial|civil rights|discrimination|prejudices?", True),
    ("lgbtq+", r"lgbt|gay\b|gays|lesbian|queer|homosexuality|gender identity|transgender|bisexual", True),
    ("jewish lives", r"\bjews\b|jewish|judaism", True),
    ("native lives", r"indians of north america|native americans|indigenous|first nations|aboriginal", True),
    ("mental health", r"mental (illness|disorders|health)|mentally ill|depression|anxiety|suicide|bipolar|schizophren|ptsd|trauma|eating disorders", False),
    ("addiction", r"alcohol|drug (abuse|addicts|traffic)|addiction|substance abuse|gambling", False),
    ("abuse & healing", r"abuse|abused|domestic violence|rape|survivors|healing|recovery", False),
    ("illness & medicine", r"physicians|doctors|nurses|hospitals|patients|diseases|epidemics|medicine|cancer|medical", False),
    ("disability", r"people with disabilities|blind\b|deaf|autis|disabilit|wheelchair", False),
    ("grief & loss", r"grief|bereavement|loss\b|widows|widowers|death\b|dying|mourning|funerals?", False),
    ("identity & self-discovery", r"identity|self-discovery|self-acceptance|individuality|self concept|self-perception|self-realization|belonging", False),
    ("redemption & forgiveness", r"redemption|forgiveness|atonement|guilt|second chances", False),
    ("loneliness", r"loneliness|solitude|isolation|social isolation|alienation", False),
    ("coming of age", r"coming[- ]of[- ]age|adolescence|teenagers|teenage|growing up|youth\b|childhood|bildungsroman|first love", False),
    ("school life", r"school stories|schools?\b|boarding schools|middle schools|private schools|high schools?|students|teachers|college|universit|campus|teacher-student", False),
    ("orphans", r"orphans|abandoned children|foster", False),
    ("found family", r"found family|chosen family|adopted|adoption|foster", False),
    ("friendship", r"friendship|friends\b|best friends|female friendship|male friendship|companionship", False),
    ("family life", r"family life|families|family relationships|family & relationships|dysfunctional famil|parent and child|parents\b|grandparents|grandmothers|grandfathers|stepfamilies|family problems|generations", False),
    ("siblings", r"siblings|brothers and sisters|sisters|brothers|twins|sibling rivalry|cousins", False),
    ("mothers & daughters", r"mothers and daughters|mother and child|mothers\b|single mothers|motherhood", False),
    ("fathers & sons", r"fathers and sons|fathers and daughters|father-(son|daughter)|fathers\b", False),
    ("marriage", r"marriage|married (people|women)|husband and wife|arranged marriage|divorce|wives|widows|weddings?|adultery|infidelity", False),
    ("love stories", r"^love$|love stories|love affairs|\bromance|courtship|forbidden love|mate selection|man-woman|first loves", False),
    ("enemies to lovers", r"enemies to lovers|rivals? to lovers|hate to love|fake relationship|marriage of convenience|fake dating", False),
    ("second chances", r"second chance|reunion|former lovers|exes\b", False),
    ("women's lives", r"women\b|young women|single women|women authors|female|girls\b|feminis|sex role|sexism|women's studies", False),
    ("men & masculinity", r"\bmen\b|young men|masculinity|male|boys\b|boys & men", True),
    ("pregnancy & babies", r"pregnan|babies|infants|childbirth|newborn|motherhood", False),
    ("aging", r"older (men|women|people)|aging|old age|elderly|retirement|grandparent", False),
    # --- magic, myth, monsters ---
    ("magic", r"\bmagic|wizards?|sorcer|enchant|spells?|magical|warlocks?|magicians|necromancy|mages?", False),
    ("dragons", r"dragons?|dragones|drachen", False),
    ("witches", r"witch|brujas|hexen|coven", False),
    ("fairy tales & folklore", r"fairy tales|fairies|fairy\b|folklore|folk tales|legends|fables|retellings|myths?\b", False),
    ("mythology", r"mytholog|greek gods|norse|norse gods|gods\b|goddesses|olympus|pantheon|demigods|deities|trojan", False),
    ("knights & castles", r"knights and knighthood|knights\b|castles|chivalry|crusades|arthurian|round table|camelot", False),
    ("royalty & courts", r"kings and rulers|kings, queens|queens\b|princes\b|princesses|courts and courtiers|royalty|royal family|monarch|empresses|emperors|thrones?", False),
    ("prophecy & chosen ones", r"prophe|chosen one|destiny|fate and fatalism|oracle", False),
    ("quests", r"quests?\b|journey to|epic fantasy|high fantasy|heroes and heroines|heroes\b|hero's journey", False),
    ("ghosts", r"ghosts?|haunted|hauntings|poltergeist|spirits", False),
    ("vampires", r"vampire|vampiros|dracula|bloodsuckers|undead", False),
    ("werewolves & shifters", r"werewolves|shapeshifters?|shifters|lycanthrop|were-", False),
    ("monsters", r"monsters?|demons?|creatures|zombies?|supernatural|paranormal|occult|possession|exorcis|cthulhu|lovecraft", False),
    ("angels & demons", r"angels|demons|heaven|hell\b|devil|satan|fallen angels|apocalyps", False),
    ("gothic", r"gothic|haunted houses?|manor|ancestral|mansions?|moors|brooding", False),
    ("horror", r"horror|nightmares|creepy|slasher|scary|fear street|goosebumps", False),
    ("psychological suspense", r"psychological|unreliable|obsession|stalkers?|domestic suspense|twist|manipulat|gaslight", False),
    ("fantasy worlds", r"imaginary (place|places|countries|kingdoms)|imaginary wars|alternate (worlds|universes)|secondary world|invented worlds|portal fantasy|parallel worlds|other worlds", False),
    ("fantasy epics", r"\bepic\b|sagas|fantasy fiction, epic|epic fantasy", False),
    ("magical realism", r"magical realism|magic realism|realismo magico", False),
    ("urban fantasy", r"urban fantasy|contemporary fantasy|paranormal romance|modern magic", False),
    ("cozy fantasy", r"cozy fantasy|low fantasy|slice of life fantasy|gentle fantasy|cottagecore", False),
    # --- science fiction ---
    ("space & aliens", r"space flight|space colonies|human-alien|extraterrestrial|aliens?\b|outer space|interplanetary|space opera|space ships?|spaceships?|galax|astronauts|mars\b|planets?|interstellar|space travel", False),
    ("time travel", r"time travel|voyages dans le temps|space and time|time machines|temporal|alternate history", False),
    ("dystopia", r"dystopi|utopi|totalitarian|post-?apocalyptic|end of the world|apocalypse|survivalism|plague|pandemic", False),
    ("robots & ai", r"robots?|artificial intelligence|androids?|cyborgs?|machine intelligence|sentient|computers\b|singularity", False),
    ("cyberpunk & tech", r"cyberpunk|cyberspace|virtual reality|hackers?|internet|technology|genetic engineering|nanotechnology|biotechnology", False),
    ("climate & nature futures", r"climate|global warming|environmental|ecology|eco-", False),
    ("first contact", r"first contact|contact with aliens|invasion|alien invasion", False),
    ("science & discovery", r"scientists?|physics|physicists|astronomy|cosmology|evolution|genetics|biology|chemistry|mathematics|mathematicians|scientific discoveries|inventors?", False),
    # --- tone and cozy markers ---
    ("humor", r"humor|humorous|comedy|satire|funny|parod|farce|wit and", False),
    ("dark & gritty", r"\bdark\b|grim|gritty|noir|bleak|violence|violent|brutal|cruelty|torture", False),
    ("feel-good", r"feel-good|heartwarming|uplifting|inspiring|hopeful|optimis|wholesome|comfort|cheerful|gentle", False),
    ("cozy", r"\bcozy|cosy|hygge|comfort read|cozy mysteries|cozy fantasy|cottagecore|slice of life", False),
    ("small town life", r"small towns?|villages?|country life|rural|farm life|farms?\b|ranch|city and town life|hometown|neighbou?rs|community", False),
    ("seaside & islands", r"islands?\b|coastal|seaside|beaches|lighthouses?|harbou?r|fishing villages|cornwall|maine", False),
    ("gardens & nature", r"\bgardens?\b|gardening|flowers|herbs|botany|beekeeping|orchards?|countryside", False),
    ("food & cooking", r"cooking|cookery|food\b|baking|bakers?|bakeries|restaurants?|chefs?|recipes|meals?|cafes?|coffee|desserts", False),
    ("tea & cafes", r"\btea\b|teas\b|teahouse|tea rooms?|cafes?|coffee shops?|coffeehouses?|tearoom", False),
    ("books about books", r"bookstores?|bookshops?|booksellers?|\blibraries\b|\blibrarians?\b|bibliophil|book clubs?|\bbookbinding|reading, ?psychology|\bbibliomania", False),
    ("letters & diaries", r"letters\b|correspondence|diaries|diary fiction|epistolary|journals?\b|memoirs? of", False),
    ("animals", r"animals?\b|pets\b|wildlife|zoo|farm animals|talking animals|human-animal|beasts", False),
    ("cats", r"\bcats?\b|feral cats|kittens?|felines", False),
    ("dogs", r"\bdogs?\b|puppies|puppy|canines|wolves", False),
    ("horses", r"horses|ponies|riding|equestrian|horse racing", False),
    ("christmas", r"christmas|santa claus|\badvent\b", False),
    ("halloween & autumn", r"halloween|autumn|fall\b|harvest|pumpkins?|all hallows", False),
    ("winter", r"winter|\bsnow\b|blizzard|arctic", False),
    ("summer", r"summer|\bvacations?\b|\bbeach(es)?\b|\bcamps?\b|camping", False),
    ("rainy days", r"\brain\b|\brainy\b|\bfog\b|\bmist\b|gloomy|drizzle", False),
    ("travel & places", r"voyages and travels|tourism|expatriates|backpack|(?<!time )\btravel\b", False),
    ("art & music", r"artists?|painting|painters|music|musicians|singers|composers|orchestra|actors|dancers|ballet|theater|theatre|film|art\b|photography", False),
    ("fashion & beauty", r"fashion|beauty|models|clothing|dress|style|designer", False),
    ("sports", r"sports?\b|athletes|football|baseball|basketball|soccer|boxing|running|olympic|racing|tennis|golf|hockey", False),
    ("games & puzzles", r"\bchess\b|puzzles?|gamblers|\bcard games\b|\bvideo games\b|role-playing|escape room|riddles|board games", False),
    ("crafts & making", r"crafts|knitting|sewing|quilt|pottery|woodworking|crochet|handicraft", False),
    ("business & money", r"business\b|economics|finance|investing|investments|entrepreneur|money\b|wealth|stock market|marketing|sales\b|management|capital", False),
    ("leadership & work", r"leadership|career|work\b|employees|workplace|productivity|organizational|success|negotiat|decision making|strategy|strategic", False),
    ("habits & mindset", r"habits|self-help|personal growth|motivation|self-improvement|mindset|psychology of|happiness|life change|self-actualization|self help|resilience", False),
    ("mindfulness & meaning", r"mindfulness|meditation|spiritual|spirituality|buddhis|stoic|meaning of life|zen|philosophy of life|contentment|inner peace|religious life", False),
    ("health & body", r"health|fitness|nutrition|diet|exercise|sleep|medicine|wellness|yoga|body", False),
    ("mind & brain", r"cognition|neuroscience|\bbrain\b|consciousness|cognitive|psychology of|thinking, fast", False),
    ("philosophy & ideas", r"philosoph|metaphysics|epistemology|existential|\bethics\b|theory of knowledge", False),
    ("history & the past", r"history, modern|history, ancient|world history|civilization|\bempires?\b|dynast|early works to 1800", False),
    ("nature & environment", r"environment|nature\b|conservation|wildlife|ecology|oceans|climate|rainforest|mountains|natural history", False),
    ("technology & society", r"technology|internet|social media|digital|artificial intelligence|computers|automation|privacy|cyber|software|programming", False),
    ("language & words", r"linguistic|grammar|rhetoric|vocabulary|dictionar|etymolog", False),
    ("religion & faith", r"religion|christian|church|bible|god\b|faith|islam|muslim|hindu|buddh|catholic|jesus|spiritual", False),
    ("crime & justice", r"justice|prisons|police|law enforcement|criminal justice|wrongful|death penalty|incarceration", False),
    ("education", r"\beducation\b|pedagogy|curriculum|study and teaching|\bteaching\b", False),
    # --- places ---
    ("england", r"\bengland\b|english countryside|great britain|british|london \(england\)|victorian england", False),
    ("london", r"london", False),
    ("scotland & ireland", r"scotland|scottish|highlands|ireland|irish|dublin|edinburgh|hebrides", False),
    ("france & paris", r"france|french\b|paris|provence|riviera", False),
    ("italy", r"italy|italian|rome\b|venice|florence|tuscany", False),
    ("spain & latin america", r"\bspain\b|latin america|mexico|argentina|colombia|\bcuba\b|brazil|\bchile\b|\bperu\b", False),
    ("germany & central europe", r"germany|german\b|berlin|austria|vienna|prague|poland|hungary|czech", False),
    ("russia & eastern europe", r"russia|soviet|moscow|st\. petersburg|ukraine|siberia|eastern europe", False),
    ("japan", r"japan|japanese|tokyo|kyoto|samurai|geisha", False),
    ("china & east asia", r"china|chinese|beijing|korea|taiwan|hong kong|shanghai|tibet|vietnam\b", False),
    ("india & south asia", r"india\b|indian\b|pakistan|bangladesh|sri lanka|nepal|bombay|mumbai|delhi", False),
    ("africa", r"africa\b|african\b|nigeria|kenya|south africa|egypt|ghana|ethiopia|congo|sahara", False),
    ("middle east", r"middle east|iran\b|iraq|israel|palestin|arab|saudi|syria|lebanon|turkey|afghanistan", False),
    ("new york", r"new york|manhattan|brooklyn|harlem", False),
    ("california & the west coast", r"california|los angeles|san francisco|hollywood|oregon|seattle|pacific northwest|washington \(state\)", False),
    ("american south", r"southern states|south \(u\.s\.\)|mississippi|louisiana|new orleans|georgia \(u\.s\.|alabama|texas|tennessee|carolina|appalachia|deep south|savannah", False),
    ("new england", r"new england|maine\b|massachusetts|boston|vermont|connecticut|new hampshire|cape cod|rhode island", False),
    ("american midwest", r"midwest|chicago|ohio|michigan|indiana|iowa|wisconsin|minnesota|kansas|nebraska", False),
    ("american west", r"west \(u\.s\.\)|colorado|montana|wyoming|nevada|arizona|new mexico|utah|idaho|alaska|rocky mountains|southwest", False),
    ("canada & australia", r"canada|canadian|australia|australian|new zealand|toronto|sydney|outback", False),
    ("washington & politics", r"washington \(d\.c\.|white house|congress|capitol|federal government|president", False),
]
LEXICON = [(name, re.compile(rx, re.I), hidden) for name, rx, hidden in LEXICON]
HIDDEN = {name for name, _rx, hidden in LEXICON if hidden}

# "Fictitious character" and "imaginary place" subjects mark a series or a shared universe.
UNIVERSE = re.compile(r"^(?P<name>[^()]+?)\s*\((?:fictitious character|imaginary place|fictitious characters?)(?: : [^)]*)?\)$")
UNIVERSE_JUNK = {"god", "jesus christ", "christ", "bible", "satan", "santa claus", "devil", "death", "angel"}

NON_ASCII = re.compile(r"[^\x00-\x7f]")
TAIL = re.compile(r"(,| --| -|\()\s*(juvenile )?fiction\)?$")
MIN_DF = 5          # a theme must be shared by at least this many books to be useful
PER_BOOK = 8


def normalize(subject):
    s = bc.fold(subject).strip().lower()
    s = s.split(" -- ")[0]
    s = TAIL.sub("", s).strip(" ,;.")
    return re.sub(r"\s+", " ", s)


def universe_name(s):
    m = UNIVERSE.match(s)
    if not m:
        return None
    name = m.group("name").strip()
    if "," in name:  # "potter, harry" -> "harry potter"
        last, _, first = name.partition(",")
        name = (first.strip() + " " + last.strip()).strip()
    name = re.sub(r"\s+", " ", name)
    if not name or name in UNIVERSE_JUNK or NON_ASCII.search(name) or len(name) > 36:
        return None
    return name


def themes_for(doc):
    subjects = []
    for raw in doc.get("subject") or []:
        s = normalize(raw)
        if s and len(s) <= 60 and not NON_ASCII.search(s) and not bc.NOISE_SUBJECT.search(s):
            subjects.append(s)
    hits = Counter()
    universes = Counter()
    for s in subjects:
        u = universe_name(s)
        if u:
            universes[u] += 1
            continue
        for name, rx, _hidden in LEXICON:
            if rx.search(s):
                hits[name] += 1
    return hits, universes


def load_cache():
    best = {}
    for path in glob.glob(os.path.join(CACHE, "*.json")):
        try:
            data = json.load(open(path, encoding="utf-8"))
        except Exception:
            continue
        for doc in (data.get("docs") or []) if isinstance(data, dict) else []:
            wid = (doc.get("key") or "").split("/")[-1]
            if wid and len(doc.get("subject") or []) > len((best.get(wid) or {}).get("subject") or []):
                best[wid] = doc
    return best


def main():
    books = json.load(open(CATALOG, encoding="utf-8"))
    docs = load_cache()
    raw = {}
    df = Counter()
    for b in books:
        doc = docs.get(b["id"])
        hits, universes = themes_for(doc) if doc else (Counter(), Counter())
        raw[b["id"]] = (hits, universes)
        df.update(hits.keys())
        df.update("series:" + u for u in universes)

    n = len(books)
    for b in books:
        hits, universes = raw[b["id"]]
        scored = []
        for name, count in hits.items():
            if df[name] < MIN_DF:
                continue
            # Specific beats common; several matching subjects beat one.
            scored.append((name, count / (1.0 + df[name] / n * 6.0)))
        # A book usually has several character subjects for one series; keep the two most widely shared.
        shared = sorted(((df["series:" + u], u, count) for u, count in universes.items() if df["series:" + u] >= 3), reverse=True)
        for _df, u, count in shared[:2]:
            scored.append(("series:" + u, 2.0 + count))
        scored.sort(key=lambda kv: (-kv[1], kv[0]))
        b["th"] = [name for name, _ in scored[:PER_BOOK]]

    with open(CATALOG, "w", encoding="utf-8") as fh:
        json.dump(books, fh, ensure_ascii=False, separators=(",", ":"))

    used = Counter(t for b in books for t in b["th"])
    with_themes = sum(1 for b in books if b["th"])
    print("books: %d   with themes: %d (%.0f%%)   avg themes/book: %.1f   file: %.0f KB"
          % (n, with_themes, 100.0 * with_themes / n, sum(len(b["th"]) for b in books) / n,
             os.path.getsize(CATALOG) / 1024))
    print("themes used: %d of %d lexicon entries (+%d series)"
          % (sum(1 for t in used if not t.startswith("series:")), len(LEXICON), sum(1 for t in used if t.startswith("series:"))))
    print("top:", used.most_common(45))
    print("rare (<8):", sorted(t for t, c in used.items() if c < 8 and not t.startswith("series:"))[:60])
    print("series:", sorted(((t, c) for t, c in used.items() if t.startswith("series:")), key=lambda kv: -kv[1])[:40])
    for theme in ("cozy", "tea & cafes", "books about books", "small town life", "found family", "feel-good", "cats"):
        titles = sorted((b for b in books if theme in b["th"]), key=lambda b: -b["pop"])[:7]
        print("  [%s] %d: %s" % (theme, used[theme], "; ".join(b["t"] for b in titles)))
    for title in ("The Hobbit", "Circe", "Project Hail Mary", "Pride and Prejudice", "Gone Girl", "Atomic Habits",
                  "The Night Circus", "Harry Potter and the Philosopher's Stone", "Educated", "The Midnight Library"):
        for b in books:
            if b["t"] == title:
                print("  %-24s %s | %s" % (title, b["g"], b["th"]))
                break


if __name__ == "__main__":
    main()
