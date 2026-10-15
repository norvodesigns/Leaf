import Foundation

/// A single multiple-choice comprehension question shown after a speed-test passage.
struct ComprehensionQuestion: Hashable, Sendable {
    let prompt: String
    let choices: [String]   // exactly 4
    let answerIndex: Int
}

/// An original passage used by the onboarding reading-speed test.
struct SpeedTestPassage: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let kicker: String      // a short eyebrow like "An essay" / "A short story"
    let paragraphs: [String]
    let questions: [ComprehensionQuestion]  // exactly 3
    var wordCount: Int { paragraphs.reduce(0) { $0 + $1.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count } }
}

/// Bundled, original reading-speed-test content. All passages were written for Leaf.
/// Typographic punctuation (’ “ ” —) is used throughout so nothing needs escaping.
enum SpeedTestPassages {
    static let all: [SpeedTestPassage] = [bindery, leapingEye, sixpence]

    /// Picks the next passage so a retake shows a different one.
    static func passage(after previousID: String?) -> SpeedTestPassage {
        guard let previousID,
              let index = all.firstIndex(where: { $0.id == previousID }) else {
            return all[0]
        }
        return all[(index + 1) % all.count]
    }

    // MARK: - 1. Literary fiction

    private static let bindery = SpeedTestPassage(
        id: "bindery",
        title: "The Bindery on Wren Street",
        kicker: "A short story",
        paragraphs: [
            "The man set the dictionary on Mara’s workbench as if it might wake. Its spine had split into three loose pieces, and the cover hung by a single strip of cloth. “It was my father’s,” he said. “Then mine. My daughter learned to spell from it, mostly by arguing with it.” Mara turned the book over in her hands. The paper had gone soft from decades of thumbs, and someone had pressed a four-leaf clover between the pages for the letter C.",
            "She had been binding books in the narrow shop on Wren Street for forty-one years, long enough to know that people rarely brought her a book. They brought her a kitchen table, a long illness, a summer by the sea. The book was only the part that could be held. So she did not promise him it would look new. She promised it would open again without fear.",
            "For a week the dictionary rested in her press between boards of beechwood. She scraped the old glue from the spine with a dull knife and a great deal of patience, sewed each section back onto linen tapes, and mended the torn pages with a tissue so thin it seemed to vanish when wet. The work could not be hurried. Paste dries when it is ready, not when you are.",
            "When the man returned, she placed the book in his hands and showed him how it now fell open, flat and easy, at any page he chose. He found the clover first. Then he laughed out loud, because beside the word “cantankerous” his daughter had written, in pencil and in enormous letters, his own name.",
            "Mara had left that pencil mark exactly where it was. Some repairs, she believed, were simply not hers to make."
        ],
        questions: [
            ComprehensionQuestion(
                prompt: "What does the man bring to Mara’s shop?",
                choices: [
                    "A family atlas with a torn map",
                    "A cookbook stained by years of use",
                    "A worn dictionary handed down in his family",
                    "A diary his daughter kept as a child"
                ],
                answerIndex: 2
            ),
            ComprehensionQuestion(
                prompt: "What does Mara believe people are really bringing her?",
                choices: [
                    "The memories and lives attached to their books",
                    "Books they hope she will buy from them",
                    "Simple jobs they could easily do themselves",
                    "Gifts they plan to give to strangers"
                ],
                answerIndex: 0
            ),
            ComprehensionQuestion(
                prompt: "Why does Mara leave the pencil mark in the book?",
                choices: [
                    "She ran out of time before he came back",
                    "Erasing it would have damaged the paper",
                    "She never noticed it during the repair",
                    "She feels it belongs to the family’s story, not to her"
                ],
                answerIndex: 3
            )
        ]
    )

    // MARK: - 2. Light science

    private static let leapingEye = SpeedTestPassage(
        id: "leaping-eye",
        title: "The Leaping Eye",
        kicker: "An essay",
        paragraphs: [
            "Watch someone read and you might assume their eyes glide across each line like a train on a track. They don’t. The eyes move in a series of quick jumps called saccades, pausing briefly between each one. These pauses, called fixations, are when nearly all the reading happens. A practiced reader makes three or four of them every second and almost never notices.",
            "The reason lies in the structure of the eye. Only a tiny region at the center of the retina, the fovea, sees detail sharply enough to make out letters. Everything around it is a soft blur of shapes. So the eye has to keep moving the fovea from one cluster of words to the next, like a flashlight sweeping a dark room.",
            "Stranger still, the brain largely ignores what the eyes see during each jump, which is why the world does not smear each time your gaze shifts. What feels like a smooth, unbroken line of text is stitched together from still snapshots. Readers also skip many short, predictable words such as “the” and “of,” and now and then they jump back to check something they missed.",
            "Each fixation takes in more than a single word. For readers of English, the useful window stretches further to the right of the fixation point than to the left, because that is where the next words are coming from. Readers of Hebrew, which runs from right to left, show the opposite pattern. The brain, in other words, tunes its attention to the direction of travel.",
            "This may help explain a familiar experience: remembering that a favorite line sat near the bottom of a left-hand page. Because reading is built from physical movements across a physical surface, the mind often files words together with their place. A page is not only something we read. It is somewhere we have been."
        ],
        questions: [
            ComprehensionQuestion(
                prompt: "According to the essay, how do the eyes move during reading?",
                choices: [
                    "In one smooth, continuous sweep along each line",
                    "In quick jumps separated by brief pauses",
                    "Back and forth at random, with no pattern",
                    "Straight down the page, one line at a time"
                ],
                answerIndex: 1
            ),
            ComprehensionQuestion(
                prompt: "Why do the eyes need to keep moving while we read?",
                choices: [
                    "Holding them still quickly causes headaches",
                    "Words fade from memory unless they are reread",
                    "The brain needs constant motion to stay alert",
                    "Only a small central part of the eye sees sharply enough to read letters"
                ],
                answerIndex: 3
            ),
            ComprehensionQuestion(
                prompt: "How does the reading window of Hebrew readers differ from that of English readers?",
                choices: [
                    "It reaches further to the left, the direction their text runs",
                    "It is much smaller and covers only one letter",
                    "It reaches further up and down the page",
                    "It is exactly the same in every language"
                ],
                answerIndex: 0
            )
        ]
    )

    // MARK: - 3. Narrative history

    private static let sixpence = SpeedTestPassage(
        id: "sixpence",
        title: "Sixpence a Story",
        kicker: "A little history",
        paragraphs: [
            "In 1935, a British publisher named Allen Lane was waiting for a train at Exeter station, or so the story goes, and found nothing on the bookstall worth reading. There were magazines and cheap reprints of forgettable novels, but good books came in hardcover, at prices most people could not spend casually. Lane wondered why serious writing could not be sold as cheaply and as easily as a packet of cigarettes.",
            "His answer was Penguin Books. That summer he released ten paperbacks, among them a novel by Ernest Hemingway and a mystery by Agatha Christie, each priced at sixpence. Many booksellers were doubtful; they feared that cheap books would cheapen reading itself. Then a large order arrived from the Woolworths chain, and Penguins began turning up in shops that had never sold serious books before.",
            "The design was part of the appeal. Borrowing ideas from a German publisher called Albatross, Penguin used clean typography and color-coded covers: orange for fiction, green for crime, dark blue for biography. A reader could spot the kind of book they wanted from across a room, and the little bird on the cover became a promise of quality.",
            "Across the Atlantic, Pocket Books launched in 1939 with paperbacks at twenty-five cents. During the Second World War, American publishers printed well over a hundred million compact Armed Services Editions, shaped to slip into a uniform pocket, and shipped them to troops overseas. Many soldiers who had never thought of themselves as readers came home with the habit. One novel that had disappointed in its first life, The Great Gatsby, found a large new audience this way.",
            "The paperback changed what a book could be: not furniture for a shelf, but a companion for a commute, a beach, a long night. Nearly every paperback in a coat pocket today owes something to that empty bookstall."
        ],
        questions: [
            ComprehensionQuestion(
                prompt: "What problem was Allen Lane trying to solve?",
                choices: [
                    "Good books were too expensive for casual buyers",
                    "Libraries were closing across the country",
                    "Authors could not find anyone to publish them",
                    "Bookshops refused to stock mystery novels"
                ],
                answerIndex: 0
            ),
            ComprehensionQuestion(
                prompt: "What did Penguin’s color-coded covers help readers do?",
                choices: [
                    "Tell how long each book was",
                    "Know the price before asking",
                    "Recognize the kind of book at a glance",
                    "Find the author’s other titles"
                ],
                answerIndex: 2
            ),
            ComprehensionQuestion(
                prompt: "What part did the Second World War play in the paperback’s story?",
                choices: [
                    "It forced publishers to stop printing paperbacks for years",
                    "Huge numbers of pocket-sized books sent to troops spread the reading habit",
                    "It made hardcover books cheaper than paperbacks",
                    "It put an end to Penguin’s business in Britain"
                ],
                answerIndex: 1
            )
        ]
    )
}
