/// Curated set of SF Symbols offered for tab icons. The symbols are grouped by
/// theme; the picker renders each group with extra spacing between them (no
/// labels — that would cost a translation per group). Every name here is an SF
/// Symbols 4-or-earlier symbol, so it resolves on macOS 14, the deployment
/// floor. Order is stable and cosmetic only: saved icons are stored by name, so
/// regrouping never disturbs an existing choice.
enum IconCatalog {
    /// Thematic groups, rendered top-to-bottom in the picker with a gap between.
    static let groups: [[String]] = [
        // MARK: home & places
        [
            "house", "house.fill", "house.circle", "building", "building.2",
            "building.2.fill", "building.columns", "building.columns.fill",
            "map", "map.fill", "mappin", "mappin.circle", "mappin.and.ellipse",
            "location", "location.fill", "location.circle", "signpost.right",
            "globe", "bed.double", "bed.double.fill",
        ],
        // MARK: time
        [
            "clock", "clock.fill", "clock.circle", "clock.arrow.circlepath",
            "alarm", "alarm.fill", "timer", "stopwatch", "stopwatch.fill",
            "hourglass", "calendar", "calendar.circle", "calendar.badge.clock",
            "calendar.badge.plus", "deskclock", "deskclock.fill",
        ],
        // MARK: work & study
        [
            "briefcase", "briefcase.fill", "folder", "folder.fill", "tray",
            "tray.fill", "archivebox", "archivebox.fill", "doc", "doc.text",
            "doc.on.doc", "list.bullet", "checklist", "note.text", "book",
            "book.closed", "books.vertical", "graduationcap", "graduationcap.fill",
            "pencil", "paperclip", "printer", "newspaper",
        ],
        // MARK: creativity & media
        [
            "paintbrush", "paintbrush.fill", "paintbrush.pointed", "paintpalette",
            "paintpalette.fill", "pencil.tip", "scribble", "highlighter",
            "eyedropper", "camera", "photo", "photo.fill", "film", "music.note",
            "music.note.list", "music.mic", "guitars", "pianokeys", "mic",
            "headphones", "video", "wand.and.stars", "theatermasks", "scissors",
            "ruler",
        ],
        // MARK: communication
        [
            "envelope", "envelope.fill", "envelope.open", "paperplane",
            "paperplane.fill", "bubble.left", "bubble.right",
            "bubble.left.and.bubble.right", "message", "message.fill", "phone",
            "phone.fill", "bell", "bell.fill", "bell.badge", "megaphone",
            "megaphone.fill", "quote.bubble", "ellipsis.bubble", "at",
        ],
        // MARK: tech & devices
        [
            "desktopcomputer", "laptopcomputer", "display", "gauge", "keyboard",
            "computermouse", "cpu", "memorychip", "internaldrive",
            "externaldrive", "tv", "tv.fill", "gamecontroller",
            "gamecontroller.fill", "iphone", "ipad", "printer.fill", "network",
            "wifi", "antenna.radiowaves.left.and.right", "powerplug",
            "battery.100", "bolt", "bolt.fill",
        ],
        // MARK: transport
        [
            "airplane", "airplane.departure", "airplane.arrival", "airplane.circle",
            "car", "car.fill", "car.circle", "bus", "tram", "tram.fill",
            "tram.circle", "bicycle", "bicycle.circle", "scooter", "fuelpump",
            "fuelpump.fill", "figure.walk", "parkingsign",
        ],
        // MARK: nature & weather
        [
            "sun.max", "sun.max.fill", "sun.min", "sunrise", "sunset", "moon",
            "moon.fill", "moon.stars", "cloud", "cloud.fill", "cloud.rain",
            "cloud.snow", "cloud.bolt", "wind", "snowflake", "drop", "drop.fill",
            "flame", "flame.fill", "leaf", "leaf.fill", "tortoise", "hare",
            "pawprint", "pawprint.fill", "ant", "ladybug",
        ],
        // MARK: health & sport
        [
            "heart", "heart.fill", "heart.circle", "bandage", "cross", "cross.fill",
            "cross.case", "pills", "pills.fill", "waveform.path.ecg", "lungs",
            "figure.walk.circle", "figure.run", "figure.wave", "sportscourt",
            "sportscourt.fill", "soccerball", "trophy", "trophy.fill", "rosette",
        ],
        // MARK: finance & shopping
        [
            "cart", "cart.fill", "cart.circle", "bag", "bag.fill", "creditcard",
            "creditcard.fill", "banknote", "banknote.fill", "dollarsign.circle",
            "dollarsign.square", "eurosign.circle", "gift", "gift.fill", "tag",
            "tag.fill", "wallet.pass", "wallet.pass.fill", "percent", "chart.pie",
            "chart.bar", "chart.line.uptrend.xyaxis",
        ],
        // MARK: symbols & shapes
        [
            "star", "star.fill", "star.circle", "circle", "square", "triangle",
            "diamond", "hexagon", "seal", "shield", "shield.fill", "flag",
            "flag.fill", "bookmark", "bookmark.fill", "sparkles", "crown",
            "crown.fill", "checkmark.seal", "key", "key.fill", "lock", "gearshape",
            "gearshape.2", "infinity",
        ],
        // MARK: misc
        [
            "lightbulb", "lightbulb.fill", "magnifyingglass", "trash", "trash.fill",
            "cup.and.saucer", "cup.and.saucer.fill", "fork.knife", "hammer",
            "hammer.fill", "wrench.adjustable", "wrench.and.screwdriver",
            "screwdriver", "umbrella", "umbrella.fill", "suitcase", "suitcase.fill",
            "handbag", "puzzlepiece", "puzzlepiece.fill", "atom",
            "flashlight.on.fill",
        ],
    ]

    /// Flat list in group order — used wherever a single sequence is needed
    /// (the "first unused icon" pick for a new tab, membership checks).
    static let symbols: [String] = groups.flatMap { $0 }
}
