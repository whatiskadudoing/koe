// KoeModels - Centralized model management for Koe
//
// This package provides:
// - Model definitions and registry
// - Model download management with progress tracking
// - Bundled vs downloaded model detection
//
// Usage:
//   let manager = ModelManager.shared
//   await manager.checkAllModels()
//   if !manager.areRequiredModelsAvailable {
//       try await manager.downloadRequiredModels()
//   }

import Foundation

// Re-export all public types
public typealias KoeModelDefinition = ModelDefinition
public typealias KoeModelStatus = ModelStatus
public typealias KoeModelCategory = ModelCategory
public typealias KoeModelSource = ModelSource
