import Foundation
import StoreKit

@MainActor
final class PurchaseManager: ObservableObject {
    static let repeatProProductID = "com.incasei4get.InCaseI4Get.pro.repeat"

    @Published private(set) var isPro: Bool
    @Published private(set) var product: Product?
    @Published private(set) var isPurchasing = false
    @Published private(set) var errorMessage: String?

    private let forcedUnlocked: Bool
    private var updatesTask: Task<Void, Never>?

    private enum PurchaseError: Error {
        case failedVerification
    }

    init() {
        forcedUnlocked = ProcessInfo.processInfo.arguments.contains("-proUnlocked")
        isPro = forcedUnlocked

        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard case .verified(let transaction) = update else { continue }
                await transaction.finish()
                await self?.refreshEntitlements()
            }
        }

        Task {
            await loadProduct()
            await refreshEntitlements()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func loadProduct() async {
        do {
            product = try await Product.products(
                for: [Self.repeatProProductID]
            ).first
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func purchasePro() async -> Bool {
        guard let product else {
            errorMessage = AppLanguage.current.text(.purchaseNotAvailable)
            return false
        }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try verified(verification)
                await transaction.finish()
                await refreshEntitlements()
                return isPro
            case .pending:
                errorMessage = AppLanguage.current.text(.purchasePending)
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        return false
    }

    func restorePurchases() async -> Bool {
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
            return isPro
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func refreshEntitlements() async {
        if forcedUnlocked {
            isPro = true
            return
        }

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == Self.repeatProProductID,
               transaction.revocationDate == nil {
                isPro = true
                return
            }
        }

        isPro = false
    }

    private func verified<T>(
        _ result: VerificationResult<T>
    ) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified:
            throw PurchaseError.failedVerification
        }
    }
}
