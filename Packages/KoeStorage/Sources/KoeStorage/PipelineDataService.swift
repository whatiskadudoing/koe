import Foundation

// MARK: - Pipeline Data Service

/// Centralized service for pipeline execution data management.
/// This is the single entry point for all pipeline data operations.
/// The underlying storage implementation can be swapped without changing consumers.
///
/// Features:
/// - Automatic retention policy (delete data older than X days)
/// - Configurable maximum executions limit
/// - Repository abstraction for swappable storage (JSON, SQLite, Core Data, etc.)
/// - Analytics helpers for debugging and optimization
///
/// Usage:
/// ```swift
/// // Configure retention (default: 30 days)
/// await PipelineDataService.shared.setRetentionDays(7)
///
/// // Save execution
/// await PipelineDataService.shared.save(executionData)
///
/// // Query recent
/// let recent = await PipelineDataService.shared.getRecent(limit: 10)
/// ```
public actor PipelineDataService {
    // MARK: - Singleton

    public static let shared = PipelineDataService()

    // MARK: - Dependencies

    private var repository: PipelineDataRepository

    // MARK: - Configuration

    /// Maximum number of executions to retain
    public var maxExecutions: Int = 1000

    /// Maximum age for executions (older ones are pruned)
    public var maxAge: TimeInterval = 7 * 24 * 60 * 60  // 7 days default

    /// Whether to auto-prune old executions on save
    public var autoPrune: Bool = true

    // MARK: - Initialization

    private init() {
        // Default to JSON repository
        self.repository = JSONPipelineDataRepository.shared
    }

    /// Initialize with a custom repository (for testing or alternative storage)
    public init(repository: PipelineDataRepository) {
        self.repository = repository
    }

    // MARK: - Configuration Methods

    /// Set retention period in days
    public func setRetentionDays(_ days: Int) {
        maxAge = TimeInterval(days * 24 * 60 * 60)
    }

    /// Set maximum number of executions to keep
    public func setMaxExecutions(_ count: Int) {
        maxExecutions = count
    }

    /// Enable or disable auto-pruning
    public func setAutoPrune(_ enabled: Bool) {
        autoPrune = enabled
    }

    // MARK: - Repository Swapping

    /// Change the underlying repository implementation
    /// Use this to switch between JSON, SQLite, Core Data, or remote storage
    public func setRepository(_ newRepository: PipelineDataRepository) {
        self.repository = newRepository
    }

    // MARK: - Save Operations

    /// Save a pipeline execution record
    public func save(_ execution: PipelineExecutionData) async throws {
        try await repository.save(execution)

        // Auto-prune if enabled
        if autoPrune {
            await pruneIfNeeded()
        }
    }

    /// Save with automatic enrichment of system context
    public func saveWithSystemContext(_ execution: PipelineExecutionData) async throws {
        // Create enriched execution with system info if not present
        var enrichedExecution = execution

        if execution.systemInfo == nil {
            enrichedExecution = PipelineExecutionData(
                id: execution.id,
                timestamp: execution.timestamp,
                completedAt: execution.completedAt,
                pipelineName: execution.pipelineName,
                triggerType: execution.triggerType,
                status: execution.status,
                totalDurationMs: execution.totalDurationMs,
                nodes: execution.nodes,
                originalInput: execution.originalInput,
                finalOutput: execution.finalOutput,
                error: execution.error,
                settings: execution.settings,
                subPipelineSettings: execution.subPipelineSettings,
                systemInfo: SystemContextInfo.current(),
                audioContext: execution.audioContext,
                transcriptionContext: execution.transcriptionContext,
                aiContext: execution.aiContext,
                userContext: execution.userContext,
                sessionId: execution.sessionId
            )
        }

        try await save(enrichedExecution)
    }

    // MARK: - Query Operations

    /// Get a specific execution by ID
    public func get(id: UUID) async throws -> PipelineExecutionData? {
        try await repository.load(id: id)
    }

    /// Get recent executions (most recent first)
    public func getRecent(limit: Int = 20) async throws -> [PipelineExecutionData] {
        try await repository.loadRecent(limit: limit)
    }

    /// Get executions within a date range
    public func get(from startDate: Date, to endDate: Date) async throws -> [PipelineExecutionData] {
        try await repository.load(from: startDate, to: endDate)
    }

    /// Get the most recent execution
    public func getMostRecent() async throws -> PipelineExecutionData? {
        let recent = try await repository.loadRecent(limit: 1)
        return recent.first
    }

    /// Get total count of stored executions
    public func count() async throws -> Int {
        try await repository.count()
    }

    // MARK: - Delete Operations

    /// Delete a specific execution
    public func delete(id: UUID) async throws {
        try await repository.delete(id: id)
    }

    /// Delete all executions older than a date
    public func deleteOlderThan(_ date: Date) async throws -> Int {
        try await repository.deleteOlderThan(date)
    }

    /// Clear all execution data
    public func clearAll() async throws {
        let cutoffDate = Date.distantFuture
        _ = try await repository.deleteOlderThan(cutoffDate)
    }

    // MARK: - Maintenance

    /// Prune old executions based on maxExecutions and maxAge
    public func pruneIfNeeded() async {
        do {
            // Prune by age
            let cutoffDate = Date().addingTimeInterval(-maxAge)
            let deletedByAge = try await repository.deleteOlderThan(cutoffDate)
            if deletedByAge > 0 {
                print("[PipelineDataService] Pruned \(deletedByAge) executions older than \(Int(maxAge / 86400)) days")
            }

            // Prune by count if still over limit
            let currentCount = try await repository.count()
            if currentCount > maxExecutions {
                // Load all and delete oldest ones
                let all = try await repository.loadRecent(limit: currentCount)
                let toDelete = all.suffix(currentCount - maxExecutions)
                for execution in toDelete {
                    try await repository.delete(id: execution.id)
                }
                print("[PipelineDataService] Pruned \(toDelete.count) executions to maintain limit of \(maxExecutions)")
            }
        } catch {
            print("[PipelineDataService] Prune failed: \(error)")
        }
    }

    /// Force cleanup of old data (can be called at app startup)
    public func performMaintenance() async {
        await pruneIfNeeded()
    }

    // MARK: - Analytics Helpers

    /// Get average execution duration for recent executions
    public func averageDuration(limit: Int = 100) async throws -> Double {
        let recent = try await repository.loadRecent(limit: limit)
        guard !recent.isEmpty else { return 0 }
        let total = recent.reduce(0.0) { $0 + $1.totalDurationMs }
        return total / Double(recent.count)
    }

    /// Get success rate for recent executions
    public func successRate(limit: Int = 100) async throws -> Double {
        let recent = try await repository.loadRecent(limit: limit)
        guard !recent.isEmpty else { return 0 }
        let successCount = recent.filter { $0.status == .success }.count
        return Double(successCount) / Double(recent.count)
    }

    /// Get executions grouped by status
    public func countByStatus(limit: Int = 100) async throws -> [ExecutionStatus: Int] {
        let recent = try await repository.loadRecent(limit: limit)
        var counts: [ExecutionStatus: Int] = [:]
        for execution in recent {
            counts[execution.status, default: 0] += 1
        }
        return counts
    }

    /// Get storage statistics
    public func getStorageStats() async throws -> StorageStats {
        let count = try await repository.count()
        let recent = try await repository.loadRecent(limit: count)

        let oldestDate = recent.last?.timestamp
        let newestDate = recent.first?.timestamp
        let totalDuration = recent.reduce(0.0) { $0 + $1.totalDurationMs }

        return StorageStats(
            executionCount: count,
            oldestExecutionDate: oldestDate,
            newestExecutionDate: newestDate,
            averageDurationMs: count > 0 ? totalDuration / Double(count) : 0,
            retentionDays: Int(maxAge / 86400),
            maxExecutions: maxExecutions
        )
    }
}

// MARK: - Storage Stats

/// Statistics about stored pipeline data
public struct StorageStats: Sendable {
    public let executionCount: Int
    public let oldestExecutionDate: Date?
    public let newestExecutionDate: Date?
    public let averageDurationMs: Double
    public let retentionDays: Int
    public let maxExecutions: Int

    public var summary: String {
        """
        Pipeline Data Storage:
        - Executions: \(executionCount)
        - Oldest: \(oldestExecutionDate?.description ?? "N/A")
        - Newest: \(newestExecutionDate?.description ?? "N/A")
        - Avg Duration: \(String(format: "%.0f", averageDurationMs))ms
        - Retention: \(retentionDays) days
        - Max: \(maxExecutions)
        """
    }
}
