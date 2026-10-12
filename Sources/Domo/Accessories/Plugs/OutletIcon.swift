import AppKit

/// Microsoft's Fluent Emoji 3D icons (MIT), picked from an outlet's name.
/// Raw values are the file names in Resources/Icons.
enum OutletIcon: String, CaseIterable, Identifiable {
    case plug = "electric_plug"
    case television
    case speaker = "speaker_high_volume"
    case soundbar = "radio"
    case headphones = "headphone"
    case gameConsole = "video_game"
    case monitor = "desktop_computer"
    case laptop
    case light = "light_bulb"
    case charger = "battery"
    case phone = "mobile_phone"
    case watch
    case router = "antenna_bars"
    case audioGear = "control_knobs"
    case printer
    case coffee = "hot_beverage"
    case kettle = "teapot"
    case heater = "fire"
    case fan = "wind_face"
    case humidifier = "droplet"
    case cooler = "snowflake"
    case aquarium = "tropical_fish"
    case plant = "potted_plant"
    case tree = "christmas_tree"
    case camera
    case vacuum = "robot"
    case pet = "cat"
    case clock = "alarm_clock"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plug: "Plug"
        case .television: "TV"
        case .speaker: "Speaker"
        case .soundbar: "Sound Bar"
        case .headphones: "Headphones"
        case .gameConsole: "Game Console"
        case .monitor: "Monitor"
        case .laptop: "Laptop"
        case .light: "Light"
        case .charger: "Charger"
        case .phone: "Phone"
        case .watch: "Watch"
        case .router: "Router"
        case .audioGear: "Audio Gear"
        case .printer: "Printer"
        case .coffee: "Coffee"
        case .kettle: "Kettle"
        case .heater: "Heater"
        case .fan: "Fan"
        case .humidifier: "Humidifier"
        case .cooler: "Cooler"
        case .aquarium: "Aquarium"
        case .plant: "Plant"
        case .tree: "Christmas Tree"
        case .camera: "Camera"
        case .vacuum: "Vacuum"
        case .pet: "Pet"
        case .clock: "Clock"
        }
    }

    /// English and Turkish, folded (lowercase, no diacritics). Checked in
    /// this order, so "sound bar" wins over "sound" and "macbook" over "mac".
    private static let keywords: [(OutletIcon, [String])] = [
        (.soundbar, ["soundbar", "sound bar", "ses cubugu"]),
        (.gameConsole, ["playstation", "ps5", "ps4", "xbox", "nintendo", "konsol", "console", "oyun", "game"]),
        // Before desks and screens: "Desk Light" and "Monitor Light Bar" are lights.
        (.light, ["light", "lamp", "lamba", "isik", "abajur", "ampul", "avize", "led", "aydinlatma", "spot", "strip"]),
        (.monitor, ["monitor", "ekran", "display", "desktop", "imac", "mac mini", "bilgisayar", "computer", "pc"]),
        (.laptop, ["macbook", "laptop", "notebook", "dizustu", "desk", "masa"]),
        (.television, ["televizyon", "television", "apple tv", "tv"]),
        (.headphones, ["kulaklik", "headphone", "headset"]),
        (.speaker, ["subwoofer", "speaker", "hoparlor", "homepod", "sonos", "amfi", "anfi", "amp", "sound", "ses", "audio"]),
        (.audioGear, ["mixer", "dac", "interface", "studio"]),
        (.router, ["modem", "router", "wifi", "wi-fi", "internet", "mesh", "network", "ag"]),
        (.charger, ["type-c", "typec", "type c", "usb-c", "usbc", "sarj", "charger", "charging", "adapter", "adaptor"]),
        (.watch, ["watch", "saat sarj"]),
        (.phone, ["usb", "telefon", "phone", "iphone", "ipad", "tablet"]),
        (.printer, ["printer", "yazici", "3d"]),
        (.coffee, ["kahve", "coffee", "espresso", "nespresso"]),
        (.kettle, ["kettle", "su isitici", "cay", "demlik"]),
        (.heater, ["isitici", "heater", "soba", "radyator", "kalorifer"]),
        (.fan, ["vantilator", "fan", "air purifier", "hava temizleyici", "purifier"]),
        (.humidifier, ["nemlendirici", "humidifier", "nem alici", "dehumidifier"]),
        (.cooler, ["klima", "air conditioner", "cooler", "buzdolabi", "fridge", "freezer"]),
        (.aquarium, ["akvaryum", "aquarium", "balik"]),
        (.tree, ["yilbasi", "christmas", "agac"]),
        (.plant, ["bitki", "plant", "saksi", "cicek", "grow"]),
        (.camera, ["kamera", "camera", "cam"]),
        (.vacuum, ["supurge", "vacuum", "roborock", "robot"]),
        (.pet, ["kedi", "kopek", "mama", "cat", "dog", "pet", "feeder"]),
        (.clock, ["saat", "clock", "alarm"]),
    ]

    /// Best match for a name; falls back to a plug (or a charger for USB).
    static func guess(for name: String, isUSB: Bool) -> OutletIcon {
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr"))
            .replacingOccurrences(of: "ı", with: "i")
        let words = Set(folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        for (icon, terms) in keywords {
            // Short terms ("tv", "ag", "pc") must be whole words; longer ones can sit inside a word.
            if terms.contains(where: { $0.count <= 3 ? words.contains($0) : folded.contains($0) }) {
                return icon
            }
        }
        return isUSB ? .charger : .plug
    }

    private static var cache: [OutletIcon: NSImage] = [:]

    var image: NSImage? {
        if let cached = Self.cache[self] { return cached }
        let image = Bundle.main.url(forResource: rawValue, withExtension: "png", subdirectory: "Icons")
            .flatMap(NSImage.init(contentsOf:))
        Self.cache[self] = image
        return image
    }
}
