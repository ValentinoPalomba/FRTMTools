import Foundation

extension IPAToolStoreApp {
    var priceString: String? {
        guard let price else { return nil }
        if price == 0 {
            return "Free"
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        if #available(macOS 13.0, *) {
            formatter.currencyCode = Locale.current.currency?.identifier ?? Locale.current.currency?.identifier ?? "USD"
        } else {
            formatter.currencyCode = Locale.current.currencyCode ?? "USD"
        }
        return formatter.string(from: NSNumber(value: price))
    }
}
