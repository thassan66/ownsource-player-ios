import Foundation

struct ParentalControlService {
    var pin: String
    var protectedCategories: Set<String>
    var isUnlocked: Bool

    func isRestricted(_ channel: Channel) -> Bool {
        let category = channel.category.lowercased()
        let name = channel.name.lowercased()
        let sensitiveTerms = ["adult", "xxx", "18+", "18 plus", "mature"]

        return protectedCategories.contains(channel.category)
            || sensitiveTerms.contains { category.contains($0) || name.contains($0) }
    }

    func canShow(_ channel: Channel) -> Bool {
        pin.isEmpty || isUnlocked || !isRestricted(channel)
    }

    func unlock(with enteredPIN: String) -> Bool {
        !pin.isEmpty && enteredPIN == pin
    }
}

