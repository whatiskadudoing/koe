// KoeRefinement - AI text refinement services for Koe (声)
//
// This package provides text refinement using local LLMs:
// - AIService: Main entry point for AI text processing
// - AIProvider: Protocol for AI backends
// - LlamaCppProvider: Embedded llama.cpp for offline AI
// - OllamaRefinementService: Uses Ollama for custom models
//
// Supports multiple quality tiers:
// - Fast: Bundled model, works offline immediately (~500MB)
// - Smart: Downloaded model, better quality (~2GB)
// - Best: Larger model, highest quality (~4GB)
// - Custom: Use Ollama with any model

// Re-export public types
@_exported import KoeDomain
