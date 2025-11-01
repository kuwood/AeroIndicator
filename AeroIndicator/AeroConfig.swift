import Foundation
import Toml

func readConfigFile() -> String? {
    let fileManager = FileManager.default
    let homeDirectory = fileManager.homeDirectoryForCurrentUser.path
    let configPath = "\(homeDirectory)/.config/aeroIndicator/config.toml"
    let path = URL(fileURLWithPath: configPath)
    do {
        let content = try String(contentsOf: path, encoding: .utf8)
        return content
    } catch {
        print("Error reading config file: \(error)")
        return nil
    }
}

let defaultConfig = AeroConfig(
    source: "aerospace",
    position: "bottom-left",
    outerPadding: 20,
    innerPadding: 12,
    borderRadius: 12,
    fontSize: nil,
    iconSize: 16
)

func readConfig() -> AeroConfig {
    guard let configString = readConfigFile() else { return defaultConfig }
    let config = try? Toml(withString: configString)

    let source = config?.string("source") ?? defaultConfig.source
    let position = config?.string("position") ?? defaultConfig.position
    let outerPadding = config?.doubleInt("outer-padding") ?? defaultConfig.outerPadding
    let innerPadding = config?.doubleInt("inner-padding") ?? defaultConfig.innerPadding
    let borderRadius = config?.doubleInt("border-radius") ?? defaultConfig.borderRadius
    let fontSize = config?.doubleInt("font-size") ?? defaultConfig.fontSize
    let iconSize = config?.doubleInt("icon-size") ?? defaultConfig.iconSize

    // Security: Validate source is one of the allowed values
    let validSources = ["aerospace", "yabai"]
    let validatedSource = validSources.contains(source) ? source : defaultConfig.source

    // Security: Validate position is one of the allowed values
    let validPositions = ["bottom-left", "bottom-center", "bottom-right", "top-left", "top-center", "top-right", "center"]
    let validatedPosition = validPositions.contains(position) ? position : defaultConfig.position

    return AeroConfig(
        source: validatedSource,
        position: validatedPosition,
        outerPadding: outerPadding,
        innerPadding: innerPadding,
        borderRadius: borderRadius,
        fontSize: fontSize,
        iconSize: iconSize
    )
}

struct AeroConfig {
    var source: String
    var position: String
    var outerPadding: Double
    var innerPadding: Double
    var borderRadius: Double
    var fontSize: Double?
    var iconSize: Double
}

extension Toml {
    func doubleInt(_ key: String) -> Double? {
        if let doubleResult = self.double(key) {
            return doubleResult
        }
        if let intResult = self.int(key) {
            return Double(intResult)
        }
        return nil
    }
}
