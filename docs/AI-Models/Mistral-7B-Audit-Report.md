# Mistral 7B - Model Audit Report

**Date**: January 2026
**Model**: `mistral:7b` via Ollama
**Purpose**: AI Processing node for Koe voice-to-text app
**Current Implementation**: Translation node

---

## Table of Contents

1. [Model Overview](#model-overview)
2. [Testing Methodology](#testing-methodology)
3. [Capability Audit Results](#capability-audit-results)
4. [Combination Tests](#combination-tests)
5. [Recommended Use Cases](#recommended-use-cases)
6. [Implementation Details](#implementation-details)
7. [Prompting Best Practices](#prompting-best-practices)
8. [Resources & References](#resources--references)

---

## Model Overview

### What is Mistral 7B?

Mistral 7B is a 7-billion parameter language model released by Mistral AI in September 2023. Despite its smaller size, it outperforms larger models like LLaMA 2 13B across multiple benchmarks.

### Key Technical Features

| Feature | Description |
|---------|-------------|
| **Parameters** | 7 billion |
| **Architecture** | Transformer with GQA + SWA |
| **Context Length** | ~32K tokens (up to 131K with sliding window) |
| **License** | Apache 2.0 (fully open source) |
| **Size on Disk** | ~4 GB (quantized) |

### Architecture Innovations

1. **Grouped-Query Attention (GQA)**: Faster inference by sharing key-value heads
2. **Sliding Window Attention (SWA)**: Efficient handling of long sequences
3. **Optimized for Real-Time**: Low latency suitable for dictation apps

---

## Testing Methodology

### Test Environment

```
Platform: macOS (Apple Silicon)
Ollama Version: Latest
Model: mistral:7b
Temperature: 0 (deterministic output)
API Endpoint: http://localhost:11434/api/generate
```

### Test Approach

Each capability was tested with **3+ different examples** using curl commands against the Ollama API:

```bash
curl -s http://localhost:11434/api/generate -d '{
  "model": "mistral:7b",
  "prompt": "[INST] <instruction> [/INST]",
  "stream": false,
  "options": {"temperature": 0}
}' | jq -r '.response'
```

### Prompt Format

Mistral 7B uses the `[INST]...[/INST]` format for instruction following:

```
[INST] Your instruction here. Output ONLY the result. [/INST]
```

**Key insight**: Adding "Output ONLY the [result type]" significantly reduces unwanted explanations.

---

## Capability Audit Results

### 1. Translation

**Rating**: ⭐⭐⭐⭐⭐ EXCELLENT

| Language | Input | Output | Status |
|----------|-------|--------|--------|
| Spanish | "Hello, how are you today?" | "Hola, ¿cómo estás hoy?" | ✅ |
| German | "I would like to order a coffee and a croissant" | "Ich möchte bitte einen Kaffee und eine Croissant bestellen" | ✅ |
| French | "The restaurant is closed on Sundays" | "Le restaurant est fermé les dimanches" | ✅ |
| Chinese | "Thank you for your help" | "谢谢您的帮助。真是很感激。" | ✅ |
| Portuguese | "I need to schedule a meeting" | "Preciso agendar uma reunião" | ✅ |
| Japanese | "The weather is beautiful today" | "今日天気は美しいです" | ✅ |

**Conclusion**: Translation is highly reliable and the primary recommended use case.

---

### 2. Code Generation

**Rating**: ⭐⭐⭐⭐⭐ EXCELLENT

| Test | Language | Description | Status |
|------|----------|-------------|--------|
| Prime checker | Python | Optimized algorithm with edge cases | ✅ |
| Factorial | JavaScript | Correct recursive implementation | ✅ |
| Sort dictionaries | Python | Proper lambda with sorted() | ✅ |
| String reverse | Swift | Idiomatic Swift using reversed() | ✅ |
| SQL query | SQL | Correct JOIN, GROUP BY, ORDER BY, LIMIT | ✅ |

**Sample Output** (Python prime checker):
```python
def is_prime(n):
    if n <= 1:
        return False
    elif n <= 3:
        return True
    elif n % 2 == 0 or n % 3 == 0:
        return False
    i = 5
    while i * i <= n:
        if n % i == 0 or n % (i + 2) == 0:
            return False
        i += 6
    return True
```

**Conclusion**: Produces working, idiomatic code across multiple languages.

---

### 3. Grammar & Text Cleanup

**Rating**: ⭐⭐⭐⭐⭐ EXCELLENT

| Test | Input Problem | Output | Status |
|------|---------------|--------|--------|
| Filler words | "so like um I was thinking that maybe we should you know go..." | "Let's go to the store and buy some groceries as we're running low on food." | ✅ |
| Punctuation | "i went to the store yesterday and bought apples oranges..." | "I went to the store yesterday and bought apples, oranges, bananas, and grapes. Then I went home and made a fruit salad; it was delicious." | ✅ |
| Spelling | "Their going to the libary tommorow becuase..." | "They're going to the library tomorrow because they need to study for their exams which are next week." | ✅ |

**Conclusion**: Excellent for cleaning up dictation output - removes filler words, fixes grammar, adds punctuation.

---

### 4. Summarization

**Rating**: ⭐⭐⭐⭐ VERY GOOD

| Test | Task | Result |
|------|------|--------|
| One sentence summary | Product announcement | Concise, captured key points |
| Bullet points | Sales report | Clean 3-bullet summary |
| Action items extraction | Meeting notes | Extracted all 4 action items correctly |

**Sample Output** (Action items):
```
* John will handle the client presentation by Friday
* Sarah needs to review the budget proposal and send feedback by Wednesday
* The development team should complete the API integration by end of month
* Mike will schedule a follow-up meeting for next Tuesday
```

**Conclusion**: Very good at summarization, occasionally verbose but accurate.

---

### 5. Format Conversion

**Rating**: ⭐⭐⭐⭐⭐ EXCELLENT

| Conversion | Status | Notes |
|------------|--------|-------|
| Text → Numbered list | ✅ | Clean step-by-step format |
| Text → JSON | ✅ | Valid, properly structured JSON |
| Text → Markdown table | ✅ | Correct table syntax |
| Text → Bullet points | ✅ | Clean bullet format |

**Sample Output** (JSON):
```json
{
  "name": "John Smith",
  "age": 35,
  "job_title": "software engineer",
  "company": "Google",
  "location": "San Francisco"
}
```

**Conclusion**: Handles structured output very well.

---

### 6. Tone Adjustment

**Rating**: ⭐⭐⭐⭐ VERY GOOD

| Test | Direction | Result |
|------|-----------|--------|
| Casual → Formal | ✅ | Professional business tone |
| Formal → Casual | ✅ | Friendly tone, added emoji |
| Rude → Polite | ✅ | Diplomatic rewrite |

**Caveat**: Tends to over-expand text (single sentence can become full email). Best used with explicit length constraints.

---

### 7. Math Reasoning

**Rating**: ⭐⭐⭐⭐⭐ EXCELLENT

| Problem | Answer | Status |
|---------|--------|--------|
| $2 × 15 apples, change from $50 | $20 | ✅ Correct |
| 25% off $80 | $60 | ✅ Correct |
| "5 machines, 5 minutes, 5 widgets" puzzle | 5 minutes | ✅ Correct (tricky!) |

**Conclusion**: Surprisingly strong math reasoning, including logic puzzles.

---

## Combination Tests

Testing whether Mistral 7B can handle **multiple chained operations** in a single prompt - combining cleanup, translation, formatting, and tone adjustment.

### Test Results

#### Basic Combinations (2 operations)

| Test | Operations | Input | Output | Status |
|------|------------|-------|--------|--------|
| Translate + Summarize | Condense → Spanish | Long meeting notes | "Resumen: Hoy se discutió una extensa reunión sobre el lanzamiento..." | ✅ |
| Cleanup + Translate | Remove fillers → Portuguese | "so um like I was thinking..." | "Agenda uma reunião para a semana próxima..." | ✅ |
| Action Items + Translate | Extract → German | Meeting notes | "1. John muss den Bericht bis Freitag beenden..." | ✅ |
| Summarize + Bullets + Translate | Condense → List → Spanish | Product announcement | Clean Spanish bullet points | ✅ |

#### Advanced Combinations (3+ operations)

| Test | Operations | Result | Status |
|------|------------|--------|--------|
| Cleanup + Formal + Translate | Remove fillers → Professional tone → French | "Le rapport est terminé et je pense qu'il est de bonne qualité." | ✅ |
| Cleanup + Summarize + Formal + Translate | 4 operations → Portuguese | Works but slightly verbose | ⚠️ |

### Format Conversion Combinations

| Test | Input Type | Output Format | Result | Status |
|------|------------|---------------|--------|--------|
| **Dictation → Email** | Casual spoken text | Professional email | Full email with subject, greeting, body, signature | ✅ |
| **Dictation → Slack** | Messy dictation | Brief casual message | "Hey there! Finished the code review, but found a few issues..." | ✅ |
| **Dictation → Git Commit** | Spoken description | Conventional commit | "feat: Added notification preference button..." | ✅ |
| **Dictation → JIRA Ticket** | Meeting notes | Full ticket format | Title, Description, Acceptance Criteria, Priority | ✅ |
| **Translate → Email** | Casual English | Spanish formal email | "Estimado(a), Le informo que la reunión ha sido reprogramada..." | ✅ |

### AI Prompt Enhancement

| Test | Input | Output | Status |
|------|-------|--------|--------|
| **Vague → Specific Prompt** | "write me a landing page" | Detailed 9-point specification with expected outputs and constraints | ✅ |
| **Messy → Clear Prompt** | "um so like I want you to help me write like a function that um..." | "Write a Python function named `find_numbers_above_threshold`..." | ✅ |
| **Vague → Technical Spec** | "make the app faster" | Comprehensive 9-section optimization specification | ✅ |

### Sample Outputs

#### Dictation → Slack Message
```
Input:  "um hey so like I finished the code review and uh there are a few
        things that need to be fixed before we can merge it you know like
        the error handling is missing and also um the tests are failing"

Output: "Hey there! Finished the code review, but found a few issues before
        merging. Missing error handling and tests are currently failing.
        Let's sort it out!"
```

#### Dictation → Git Commit
```
Input:  "so I added a new button to the settings page that lets users um
        you know change their notification preferences and I also fixed
        a bug where the app would crash when you clicked save without
        entering anything"

Output: "feat: Added notification preference button to settings page
        fix: Fixed app crash when saving without entry"
```

#### Dictation → JIRA Ticket
```
Input:  "users are complaining that the search is too slow especially when
        there are lots of results and we need to add pagination and maybe
        some caching to fix it this is blocking several customers"

Output:
Title: Implement Pagination and Caching for Search Functionality

Description: Users have reported slow search performance, particularly
when dealing with large result sets. This issue is affecting multiple
customers and hindering their productivity.

Acceptance Criteria:
1. Pagination should be added to the search results
2. Caching mechanism should be implemented
3. Performance tests should confirm improvement
4. Documentation should be provided

Priority: High (Blocker)
```

#### Messy Request → AI Prompt
```
Input:  "um so like I want you to help me write like a function that um
        you know takes a list of numbers and like finds the ones that
        are bigger than um like some threshold value you know"

Output: "Write a Python function named `find_numbers_above_threshold`
        that accepts a list of numbers as an argument. The function
        should return a new list containing only the numbers from the
        input list that are greater than a specified threshold value."
```

### Key Findings

#### Optimal Pipeline Length

| Operations | Quality | Recommendation |
|------------|---------|----------------|
| 2 operations | ⭐⭐⭐⭐⭐ Excellent | Ideal for most use cases |
| 3 operations | ⭐⭐⭐⭐ Very Good | Works well with clear instructions |
| 4+ operations | ⭐⭐⭐ Good | Quality degrades, may be verbose |

**Sweet spot**: `[Cleanup] + [One Transform] + [Translate]`

#### Best Combination Patterns

```
DICTATION → [Cleanup] → [Format] → [Optional: Translate] → OUTPUT

Recommended flows:
1. Voice → Clean → Email format
2. Voice → Clean → Slack message
3. Voice → Clean → Git commit
4. Voice → Clean → JIRA ticket
5. Voice → Clean → Translate → Target language
6. Voice → Clean → Summarize → Bullets
7. Voice → Clean → Improve as AI prompt
```

### Suggested Multi-Mode Node Design

Based on combination tests, the Translate node could support multiple modes:

| Mode | Pipeline | Best For |
|------|----------|----------|
| **Translate** | Clean → Translate to X | International communication |
| **Email** | Clean → Formal → Email format | Professional emails |
| **Slack** | Clean → Casual → Brief | Quick team messages |
| **Commit** | Clean → Conventional commits | Developer workflow |
| **JIRA** | Clean → Extract → Ticket format | Meeting notes to tickets |
| **Prompt** | Clean → Improve specificity | Better AI interactions |
| **Summary** | Clean → Summarize → Bullets | Quick overviews |

### Prompt Templates for Combinations

#### Cleanup + Translate
```
[INST] First fix the grammar and remove filler words, then translate to {language}.
Output ONLY the final {language} text.

Text: {input_text} [/INST]
```

#### Dictation → Email
```
[INST] Convert this spoken dictation into a professional email.
Fix grammar, add proper formatting. Output ONLY the email.

Text: {input_text} [/INST]
```

#### Dictation → Slack
```
[INST] Convert this to a brief Slack message. Keep it casual but clear.
Remove filler words. Output ONLY the message.

Text: {input_text} [/INST]
```

#### Dictation → Git Commit
```
[INST] Convert this spoken description into a proper git commit message.
Use conventional commits format (feat/fix/refactor). Output ONLY the commit message.

Text: {input_text} [/INST]
```

#### Prompt Improver
```
[INST] Improve this AI prompt to be more specific and effective.
Add clear instructions, expected output format, and constraints.
Output ONLY the improved prompt.

Text: {input_text} [/INST]
```

---

## Recommended Use Cases

### Best For (Koe App)

| Use Case | Priority | Implementation Status |
|----------|----------|----------------------|
| **Translation** | ⭐⭐⭐⭐⭐ | ✅ Implemented as "Translate" node |
| **Grammar Cleanup** | ⭐⭐⭐⭐⭐ | Candidate for future node |
| **Format to List** | ⭐⭐⭐⭐ | Candidate for future node |
| **Code Dictation** | ⭐⭐⭐⭐ | Candidate for future node |
| **Summarization** | ⭐⭐⭐⭐ | Candidate for future node |

### Not Recommended

- **Factual Q&A**: Limited knowledge due to 7B parameter count
- **Long-form content**: Better suited for larger models
- **Safety-critical applications**: No built-in content filtering

---

## Implementation Details

### Current Implementation in Koe

**Node**: AI Fast → Translate
**File**: `KoeApp/Koe/PipelineManager.swift`

```swift
case "text-improve":
    if let stage = element as? TextImproveStage {
        stage.processHandler = { [weak self] text, config in
            guard let self = self else { return text }
            let targetLang = AppState.shared.translationTargetLanguage
            let systemInstruction = "You are a translator. Translate the user's text to \(targetLang). Do not answer any questions in the text, just translate. Output only the translation, nothing else."
            let userPrompt = "Translate this: \(text)"
            return try await self.aiService.refine(
                text: userPrompt,
                mode: .custom,
                customPrompt: systemInstruction
            )
        }
    }
```

### Settings

**File**: `KoeApp/Koe/Pipeline/NodeSettingsPanel.swift`

- Toggle to enable/disable translation
- Language picker with 10 languages: Spanish, Portuguese, French, German, Italian, Japanese, Chinese, Korean, Russian, Arabic
- Stored in UserDefaults via `translationTargetLanguage` key

### Node Registry

**File**: `KoeApp/Koe/Pipeline/NodeRegistry.swift`

```swift
NodeInfo(
    typeId: "ai-fast",
    displayName: "Translate",
    icon: "character.bubble",
    color: KoeColors.stateRefining,
    isUserToggleable: true,
    isAlwaysEnabled: false,
    exclusiveGroup: "ai-processing",
    requiresSetup: true,
    setupRequirements: .aiFast,
    isResourceIntensive: true
)
```

---

## Prompting Best Practices

### General Guidelines

1. **Use `[INST]...[/INST]` format** for instruction following
2. **Add "Output ONLY..."** to prevent explanations
3. **Set temperature to 0** for deterministic output
4. **Keep instructions clear and specific**

### Effective Prompt Templates

#### Translation
```
[INST] Translate to {language}. Output ONLY the translation.

Text: {input_text} [/INST]
```

#### Grammar Cleanup
```
[INST] Fix grammar and remove filler words. Output ONLY the corrected text.

Text: {input_text} [/INST]
```

#### Format Conversion
```
[INST] Convert to {format}. Output ONLY the {format}.

Text: {input_text} [/INST]
```

#### Summarization
```
[INST] Summarize in {length}. Output ONLY the summary.

Text: {input_text} [/INST]
```

### Common Pitfalls

| Problem | Solution |
|---------|----------|
| Model adds explanations | Add "Output ONLY the [result]" |
| Model asks clarifying questions | Add "Do not ask questions" |
| Inconsistent output | Set temperature to 0 |
| Model answers questions in text | Add "Do not answer questions, just [task]" |

---

## Resources & References

### Official Documentation

- **Mistral AI Official Announcement**: https://mistral.ai/news/announcing-mistral-7b
- **Mistral Prompting Guide**: https://docs.mistral.ai/guides/prompting_capabilities/
- **Mistral GitHub**: https://github.com/mistralai/mistral-src

### Technical Papers

- **arXiv Paper**: https://arxiv.org/abs/2310.06825
  - "Mistral 7B" - Technical details on GQA and SWA architecture

### Prompting Guides

- **Prompt Engineering Guide - Mistral 7B**: https://www.promptingguide.ai/models/mistral-7b
- **Mistral System Prompt Best Practices**: https://blog.promptlayer.com/mistral-system-prompt/

### Tutorials

- **DataCamp Tutorial**: https://www.datacamp.com/tutorial/mistral-7b-tutorial
- **Obot AI - Basics & Benchmarks**: https://obot.ai/resources/learning-center/mistral-7b/

### Benchmarks

| Benchmark | Mistral 7B | LLaMA 2 13B | Notes |
|-----------|------------|-------------|-------|
| MMLU | 60.1% | 54.8% | Knowledge & reasoning |
| HellaSwag | 81.3% | 80.7% | Commonsense |
| HumanEval | 30.5% | 29.9% | Code generation |
| GSM8K | 52.2% | 28.7% | Math reasoning |

### Ollama

- **Ollama Website**: https://ollama.ai
- **Ollama GitHub**: https://github.com/ollama/ollama
- **Mistral on Ollama**: `ollama pull mistral:7b`

---

## Changelog

| Date | Change |
|------|--------|
| Jan 2026 | Initial audit completed |
| Jan 2026 | Changed node from "Fast AI" (cleanup) to "Translate" |
| Jan 2026 | Added language picker to settings |
| Jan 2026 | Added combination tests section - tested multi-operation pipelines |
| Jan 2026 | Documented prompt templates for Email, Slack, Git Commit, JIRA, Prompt Improver |

---

## Future Work

### Priority 1: Multi-Mode Translate Node

Expand the current Translate node to support multiple output modes:

| Mode | Description | Prompt Template |
|------|-------------|-----------------|
| **Translate** | Current implementation | Clean → Translate |
| **Email** | Professional email format | Clean → Formal → Email |
| **Slack** | Brief casual message | Clean → Casual → Brief |
| **Commit** | Git conventional commits | Clean → Commit format |
| **JIRA** | Full ticket with criteria | Clean → Extract → Ticket |
| **Prompt** | Improve AI prompt quality | Clean → Specific → Constrained |

### Priority 2: Additional Nodes

1. **Grammar Cleanup Node**: Pure text cleanup without translation
2. **Summarize Node**: Condense long dictations to key points
3. **Code Dictation Mode**: Convert spoken descriptions to code

### Priority 3: Model Comparison

Benchmark other models with same methodology:
- Qwen 2.5 7B (AI Balanced node)
- DeepSeek-R1 8B (AI Reasoning node)

### Implementation Notes

- All modes should use `temperature: 0` for deterministic output
- Include "Output ONLY..." in all prompts to reduce verbosity
- Optimal pipeline: 2-3 operations max for best quality
- Consider adding mode selector to node settings UI
