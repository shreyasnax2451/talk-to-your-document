# DocChat — project context

Context carried over from the build-out sessions (October 2026), so a new
session or teammate can continue without the chat history. The design source
is the architecture guide *On-Device PDF Q&A App — SLM Architecture Guide*
(Oct 2026); this file records what was actually built, what was decided and
why, and what is still open.

Companion document: `docs/DocChat-Approach-and-Limitations.pdf` (features,
the approach explained, and the full list of limitations).

## Goal and current scope

A Flutter app (Android + iOS) that answers questions about the user's PDFs
entirely on the phone: parsing, indexing, search and answering all run
on-device. The backend is meant to handle login only.

In scope now: upload → index → ask, with citations. **Deliberately skipped
for now:** login, and the custom model download server (manifest + CDN) —
models download straight from Hugging Face.

## Branch and commits (`llms-and-chat`)

| Commit | What |
|---|---|
| `936e4bd` | On-device indexing (pdfrx → chunks → EmbeddingGemma → SQLite + FTS5) and Qwen3-4B answering with citations; real chats replace sample data; sidebar navigation fix |
| `f2278f9` | Selectable answering model (RAM-based recommendation), background model downloads with SHA-256 check, indexing progress notifications |
| `fa86e18` | User-facing model names, download-gated first launch, background-safe answering (Android foreground service, partial-answer saving, iOS clean stop) |
| `8f127bc` | Query planner: intent per question, retrieval plan per intent, fact extraction, numeric calculation in code, evaluation test |
| `0861b36` | Model selection locked while a model downloads; these docs |
| `881e65c` | Per-chat context (scope lock, topic memory for follow-up chains); no duplicate downloads; one combined banner percentage |
| (next commit) | Android downloads run as a foreground job (fixes restarts from 0% / stuck at 100%); real restarts shown; Features section in the docs |

Nothing is pushed. Verified on the Windows laptop (`flutter test` and the
opt-in evaluation) and tested by hand by the user on one Android phone
(downloads, setup, chat). Phone timings and memory use have not been
measured; there is no iOS build.

## Features

What a user can do in the app today:

- **Private by design**: PDFs, index, chats and models stay on the phone;
  nothing about documents or questions is sent to a server. Works offline
  once models are downloaded. No account needed yet.
- **Setup and models**: first-launch screen to choose **High accuracy** or
  **Basic**, with the one suiting the phone's RAM marked **Recommended** and
  pre-selected; one Download button; the choice is locked while downloading;
  the **Default resources pack** downloads automatically; the app opens once
  both are verified. Change or delete models later from the profile menu
  (the current model stays in use until the new one is ready).
- **Downloads**: background downloads that survive closing the app and
  network drops, progress notification plus one combined in-app banner,
  Wi-Fi-only option, SHA-256 check of every file.
- **Library**: upload PDFs; background indexing one at a time with progress
  on the card and in a notification; retry failed documents; rename; delete
  (removes all its data); document viewer with the extracted text.
- **Chat**: plain-language questions; streaming answers with Stop; page
  citations `[p. 3]` and source chips that open the document at that page;
  copy and regenerate; "Not found in your documents." instead of guessing.
- **Kinds of question**: facts, follow-ups, section and whole-document
  summaries, lists, comparisons, exact calculations (totals, differences,
  averages, days between dates); greetings answered instantly.
- **Chats**: saved and listed under Recents; rename or delete; each chat is
  about one document or all documents, fixed once it has messages
  (choosing another starts a new chat); follow-ups remember the topic.
- **In the background**: on Android, indexing and answering continue after
  leaving the app (progress notification, then "Your document is ready" /
  "Your answer is ready"); partial answers are saved. On iOS an answer stops
  cleanly when backgrounded and can be regenerated.

## Stack

- Flutter 3.47.8 / Dart 3.13.7
- `llamadart` ^0.16.5 (llama.cpp, GGUF; build hook ships only the llama.cpp
  runtime) + `llamadart_llama_cpp_flutter` for Apple
- `pdfrx` ^2.10.1 (PDFium) for text extraction
- `sqlite3` ^3.8.0 (bundled SQLite with FTS5)
- `background_downloader` ^9.6.4, `flutter_local_notifications` ^22.3.3,
  `device_info_plus` ^13.3.0, `crypto`, `path_provider`
- iOS deployment target 16.4; Android core library desugaring on

## Models (lib/services/model_config.dart)

| User-facing name | Model | File | Size |
|---|---|---|---|
| Default resources pack (always) | EmbeddingGemma-300M Q8_0 | ggml-org/embeddinggemma-300M-GGUF | 334 MB |
| High accuracy | Qwen3-4B Q4_K_M | Qwen/Qwen3-4B-GGUF | 2.5 GB |
| Basic | Qwen3-1.7B Q5_K_M | unsloth/Qwen3-1.7B-GGUF | 1.26 GB |

- Recommended = High accuracy if the phone reports ≥ 7 GB RAM (8 GB phones
  report ~7.2–7.6), else Basic; Basic if RAM can't be read.
- Model names are **never shown to users** (user requirement); only
  "High accuracy", "Basic", "Default resources pack".
- Answering models: 4K context, q8_0 KV cache, Qwen3 thinking mode off.
- Files live in `<app support>/models/`, verified against published SHA-256.
- Download progress (`ModelManager`):
  - Android downloads run as a foreground job (`Config.runInForeground`).
    Without it WorkManager stops jobs after ~9 minutes and the pause/resume
    cycle could restart a 2.5 GB download from 0% (seen on a phone: the
    notification jumped back while the app sat at "Downloading · 100%").
  - Never starts a second copy of a download (checks the downloader's tasks
    first; resumes paused ones).
  - Drops under 5 points are treated as out-of-order reports and smoothed;
    larger drops are real restarts and are shown.
  - The top banner shows one size-weighted figure for the whole batch
    instead of switching between items.

## How it works (short)

1. **First launch**: resources pack starts downloading immediately; setup
   screen lists the answering models with "Recommended" pre-selected and a
   single **Download** button. Once a download starts the choice is locked
   (other model, Wi-Fi switch and button disabled) until it finishes or
   fails. The app stays on this screen until the chosen model *and* the
   resources pack are verified. Changing models later keeps the current one
   in use until the new one is ready.
2. **Indexing** (on upload, queued one at a time): copy PDF into app storage
   → pdfrx text per page → page-scoped chunks (1,600 chars, 200 overlap,
   re-split if > 1,024 tokens) → EmbeddingGemma (`title: … | text: …`,
   batches of 8) → SQLite: pages, chunks + vectors, FTS5 index, extracted
   facts (dates, amounts, durations, percentages, IDs). Android shows a
   foreground-service progress notification.
3. **Answering**: `QueryPlanner` (pattern rules, no model call) picks an
   intent → `ContextBuilder` gathers passages for it → `AnswerService` uses
   the intent's prompt → citations `[n]` rewritten to `[p. N]` with source
   chips. Lookups and follow-ups send the top 5 chunks whole (up to ~8,000
   chars, ~2,000 tokens, so the answer sentence is never cut); every other
   intent is held to ~7,000 chars (`ContextBuilder.budgetChars`).

| Intent | Retrieval |
|---|---|
| smallTalk | none, canned reply |
| lookup (default) | hybrid search top 5, whole chunks |
| follow-up | same as lookup, searched with the chat's topic question merged in; topic + previous Q/A in prompt |
| sectionSummary | best hit + neighbouring chunks + 1 more hit (≤ 4), trimmed to the budget |
| documentSummary | 6 evenly spaced samples (split across up to 3 newest docs), trimmed |
| list | up to 12 matching-sentence excerpts (≤ 450 chars) + facts of the asked kind |
| compare | 3 per side (≤ 6), labelled, trimmed |
| numeric | top 6 trimmed to ~5,000 chars + facts from the same pages; model extracts values as JSON, code computes |

Hybrid search = brute-force cosine over stored vectors + FTS5 BM25, 20
candidates each, merged with Reciprocal Rank Fusion (k = 60). **No reranker.**

4. **Context per chat**: each chat stores its messages, title and scope (one
   document or "All documents") on the device.
   - **Scope is locked once a chat has messages**: choosing another scope in
     the scope sheet starts a new chat about it (`AppState.changeScope`).
   - **Topic memory**: `QueryPlanner.contextOf` replays the chat's earlier
     questions to find the previous real question (small talk skipped) and
     the *topic question* — the last question that was not a follow-up.
     Follow-ups are searched with the topic question, so chains like "hotel
     cap in metro cities?" → "and in other cities?" → "what about Pune?" stay
     on hotel caps. Nothing extra is stored; it is recomputed from the chat.
   - The model sees the topic question and only the last exchange; there is
     no longer-term conversation summary.

5. **Background work** (`BackgroundNotifications`): on Android one
   foreground service covers indexing and answering, with a progress
   notification ("Indexing X · 42%", "Writing an answer…"); "Your document is
   ready" / "Your answer is ready" when finished while the app is away.
   Partial answers are saved every 3 s; the answering model is unloaded when
   the app is backgrounded (or when an answer finishes in the background).
   iOS forbids background GPU work, so an answer stops cleanly with a note to
   regenerate.

## Decisions and why

- **No reranker.** MiniLM GGUFs on Hugging Face are broken (llama.cpp's BERT
  converter drops the pooler layer the classifier needs; scores ≈ 0); jina
  tiny was weak (3/5 top-1); Qwen3-Reranker-0.6B was accurate but 639 MB and
  ~10 s/question on a phone, and did not beat hybrid search on a 10-page test
  (hybrid 7/8 top-1, reranked 6/8). User chose no reranker.
- **Rule-based query planning**, not model classification: instant on a
  phone; unknown questions fall back to lookup (the original behaviour).
- **Arithmetic in code** (guide's advice): the model once answered 238 days
  instead of 274 when it did the maths itself.
- **Summary speed work was reverted by the user** (sampling-only summary path
  and a "Thought for Ns" line) because the planner now covers summaries.
- **Encryption deferred**; it would not slow the model (model files are
  never encrypted, SQLCipher overhead is milliseconds).
- **Chat scope is locked after the first message** so a chat is one
  consistent context; follow-up memory is rule-based (no extra model call)
  to keep phone answers fast.

## Build and install (Windows, no Android Studio, no USB)

- SDK via Scoop: `android-clt` (main bucket) + `temurin21-jdk`; licenses
  accepted by the user; Flutter configured with `--android-sdk` and
  `--jdk-dir`.
- Build: `flutter build apk --release --split-per-abi --target-platform android-arm64`
  → `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` (~74 MB).
  Must run in a normal terminal: inside the Claude sandbox Gradle fails with
  "Unable to establish loopback connection".
- Install over Wi-Fi: `python -m http.server 8000 --directory build/app/outputs/flutter-apk`
  and open `http://<pc-ip>:8000` on the phone. The Wi-Fi profile must be
  **Private** (a Public profile has a firewall rule blocking Python).
- Wireless `adb pair` failed with "protocol fault" (network reachable); not
  resolved. USB is not available to the user.

## Tests

- `flutter test`: 56 unit tests (chunker, FTS query, fact extraction,
  planner incl. follow-up chains, calculator, chat scope lock, model config,
  setup screen incl. download lock, download progress, smoke).
- `test/eval/answer_eval_test.dart`: opt-in end-to-end evaluation (16 cases,
  every intent, including a two-step follow-up) — needs `DOCCHAT_EVAL_DIR`
  with the GGUF files and
  `LLAMADART_NATIVE_LIB_DIR=build/native_assets/windows`. All 16 cases pass
  with the High accuracy model on the laptop (5–21 s per answer there). The
  follow-up chain case ("what about Pune?") stays on topic but the answer
  hedges: it gives both caps without inferring Pune is not a listed metro
  (the metro list is only in the daily-allowance sentence).
- `sample-docs/employee-handbook-2026.pdf`: fictional 4-page handbook with
  known answers, used by the evaluation.

## Open items

See the limitations section of the PDF. Highest value next: measure
indexing/answer times and memory on a 6 GB and an 8 GB phone; an iOS build;
encryption at rest (SQLCipher + Keystore/Keychain); own model manifest/CDN;
re-index on embedding-model change; OCR for scanned PDFs; table-aware
extraction; a longer-term conversation summary if users need memory beyond
the current topic.
