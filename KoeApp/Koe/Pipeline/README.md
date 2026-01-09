# Pipeline Node System

This document describes the architecture for pipeline nodes in Koe. The system provides a unified, future-proof pattern for defining, displaying, and managing pipeline nodes.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        NodeRegistry                              │
│  (Single source of truth for all node definitions)              │
│                                                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │  NodeInfo   │  │  NodeInfo   │  │  NodeInfo   │  ...        │
│  │ "recorder"  │  │"text-improve"│ │ "auto-type" │             │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
└─────────────────────────────────────────────────────────────────┘
                              │
          ┌───────────────────┼───────────────────┐
          ▼                   ▼                   ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│ NodeStateController│  │ PipelineNodeView │  │ HistoryDetailContent │
│ (Runtime state)    │  │ (Visual display) │  │ (Report display) │
└─────────────────┘  └─────────────────┘  └─────────────────┘
```

## Core Components

### 1. NodeInfo (Node Definition)

Located in: `Pipeline/NodeRegistry.swift`

`NodeInfo` is the complete definition of a node. Every node property is defined here:

```swift
struct NodeInfo {
    // Identity
    let typeId: String           // Unique identifier (e.g., "text-improve")
    let displayName: String      // UI label (e.g., "Improve")
    let icon: String             // SF Symbol name (e.g., "sparkles")
    let color: Color             // Theme color

    // State Behavior
    let isUserToggleable: Bool   // Can user toggle on/off?
    let isAlwaysEnabled: Bool    // Core functionality that can't be disabled?
    let requiredNodes: [String]  // Dependencies (other nodes that must be enabled)
    let dimsWhenRunning: [String] // Nodes to dim when this is running (mutual exclusion)

    // Report Behavior
    let outputType: NodeOutputType  // What kind of output (.text, .audio, .none, .custom)
    let inputDescription: String    // Description in reports (e.g., "Raw transcription")
    let isAction: Bool              // Is this a side effect (vs transformation)?
    let actionDescription: String?  // What the action does (e.g., "Typed to active window")
    let showsComparison: Bool       // Show before/after in reports?

    // Settings
    let hasSettings: Bool           // Does this node have a settings panel?
    let persistenceKey: String?     // UserDefaults key for enabled state
}
```

### 2. NodeRegistry (Central Registry)

Located in: `Pipeline/NodeRegistry.swift`

The registry is the **single source of truth** for all node definitions. Both UI components and report views look up nodes here.

```swift
// Access the shared registry
let registry = NodeRegistry.shared

// Look up a node
let nodeInfo = registry.nodeOrDefault(for: "text-improve")
print(nodeInfo.displayName)  // "Improve"
print(nodeInfo.icon)         // "sparkles"

// Get all toggleable nodes
let toggleable = registry.toggleableNodes
```

### 3. NodeStateController (Runtime State)

Located in: `Pipeline/NodeStateController.swift`

Manages runtime state for nodes - toggle states, dependencies, and mutual exclusion.

```swift
// Create a controller for the pipeline
let controller = NodeStateController.forPipeline(appState: appState)

// Check if a node is enabled
if controller.isEnabled(.improve) { ... }

// Get a SwiftUI binding
let binding = controller.binding(for: .voiceTrigger)

// Toggle a node
controller.toggle(.autoEnter)

// Get full state (for complex UI logic)
let state = controller.state(for: .voiceTrigger)
print(state.isToggledOn)        // User's preference
print(state.requirementsMet)     // Dependencies satisfied?
print(state.isTemporarilyDimmed) // Another node is running?
print(state.opacity)             // Computed opacity for UI
```

### 4. NodeToggleIndicator (UI Component)

Located in: `KoeUI/Components/NodeToggle.swift`

A reusable toggle indicator for nodes. Shows as a small colored dot that can be clicked.

```swift
// In a node view
NodeToggleIndicator(
    isOn: $isEnabled,
    size: 10,
    onColor: .green,
    offColor: .gray
)
```

## How to Add a New Node

### Step 1: Define the Node in NodeRegistry

Add a new `NodeInfo` to `registerBuiltInNodes()`:

```swift
NodeInfo(
    typeId: "my-new-node",              // Unique identifier
    displayName: "My New Node",          // Display name
    icon: "wand.and.stars",              // SF Symbol
    color: .purple,                      // Theme color
    isUserToggleable: true,              // User can toggle
    isAlwaysEnabled: false,              // Not core functionality
    requiredNodes: ["transcribe"],       // Requires transcribe to be enabled
    dimsWhenRunning: [],                 // No mutual exclusion
    outputType: .text,                   // Produces text output
    inputDescription: "Transcribed text", // Input description in reports
    isAction: false,                     // Transforms data (not a side effect)
    actionDescription: nil,              // N/A for non-actions
    showsComparison: true,               // Show before/after
    hasSettings: true,                   // Has settings panel
    persistenceKey: "isMyNewNodeEnabled" // UserDefaults key
)
```

### Step 2: Add to PipelineStageInfo (if visual)

If the node appears in the pipeline strip, add it to the enum:

```swift
// In PipelineStageInfo.swift
enum PipelineStageInfo: String, CaseIterable, Identifiable {
    // ... existing cases ...
    case myNewNode
}

// Add to registryTypeId mapping
private var registryTypeId: String {
    switch self {
    // ... existing cases ...
    case .myNewNode: return "my-new-node"
    }
}
```

### Step 3: Add State Persistence (if toggleable)

In `NodeStateController.forPipeline()`:

```swift
getPersistedState: { node in
    switch node {
    // ... existing cases ...
    case .myNewNode: return appState.isMyNewNodeEnabled
    }
},
setPersistedState: { node, enabled in
    switch node {
    // ... existing cases ...
    case .myNewNode: appState.isMyNewNodeEnabled = enabled
    }
}
```

And add the property to `AppState.swift`:

```swift
public var isMyNewNodeEnabled: Bool = false {
    didSet {
        UserDefaults.standard.set(isMyNewNodeEnabled, forKey: "isMyNewNodeEnabled")
    }
}
```

### Step 4: Implement the Pipeline Element

In `KoePipeline`, implement the actual processing:

```swift
public final class MyNewNodeStage: PipelineStage {
    public let stageTypeId = "my-new-node"
    public let displayName = "My New Node"
    public let description = "Does something cool"
    public let icon = "wand.and.stars"

    public func process(_ context: PipelineContext) async throws {
        // Your processing logic here
    }
}
```

## Node Types

### Triggers
Nodes that start the pipeline. Mutually exclusive at runtime (only one can be active).

- `hotkey-trigger` - Keyboard shortcut
- `voice-trigger` - Voice command detection

### Processing Stages
Nodes that transform data.

- `recorder` - Captures audio
- `transcribe` - Converts audio to text
- `text-improve` - AI text refinement

### Actions
Nodes that perform side effects (no output transformation).

- `auto-type` - Types text to active window
- `auto-enter` - Presses Enter key

## Output Types

```swift
enum NodeOutputType {
    case text      // Produces text (most common)
    case audio     // Produces audio (waveform display)
    case none      // No output (actions)
    case custom(String)  // Custom rendering
}
```

## Best Practices

1. **Always define nodes in NodeRegistry** - This is the single source of truth
2. **Use meaningful typeIds** - They're used for persistence and metrics
3. **Set appropriate outputType** - Determines how reports display the node
4. **Define relationships** - Use `requiredNodes` and `dimsWhenRunning` for dependencies
5. **Use persistenceKey** - For nodes that can be toggled, so state persists across launches

## File Locations

| File | Purpose |
|------|---------|
| `Pipeline/NodeRegistry.swift` | Node definitions and registry |
| `Pipeline/NodeStateController.swift` | Runtime state management |
| `Pipeline/PipelineNodeView.swift` | Visual node component |
| `Pipeline/PipelineStripView.swift` | Pipeline visualization |
| `Pipeline/PipelineStageInfo.swift` | Stage enum for UI |
| `KoeUI/Components/NodeToggle.swift` | Toggle indicator component |
