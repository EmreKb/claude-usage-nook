import Foundation
import Observation

@MainActor
@Observable
final class UsageModel {
    static let refreshInterval: Duration = .seconds(180)

    private(set) var limits: [UsageLimit] = []
    private(set) var errorMessage: String?
    private(set) var lastUpdated: Date?
    private(set) var isLoading = false

    private var pollingTask: Task<Void, Never>?

    func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: UsageModel.refreshInterval)
            }
        }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let credential = try await Task.detached { try CredentialStore.loadCredential() }.value
            limits = try await UsageClient.fetchLimits(using: credential)
            errorMessage = nil
            lastUpdated = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
