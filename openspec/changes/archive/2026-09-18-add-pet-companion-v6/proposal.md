## Why

The pet system now provides goals and short invitations, but the companion mostly disappears once practice begins and its room changes are still abstract. The next step should make learning feel like a shared activity, create visible consequences in the pet home, and measure whether those prompts actually encourage voluntary practice without introducing pressure mechanics.

## What Changes

- Keep the named pet visible during fixed three-question sessions and react gently to correct answers, incorrect answers, and longer thinking time.
- Wrap each three-question session in a short room-and-furniture mission using the current textbook, while retaining the existing grading and progress records.
- Give newly unlocked learning furniture an obvious visual state change, such as a lit lamp, a filled bookcase, or a blooming plant.
- Add a non-punitive daily return variation: the pet may occupy another valid room position and offer a short message based on recent learning, without streaks, decay, or missed-day penalties.
- Record a versioned local engagement event log covering invitation views and starts, three-question completions, voluntary repeat practice, and next-day returns, with metrics derived from those events.
- Model the log as a future upload outbox with stable event IDs, timestamps, session/install identifiers, typed context and delivery state so it can later map to protobuf and gRPC without rewriting producers.
- Keep this phase offline and private: do not implement network upload or store answer text, audio, pet names, or direct student identity.

## Capabilities

### New Capabilities

- `pet-engagement-events`: Defines privacy-preserving, versioned local event records, retention and delivery-state semantics, plus derived engagement measures for evaluating pet invitations and return behavior and supporting a future gRPC uploader.

### Modified Capabilities

- `pet-quick-practice`: Adds an in-session companion, answer/thinking reactions, themed room missions, and voluntary repeat-practice tracking.
- `pet-home`: Adds visible furniture state changes and non-punitive daily return variation tied to existing learning history.
- `pet-growth`: Connects newly earned furniture unlocks and milestone events to visible companion and room feedback without adding another reward economy.

## Impact

- Flutter practice and pet-home screens gain new companion presentation state and lightweight animations.
- Pet profile or a separate local companion-state record gains visit and room-state metadata with backward-compatible migration.
- Quick-practice launch and completion paths append typed events through a repository boundary; dashboards derive counts and rates from the log.
- The event envelope is designed for later protobuf/gRPC mapping, but this change does not add a `.proto`, endpoint, authentication, background uploader, or network dependency.
- Existing textbook questions, mastery calculations, mistake handling, growth awards, and three-question selection remain the source of learning truth.
- No network service, account identifier, advertising SDK, new currency, streak, hunger, decay, or notification permission is introduced.
