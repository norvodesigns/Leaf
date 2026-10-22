#!/usr/bin/env python3
"""Build the quick-start seed catalog (scripts/data/books.seed.json) from the Open Library search API.

This is the small, crawl-based catalog (about 5,000 books). The app no longer bundles this JSON: the bundled catalog is
the SQLite database that scripts/catalog/build_catalog_db.py makes, either from the full Open Library dumps or, with
--from-json, from this seed. This file is also the home of the quality rules and the subject-to-genre mapping that the
dump pipeline imports, so edit those here and both pipelines follow.

Data source: the Open Library search API (https://openlibrary.org/search.json).
Python 3 standard library only.  Run from anywhere:

    python3 -I scripts/build_catalog.py            # fetch (cached) + build
    python3 -I scripts/build_catalog.py --offline  # build from cache only

Raw API responses are cached in scripts/.cache/ (git-ignored), so re-runs are
fast and polite.  Requests are throttled to ~1/second with retry + backoff.

Output: a compact JSON array sorted by popularity, one object per work:
    {"id":"OL82563W","t":"Title","a":"Author","y":1997,"p":223,"w":76900,
     "c":10521270,"g":["fantasy","young-adult"],"pop":12345}
"""

import hashlib
import json
import math
import os
import re
import sys
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter, defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE_DIR = os.path.join(ROOT, "scripts", ".cache")
OUT_PATH = os.path.join(ROOT, "scripts", "data", "books.seed.json")

API = "https://openlibrary.org/search.json"
USER_AGENT = "Leaf/1.0 (https://github.com/norvodesigns/leaf)"
FIELDS = ",".join([
    "key", "title", "author_name", "author_key", "first_publish_year",
    "number_of_pages_median", "cover_i", "subject", "readinglog_count",
    "want_to_read_count", "ratings_count", "language", "publish_year",
    "edition_count",
    "editions", "editions.title", "editions.language", "editions.cover_i",
])
MIN_INTERVAL = 1.0      # seconds between live requests
PAGE_SIZE = 500

TARGET_COUNT = 5200     # books taken purely by popularity
MAX_COUNT = 6000        # hard cap after genre / must-have top-ups
MIN_PER_GENRE = 40      # every genre tag gets at least this many books
MIN_POP_TOPUP = 15      # ...but only books with at least this much interest

GENRES = [
    "fiction", "classics", "literary", "fantasy", "science-fiction", "mystery",
    "thriller", "romance", "historical", "horror", "young-adult", "children",
    "poetry", "drama", "short-stories", "graphic", "biography", "memoir",
    "history", "science", "philosophy", "psychology", "self-help", "business",
    "politics", "religion", "nature", "travel", "essays", "humor", "food", "art",
]
GENRE_SET = set(GENRES)

# --------------------------------------------------------------------------
# HTTP + cache
# --------------------------------------------------------------------------

_last_request = [0.0]
OFFLINE = False
STATS = Counter()


def fetch_json(params):
    """GET search.json with params; cached on disk by URL."""
    query = urllib.parse.urlencode(sorted(params.items()))
    url = API + "?" + query
    digest = hashlib.sha1(url.encode("utf-8")).hexdigest()[:20]
    path = os.path.join(CACHE_DIR, digest + ".json")
    if os.path.exists(path):
        STATS["cache_hits"] += 1
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    if OFFLINE:
        STATS["cache_misses_offline"] += 1
        return None
    delay = 2.0
    for attempt in range(6):
        wait = MIN_INTERVAL - (time.time() - _last_request[0])
        if wait > 0:
            time.sleep(wait)
        _last_request[0] = time.time()
        try:
            req = urllib.request.Request(url, headers={
                "User-Agent": USER_AGENT, "Accept": "application/json"})
            with urllib.request.urlopen(req, timeout=90) as resp:
                raw = resp.read()
            data = json.loads(raw.decode("utf-8"))
            if "docs" not in data:
                raise ValueError("unexpected response: %s" % str(data)[:200])
            os.makedirs(CACHE_DIR, exist_ok=True)
            tmp = path + ".tmp"
            with open(tmp, "w", encoding="utf-8") as fh:
                json.dump(data, fh, ensure_ascii=False)
            os.replace(tmp, path)
            STATS["requests"] += 1
            return data
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError,
                ValueError, ConnectionError, OSError) as exc:
            code = getattr(exc, "code", None)
            if code in (400, 404):
                print("  ! %s for %s" % (code, url), file=sys.stderr)
                return None
            print("  ! attempt %d failed (%s); retrying in %.0fs"
                  % (attempt + 1, exc, delay), file=sys.stderr)
            time.sleep(delay)
            delay = min(delay * 2, 60)
    print("  ! giving up on %s" % url, file=sys.stderr)
    STATS["failed_requests"] += 1
    return None


def search(q, sort="readinglog", limit=PAGE_SIZE, offset=0):
    params = {"q": q, "fields": FIELDS, "limit": str(limit), "lang": "en"}
    if sort:
        params["sort"] = sort
    if offset:
        params["offset"] = str(offset)
    data = fetch_json(params)
    return (data or {}).get("docs", []), (data or {}).get("numFound", 0)


# --------------------------------------------------------------------------
# What to fetch
# --------------------------------------------------------------------------

# General popularity sweep: every work with a reading log of at least N.
GENERAL_QUERY = "readinglog_count:[40 TO *]"
GENERAL_PAGES = 60  # up to 30k works; stops early when exhausted

# Subject sweeps (query, genre hint, pages of 500 sorted by reading log).
SUBJECT_QUERIES = [
    ('subject:fantasy', "fantasy", 2),
    ('subject:"science fiction"', "science-fiction", 2),
    ('subject:dystopias', "science-fiction", 1),
    ('subject:"mystery and detective stories"', "mystery", 2),
    ('subject:"detective and mystery stories"', "mystery", 1),
    ('subject:thrillers', "thriller", 2),
    ('subject:suspense', "thriller", 1),
    ('subject:romance', "romance", 2),
    ('subject:"love stories"', "romance", 1),
    ('subject:"historical fiction"', "historical", 2),
    ('subject:horror', "horror", 2),
    ('subject:"young adult fiction"', "young-adult", 2),
    ('subject:"juvenile fiction"', "children", 2),
    ('subject:"picture books"', "children", 1),
    ('subject:"classic literature"', "classics", 2),
    ('subject:classics', "classics", 1),
    ('subject:"literary fiction"', "literary", 1),
    ('subject:"psychological fiction"', "literary", 1),
    ('subject:poetry', "poetry", 2),
    ('subject:drama', "drama", 1),
    ('subject:plays', "drama", 1),
    ('subject:tragedies', "drama", 1),
    ('subject:"short stories"', "short-stories", 2),
    ('subject:"graphic novels"', "graphic", 2),
    ('subject:comics', "graphic", 1),
    ('subject:manga', "graphic", 1),
    ('subject:biography', "biography", 2),
    ('subject:autobiography', "memoir", 1),
    ('subject:memoir', "memoir", 1),
    ('subject:history', "history", 2),
    ('subject:science', "science", 2),
    ('subject:"popular works"', None, 1),
    ('subject:philosophy', "philosophy", 2),
    ('subject:psychology', "psychology", 2),
    ('subject:"self-help"', "self-help", 2),
    ('subject:"success"', "self-help", 1),
    ('subject:business', "business", 2),
    ('subject:economics', "business", 1),
    ('subject:politics', "politics", 2),
    ('subject:religion', "religion", 2),
    ('subject:spirituality', "religion", 1),
    ('subject:nature', "nature", 1),
    ('subject:"natural history"', "nature", 1),
    ('subject:travel', "travel", 1),
    ('subject:"voyages and travels"', "travel", 1),
    ('subject:essays', "essays", 1),
    ('subject:humor', "humor", 2),
    ('subject:cooking', "food", 1),
    ('subject:food', "food", 1),
    ('subject:art', "art", 1),
    ('subject:music', "art", 1),
    ('subject:photography', "art", 1),
    ('subject:fiction', None, 2),
    ('subject:"new york times bestseller"', None, 2),
]

# Spot-check list: (title, author surname). Missing ones get a targeted search.
MUST_HAVE = [
    ("The Hobbit", "Tolkien"), ("The Fellowship of the Ring", "Tolkien"),
    ("1984", "Orwell"), ("Animal Farm", "Orwell"),
    ("Pride and Prejudice", "Austen"), ("Emma", "Austen"),
    ("Moby-Dick", "Melville"), ("War and Peace", "Tolstoy"),
    ("Anna Karenina", "Tolstoy"), ("Crime and Punishment", "Dostoevsky"),
    ("The Brothers Karamazov", "Dostoevsky"),
    ("Dune", "Herbert"), ("Harry Potter and the Philosopher's Stone", "Rowling"),
    ("To Kill a Mockingbird", "Lee"), ("The Great Gatsby", "Fitzgerald"),
    ("Jane Eyre", "Bronte"), ("Wuthering Heights", "Bronte"),
    ("The Catcher in the Rye", "Salinger"), ("Brave New World", "Huxley"),
    ("Fahrenheit 451", "Bradbury"), ("Frankenstein", "Shelley"),
    ("Dracula", "Stoker"), ("The Odyssey", "Homer"), ("The Iliad", "Homer"),
    ("Don Quixote", "Cervantes"), ("Les Miserables", "Hugo"),
    ("The Count of Monte Cristo", "Dumas"), ("Great Expectations", "Dickens"),
    ("A Tale of Two Cities", "Dickens"), ("Little Women", "Alcott"),
    ("The Lord of the Flies", "Golding"), ("Of Mice and Men", "Steinbeck"),
    ("The Grapes of Wrath", "Steinbeck"), ("Beloved", "Morrison"),
    ("One Hundred Years of Solitude", "Marquez"),
    ("The Handmaid's Tale", "Atwood"), ("The Hunger Games", "Collins"),
    ("The Da Vinci Code", "Brown"), ("Gone Girl", "Flynn"),
    ("The Girl with the Dragon Tattoo", "Larsson"), ("The Shining", "King"),
    ("It", "King"), ("Ender's Game", "Card"), ("Foundation", "Asimov"),
    ("The Hitchhiker's Guide to the Galaxy", "Adams"), ("The Martian", "Weir"),
    ("Project Hail Mary", "Weir"), ("Where the Crawdads Sing", "Owens"),
    ("The Midnight Library", "Haig"), ("It Ends with Us", "Hoover"),
    ("Fourth Wing", "Yarros"), ("The Name of the Wind", "Rothfuss"),
    ("A Game of Thrones", "Martin"), ("The Way of Kings", "Sanderson"),
    ("Rebecca", "Maurier"), ("And Then There Were None", "Christie"),
    ("The Hound of the Baskervilles", "Doyle"), ("The Book Thief", "Zusak"),
    ("The Kite Runner", "Hosseini"), ("Life of Pi", "Martel"),
    ("Charlotte's Web", "White"), ("Matilda", "Dahl"),
    ("Where the Wild Things Are", "Sendak"), ("The Cat in the Hat", "Seuss"),
    ("The Lion, the Witch and the Wardrobe", "Lewis"),
    ("Alice's Adventures in Wonderland", "Carroll"),
    ("Watchmen", "Moore"), ("Maus", "Spiegelman"), ("Persepolis", "Satrapi"),
    ("Leaves of Grass", "Whitman"), ("The Waste Land", "Eliot"),
    ("Milk and Honey", "Kaur"), ("Hamlet", "Shakespeare"),
    ("Macbeth", "Shakespeare"), ("Romeo and Juliet", "Shakespeare"),
    ("Death of a Salesman", "Miller"), ("A Streetcar Named Desire", "Williams"),
    ("Dubliners", "Joyce"), ("Sapiens", "Harari"), ("Educated", "Westover"),
    ("Becoming", "Obama"), ("Atomic Habits", "Clear"),
    ("Thinking, Fast and Slow", "Kahneman"), ("A Brief History of Time", "Hawking"),
    ("The Diary of a Young Girl", "Frank"), ("Steve Jobs", "Isaacson"),
    ("The Immortal Life of Henrietta Lacks", "Skloot"),
    ("Guns, Germs, and Steel", "Diamond"), ("Silent Spring", "Carson"),
    ("On the Origin of Species", "Darwin"), ("Meditations", "Aurelius"),
    ("The Art of War", "Sun"), ("The Republic", "Plato"),
    ("The Prince", "Machiavelli"), ("Man's Search for Meaning", "Frankl"),
    ("How to Win Friends and Influence People", "Carnegie"),
    ("The 7 Habits of Highly Effective People", "Covey"),
    ("Rich Dad, Poor Dad", "Kiyosaki"), ("The Lean Startup", "Ries"),
    ("Good to Great", "Collins"), ("Born a Crime", "Noah"),
    ("Bossypants", "Fey"), ("Kitchen Confidential", "Bourdain"),
    ("Salt, Fat, Acid, Heat", "Nosrat"), ("Into the Wild", "Krakauer"),
    ("Into Thin Air", "Krakauer"), ("A Walk in the Woods", "Bryson"),
    ("In Cold Blood", "Capote"), ("The Story of Art", "Gombrich"),
    ("Walden", "Thoreau"), ("The Fire Next Time", "Baldwin"),
    ("Mere Christianity", "Lewis"), ("The Power of Now", "Tolle"),
    ("Quiet", "Cain"), ("Freakonomics", "Levitt"),
    ("The Road", "McCarthy"), ("Beowulf", None),
    ("Things Fall Apart", "Achebe"), ("The Alchemist", "Coelho"),
    ("The Little Prince", "Saint-Exupery"), ("Normal People", "Rooney"),
    ("The Seven Husbands of Evelyn Hugo", "Reid"), ("Circe", "Miller"),
    ("Slaughterhouse-Five", "Vonnegut"), ("Catch-22", "Heller"),
    ("Lolita", "Nabokov"), ("Ulysses", "Joyce"), ("Middlemarch", "Eliot"),
    ("Mrs Dalloway", "Woolf"), ("The Bell Jar", "Plath"),
    ("Invisible Man", "Ellison"), ("Their Eyes Were Watching God", "Hurston"),
    ("The Color Purple", "Walker"), ("The Old Man and the Sea", "Hemingway"),
    ("Gone with the Wind", "Mitchell"), ("The Stand", "King"),
    ("The Silmarillion", "Tolkien"), ("The Princess Bride", "Goldman"),
    ("Neuromancer", "Gibson"), ("Do Androids Dream of Electric Sheep?", "Dick"),
    ("The Left Hand of Darkness", "Le Guin"), ("A Wizard of Earthsea", "Le Guin"),
    ("Good Omens", "Pratchett"), ("American Gods", "Gaiman"),
    ("The Three-Body Problem", "Liu"), ("Norwegian Wood", "Murakami"),
    ("The Remains of the Day", "Ishiguro"), ("Never Let Me Go", "Ishiguro"),
    ("Pachinko", "Lee"), ("The Goldfinch", "Tartt"), ("The Secret History", "Tartt"),
    ("A Little Life", "Yanagihara"), ("Station Eleven", "Mandel"),
    ("Big Little Lies", "Moriarty"), ("The Silent Patient", "Michaelides"),
    ("Rebecca", "du Maurier"), ("The Giver", "Lowry"),
    ("Wonder", "Palacio"), ("Holes", "Sachar"),
    ("The Very Hungry Caterpillar", "Carle"), ("Goodnight Moon", "Brown"),
    ("Percy Jackson and the Lightning Thief", "Riordan"),
    ("Twilight", "Meyer"), ("The Fault in Our Stars", "Green"),
    ("Six of Crows", "Bardugo"), ("A Court of Thorns and Roses", "Maas"),
    ("The Song of Achilles", "Miller"), ("Educated", "Westover"),
    ("When Breath Becomes Air", "Kalanithi"), ("The Glass Castle", "Walls"),
    ("I Know Why the Caged Bird Sings", "Angelou"), ("Long Walk to Freedom", "Mandela"),
    ("The Autobiography of Malcolm X", "Malcolm"), ("Night", "Wiesel"),
    ("The Wright Brothers", "McCullough"), ("Team of Rivals", "Goodwin"),
    ("The Body Keeps the Score", "Kolk"), ("Outliers", "Gladwell"),
    ("The Selfish Gene", "Dawkins"), ("Cosmos", "Sagan"),
    ("The Gene", "Mukherjee"), ("The Wealth of Nations", "Smith"),
    ("Capital in the Twenty-First Century", "Piketty"),
    ("The Communist Manifesto", "Marx"), ("Beyond Good and Evil", "Nietzsche"),
    ("Thus Spoke Zarathustra", "Nietzsche"), ("The Stranger", "Camus"),
    ("The Metamorphosis", "Kafka"), ("The Trial", "Kafka"),
    ("Siddhartha", "Hesse"), ("Heart of Darkness", "Conrad"),
    ("The Picture of Dorian Gray", "Wilde"), ("The Canterbury Tales", "Chaucer"),
    ("Paradise Lost", "Milton"), ("The Divine Comedy", "Dante"),
    ("The Secret Garden", "Burnett"), ("Anne of Green Gables", "Montgomery"),
    ("Treasure Island", "Stevenson"), ("The Call of the Wild", "London"),
    ("Mastering the Art of French Cooking", "Child"), ("The Joy of Cooking", "Rombauer"),
    ("Eat, Pray, Love", "Gilbert"), ("Wild", "Strayed"),
    ("The Year of Magical Thinking", "Didion"), ("Slouching Towards Bethlehem", "Didion"),
    ("Me Talk Pretty One Day", "Sedaris"), ("Calvin and Hobbes", "Watterson"),
    ("Sandman", "Gaiman"), ("Fun Home", "Bechdel"),
]

# --------------------------------------------------------------------------
# Text helpers
# --------------------------------------------------------------------------


def fold(s):
    """ASCII-fold and lowercase."""
    s = unicodedata.normalize("NFKD", s or "")
    s = "".join(ch for ch in s if not unicodedata.combining(ch))
    return s.lower()


def is_latin_text(s):
    for ch in s:
        if ch.isalpha():
            try:
                if "LATIN" not in unicodedata.name(ch):
                    return False
            except ValueError:
                return False
    return True


SMALL_WORDS = {"a", "an", "the", "and", "but", "or", "nor", "for", "of", "on",
               "in", "at", "to", "by", "up", "as", "via", "vs", "from", "into",
               "with", "over", "per", "than", "off"}


def smart_title(title):
    """Capitalise major words of an otherwise lower-cased title."""
    words = title.split(" ")
    out = []
    after_colon = True
    for i, w in enumerate(words):
        core = w.lstrip("\"'“‘(")
        lead = w[:len(w) - len(core)]
        if (core and core[0].isalpha() and core[0].islower() and core.isascii()
                and "." not in core
                and (after_colon or i == len(words) - 1
                     or core.lower().strip(",;:!?") not in SMALL_WORDS)):
            core = core[0].upper() + core[1:]
        out.append(lead + core)
        after_colon = w.endswith(":") or w.endswith("—")
    return " ".join(out)


SERIES_PAREN = re.compile(r"\s*\((?:[^()]*)\)\s*$")
BRACKETS = re.compile(r"\s*\[[^\]]*\]")
A_NOVEL = re.compile(r"\s*[:;,\-–—]\s*(?:a|the)\s+(?:novel|roman|memoir|thriller)"
                     r"(?:\s+in\s+\w+)?\s*\.?$", re.I)
ALT_TITLE = re.compile(r"\s*(?:;\s*or,?|,\s*or,|,\s*or(?=\s+(?:The|There|A|An)\b))"
                       r"\s+[A-Z].*$")
EDITION_SUFFIX = re.compile(
    r"\s*[:\-–—,]\s*(?:the\s+)?(?:deluxe|collector'?s|special|anniversary|"
    r"illustrated|annotated|unabridged|abridged|movie tie-in|tie-in|"
    r"\d+(?:st|nd|rd|th)\s+anniversary)\b.*$", re.I)


def clean_title(t):
    t = re.sub(r"\s+", " ", (t or "").strip())
    t = BRACKETS.sub("", t)
    for _ in range(2):
        nt = SERIES_PAREN.sub("", t)
        if nt.strip():
            t = nt
    t = A_NOVEL.sub("", t)
    t = ALT_TITLE.sub("", t)
    t = EDITION_SUFFIX.sub("", t)
    t = t.strip(" .;,:/-–—")
    t = t.replace("’", "'").replace("‘", "'")
    if t and is_latin_text(t):
        letters = [c for c in t if c.isalpha()]
        lower_words = [w for w in t.split() if w[:1].islower()
                       and w.lower() not in SMALL_WORDS]
        if letters and (t == t.lower() or lower_words):
            t = smart_title(t)
        if t.isupper() and len(t) > 4:
            t = smart_title(t.lower())
    return t


ARTICLES = re.compile(r"^(the|a|an)\s+")
TITLE_ALIASES = {
    "nineteen eightyfour": "1984",
    "harry potter and the sorcerers stone": "harry potter and the philosophers stone",
    "ten little indians": "and then there were none",
    "the lightning thief": "percy jackson and the lightning thief",
    "lightning thief": "percy jackson and the lightning thief",
    "mobydick or the whale": "mobydick",
    "moby dick": "mobydick",
    "moby dick or the whale": "mobydick",
    "les miserables": "les miserables",
    "frankenstein or the modern prometheus": "frankenstein",
    "alice in wonderland": "alices adventures in wonderland",
    "the adventures of huckleberry finn": "adventures of huckleberry finn",
    "the strange case of dr jekyll and mr hyde": "strange case of dr jekyll and mr hyde",
    "dr jekyll and mr hyde": "strange case of dr jekyll and mr hyde",
    "the wonderful wizard of oz": "wizard of oz",
}


def norm_title(t):
    s = fold(t)
    s = s.replace("&", " and ")
    s = re.sub(r"[^a-z0-9 ]+", "", s)
    s = re.sub(r"\s+", " ", s).strip()
    s = TITLE_ALIASES.get(s, s)
    s = ARTICLES.sub("", s)
    s = TITLE_ALIASES.get(s, s)
    return s


def author_last(a):
    toks = re.sub(r"[^a-z\- ]+", " ", fold(a)).split()
    toks = [t for t in toks if t not in {"jr", "sr", "ii", "iii", "phd", "md"}]
    return toks[-1] if toks else ""


def tokens(s):
    return set(re.sub(r"[^a-z0-9 ]+", " ", fold(s)).split()) - {"the", "a", "an", "of", "and"}


# --------------------------------------------------------------------------
# Overrides for famous translated works / non-English author records
# --------------------------------------------------------------------------

# Open Library author key -> English display name.
AUTHOR_OVERRIDES = {
    "OL26783A": "Leo Tolstoy",
    "OL22242A": "Fyodor Dostoevsky",
    "OL382524A": "Haruki Murakami",
    "OL7044246A": "Liu Cixin",
    "OL18293A": "Laozi",
    "OL18404A": "Homer",
    "OL714657A": "Osamu Dazai",
    "OL7524457A": "Toshikazu Kawaguchi",
    "OL30553A": "Sun Tzu",
    "OL7536525A": "Ichiro Kishimi",
}

# Name patterns (matched on the ASCII-folded first author) -> English name.
AUTHOR_NAME_FIXES = [
    (r"tolsto[iy]", r"\b(lev|leo|leon|l\.?)\b", "Leo Tolstoy"),
    (r"dosto[iy]?e[vw]sk", None, "Fyodor Dostoevsky"),
    (r"chekhov|chejov|tchekhov|tschechow", None, "Anton Chekhov"),
    (r"turgenev", None, "Ivan Turgenev"),
    (r"bulgakov", None, "Mikhail Bulgakov"),
    (r"pushkin", None, "Alexander Pushkin"),
    (r"gogol", None, "Nikolai Gogol"),
    (r"solzhenitsyn", None, "Aleksandr Solzhenitsyn"),
    (r"^platon?$|^plato\b", None, "Plato"),
    (r"^aristot", None, "Aristotle"),
    (r"^homer(o|e|us)?$", None, "Homer"),
    (r"marcus aurelius|marco aurelio|^aurelius", None, "Marcus Aurelius"),
    (r"^seneca|lucius annaeus seneca", None, "Seneca"),
    (r"^epictet", None, "Epictetus"),
    (r"machiavel|maquiavel", None, "Niccolò Machiavelli"),
    (r"^dante alighieri|^dante$", None, "Dante Alighieri"),
    (r"cervantes", None, "Miguel de Cervantes"),
    (r"^julio verne|^jules verne", None, "Jules Verne"),
    (r"confuci", None, "Confucius"),
    (r"^sun tzu|^sunzi|^sun zi", None, "Sun Tzu"),
    (r"^lao ?tzu|^laozi|^lao-tzu|^lao tse", None, "Laozi"),
    (r"^rumi$|jalal al-din rumi|jalaluddin rumi|jalal ad-din", None, "Rumi"),
    (r"kahlil gibran|khalil gibran|jubran", None, "Kahlil Gibran"),
    (r"^sophocles|^sofocles", None, "Sophocles"),
    (r"^euripides", None, "Euripides"),
    (r"^ovid", None, "Ovid"),
    (r"^virgil|^vergil|^publius vergilius", None, "Virgil"),
]

# Open Library work id -> English title (only where the work record title is
# in the original language or otherwise unusable).
TITLE_OVERRIDES = {
    "OL267096W": "Anna Karenina",
    "OL796465W": "The Alchemist",
}

# Open Library work id -> first publication year, where OL's is clearly off.
YEAR_OVERRIDES = {}

# Ancient / medieval texts: OL's "first publish year" is just an old printing.
UNDATED_TITLES = {
    "art of war", "meditations", "odyssey", "iliad", "aeneid", "republic",
    "tao te ching", "bhagavad gita", "beowulf", "epic of gilgamesh",
    "gilgamesh", "kama sutra", "kama sutra of vatsyayana", "analects",
    "bible", "holy bible", "quran", "koran", "symposium", "apology",
    "nicomachean ethics", "poetics", "politics", "oedipus rex",
    "oedipus the king", "antigone", "medea", "the histories", "histories",
    "metamorphoses", "letters from a stoic", "on the shortness of life",
    "enchiridion", "discourses", "book of five rings", "dhammapada",
    "upanishads", "canterbury tales", "divine comedy", "inferno",
    "one thousand and one nights", "arabian nights", "tale of genji",
    "the prophet", "rubaiyat of omar khayyam", "mahabharata", "ramayana",
    "sir gawain and the green knight", "confessions", "city of god",
    "the consolation of philosophy", "consolation of philosophy",
    "phaedo", "the trial and death of socrates", "oresteia",
}

# Heavily illustrated middle-grade series (ASCII-folded author names).
ILLUSTRATED_CHILDREN_AUTHORS = {
    "jeff kinney", "rachel renee russell", "lincoln peirce", "liz pichon",
    "dav pilkey", "tom watson", "jim benton", "james patterson & chris grabenstein",
}

# Approximate known word counts for famous books (title, author surname, words).
# Only books whose length is widely documented; translations use the standard
# English translation's length.
KNOWN_WORDS = [
    ("The Hobbit", "Tolkien", 95000),
    ("The Fellowship of the Ring", "Tolkien", 187800),
    ("The Two Towers", "Tolkien", 156200),
    ("The Return of the King", "Tolkien", 137100),
    ("The Lord of the Rings", "Tolkien", 481100),
    ("The Silmarillion", "Tolkien", 130100),
    ("Harry Potter and the Philosopher's Stone", "Rowling", 76900),
    ("Harry Potter and the Chamber of Secrets", "Rowling", 85100),
    ("Harry Potter and the Prisoner of Azkaban", "Rowling", 107300),
    ("Harry Potter and the Goblet of Fire", "Rowling", 190600),
    ("Harry Potter and the Order of the Phoenix", "Rowling", 257000),
    ("Harry Potter and the Half-Blood Prince", "Rowling", 168900),
    ("Harry Potter and the Deathly Hallows", "Rowling", 198200),
    ("A Game of Thrones", "Martin", 292700),
    ("A Clash of Kings", "Martin", 318900),
    ("A Storm of Swords", "Martin", 414600),
    ("A Feast for Crows", "Martin", 295000),
    ("A Dance with Dragons", "Martin", 414800),
    ("The Hunger Games", "Collins", 99800),
    ("Catching Fire", "Collins", 101600),
    ("Mockingjay", "Collins", 100300),
    ("Twilight", "Meyer", 119000),
    ("New Moon", "Meyer", 132800),
    ("Eclipse", "Meyer", 147900),
    ("Breaking Dawn", "Meyer", 192200),
    ("Divergent", "Roth", 105100),
    ("The Fault in Our Stars", "Green", 67200),
    ("The Book Thief", "Zusak", 118900),
    ("The Giver", "Lowry", 43600),
    ("A Wrinkle in Time", "L'Engle", 50000),
    ("Percy Jackson and the Lightning Thief", "Riordan", 87200),
    ("The Golden Compass", "Pullman", 112800),
    ("Northern Lights", "Pullman", 112800),
    ("The Outsiders", "Hinton", 48500),
    ("Holes", "Sachar", 47100),
    ("Hatchet", "Paulsen", 42300),
    ("Bridge to Terabithia", "Paterson", 32900),
    ("Number the Stars", "Lowry", 27200),
    ("Charlotte's Web", "White", 31900),
    ("Charlie and the Chocolate Factory", "Dahl", 30600),
    ("Matilda", "Dahl", 40100),
    ("Coraline", "Gaiman", 30600),
    ("The Lion, the Witch and the Wardrobe", "Lewis", 38400),
    ("Alice's Adventures in Wonderland", "Carroll", 26400),
    ("Through the Looking-Glass", "Carroll", 29000),
    ("The Wonderful Wizard of Oz", "Baum", 39300),
    ("Peter Pan", "Barrie", 47200),
    ("The Secret Garden", "Burnett", 80400),
    ("Anne of Green Gables", "Montgomery", 97400),
    ("The Wind in the Willows", "Grahame", 58400),
    ("Treasure Island", "Stevenson", 67000),
    ("Strange Case of Dr Jekyll and Mr Hyde", "Stevenson", 25500),
    ("The Little Prince", "Saint-Exupery", 17000),
    ("The Cat in the Hat", "Seuss", 1600),
    ("Where the Wild Things Are", "Sendak", 340),
    ("Goodnight Moon", "Brown", 130),
    ("The Very Hungry Caterpillar", "Carle", 220),
    ("1984", "Orwell", 88900),
    ("Animal Farm", "Orwell", 30000),
    ("Brave New World", "Huxley", 63800),
    ("Fahrenheit 451", "Bradbury", 46100),
    ("The Great Gatsby", "Fitzgerald", 47100),
    ("To Kill a Mockingbird", "Lee", 99100),
    ("The Catcher in the Rye", "Salinger", 73400),
    ("Lord of the Flies", "Golding", 59900),
    ("Of Mice and Men", "Steinbeck", 29600),
    ("The Grapes of Wrath", "Steinbeck", 169500),
    ("The Old Man and the Sea", "Hemingway", 26600),
    ("The Sun Also Rises", "Hemingway", 67700),
    ("Slaughterhouse-Five", "Vonnegut", 49500),
    ("Catch-22", "Heller", 174300),
    ("One Hundred Years of Solitude", "Marquez", 144500),
    ("The Bell Jar", "Plath", 66800),
    ("Lolita", "Nabokov", 112500),
    ("Mrs Dalloway", "Woolf", 63400),
    ("Ulysses", "Joyce", 265200),
    ("Infinite Jest", "Wallace", 543700),
    ("Gone with the Wind", "Mitchell", 418000),
    ("Atlas Shrugged", "Rand", 562000),
    ("The Fountainhead", "Rand", 311600),
    ("The Road", "McCarthy", 58700),
    ("Pride and Prejudice", "Austen", 122200),
    ("Sense and Sensibility", "Austen", 119400),
    ("Emma", "Austen", 155900),
    ("Persuasion", "Austen", 83700),
    ("Northanger Abbey", "Austen", 77400),
    ("Mansfield Park", "Austen", 159300),
    ("Jane Eyre", "Bronte", 183900),
    ("Wuthering Heights", "Bronte", 107900),
    ("Frankenstein", "Shelley", 74800),
    ("Dracula", "Stoker", 160400),
    ("Moby-Dick", "Melville", 206100),
    ("The Scarlet Letter", "Hawthorne", 63600),
    ("Adventures of Huckleberry Finn", "Twain", 109600),
    ("The Adventures of Tom Sawyer", "Twain", 70000),
    ("Little Women", "Alcott", 185000),
    ("The Picture of Dorian Gray", "Wilde", 78500),
    ("Heart of Darkness", "Conrad", 38000),
    ("The Call of the Wild", "London", 32000),
    ("White Fang", "London", 72100),
    ("The War of the Worlds", "Wells", 60200),
    ("The Time Machine", "Wells", 32100),
    ("Gulliver's Travels", "Swift", 104000),
    ("The Hound of the Baskervilles", "Doyle", 59400),
    ("A Study in Scarlet", "Doyle", 43000),
    ("The Adventures of Sherlock Holmes", "Doyle", 104300),
    ("Great Expectations", "Dickens", 183300),
    ("A Tale of Two Cities", "Dickens", 135400),
    ("Oliver Twist", "Dickens", 156000),
    ("David Copperfield", "Dickens", 358000),
    ("Bleak House", "Dickens", 360900),
    ("A Christmas Carol", "Dickens", 28900),
    ("Middlemarch", "Eliot", 316100),
    ("War and Peace", "Tolstoy", 587300),
    ("Anna Karenina", "Tolstoy", 349700),
    ("Crime and Punishment", "Dostoevsky", 211600),
    ("The Brothers Karamazov", "Dostoevsky", 364200),
    ("Les Miserables", "Hugo", 530000),
    ("The Count of Monte Cristo", "Dumas", 464200),
    ("The Metamorphosis", "Kafka", 22000),
    ("The Stranger", "Camus", 36800),
    ("Dune", "Herbert", 188000),
    ("Ender's Game", "Card", 100600),
    ("The Hitchhiker's Guide to the Galaxy", "Adams", 46300),
    ("The Martian", "Weir", 104600),
    ("The Name of the Wind", "Rothfuss", 250000),
    ("The Wise Man's Fear", "Rothfuss", 400000),
    ("The Way of Kings", "Sanderson", 383400),
    ("Words of Radiance", "Sanderson", 399400),
    ("Oathbringer", "Sanderson", 451900),
    ("Rhythm of War", "Sanderson", 455900),
    ("The Final Empire", "Sanderson", 214000),
    ("Mistborn", "Sanderson", 214000),
    ("The Eye of the World", "Jordan", 305900),
    ("The Stand", "King", 471500),
    ("It", "King", 445100),
    ("Watership Down", "Adams", 156200),
    ("The Da Vinci Code", "Brown", 139000),
    ("Gone Girl", "Flynn", 145700),
    ("The Alchemist", "Coelho", 39000),
    ("The Holy Bible", "", 783100),
    ("The Bible", "", 783100),
]

# --------------------------------------------------------------------------
# Filters
# --------------------------------------------------------------------------

JUNK_TITLE = re.compile(
    r"(study guide|sparknotes|spark notes|cliffs? ?notes|cliff'?s notes|"
    r"monarch notes|\bsummary\b|\bsummaries\b|\bworkbook\b|\bwork book\b|"
    r"colou?ring|activity book|sticker|box(?:ed)? ?set|\bset of\b|"
    r"complete works|collected works|selected works|\bworks of\b|"
    r"complete novels|complete plays|complete poems|complete tales|"
    r"complete collection|complete series|complete set|"
    r"^the complete\b|^complete\b|\bomnibus\b|anthology|"
    r"\b(?:trilogy|quartet|quintet|series|saga|collection|boxset|"
    r"duology|bundle|books)$|"
    r"\bbooks?\s*\d+\s*(?:-|–|to|&|and|through)\s*\d+|"
    r"\bvol(?:ume)?s?\.?\s*\d+\s*(?:-|–|to|&|and|through)\s*\d+|"
    r"\b\d+\s*books?\s+(?:in|collection|set)|book collection|collection set|"
    r"reader'?s'? guide|teacher'?s guide|teaching guide|lesson plans?|"
    r"\btest prep\b|\bexam\b|\bexams\b|\bquiz\b|trivia|critical commentary|"
    r"literature guide|novel units?|bookrags|unofficial guide|key takeaways|"
    r"\bcalendar\b|gratitude journal|guided journal|\bplanner\b|"
    r"\btextbook\b|\bhandbook\b|\bmanual\b|\bdictionary\b|\bencyclopedia\b|"
    r"\bthesaurus\b|\batlas of\b|\bcookbook collection\b|"
    r"^(?:principles|fundamentals|elements|essentials|introduction|concepts|"
    r"foundations) (?:of|to)\b|"
    r"\b\d+(?:st|nd|rd|th) ed(?:ition|\.)?|\bedition\b|"
    r"\bclass \d+|\bgrade \d+|\bncert\b|\bgmat\b|\bielts\b|"
    r"\bpart (?:one|two|three|1|2|3)$|"
    r",\s*(?:i|ii|iii|iv|v)$|\btom[eo]\b|\bband \d|"
    r"\bjournal:|\bnotebook\b|\blog book\b|\bkjv\b|\bniv\b|\besv\b)",
    re.I)

JUNK_AUTHOR = re.compile(
    r"(sparknotes|cliffs|shmoop|bookrags|supersummary|instaread|worth books|"
    r"quickread|bright summaries|litcharts|cengage|study guide|summary|"
    r"readtrepreneur|ant hive|novel units|lightning guides|kidsbooks|"
    r"scholastic|disney|dk publishing|^dk$|parragon|editors of|^various|"
    r"lonely planet|rick steves|fodor|frommer|rough guides|publications|"
    r"press$|publishing|\bstaff\b|\binc\.?$|\bltd\.?$|llc|corporation|"
    r"\bassociation|\binstitute|\bcouncil\b|\bcommittee|\bdepartment|"
    r"\buniversity|\bschool\b|\bsociety\b|\bfoundation\b|\bbureau\b|"
    r"\bministry\b|\bnaxos\b|\baudiobooks?\b|"
    r"discover press|marvel comics|dc comics|bible$|^n/a$|^unknown$)",
    re.I)

TEXTBOOK_SUBJECT = re.compile(
    r"^(textbooks?|examinations?|examinations, questions, etc\.?|"
    r"problems, exercises, etc\.?|study guides|outlines, syllabi, etc\.?|"
    r"study and teaching|programmed instruction|tests)$|"
    r"textbooks|\bexaminations\b|problems, exercises|study guides|"
    r"computer programs|programming|data processing|software|"
    r"accounting|nursing|\bdentistry\b|\bclinical\b|\bpathology\b|"
    r"law and legislation|engineering|\bcalculus\b|\balgebra\b|\bstatistics\b",
    re.I)

# Erotica. Leaf is rated for everyone, so the catalog leaves it out. One stray "eroticism" on a long subject list
# (literary classics, art history) is not enough; two such subjects, or one on a short list, is.
ADULT_SUBJECT = re.compile(r"\berotic|\bpornograph|\bbdsm\b|\bsadomasochism\b", re.I)


def is_adult(folded_subjects):
    n = sum(1 for s in folded_subjects if ADULT_SUBJECT.search(s))
    return n >= 1 and (n >= 2 or len(folded_subjects) <= 8)


FOREIGN_WORDS = {
    "de", "la", "le", "les", "el", "los", "las", "del", "des", "du", "der",
    "das", "und", "het", "een", "il", "gli", "y", "et", "och", "dos", "uma",
    "um", "os", "ein", "eine", "nel", "della", "di", "dei", "au", "aux",
    "sur", "pour", "avec", "mit", "von", "zum", "zur", "para", "por", "con",
    "una", "mi", "tu", "su", "lo", "sus", "mis", "kein", "nicht", "ist",
    "est", "dan", "yang", "ng", "na", "si", "ki", "ke", "ka", "ya", "wa",
    "ou", "et", "je", "ne", "pas", "qui", "que", "como", "muy", "mas",
    "oscura", "amor", "vida", "muerte", "noche", "mujer", "hombre",
}
FOREIGN_CHARS = set("áéíóúñçãõàèìòùâêîôûäöüßøåæœ¿¡")


def looks_foreign(title):
    if not is_latin_text(title):
        return True
    f = fold(title)
    words = re.sub(r"[^a-z' ]+", " ", f).split()
    if any(w in FOREIGN_WORDS for w in words):
        return True
    if any(c in FOREIGN_CHARS for c in title.lower()):
        return True
    return False


# --------------------------------------------------------------------------
# Genre mapping
# --------------------------------------------------------------------------

# (tag, regex) applied to each lower-cased, ASCII-folded subject string.
# Patterns are deliberately specific: Open Library merges subjects from every
# edition (adaptations, study editions, translations), so generic words such
# as "love", "murder" or "drama" show up on many unrelated novels.
GENRE_RULES = [
    ("fantasy", r"\bfantasy\b|\bmagic\b|wizards|witches|dragons|\belves\b|"
                r"sword and sorcery|imaginary places|imaginary wars|"
                r"\bfaeries\b|\bfae\b|epic fantasy|urban fantasy|high fantasy|"
                r"magicians|sorcer|fairies|fantasy fiction"),
    ("science-fiction", r"science fiction|\bsci-?fi\b|dystopi|space opera|"
                        r"time travel|\brobots\b|extraterrestrial|cyberpunk|"
                        r"life on other planets|interplanetary|space warfare|"
                        r"post-?apocalyptic|\bapocalyptic\b|space ships|"
                        r"spaceships|outer space|galactic|\bandroids\b|"
                        r"artificial intelligence|\bcloning\b|"
                        r"genetic engineering|\bmars \(planet\)"),
    ("mystery", r"mystery|mysteries|detective|whodunit|"
                r"private investigators|police procedural|\bsleuth|"
                r"crime fiction|fiction, crime|cozy|holmes, sherlock|"
                r"poirot|marple|\bpolice\b.*fiction"),
    ("thriller", r"thriller|suspense|espionage|\bspy\b|\bspies\b|"
                 r"serial murder|conspiracies|legal stories|assassins|"
                 r"kidnapping|intelligence service|secret service|"
                 r"psychopaths|domestic noir|fiction, psychological thriller"),
    ("romance", r"(?<!r )romance(?! (?:norte|ingles|frances|brasileiro|"
                r"portugues|americano|russo|alemao|literature|languages|"
                r"philology))|love stories|romantic(?! poetry| period| era|ism)|"
                r"\berotic|chick lit|regency|romantic comedy|billionaire|"
                r"enemies to lovers|second chance|fiction, romance|"
                r"romance fiction|\bdating \(social"),
    ("historical", r"historical fiction|fiction, historical|"
                   r"historical novel|historical romance|"
                   r"world war, 1939-1945.*fiction|world war, 1914-1918.*fiction|"
                   r"civil war, 1861-1865.*fiction|holocaust.*fiction|"
                   r"\bvikings\b|tudors|fiction, war|war stories"),
    ("horror", r"horror|ghost stories|\bvampires\b|zombies|haunted houses|"
               r"werewolves|occult fiction|paranormal fiction|"
               r"gothic fiction|\bgothic\b.*fiction|demonology|"
               r"fiction, ghost|exorcism|fiction, occult"),
    ("young-adult", r"young adult|\bteen|adolescen|high school|"
                    r"nyt:young-adult|nyt:series-books|coming of age"),
    ("children", r"juvenile fiction|juvenile literature|children'?s|"
                 r"picture books|board books|stories in rhyme|"
                 r"nursery rhymes|bedtime|beginner books|easy reading|"
                 r"readers \(primary\)|nyt:childrens|nyt:picture|"
                 r"toy and movable|middle grade|\bkindergarten|preschool"),
    ("classics", r"\bclassics?\b|classic literature|great books|"
                 r"literary classics|harvard classics"),
    ("literary", r"literary fiction|fiction, literary|psychological fiction|"
                 r"bildungsroman|domestic fiction|fiction, general|"
                 r"^literature$|american literature|english literature|"
                 r"modern literature|british literature|"
                 r"fiction, psychological|family saga|fiction, family life|"
                 r"booker prize|pulitzer prize|national book award|"
                 r"^literary$|fiction / literary|fiction, coming of age"),
    ("poetry", r"poetry|\bpoems\b|\bverse\b|sonnets|haiku|epic poetry|"
               r"\bpoets?\b|ballads|\bodes\b"),
    ("drama", r"^drama$|\bdrama\b|\bplays\b|tragedies|\btragedy\b|comedies|"
              r"theater|theatre|screenplays|dramatic works|"
              r"shakespeare, william, 1564-1616"),
    ("short-stories", r"short stories|short story|\bnovellas?\b"),
    ("graphic", r"graphic novels|comic books|\bcomics\b|\bmanga\b|"
                r"cartoons and comics|comic strips|nyt:graphic|"
                r"comics & graphic|bandes dessinees|superheroes|webtoon"),
    ("biography", r"biograph"),
    ("memoir", r"memoir|autobiograph|personal narratives|\bdiaries\b"),
    ("history", r"\bhistory\b|historical|world war|civilization|\bancient\b|"
                r"\bmilitary\b|\bcivil war\b|antiquities|archaeolog|"
                r"middle ages|revolution|holocaust"),
    ("science", r"\bscience\b|physics|biology|astronomy|cosmology|"
                r"\bevolution\b|genetics|chemistry|mathematic|neuroscience|"
                r"\bbrain\b|universe|quantum|medicine|medical|"
                r"anthropology|human ecology|scientists|natural selection|"
                r"\bdna\b|\bgenes\b|space sciences|astrophysics|"
                r"technology|inventions|epidemiology|\bvirus"),
    ("philosophy", r"philosoph|ethics|\bstoic|existentialism|metaphysics|"
                   r"\blogic\b|epistemology|meaning of life|"
                   r"conduct of life|\bvirtue\b|nihilism"),
    ("psychology", r"psycholog|mental health|\bbehavior\b|behaviour|"
                   r"cognitive|emotions|personality|human behavior|"
                   r"happiness|\bmind\b|thought and thinking|"
                   r"decision making|interpersonal relations|\bhabits?\b|"
                   r"anxiety|depression|trauma|psychiatr"),
    ("self-help", r"self-help|self help|self-actualization|"
                  r"self actualization|\bsuccess\b|personal growth|"
                  r"personal development|motivation|self-improvement|"
                  r"self-realization|time management|productivity|"
                  r"nyt:advice|mindfulness|self-esteem|self-confidence|"
                  r"conduct of life|life skills|attitude|positive thinking|"
                  r"\bhabits?\b"),
    ("business", r"business|management|economics|economic|finance|"
                 r"financial|investing|investments|\bmoney\b|"
                 r"entrepreneur|leadership|marketing|\bwealth\b|"
                 r"\bsales\b|selling|\bstocks?\b|capitalism|corporations|"
                 r"nyt:business|negotiation|startup|careers"),
    ("politics", r"politic|government|democracy|social justice|"
                 r"race relations|racism|feminism|civil rights|"
                 r"international relations|world politics|elections|"
                 r"presidents|communism|socialism|totalitarian|"
                 r"human rights|social movements|propaganda|"
                 r"public policy|geopolitics"),
    ("religion", r"religio|christian|\bbible\b|\bgod\b|spiritual|theolog|"
                 r"buddhis|\bislam\b|\bchurch\b|\bprayer\b|\bfaith\b|"
                 r"\bjesus\b|hinduism|judaism|\bzen\b|\bmeditation\b|"
                 r"\bquran\b|koran|sacred|devotional|catholic|taoism"),
    ("nature", r"\bnature\b|natural history|environment|ecology|"
               r"\banimals\b|\bbirds\b|\bplants\b|\btrees\b|wildlife|"
               r"climat|outdoor|wilderness|forests|oceans|"
               r"conservation|naturalists|mountaineering|gardening"),
    ("travel", r"\btravel|voyages and travels|description and travel|"
               r"adventure travel|guidebooks|travelers|journeys|"
               r"road trips|expeditions"),
    ("essays", r"\bessays?\b"),
    ("humor", r"\bhumou?r|humorous|\bcomedy\b|wit and humor|satire|"
              r"\bfunny\b|parodies"),
    ("food", r"cooking|cookbook|cookery|\bfood\b|recipes|gastronomy|"
             r"baking|\bwine\b|nutrition|\bdiet\b|\bchefs?\b|cuisine|"
             r"restaurants|vegetarian|vegan"),
    ("art", r"\bart\b|\barts\b|painting|painters|\bartists?\b|photograph|"
            r"\bdesign\b|architecture|\bmusic|drawing|sculpture|"
            r"\bfilm\b|motion pictures|creativity|creative ability|"
            r"art history|fashion"),
]
GENRE_RX = [(tag, re.compile(rx)) for tag, rx in GENRE_RULES]

FICTION_RX = re.compile(
    r"(?<!non)(?<!non-)\bfiction\b|\bnovels?\b|fantasy|science fiction|"
    r"mystery and detective|detective and mystery|thrillers|love stories|"
    r"ghost stories|horror tales|short stories|fairy tales|"
    r"nyt:.*-fiction|^romance|fiction, romance|stories$|\bromans?\b|"
    r"juvenile fiction|graphic novels|\bmanga\b|\bnovela\b")
NONFICTION_RX = re.compile(
    r"biograph|autobiograph|\bhistory\b(?!.*fiction)|nonfiction|non-fiction|"
    r"juvenile literature|essays|self-help|handbooks|personal narratives|"
    r"popular works|nyt:.*nonfiction|nyt:advice|economics|business|"
    r"psychology|philosophy|science|social aspects|religious aspects|"
    r"\bstudy\b|methodology|research|guidebooks|cooking|recipes|"
    r"politics and government|management|self-actualization|"
    r"success|anecdotes|correspondence|interviews|description and travel")

# Tags that only make sense for fiction / for non-fiction.
FICTION_ONLY = {"fantasy", "science-fiction", "mystery", "thriller", "romance",
                "historical", "horror", "literary", "short-stories", "fiction"}
NONFICTION_ONLY = {"biography", "memoir", "history", "science", "psychology",
                   "self-help", "business", "politics", "nature", "travel",
                   "essays", "food", "art"}
# Forms that OL often attaches via adaptations; they need a dominant signal.
FORM_TAGS = {"graphic", "poetry", "drama", "short-stories"}
YA_AUDIENCE = re.compile(r"young adult|nyt:young-adult|nyt:series-books|"
                         r"teen fiction|fiction, teen|teen & young adult")

# Tie-break priority (earlier wins): specific genres before broad ones.
PRIORITY = {t: i for i, t in enumerate([
    "graphic", "poetry", "drama", "short-stories", "fantasy",
    "science-fiction", "mystery", "thriller", "horror", "romance",
    "historical", "young-adult", "children", "memoir", "biography",
    "self-help", "business", "psychology", "science", "history",
    "philosophy", "politics", "religion", "nature", "travel", "food", "art",
    "humor", "essays", "classics", "literary", "fiction"])}

NOISE_SUBJECT = re.compile(
    r"^(accessible book|protected daisy|in library|lending library|"
    r"large type books|overdrive|open_syllabus_project|"
    r"long now manual for civilization|internet archive wishlist|"
    r"new york times bestseller|new york times reviewed|"
    r"open library staff picks|reading level-grade \d+|"
    r"fiction in english|translations into .*|translations from .*|"
    r"english language|language arts|\[fic\]|general|fiction|"
    r"readers|reading materials|large print books|award:.*|"
    r"series:.*|nyt:.*=\d{4}.*)$")
NYT_LIST = re.compile(r"^nyt:([a-z\-_]+)=")
NYT_TAGS = [
    (r"graphic", "graphic"), (r"picture", "children"),
    (r"childrens|middle-grade", "children"), (r"young-adult", "young-adult"),
    (r"advice|self", "self-help"), (r"business", "business"),
    (r"science", "science"), (r"sports", None),
]


def subject_list(doc):
    out, seen, nyt = [], set(), set()
    for s in doc.get("subject") or []:
        f = fold(s).strip()
        m = NYT_LIST.match(f)
        if m:
            nyt.add(m.group(1))
        if not f or f in seen or NOISE_SUBJECT.search(f):
            continue
        seen.add(f)
        out.append(f)
    return out, nyt


def classify(doc, hints, year, pages):
    """Return (tags, is_fiction) from raw subjects + query hints."""
    subjects, nyt = subject_list(doc)
    all_subjects = [fold(s) for s in doc.get("subject") or []]

    fic = sum(1 for s in all_subjects if FICTION_RX.search(s))
    nonfic = sum(1 for s in all_subjects if NONFICTION_RX.search(s)
                 and not FICTION_RX.search(s))
    for lst in nyt:
        if "nonfiction" in lst or "advice" in lst or "business" in lst:
            nonfic += 3
        elif "fiction" in lst:
            fic += 3
    hint_fic = sum(1 for h in hints if h in FICTION_ONLY or h in
                   {"young-adult", "children", "classics", "graphic"})
    hint_nf = sum(1 for h in hints if h in NONFICTION_ONLY or h in
                  {"philosophy", "religion"})
    fic_total = fic + 0.5 * hint_fic
    nf_total = nonfic * 0.8 + 0.5 * hint_nf
    is_fiction = fic_total > 0 and fic_total >= nf_total
    blocked = NONFICTION_ONLY if is_fiction else FICTION_ONLY

    scores = Counter()
    for s in subjects:
        hit = set()
        for tag, rx in GENRE_RX:
            if rx.search(s):
                hit.add(tag)
        if "science fiction" in s or "sci-fi" in s:
            hit.discard("science")
        if "history and criticism" in s or "natural history" in s:
            hit.discard("history")
        if "psychological fiction" in s or "fiction, psychological" in s:
            hit.discard("psychology")
        if "juvenile" in s and "young adult" not in s:
            hit.discard("young-adult")
        if not is_fiction and "historical" in hit:
            hit.add("history")
        for tag in hit - blocked:
            if tag == "young-adult" and not YA_AUDIENCE.search(s):
                scores[tag] += 0.5   # a theme (teenagers), not an audience
            else:
                scores[tag] += 1
    for lst in nyt:
        for rx, tag in NYT_TAGS:
            if re.search(rx, lst):
                if tag and tag not in blocked:
                    scores[tag] += 2
                break
    for h in hints:
        if h and h not in blocked:
            scores[h] += 1.5
    if is_fiction:
        for tag in ("philosophy", "religion", "humor"):
            if scores.get(tag, 0) < 2:
                scores.pop(tag, None)

    final = Counter({t: v for t, v in scores.items() if v > 0})
    n_subjects = max(1, len(subjects))

    # Audience: children vs young adult.
    ch, ya = final.get("children", 0), final.get("young-adult", 0)
    if ch and pages and pages >= 200 and is_fiction:
        # Long "juvenile fiction" is middle-grade / YA reading.
        final["young-adult"] = max(ya, ch)
        del final["children"]
    elif ch and ya:
        if ya >= ch and pages and pages >= 150:
            del final["children"]
        else:
            del final["young-adult"]

    # Forms (graphic/poetry/drama/short stories) must dominate: OL merges
    # comic, stage and anthology adaptations into the original work.
    if final:
        for form in FORM_TAGS:
            sc = final.get(form, 0)
            if not sc:
                continue
            others = max([v for t, v in final.items() if t != form] or [0])
            dominant = ((sc > others and sc >= 3)
                        or (sc >= 0.8 * others and sc / n_subjects >= 0.2))
            if not dominant or (form in ("drama", "poetry") and sc < 2
                                and pages and pages > 250):
                del final[form]

    # Old works are classics.
    if year is not None and year <= 1930 and final is not None and (
            is_fiction or final.get("poetry") or final.get("drama")
            or final.get("philosophy") or final.get("religion")
            or final.get("history") or final.get("science")):
        final["classics"] = max([final.get("classics", 0)] + list(final.values()) + [1])

    final.pop("fiction", None)
    if not final:
        return (["fiction"] if is_fiction else []), is_fiction

    old = year is not None and year <= 1930
    # Broad labels rank a little below specific genres with the same support.
    rank = {t: sc * (0.75 if t in ("literary", "classics") and not
                     (t == "classics" and old) else 1.0)
            for t, sc in final.items()}
    top = max(rank.values())
    ranked = sorted(rank.items(), key=lambda kv: (-kv[1], PRIORITY[kv[0]]))
    tags = [t for t, sc in ranked if sc >= max(1, 0.3 * top)][:3]
    if not tags:
        tags = [ranked[0][0]]
    if "classics" in tags and old:
        tags = ["classics"] + [t for t in tags if t != "classics"]
    return tags, is_fiction


def robust_year(doc):
    """first_publish_year, skipping isolated bogus early edition dates."""
    y = doc.get("first_publish_year")
    years = sorted({v for v in (doc.get("publish_year") or [])
                    if isinstance(v, int) and 0 < v <= 2027})
    if not isinstance(y, int):
        return years[0] if years else None
    if y > 2027:
        return None
    if y not in years or len(years) < 3:
        return y
    i = years.index(y)
    for _ in range(3):
        if i + 1 >= len(years):
            break
        cur, nxt = years[i], years[i + 1]
        dense = sum(1 for v in years[i + 1:] if v <= nxt + 5) >= 2
        # Modern bestsellers get editions every year from launch on, so an
        # isolated earlier year is almost always a data-entry error.
        if dense and ((nxt >= 1990 and nxt - cur > 3)
                      or (cur < 1800 and nxt >= 1900)):
            i += 1
        else:
            break
    return years[i]


# --------------------------------------------------------------------------
# Word counts
# --------------------------------------------------------------------------

def words_per_page(tags):
    if "graphic" in tags:
        return 60
    if "children" in tags:
        return 120
    if "poetry" in tags:
        return 140
    if "young-adult" in tags:
        return 250
    return 270


KNOWN_INDEX = {}
for _t, _a, _w in KNOWN_WORDS:
    KNOWN_INDEX[(norm_title(_t), author_last(_a) if _a else "")] = _w


def known_words(title, author):
    key = (norm_title(title), author_last(author))
    if key in KNOWN_INDEX:
        return KNOWN_INDEX[key]
    # Surname spellings differ (Dostoevsky / Dostoyevsky); fall back on title
    # plus first three letters of the surname.
    nt = norm_title(title)
    al = author_last(author)
    for (kt, ka), w in KNOWN_INDEX.items():
        if kt == nt and (ka == "" or (al and ka[:3] == al[:3])):
            return w
    return None


# --------------------------------------------------------------------------
# Building entries
# --------------------------------------------------------------------------

def english_author(doc):
    names = doc.get("author_name") or []
    keys = doc.get("author_key") or []
    if not names:
        return None
    name = re.sub(r"\s+", " ", names[0]).strip()
    key = keys[0] if keys else None
    if key in AUTHOR_OVERRIDES:
        return AUTHOR_OVERRIDES[key]
    m = re.search(r"\(([^()]+)\)", name)
    if m and m.group(1).isascii() and not is_latin_text(name.replace(m.group(0), "")):
        name = m.group(1).strip()
    name = re.sub(r"\s*\(.*?\)\s*", " ", name).strip()
    name = re.sub(r",?\s*\d{3,4}\s*-\s*(\d{3,4})?\.?$", "", name).strip()
    f = fold(name)
    for rx, must, fixed in AUTHOR_NAME_FIXES:
        if re.search(rx, f) and (must is None or re.search(must, f)):
            return fixed
    if not is_latin_text(name):
        # Try the other listed names for one in Latin script.
        for alt in names[1:]:
            if is_latin_text(alt):
                return alt.strip()
        return None
    if name.isupper() and len(name) > 3:
        name = " ".join(w.capitalize() for w in name.lower().split())
    return name


def english_title(doc):
    wid = doc["key"].split("/")[-1]
    if wid in TITLE_OVERRIDES:
        return TITLE_OVERRIDES[wid], True
    raw = doc.get("title") or ""
    title = clean_title(raw)
    if not looks_foreign(raw):
        return title, False
    eds = (doc.get("editions") or {}).get("docs") or []
    ed = eds[0] if eds else {}
    et = clean_title(ed.get("title") or "")
    ok = (et and "eng" in (ed.get("language") or [])
          and is_latin_text(et) and not looks_foreign(et)
          and 2 <= len(et) <= 80
          and not re.search(r"edition|classics|volume|\bvol\b|collection|"
                            r"notes|summary|study|selected|works", et, re.I))
    if ok:
        names = " ".join(doc.get("author_name") or [])
        if tokens(et) and tokens(et) <= tokens(names) | {"count", "graf"}:
            ok = False
    if ok:
        return et, True
    if not is_latin_text(raw):
        return None, False
    return title, False


def build_entry(doc, hints, reasons):
    wid = doc["key"].split("/")[-1]
    langs = doc.get("language") or []
    if langs and "eng" not in langs:
        reasons["no_english"] += 1
        return None
    if not doc.get("author_name"):
        reasons["no_author"] += 1
        return None
    raw_author = doc["author_name"][0]
    is_bible = (fold(raw_author) == "bible"
                and norm_title(doc.get("title") or "") in ("bible", "holy bible"))
    if JUNK_AUTHOR.search(raw_author or "") and not is_bible:
        reasons["junk_author"] += 1
        return None
    title, swapped = english_title(doc)
    if is_bible:
        title, swapped = "The Bible", False
    if not title:
        reasons["foreign_title"] += 1
        return None
    if not langs and looks_foreign(doc.get("title") or "") and not swapped:
        reasons["foreign_title"] += 1
        return None
    raw_title = doc.get("title") or ""
    if JUNK_TITLE.search(raw_title) or JUNK_TITLE.search(title):
        reasons["junk_title"] += 1
        return None
    author = "Various" if is_bible else english_author(doc)
    if not author:
        reasons["foreign_author"] += 1
        return None
    if len(doc.get("author_name") or []) >= 5 and re.search(
            r"stories|tales|poems|poetry|essays|best|great|treasury|reader|"
            r"writings|voices", title, re.I):
        reasons["anthology"] += 1
        return None
    pages = doc.get("number_of_pages_median")
    if not isinstance(pages, int) or pages < 40 or pages > 2500:
        reasons["pages"] += 1
        return None
    subjects = [fold(s) for s in doc.get("subject") or []]
    tb = sum(1 for s in subjects if TEXTBOOK_SUBJECT.search(s))
    if tb >= 1 and (tb >= 2 or len(subjects) <= 8):
        reasons["textbook"] += 1
        return None
    if is_adult(subjects):
        reasons["adult"] += 1
        return None
    year = YEAR_OVERRIDES.get(wid, robust_year(doc))
    tags, is_fiction = classify(doc, hints, year, pages)
    if fold(author) in ILLUSTRATED_CHILDREN_AUTHORS:
        # Heavily illustrated middle-grade series: far fewer words per page.
        tags = ["children"] + [t for t in tags if t not in ("children", "young-adult")]
        tags = tags[:3]
    if not tags:
        reasons["no_genre"] += 1
        return None
    assert all(t in GENRE_SET for t in tags), tags
    pop = (doc.get("readinglog_count") or doc.get("want_to_read_count")
           or doc.get("ratings_count") or 0)
    cover = doc.get("cover_i")
    if swapped:
        eds = (doc.get("editions") or {}).get("docs") or []
        if eds and isinstance(eds[0].get("cover_i"), int) and eds[0]["cover_i"] > 0:
            cover = eds[0]["cover_i"]
    if not isinstance(cover, int) or cover <= 0:
        cover = None
    if wid not in YEAR_OVERRIDES and (norm_title(title) in UNDATED_TITLES
                                      or (year is not None and year < 1450)):
        year = None
    words = known_words(title, author)
    if words:
        reasons["known_word_count"] += 1
    else:
        words = int(round(pages * words_per_page(tags)))
    return {
        "id": wid, "t": title, "a": author, "y": year, "p": pages,
        "w": words, "c": cover, "g": tags, "pop": int(pop),
    }


def dedupe_key(e):
    return norm_title(e["t"]) + "|" + author_last(e["a"])


# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------

def collect():
    pool = {}
    hints = defaultdict(set)

    def add(docs, hint=None):
        n = 0
        for d in docs:
            k = d.get("key")
            if not k or not k.startswith("/works/"):
                continue
            if k not in pool:
                pool[k] = d
                n += 1
            if hint:
                hints[k].add(hint)
        return n

    print("General popularity sweep: %s" % GENERAL_QUERY)
    for page in range(GENERAL_PAGES):
        docs, found = search(GENERAL_QUERY, offset=page * PAGE_SIZE)
        add(docs)
        if not docs or (page + 1) * PAGE_SIZE >= found:
            break
    print("  pool: %d works" % len(pool))

    print("Subject sweeps (%d queries)" % len(SUBJECT_QUERIES))
    for q, hint, pages in SUBJECT_QUERIES:
        new = 0
        for page in range(pages):
            docs, found = search(q, offset=page * PAGE_SIZE)
            new += add(docs, hint)
            if not docs or (page + 1) * PAGE_SIZE >= found:
                break
        print("  %-45s +%d" % (q, new))
    print("  pool: %d works" % len(pool))
    return pool, hints


def must_have_key(title, author):
    return norm_title(title), (author_last(author) if author else None)


def find_must_haves(entries):
    have = defaultdict(list)
    for e in entries:
        have[norm_title(e["t"])].append(fold(e["a"]))
    missing = []
    for title, surname in MUST_HAVE:
        nt = norm_title(title)
        sn = fold(surname or "")
        if nt in have and (not sn or any(sn.split()[-1] in a for a in have[nt])):
            continue
        missing.append((title, surname))
    return missing


def targeted_search(pool, hints, title, surname):
    q = 'title:"%s"' % title.replace('"', "")
    if surname:
        q += ' author:"%s"' % surname
    docs, _ = search(q, limit=5)
    if not docs and surname:
        docs, _ = search("%s %s" % (title, surname), limit=5)
    added = 0
    for d in docs[:3]:
        k = d.get("key")
        if k and k not in pool:
            pool[k] = d
            added += 1
    return added


def process(pool, hints):
    reasons = Counter()
    entries = []
    for k, d in pool.items():
        e = build_entry(d, sorted(h for h in hints.get(k, ()) if h), reasons)
        if e:
            entries.append(e)
    best = {}
    for e in entries:
        key = dedupe_key(e)
        if key not in best or e["pop"] > best[key]["pop"]:
            if key in best:
                reasons["duplicate"] += 1
            best[key] = e
        else:
            reasons["duplicate"] += 1
    return list(best.values()), reasons


def select(entries, must_ids):
    entries = sorted(entries, key=lambda e: (-e["pop"], e["t"]))
    chosen = entries[:TARGET_COUNT]
    chosen_ids = {e["id"] for e in chosen}
    counts = Counter(t for e in chosen for t in e["g"])
    for g in GENRES:
        if counts[g] >= MIN_PER_GENRE:
            continue
        for e in entries[TARGET_COUNT:]:
            if counts[g] >= MIN_PER_GENRE:
                break
            if g in e["g"] and e["id"] not in chosen_ids and e["pop"] >= MIN_POP_TOPUP:
                chosen.append(e)
                chosen_ids.add(e["id"])
                for t in e["g"]:
                    counts[t] += 1
    for e in entries:
        if e["id"] in must_ids and e["id"] not in chosen_ids:
            chosen.append(e)
            chosen_ids.add(e["id"])
    chosen.sort(key=lambda e: (-e["pop"], e["t"]))
    return chosen[:MAX_COUNT]


def main():
    global OFFLINE
    OFFLINE = "--offline" in sys.argv
    os.makedirs(CACHE_DIR, exist_ok=True)
    pool, hints = collect()

    entries, reasons = process(pool, hints)
    chosen = select(entries, set())
    missing = find_must_haves(chosen)
    if missing:
        print("Spot-check: %d must-haves missing before targeted search" % len(missing))
        for title, surname in missing:
            targeted_search(pool, hints, title, surname)
        entries, reasons = process(pool, hints)
    # Must-haves found anywhere in the processed pool are always included.
    must_ids = set()
    index = defaultdict(list)
    for e in entries:
        index[norm_title(e["t"])].append(e)
    for title, surname in MUST_HAVE:
        cands = [e for e in index.get(norm_title(title), [])
                 if not surname or fold(surname).split()[-1] in fold(e["a"])]
        if cands:
            must_ids.add(max(cands, key=lambda e: e["pop"])["id"])
    chosen = select(entries, must_ids)
    missing = find_must_haves(chosen)

    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as fh:
        json.dump(chosen, fh, ensure_ascii=False, separators=(",", ":"))
        fh.write("\n")

    size = os.path.getsize(OUT_PATH)
    genre_counts = Counter(t for e in chosen for t in e["g"])
    covers = sum(1 for e in chosen if e["c"])
    print()
    print("Wrote %s" % OUT_PATH)
    print("  books: %d   size: %.0f KB   with covers: %.1f%%"
          % (len(chosen), size / 1024, 100.0 * covers / max(1, len(chosen))))
    print("  pool: %d works; kept after filters+dedupe: %d" % (len(pool), len(entries)))
    print("  rejected: %s" % dict(reasons.most_common()))
    print("  pop range: %d .. %d" % (chosen[-1]["pop"], chosen[0]["pop"]))
    print("  genres:")
    for g in GENRES:
        print("    %-16s %5d" % (g, genre_counts[g]))
    print("  must-have spot check: %d/%d present"
          % (len(MUST_HAVE) - len(missing), len(MUST_HAVE)))
    for title, surname in missing:
        print("    MISSING: %s (%s)" % (title, surname))
    print("  http: %s" % dict(STATS))


if __name__ == "__main__":
    main()
