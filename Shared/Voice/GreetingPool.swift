import Foundation

/// Every greeting line, as plain data. A row is "Headline" or "Headline | Subline"; `{title}`, `{pages}`, `{streak}`,
/// `{minutes}`, `{tea}` and `{day}` are filled by the engine, and a line whose placeholder cannot be filled is never
/// chosen. Apostrophes are typographic, like the rest of the app.
///
/// The voice, from NEXT.md section 5: short (about nine words), specific, warm and never guilty; no exclamation marks;
/// no streak threats; tea and cozy words are seasoning (about one line in three); and every line leaves a door open to
/// start. The tests hold the whole pool to those rules, so add lines freely and let them tell you if one slips.
enum GreetingPool {
    struct Section {
        var moment: GreetingMoment
        /// Nil means any time of day.
        var dayparts: Set<Daypart>?
        var rows: [String]

        init(_ moment: GreetingMoment, dayparts: Set<Daypart>? = nil, _ rows: [String]) {
            self.moment = moment
            self.dayparts = dayparts
            self.rows = rows
        }
    }

    /// The late-night signature is the line people love most, so it comes up far more often than its neighbours.
    /// (It still never repeats two days running.)
    static let weights: [String: Double] = [
        "Still up? | One more page, then bed.": 24,
        "The whole house is asleep. | Except you and the book.": 10,
        "Tea o’clock.": 6,
        "Welcome to your nook.": 6,
        "Today’s pages are done. | Anything more is a gift.": 6,
        "Day off. | The book will keep.": 4,
    ]

    static let sections: [Section] = firstMoments + celebrations + holidays + ambient + dayparts

    // MARK: Moments about the reader

    private static let firstMoments: [Section] = [
        Section(.firstEver, [
            "Welcome to your nook.",
            "Hello, reader. | Kettle on, and let’s find a first page.",
            "Welcome. | No rush, no pressure, just pages.",
            "Glad you’re here. | Pull up an armchair and pick a book.",
            "Every reading life starts with one page.",
            "Welcome in. | The first page is the easy one.",
            "Hello. | Your bookshelf starts right here.",
        ]),
        Section(.nearFinish, [
            "{pages} from the end of {title}. | The kettle can wait.",
            "The last {pages} of {title}. | You’re so close.",
            "{title} is nearly done. | {pages} to go.",
            "Almost there with {title}. | Just {pages} left.",
            "{pages} left in {title}. | Finish it today?",
            "So close to the end. | {pages}, and then a fresh cup.",
            "Nearly there. | Just {pages} to go.",
            "The ending is in sight. | {pages} left. Lamp stays on.",
            "{pages} between you and the last line. | Go on.",
            "The last stretch. | {pages} and a closing line.",
            "Only {pages} left. | The ending is yours.",
            "One cup of tea from done. | {pages} will do it.",
        ]),
        Section(.finishedToday, [
            "Finished. | A fresh cup, then a fresh book.",
            "{title}, finished. | Sit with it for a minute.",
            "That’s {title} done. | What a thing to have read.",
            "{title} is yours now. | No hurry with the next.",
            "The last page is turned. | Let it settle.",
            "One more book finished. | Well read.",
            "Closing a good book feels like this. | Full and quiet.",
            "Book finished. | Put the kettle on and choose later.",
            "Another one for the shelf. | The kettle’s earned it.",
            "A finished book. | That’s a small, real thing.",
            "The ending landed. | Stay with it over a cup of tea.",
            "Done. | Savor it. The next book can wait.",
        ]),
        Section(.welcomeBack, [
            "Welcome back. | Your bookmark’s right where you left it.",
            "There you are. | The book kept your place.",
            "Good to see you. | {title} has been waiting patiently.",
            "Welcome back. | Pick up wherever feels right.",
            "Hello again. | Ten minutes and a cup is a fine way in.",
            "Nice to have you back. | The kettle remembers.",
            "Hello, stranger. | Your place is saved.",
            "Back with the book. | Slippers on, one page at a time.",
            "Welcome back. | {title} is just as you left it.",
            "You’re back. | The next page is right there.",
            "Hello again. | No hurry. Start with a page.",
        ]),
        Section(.welcomeBackLong, [
            "Welcome back. | Your place in {title} is saved.",
            "It’s good to see you. | Start with just a page.",
            "Hello again. | The book hasn’t gone anywhere.",
            "Welcome home. | Your nook is just as you left it.",
            "A fresh start. | Any page is a good page.",
            "Hello. | Your bookmark held the door open.",
            "Long time. | The kettle’s still here. Begin anywhere.",
            "A new chapter, in a way. | Begin whenever.",
            "Back at last. | The story is happy to see you.",
            "Welcome back, reader. | Ease in with five minutes and a cup.",
        ]),
        Section(.stalled, [
            "Your place in {title} is saved. | Any page will do.",
            "{title} is patient. | Open it when you like.",
            "A good book keeps. | So does your bookmark.",
            "Still thinking about {title}? | A page is a fine start.",
            "No rush with {title}. | Or start something new.",
            "Set it aside, or pick it up. | Both are fine.",
            "Maybe a fresh page today. | Or a new book with tea.",
            "The bookmark’s patient. | So is the book.",
        ]),
    ]

    // MARK: Goals, rest and streaks

    private static let celebrations: [Section] = [
        Section(.goalMet, [
            "Today’s pages are done. | Anything more is a gift.",
            "Goal met. | Keep going if the chapter’s good.",
            "That’s today’s reading. | The rest is bonus.",
            "Done for today. | Refill the cup and read on?",
            "A good day’s reading. | Stay by the lamp if you like.",
            "Goal met. | Another cup, or call it a day?",
            "All read for today. | Anything extra is a treat.",
            "Today’s reading: done. | Go on, or go gently.",
            "That’s the goal. | The tea is well earned.",
            "You did the reading. | Anything more is gravy.",
            "Pages done. | The rest of the day is yours.",
            "Nicely done. | Blanket up, the rest is bonus.",
        ]),
        Section(.goalMet, dayparts: [.late, .smallHours], [
            "Today’s done. | Sleep well, reader.",
            "Goal met. | Lights out whenever you’re ready.",
            "All read. | Time for sleep, or one more page.",
        ]),
        Section(.goalMet, dayparts: [.dawn, .morning], [
            "Done before breakfast. | Look at you.",
            "Early finish. | The rest of the day is a bonus.",
            "Already done. | Lovely start. Second cup?",
        ]),
        Section(.goalMet, dayparts: [.dusk, .evening, .teaTime], [
            "Goal met. | The evening is all yours.",
            "Pages done. | Put the kettle on.",
        ]),
        Section(.goalPartial, [
            "{minutes} to today’s goal. | Easy ground from here.",
            "{minutes} left today. | One sitting would do it.",
            "Nearly there for today. | {minutes} and a cup of tea.",
            "Good start today. | {minutes} more and you’re done.",
            "You’re part-way through today. | {minutes} finishes it.",
            "A little more to go. | {minutes} by the lamp.",
            "Just {minutes} to go. | The kettle can wait.",
            "{minutes} from today’s goal. | One more chapter might do it.",
        ]),
        Section(.restDay, [
            "Day off. | The book will keep.",
            "Rest day. | Read anyway if you like.",
            "Nothing scheduled today. | Pages are always welcome.",
            "A rest day, planned and proper. | Enjoy it.",
            "No plan today. | Slippers, tea, whatever you feel like.",
            "Take the day. | Blanket, window, book optional.",
            "Day of rest. | Open the book only if it calls.",
            "Easy day. | A page or two, or none at all.",
            "Slow day by design. | Stay as long as you like.",
            "Rest day. | Tea, a window, maybe a chapter.",
            "Off the clock today. | The nook will be here.",
        ]),
        Section(.streakWeek, [
            "A whole week of reading. | Seven days, seven small chapters.",
            "Seven days in a row. | That’s a habit forming.",
            "One week running. | Look at you.",
            "Seven in a row. | Quietly impressive.",
        ]),
        Section(.streakWeek, dayparts: [.dusk, .evening, .late], [
            "Seven evenings in a row. | The tea tastes better.",
        ]),
        Section(.streakFortnight, [
            "Two weeks in a row. | The habit has roots.",
            "Fourteen days. | Your nook is well used.",
            "A fortnight of pages. | Lovely.",
            "Fourteen days running. | Steady wins the chapter.",
        ]),
        Section(.streakMonth, [
            "Thirty days in a row. | A whole month of pages.",
            "A month of reading. | That’s a reading life.",
            "Thirty days. | You’ve built a good habit.",
            "One month, day after day. | Pour yourself a proper pot.",
        ]),
        Section(.streakCentury, [
            "One hundred days. | That’s a lot of pages.",
            "Day one hundred. | Take a quiet bow.",
            "A hundred days in a row. | Remarkable.",
            "Triple digits. | Your bookmark is very proud.",
        ]),
        Section(.streakOther, [
            "{streak} days in a row. | Quietly impressive.",
            "{streak} days of reading. | Same armchair tomorrow?",
            "Day {streak}. | The habit is yours now.",
            "{streak} days running. | The pages add up.",
            "{streak} in a row. | That’s a lot of chapters.",
        ]),
        Section(.streakGoing, [
            "{streak} days in a row. | Same time tomorrow?",
            "Day {streak} of reading. | Nicely going.",
            "{streak} days running. | The habit is humming along.",
            "On a roll: {streak} days. | One more page today?",
            "{streak} days of pages. | Keep the kettle warm.",
        ]),
    ]

    // MARK: Holidays

    private static let holidays: [Section] = [
        Section(.newYearsEve, [
            "Last night of the year. | End it with a chapter.",
            "New Year’s Eve. | One quiet page before the noise?",
            "The year’s last evening. | A candle, a book, a pot of tea.",
            "Almost a new year. | Tea first, then pages.",
        ]),
        Section(.newYear, [
            "Happy New Year. | Let’s begin with a page.",
            "New year, clean page. | Start small.",
            "January first. | A fine day to open a book.",
            "A new year of reading. | Page one is waiting.",
            "Fresh year, fresh bookmark. | Begin gently.",
        ]),
        Section(.valentines, [
            "Happy Valentine’s Day. | Spend it with a good book.",
            "Valentine’s Day. | Book and tea, perfectly happy.",
            "Love is a good book. | And you have one.",
            "A date with a book? | Candlelight optional.",
        ]),
        Section(.easter, [
            "Happy Easter. | A slow day suits a long chapter.",
            "Easter Sunday. | Quiet hours, a pot of tea, a good book.",
            "Spring and Sunday together. | Read in the light.",
        ]),
        Section(.halloween, [
            "Happy Halloween. | Something spooky to read?",
            "Halloween. | Candle lit, spooky page open.",
            "Trick or treat? | Treat yourself to a ghost story.",
            "All Hallows’ Eve. | The right day for a shiver.",
        ]),
        Section(.spookySeason, [
            "Spooky season. | Pick a book that creaks.",
            "Cobwebs and candlelight. | Open something spooky.",
            "It’s ghost story weather.",
            "The dark comes early now. | A shiver and a page?",
            "Pumpkins on porches. | A mystery and a mug of cocoa.",
            "October. | Made for eerie chapters.",
        ]),
        Section(.thanksgiving, [
            "Happy Thanksgiving. | Save a quiet hour for a book.",
            "Thanksgiving. | Full table, then a quiet chapter.",
            "Grateful for good books. | Aren’t we all.",
            "Between the pie and the dishes. | A quiet cup, ten pages.",
        ]),
        Section(.christmasSeason, [
            "Lights are up. | Time for a winter book.",
            "December. | Made for long, quiet chapters.",
            "Cold outside, warm inside. | Blanket, lights, book.",
            "The holiday rush is on. | Steal ten minutes for pages.",
            "Snow-globe season. | Pick a cozy winter read.",
            "Wrapping paper and a good book. | A fine pair.",
        ]),
        Section(.christmasEve, [
            "Christmas Eve. | One quiet chapter before the morning.",
            "Lights low, the house hushed. | A story and a mug by the tree?",
            "Almost Christmas. | Read something to match.",
            "Christmas Eve is for stories. | Hang the stockings first.",
        ]),
        Section(.christmas, [
            "Merry Christmas. | A new book under the tree?",
            "Christmas Day. | Find an hour with a book.",
            "Merry Christmas, reader. | Tea, quiet, and pages.",
            "Happy holidays. | Today you may read all day.",
        ]),
    ]

    // MARK: Weather, moon, the book, the weekday, the season

    private static let ambient: [Section] = [
        Section(.rain, [
            "Rain on the window. | Perfect.",
            "It’s raining. | Best reading weather there is.",
            "The rain is steady. | So is a good chapter.",
            "Rainy day. | Curl up with a blanket and a book.",
            "Listen to that rain. | Now pour a cup and open the book.",
            "Rain like this asks for a book.",
            "Puddles outside, pages inside.",
            "Rain at the glass. | Kettle on?",
        ]),
        Section(.snow, [
            "Snow outside. | Stay in with a mug and a good book.",
            "Everything’s quiet under the snow. | Pages too.",
            "Snow is falling. | The pages are warm.",
            "A snow day for your book.",
            "Snowed in, happily. | Hearth, blanket, book.",
            "Soft snow, soft light. | One chapter?",
        ]),
        Section(.cold, [
            "Blanket weather.",
            "Cold out there. | Warm in here, with a book.",
            "Frosty. | Pull the blanket up and read.",
            "Chilly day. | Perfect for staying in.",
            "It’s cold outside. | Time to settle in.",
            "Brr. | A chapter under a blanket?",
        ]),
        Section(.hot, [
            "Hot out there. | Find some shade and a chapter.",
            "Too warm to do much. | Perfect for reading.",
            "Heat like this wants a porch. | And a page.",
            "A cool drink, a shady spot. | One chapter?",
            "Sticky weather. | Iced tea and a slow chapter.",
        ]),
        Section(.wind, [
            "Windy out. | Stay in, kettle on, turn pages.",
            "Hear the wind? | Good weather to read inside.",
            "Wind at the windows. | A cozy chapter?",
            "Blustery out there. | Pages stay put.",
            "Gusts and rattling panes. | Read through it.",
        ]),
        Section(.fog, [
            "Fog at the window. | A pot of tea and a hush.",
            "Soft grey fog. | Soft grey mood for reading.",
            "Mist outside. | Mystery inside?",
            "Everything’s blurred out there. | Your book is sharp.",
            "A foggy hush. | Read by the lamp until it lifts.",
        ]),
        Section(.clear, [
            "Clear skies. | Take your book outside?",
            "Bright out there. | Take a cup to a sunny spot.",
            "Blue sky. | Read by the window.",
            "A clear day. | A clear mind for reading.",
            "Sunshine today. | A chapter in the light.",
        ]),
        Section(.fullMoon, dayparts: [.dusk, .evening, .late, .smallHours], [
            "Full moon tonight. | A fine light to read by.",
            "Bright moon. | Good night for a long chapter.",
            "The moon is full. | Stories feel bigger tonight.",
            "Moonlight at the window. | Lamp low, read a little longer.",
            "Full moon. | Strange things happen in good books.",
        ]),
        Section(.newMoon, dayparts: [.dusk, .evening, .late, .smallHours], [
            "No moon tonight. | Lamp it is.",
            "Dark sky, bright page.",
            "New moon, new chapter.",
        ]),
        Section(.justStarted, [
            "New book energy. | Page one is the best page.",
            "A fresh book. | The first chapter is a hello over tea.",
            "{title} is just beginning. | Settle in.",
            "Chapter one by the lamp. | A good place to be.",
            "A new story, barely started. | Go on.",
            "The start of {title}. | Lovely.",
        ]),
        Section(.midway, [
            "Right in the middle of it. | The best part.",
            "Deep in {title}. | Keep going.",
            "Mid-book, the sweet spot. | Refill the cup.",
            "You’re well into the story. | Bookmark out, settle in.",
            "Somewhere in the middle. | Where it gets good.",
        ]),
        Section(.monday, [
            "Monday. | Start the week with a page.",
            "A new week. | Ten quiet minutes and a hot cup?",
            "It’s Monday. | A chapter makes it kinder.",
            "Monday. | Be kind to yourself: tea and a chapter.",
            "Fresh week, same good book.",
        ]),
        Section(.friday, [
            "Friday. | The week is nearly done.",
            "It’s Friday. | Read something just for fun.",
            "The weekend begins. | Kettle on for the long chapters.",
            "Friday. | A long read is well earned.",
        ]),
        Section(.friday, dayparts: [.evening, .late], [
            "Friday night is for books and blankets.",
        ]),
        Section(.saturday, [
            "Saturday. | No alarm, long chapters.",
            "A Saturday with nowhere to be. | Lovely.",
            "Slow Saturday. | Tea and a long chapter.",
            "Saturday. | Slippers on, book in hand.",
            "Weekend pages. | The best kind.",
        ]),
        Section(.sunday, [
            "Slow Sunday. | No rush.",
            "Sunday. | Long chapters allowed.",
            "Sunday light. | A good time for a book.",
            "Sunday reading. | Stay until the tea goes cold.",
            "Sunday is made for this.",
            "Easy Sunday. | Just you, the book and a blanket.",
        ]),
        Section(.spring, [
            "Spring is here. | Windows open, pages turning.",
            "Everything’s greening up. | Read outside?",
            "Soft spring light. | A cup on the sill, a book in hand.",
            "Rain and blossom. | A good-book, good-tea season.",
            "The days are getting longer. | More room for chapters.",
            "Spring air. | Open the window and the book.",
        ]),
        Section(.summer, [
            "Summer days. | Long light, long chapters.",
            "Porch season. | Bring a book and iced tea.",
            "A summer read is a small holiday.",
            "Long days now. | Plenty of time for chapters.",
            "Warm light, a cold cup, a good book.",
            "Sun on the page. | The best light.",
        ]),
        Section(.autumn, [
            "Leaves are turning. | So are your pages.",
            "Autumn light. | Perfect for a long read and a mug.",
            "Sweater weather. | Cardigan, book, tea.",
            "The air is crisp. | Time for a story.",
            "Fall is here. | Hot cocoa, good book.",
            "Crunchy leaves outside. | Quiet pages inside.",
        ]),
        Section(.winter, [
            "Winter. | Made for books.",
            "Short days, long chapters.",
            "The cold has arrived. | Settle in with a book and a blanket.",
            "Hearth, blanket, book. | Winter has everything.",
            "Frost on the glass. | A warm cup, a warm page.",
        ]),
        Section(.winter, dayparts: [.teaTime, .dusk, .evening], [
            "Dark at five. | Plenty of reading time.",
        ]),
    ]

    // MARK: Times of day

    private static let dayparts: [Section] = [
        Section(.dawn, [
            "Early bird. | The kettle’s barely warm.",
            "Quiet house. | Good light.",
            "Up before the day. | A few pages, a warm mug?",
            "First light. | First chapter.",
            "Early morning. | The world hasn’t started yet.",
            "Good morning, early reader. | Ten minutes before everything.",
            "Dawn and a book. | Nobody needs you yet.",
            "The day is still new. | Read a little of it.",
            "Sunrise pages. | Coffee or tea, then a chapter.",
            "Soft light, soft start. | One page to begin.",
            "Before the rush. | A quiet chapter, just yours.",
            "Birdsong already. | Join in with a cup and a page.",
        ]),
        Section(.morning, [
            "Morning. | Ten minutes before the day begins?",
            "Good morning. | Coffee, tea, or just the book?",
            "A fresh morning. | A fresh page.",
            "Morning light. | Perfect for reading.",
            "Bright and early. | The book is ready when you are.",
            "Good morning, reader. | What’s today’s chapter?",
            "The day’s just started. | Give it a page.",
            "Morning pages. | They make the whole day kinder.",
            "Start gently. | Five minutes counts.",
            "Hello, morning. | Hello, mug. Hello, book.",
            "A calm start. | Tea, then a chapter.",
            "Fresh pot, fresh chapter.",
        ]),
        Section(.lunch, [
            "Lunch with a chapter.",
            "Lunch break. | A cup of tea and a few pages.",
            "Midday pause. | A page between bites?",
            "Noon. | Twenty minutes, nobody’s watching.",
            "Sandwich in one hand. | Book in the other.",
            "The middle of the day. | A short reading detour?",
            "Lunchtime. | Steal a few pages.",
            "Halfway through the day. | A quiet chapter helps.",
            "Take your break. | Take your book.",
            "Midday light. | A cup, a window, a short read.",
            "Soup, tea and a story.",
            "A calm hour at noon. | Spend some on a book.",
        ]),
        Section(.afternoon, [
            "The afternoon is better with a book in it.",
            "Afternoon. | A good time for a cup and a slow page.",
            "Mid-afternoon lull. | A chapter fixes it.",
            "The day has a soft middle. | Read in it.",
            "Afternoon light. | It suits the page.",
            "Time for a little escape. | Ten minutes, maybe?",
            "Afternoon slump? | A cup and a few pages beat a nap.",
            "Quiet afternoon. | A pot of tea and a long chapter.",
            "Slow afternoon. | Slow reading.",
            "Sunlight on the page. | Hello, afternoon.",
            "A break from the day. | A page or two?",
            "Afternoon. | Nothing wrong with reading now.",
        ]),
        Section(.teaTime, [
            "Tea o’clock.",
            "Four o’clock. | A short chapter, a long breath.",
            "Tea time. | Biscuit optional, book welcome.",
            "The kettle’s on. | Is the book open?",
            "A pot of tea and a page.",
            "Teatime. | The best hour for a story.",
            "Late afternoon. | The light is going gold.",
            "Almost evening. | A short chapter first?",
            "The day is winding down. | Wind down with a page.",
            "A quiet half hour. | Read a little.",
            "The afternoon is softening. | So is the book.",
            "Steep and read. | Your hour has arrived.",
        ]),
        Section(.dusk, [
            "The lamp’s calling.",
            "Dusk. | The day is folding up.",
            "Golden hour. | Read before it fades.",
            "Evening is arriving. | Settle in with something good.",
            "Lights are coming on. | Time for the lamp and a chapter.",
            "Soft blue light outside. | Warm lamp, warm page inside.",
            "The sun is setting. | A chapter before dinner?",
            "The day is done, nearly. | The book is waiting.",
            "Twilight. | A slow, soft reading hour.",
            "Dinner soon. | Ten pages and a cup first?",
            "Shadows are long. | The pages are warm.",
            "The day exhales. | Read with it.",
        ]),
        Section(.evening, [
            "Good evening. | Kettle on?",
            "Dinner’s done. | You’ve earned a chapter.",
            "The evening is yours. | Open the book.",
            "Evening. | Time to curl up with a blanket.",
            "The best part of the day. | Reading time.",
            "Quiet evening. | A chapter fits right in.",
            "Lamp on, day off. | Just pages.",
            "Night is settling in. | So can you.",
            "Good evening, reader. | Where were we?",
            "Evening hush. | The lamp and the book do the talking.",
            "Winding down. | A few pages and a warm mug.",
            "The house is calm. | Perfect time for reading.",
            "Settle in. | The day is finished with you.",
        ]),
        Section(.late, [
            "Still up? | One more page, then bed.",
            "Still up? | The book doesn’t mind.",
            "Late one tonight. | A few pages, then sleep?",
            "It’s late. | A short chapter by the lamp is plenty.",
            "The night is quiet. | So is the book.",
            "Past bedtime? | The blanket and the story say otherwise.",
            "Midnight reading. | The best kind of quiet.",
            "Just you and the book. | And the hush.",
            "Everyone’s asleep. | One last cup of tea, one last page.",
            "One more chapter? | Just one.",
            "Late and lovely. | Read until your eyes say stop.",
            "The lamp is low. | The page is warm.",
            "The hour is late. | The pages are patient.",
            "Still awake? | Same. Open the book.",
        ]),
        Section(.smallHours, [
            "The whole house is asleep. | Except you and the book.",
            "Small hours. | The quietest pages of all.",
            "Can’t sleep? | A slow page might help.",
            "Deep night. | Read gently, by a low lamp.",
            "It’s very late. | The book will be gentle with you.",
            "The world is dark and hushed. | Blanket up, soft pages only.",
            "Night owl. | The kettle’s asleep, the book’s up.",
            "Between midnight and dawn. | Nobody’s watching. Read.",
            "Quiet like this is rare. | Spend it on pages.",
            "Sleep hasn’t come yet? | Read until it does.",
            "Small-hours thoughts? | Try a page.",
            "The night shift. | You and a paperback.",
        ]),
    ]

    // MARK: Lookups

    /// Every line, built once.
    static let all: [GreetingLine] = sections.flatMap { section in
        section.rows.map { row in
            GreetingLine(moment: section.moment, row: row, dayparts: section.dayparts, weight: weights[row] ?? 1)
        }
    }

    private static let byMoment: [GreetingMoment: [GreetingLine]] = Dictionary(grouping: all, by: \.moment)

    static func lines(in moment: GreetingMoment) -> [GreetingLine] {
        byMoment[moment] ?? []
    }
}
