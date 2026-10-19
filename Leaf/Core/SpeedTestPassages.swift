import Foundation

/// A single multiple-choice comprehension question shown after a speed-test passage.
struct ComprehensionQuestion: Hashable, Sendable {
    let prompt: String
    let choices: [String]   // exactly 4
    let answerIndex: Int
}

/// A passage used by the onboarding reading-speed test.
struct SpeedTestPassage: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let kicker: String      // a short eyebrow, here the author and the story
    let paragraphs: [String]
    let questions: [ComprehensionQuestion]  // exactly 3
    var wordCount: Int { paragraphs.reduce(0) { $0 + $1.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count } }
}

/// Reading-speed-test passages: real Sherlock Holmes, by Arthur Conan Doyle (1887 to 1892, public domain), chosen
/// because they are famous and fun to read at speed. Typographic punctuation (’ “ ” —) is used throughout so nothing
/// needs escaping.
enum SpeedTestPassages {
    static let all: [SpeedTestPassage] = [scandal, afghanistan, carbuncle]

    /// Picks the next passage so a retake shows a different one.
    static func passage(after previousID: String?) -> SpeedTestPassage {
        guard let previousID,
              let index = all.firstIndex(where: { $0.id == previousID }) else {
            return all[0]
        }
        return all[(index + 1) % all.count]
    }

    // MARK: - 1. A Scandal in Bohemia (1891)

    private static let scandal = SpeedTestPassage(
        id: "scandal",
        title: "A Scandal in Bohemia",
        kicker: "Sherlock Holmes",
        paragraphs: [
            "To Sherlock Holmes she is always the woman. I have seldom heard him mention her under any other name. In his eyes she eclipses and predominates the whole of her sex. It was not that he felt any emotion akin to love for Irene Adler. All emotions, and that one particularly, were abhorrent to his cold, precise but admirably balanced mind. He was, I take it, the most perfect reasoning and observing machine that the world has seen, but as a lover he would have placed himself in a false position.",
            "They were admirable things for the observer—excellent for drawing the veil from men’s motives and actions. But for the trained reasoner to admit such intrusions into his own delicate and finely adjusted temperament was to introduce a distracting factor which might throw a doubt upon all his mental results. Grit in a sensitive instrument, or a crack in one of his own high-power lenses, would not be more disturbing than a strong emotion in a nature such as his.",
            "“You see, but you do not observe. The distinction is clear. For example, you have frequently seen the steps which lead up from the hall to this room.”",
            "“Frequently.”",
            "“How often?”",
            "“Well, some hundreds of times.”",
            "“Then how many are there?”",
            "“How many? I don’t know.”",
            "“Quite so! You have not observed. And yet you have seen. That is just my point. Now, I know that there are seventeen steps, because I have both seen and observed.”"
        ],
        questions: [
            ComprehensionQuestion(
                prompt: "How does Watson describe Holmes’s feelings about Irene Adler?",
                choices: [
                    "He loved her, but hid it behind jokes",
                    "He felt no love for her, yet to him she stood apart from all other women",
                    "He resented her for outwitting him",
                    "He had never heard her name"
                ],
                answerIndex: 1
            ),
            ComprehensionQuestion(
                prompt: "Why would strong emotion trouble a trained reasoner?",
                choices: [
                    "It makes him too slow to act",
                    "It would turn him against his friends",
                    "It is like grit in a delicate instrument and could throw doubt on all his results",
                    "It tires the eyes and weakens the memory"
                ],
                answerIndex: 2
            ),
            ComprehensionQuestion(
                prompt: "How many steps lead up from the hall to the room?",
                choices: [
                    "Twelve",
                    "Fifteen",
                    "Seventeen",
                    "Twenty-one"
                ],
                answerIndex: 2
            )
        ]
    )

    // MARK: - 2. A Study in Scarlet (1887)

    private static let afghanistan = SpeedTestPassage(
        id: "afghanistan",
        title: "A Study in Scarlet",
        kicker: "Sherlock Holmes",
        paragraphs: [
            "“How are you?” he said cordially, gripping my hand with a strength for which I should hardly have given him credit. “You have been in Afghanistan, I perceive.”",
            "“How on earth did you know that?” I asked in astonishment.",
            "“Never mind,” said he, chuckling to himself. Later he explained. “From long habit the train of thoughts ran so swiftly through my mind that I arrived at the conclusion without being conscious of intermediate steps. There were such steps, however. The train of reasoning ran, ‘Here is a gentleman of a medical type, but with the air of a military man. Clearly an army doctor, then. He has just come from the tropics, for his face is dark, and that is not the natural tint of his skin, for his wrists are fair. He has undergone hardship and sickness, as his haggard face says clearly. His left arm has been injured. He holds it in a stiff and unnatural manner. Where in the tropics could an English army doctor have seen much hardship and got his arm wounded? Clearly in Afghanistan.’ The whole train of thought did not occupy a second. I then remarked that you came from Afghanistan, and you were astonished.”"
        ],
        questions: [
            ComprehensionQuestion(
                prompt: "Where does Holmes say the newcomer has been?",
                choices: [
                    "India",
                    "Egypt",
                    "Afghanistan",
                    "South Africa"
                ],
                answerIndex: 2
            ),
            ComprehensionQuestion(
                prompt: "What kind of man does Holmes first take him to be?",
                choices: [
                    "A sailor with the manner of a merchant",
                    "A gentleman of a medical type with the air of a military man",
                    "A lawyer who has lived abroad",
                    "A newspaper man looking for a story"
                ],
                answerIndex: 1
            ),
            ComprehensionQuestion(
                prompt: "How does Holmes know he has come from the tropics?",
                choices: [
                    "His face is dark, but his wrists are fair",
                    "He is carrying a light coat",
                    "He says the English weather feels cold",
                    "His boots are covered in red dust"
                ],
                answerIndex: 0
            )
        ]
    )

    // MARK: - 3. The Adventure of the Blue Carbuncle (1892)

    private static let carbuncle = SpeedTestPassage(
        id: "carbuncle",
        title: "The Blue Carbuncle",
        kicker: "Sherlock Holmes",
        paragraphs: [
            "I had called upon my friend Sherlock Holmes upon the second morning after Christmas, with the intention of wishing him the compliments of the season. He was lounging upon the sofa in a purple dressing-gown, a pipe-rack within his reach upon the right, and a pile of crumpled morning papers, evidently newly studied, near at hand. Beside the couch was a wooden chair, and on the angle of its back hung a very seedy and disreputable hard-felt hat, much the worse for wear, and cracked in several places. A lens and a forceps lying upon the seat of the chair suggested that the hat had been suspended in this manner for the purpose of examination.",
            "“You are engaged,” said I; “perhaps I interrupt you.”",
            "“Not at all. I am glad to have a friend with whom I can discuss my results. The matter is a perfectly trivial one”—he jerked his thumb in the direction of the old hat—“but there are points in connection with it which are not entirely devoid of interest and even of instruction.”"
        ],
        questions: [
            ComprehensionQuestion(
                prompt: "When does Watson call on Holmes?",
                choices: [
                    "On Christmas Eve",
                    "On Christmas morning",
                    "On the second morning after Christmas",
                    "On New Year’s Day"
                ],
                answerIndex: 2
            ),
            ComprehensionQuestion(
                prompt: "What is Holmes doing when Watson arrives?",
                choices: [
                    "Playing the violin by the window",
                    "Lounging on the sofa in a purple dressing-gown",
                    "Writing a letter at his desk",
                    "Pacing the room with a magnifying glass"
                ],
                answerIndex: 1
            ),
            ComprehensionQuestion(
                prompt: "What suggests that the old hat is being examined?",
                choices: [
                    "A lens and a forceps lie on the seat of the chair",
                    "It is wrapped in a newspaper",
                    "A note is pinned to the brim",
                    "It is lying on a tray beside a candle"
                ],
                answerIndex: 0
            )
        ]
    )
}
