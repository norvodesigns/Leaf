"""Believable fake catalogs, for size and latency measurements and for tests that need many rows.

Nothing here talks to the network. Titles and authors are drawn from a Zipf-like vocabulary so a few words ("the",
"of", "love") are everywhere and most are rare, which is what makes prefix searches over a real catalog slow or fast.
Popularity is heavy tailed for the same reason.
"""

import random

from catalog.schema import BookRow

SYLLABLES = ["ka", "to", "mi", "ra", "lo", "ne", "sa", "ve", "du", "an", "el", "or", "in", "ba", "ri", "so", "ta",
             "mar", "lin", "den", "ton", "ver", "ber", "han", "son", "ley", "wick", "ford", "ham", "dale"]
COMMON = ["the", "of", "and", "a", "in", "to", "love", "night", "dark", "last", "little", "secret", "house", "king",
          "queen", "girl", "man", "world", "time", "life", "death", "war", "road", "river", "garden", "island", "song",
          "winter", "summer", "dragon", "city", "book", "story", "stories", "journey", "return", "shadow", "light"]
GIVEN = ["James", "Mary", "John", "Anna", "Robert", "Emma", "Michael", "Sarah", "William", "Laura", "David",
         "Elizabeth", "Thomas", "Susan", "Charles", "Helen", "Daniel", "Alice", "Peter", "Julia", "Jean", "Ali"]
GENRES = ["fantasy", "science-fiction", "mystery", "thriller", "romance", "historical", "horror", "young-adult",
          "children", "classics", "literary", "poetry", "biography", "memoir", "history", "science", "philosophy",
          "self-help", "business", "religion", "nature", "travel", "humor", "food", "art"]
THEMES = ["magic", "dragons", "murder", "detectives", "love stories", "family life", "friendship", "war", "ghosts",
          "cozy", "tea & cafes", "small town life", "coming of age", "found family", "habits & mindset", "space & aliens",
          "england", "london", "books about books", "cats", "world war ii", "adventure", "secrets", "revenge"]


def _word_pool(rng, size):
    words = list(COMMON)
    seen = set(words)
    while len(words) < size:
        w = "".join(rng.choice(SYLLABLES) for _ in range(rng.randint(2, 4)))
        if w not in seen:
            seen.add(w)
            words.append(w)
    return words


def make_rows(count, seed=1, pool_size=None):
    """`count` BookRows with ids OL1W..., Zipf-ish words and heavy-tailed popularity. About 10% are in the pool."""
    rng = random.Random(seed)
    words = _word_pool(rng, 40000)
    surnames = [w.capitalize() for w in _word_pool(rng, 30000)[100:]]
    weights = [1.0 / (i + 1) for i in range(len(words))]
    cum = []
    total = 0.0
    for w in weights:
        total += w
        cum.append(total)

    def pick_word():
        r = rng.random() * total
        lo, hi = 0, len(cum) - 1
        while lo < hi:
            mid = (lo + hi) // 2
            if cum[mid] < r:
                lo = mid + 1
            else:
                hi = mid
        return words[lo]

    pool_size = pool_size if pool_size is not None else max(1, count // 10)
    rows = []
    for i in range(count):
        n_words = min(8, 1 + int(rng.expovariate(0.55)))
        title = " ".join(pick_word() for _ in range(n_words))
        title = title[:1].upper() + title[1:]
        author = "%s %s" % (rng.choice(GIVEN), rng.choice(surnames))
        popularity = max(1, int(1 + rng.paretovariate(0.9) * 3))
        genres = rng.sample(GENRES, rng.choice([1, 1, 2, 3]))
        themes = rng.sample(THEMES, rng.choice([0, 2, 4, 6, 8]))
        pages = int(min(2500, max(40, rng.lognormvariate(5.7, 0.45))))
        alt = [pages + d for d in (rng.randint(-40, 40), rng.randint(-40, 40)) if 40 <= pages + d <= 2500 and d]
        rows.append(BookRow(
            id="OL%dW" % (1000 + i * 7), title=title, author=author, pages=pages,
            year=rng.choice([None] + list(range(1850, 2026))), words=None,
            cover_id=rng.choice([None, rng.randint(100000, 14500000)]),
            genres=genres, themes=themes, popularity=popularity,
            page_counts=sorted(set(alt))[:3], page_sources=rng.randint(1, 30)))
    ranked = sorted(range(count), key=lambda i: -rows[i].popularity)
    for i in ranked[:pool_size]:
        rows[i].in_pool = True
    return rows
