import Foundation
import Darwin

/// Detects system hardware capabilities for automatic model selection.
/// Uses sysctlbyname for hardware detection following IINA/Aerial patterns.
/// Reference: https://github.com/iina/iina/blob/develop/iina/Sysctl.swift
struct SystemCapabilities {
    
    // MARK: - Singleton
    
    /// Cached system capabilities - hardware doesn't change during app lifetime.
    /// Pattern: ProcessInfo.processInfo, FileManager.default
    static let current = detect()
    
    // MARK: - Types
    
    /// Chip type for model capability mapping.
    /// Distinguishes Apple Silicon generations from Intel.
    enum ChipGeneration: String {
        case m1 = "M1"
        case m2 = "M2"
        case m3 = "M3"
        case m4 = "M4"
        case intel = "Intel"  // Intel Macs - no Neural Engine
        case unknown = "Unknown"
        
        /// Whether this is Apple Silicon (has Neural Engine for fast inference)
        var isAppleSilicon: Bool {
            switch self {
            case .m1, .m2, .m3, .m4: return true
            case .intel, .unknown: return false
            }
        }
    }
    
    // MARK: - Properties
    
    /// System RAM in gigabytes (rounded)
    let ramGB: Int
    
    /// Detected chip generation
    let chipGeneration: ChipGeneration
    
    /// Whether system language is English (for .en model selection)
    let isEnglishSystem: Bool
    
    // MARK: - Computed Properties
    
    /// Returns the recommended model tier based on hardware capabilities.
    /// Separates hardware capability from language selection for flexibility.
    ///
    /// Matrix:
    /// - <8GB RAM: tiny tier
    /// - 8GB + M1/M2: base tier
    /// - 8GB + M3+: large tier
    /// - 16GB+: large tier
    /// - Intel Macs: base tier max (no Neural Engine)
    var recommendedTier: PredefinedModels.ModelTier {
        // Under 8GB: tiny tier
        if ramGB < 8 {
            return .tiny
        }
        
        // Intel Macs: cap at base tier (no Neural Engine for fast inference)
        if chipGeneration == .intel || !chipGeneration.isAppleSilicon {
            return .base
        }
        
        // 8GB with M1/M2: base tier
        if ramGB < 16 && (chipGeneration == .m1 || chipGeneration == .m2) {
            return .base
        }
        
        // 8GB with M3+ or 16GB+: large tier
        return .large
    }
    
    /// Returns the recommended model name based on hardware and user's language setting.
    /// - Parameter language: User's selected language code (e.g., "en", "es", "auto")
    /// - Returns: Model name optimized for this language and hardware
    func recommendedModelName(forLanguage language: String) -> String {
        let model = PredefinedModels.recommendedModel(forLanguage: language, tier: recommendedTier)
        return model.name
    }
    
    /// Returns the recommended model name using system language.
    /// Convenience property for backward compatibility.
    var recommendedModelName: String {
        recommendedModelName(forLanguage: isEnglishSystem ? "en" : "auto")
    }
    
    // MARK: - Factory Method
    
    /// Detects current system capabilities.
    /// - Returns: SystemCapabilities with detected RAM, chip, and language.
    static func detect() -> SystemCapabilities {
        let ramGB = detectRAM()
        let chipGeneration = detectChipGeneration()
        let isEnglishSystem = detectIsEnglishSystem()
        
        return SystemCapabilities(
            ramGB: ramGB,
            chipGeneration: chipGeneration,
            isEnglishSystem: isEnglishSystem
        )
    }
    
    // MARK: - Private Detection Methods
    
    /// Detects system RAM in gigabytes.
    /// Reference: https://github.com/huggingface/swift-coreml-diffusers/blob/main/Diffusion/DiffusionApp.swift
    private static func detectRAM() -> Int {
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        // Convert bytes to GB (rounded)
        return Int(physicalMemory / (1024 * 1024 * 1024))
    }
    
    /// Detects chip generation from hardware model.
    /// Reference: https://github.com/JohnCoates/Aerial/blob/master/Aerial/Source/Models/Hardware/HardwareDetection.swift
    private static func detectChipGeneration() -> ChipGeneration {
        guard let model = sysctlString(for: "hw.model") else {
            return .unknown
        }
        
        // Mac model identifiers map to chip generations:
        // Mac14,x = M2 (2022-2023)
        // Mac15,x = M3 (2023-2024)
        // Mac16,x = M4 (2024+)
        // Earlier Mac13,x and some Mac14 = M1
        
        // Also check machdep.cpu.brand_string for direct chip info
        // Reference: https://github.com/RunanywhereAI/runanywhere-sdks
        if let cpuBrand = sysctlString(for: "machdep.cpu.brand_string") {
            if cpuBrand.contains("M4") { return .m4 }
            if cpuBrand.contains("M3") { return .m3 }
            if cpuBrand.contains("M2") { return .m2 }
            if cpuBrand.contains("M1") { return .m1 }
            if cpuBrand.contains("Intel") { return .intel }
        }
        
        // Fallback: parse model identifier
        // Reference: https://github.com/Lessica/Reveil/blob/main/Reveil/ViewModels/Modules/CPUInformation.swift
        if model.hasPrefix("Mac16") { return .m4 }
        if model.hasPrefix("Mac15") { return .m3 }
        if model.hasPrefix("Mac14") {
            // Mac14,2 = M2 MacBook Air, Mac14,3 = M2 Pro, etc.
            // Some Mac14 models are M2, some edge cases exist
            return .m2
        }
        if model.hasPrefix("Mac13") { return .m1 }
        
        // Virtual machines or older Macs
        return .unknown
    }
    
    /// Detects whether the system language is English.
    /// Used to select .en models (more accurate for English) vs multilingual models.
    private static func detectIsEnglishSystem() -> Bool {
        guard let preferred = Locale.preferredLanguages.first else {
            return true // Default to English
        }
        let languageCode = Locale(identifier: preferred).language.languageCode?.identifier ?? "en"
        return languageCode == "en"
    }
    
    /// Reads a string value from sysctl.
    /// Reference: https://github.com/iina/iina/blob/develop/iina/Sysctl.swift
    private static func sysctlString(for name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0 else {
            return nil
        }
        
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else {
            return nil
        }
        
        return String(cString: value)
    }
}

// MARK: - Debug Description

extension SystemCapabilities: CustomDebugStringConvertible {
    var debugDescription: String {
        "SystemCapabilities(ramGB: \(ramGB), chip: \(chipGeneration.rawValue), english: \(isEnglishSystem), recommended: \(recommendedModelName))"
    }
}
