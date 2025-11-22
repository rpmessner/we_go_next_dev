# Technical Architecture

This document outlines the technical decisions, technology stack, and architectural approach for the WoW Performance Analysis project.

---

## Technology Stack Decision

### Primary Language & Framework: Elixir

**Decision:** Use Elixir for the entire real-time combat log analysis engine and dashboard.

**Rationale:**

Elixir is an excellent fit for this project's core requirement: **real-time analysis of combat logs during gameplay**.

#### Why Elixir Excels Here

1. **Real-time log tailing**
   - Elixir excels at streaming file I/O
   - Can tail combat log while WoW is actively writing to it
   - `File.stream!/1` with concurrent processing
   - Minimal latency between event occurring and analysis

2. **Low-latency event processing**
   - BEAM VM designed for soft real-time systems
   - Parse and analyze combat events with minimal delay
   - Critical for "live feedback during encounter"
   - Consistent performance under load

3. **Concurrent event handling**
   - Process multiple combat events simultaneously
   - Track DoTs, cooldowns, resources in parallel states
   - Aggregate metrics without blocking
   - Natural fit for tracking many game state dimensions at once

4. **Phoenix LiveView for dashboard**
   - Real-time UI updates without complex WebSocket code
   - Push analysis results to browser instantly
   - Built-in presence tracking and state management
   - Minimal JavaScript required

5. **Fault tolerance**
   - If analysis process crashes, supervisor restarts it
   - Combat log parsing continues uninterrupted
   - Critical for long raid nights (3+ hours)
   - Let it crash philosophy prevents cascading failures

6. **Hot code reloading**
   - Update analysis rules without restarting
   - Refine rotation priorities on the fly
   - Useful for iterating during raid nights

---

## Analysis Approach: Rule-Based First, ML Later

### Phase 1: Rule-Based Analysis (Current Plan)

Start with deterministic, rule-based analysis because:

**WoW combat is well-understood:**
- Rotation priorities documented (Icy Veins, Wowhead, SimulationCraft)
- DoT/buff uptimes have known thresholds
- Resource management rules are spec-specific but known
- Cooldown timings can be validated against best practices

**Rule-based handles most use cases:**
- Rotation validation (cast X before Y, don't cap resources)
- Uptime tracking (DoTs should be >95%, buffs active during cooldowns)
- Cooldown alignment (use Tyrant with 15+ soul shards)
- Mechanic timing (interrupt at specific cast times)
- Resource waste detection (capping shards, missing procs)

**Easier to debug and explain:**
- "Your Agony uptime was 87%, should be >95%"
- "You cast Hand of Gul'dan at 5 shards, wait for 3+"
- Clear, actionable feedback

### Phase 2: Machine Learning (If Needed)

Add ML later if we discover patterns that rules can't capture:

**Potential ML applications:**
- Learning from YOUR historical patterns (not just theorycrafting)
- Adapting to YOUR playstyle quirks and preferences
- Detecting subtle inefficiencies rule-based systems miss
- Personalized recommendations based on your performance history
- Anomaly detection (unusual patterns that might indicate mistakes)
- Predictive optimization (given current state, what's optimal next action)

**Technology: Nx/Axon/Bumblebee**
- Nx: Numerical computing library for Elixir (like NumPy)
- Axon: Neural network library built on Nx
- Bumblebee: Pre-trained models and transformers
- Nx.Serving: Serve models for real-time inference

**Use Livebook for:**
- Exploratory data analysis of historical combat logs
- Interactive development and testing of analysis logic
- Training and experimenting with ML models
- Documenting analysis approaches (reproducible notebooks)
- Visualizing combat data patterns

---

## Proposed Architecture

```
Elixir Application (Real-Time Combat Analysis)
│
├── CombatLogWatcher (GenServer)
│   ├── Tail WoW combat log file
│   ├── Detect new events as WoW writes them
│   ├── Handle file rotation (if WoW creates new log files)
│   └── Emit raw combat events to processor
│
├── EventProcessor (GenStage/Flow)
│   ├── Parse combat log event format
│   ├── Normalize event structure
│   ├── Filter events relevant to player
│   ├── Enrich with game state context
│   └── Route to appropriate analyzers
│
├── AnalysisEngine (Supervisor)
│   │
│   ├── RotationAnalyzer (GenServer per spec)
│   │   ├── Validate cast sequences
│   │   ├── Check resource management
│   │   ├── Detect rotation mistakes
│   │   └── Suggest corrections
│   │
│   ├── UptimeTracker (GenServer)
│   │   ├── Track DoT uptimes (Wither, Agony, UA)
│   │   ├── Track buff uptimes
│   │   ├── Track debuff uptimes
│   │   └── Alert on dropped DoTs
│   │
│   ├── CooldownAnalyzer (GenServer)
│   │   ├── Track major cooldown usage
│   │   ├── Validate cooldown alignment
│   │   ├── Check resource pooling before CDs
│   │   └── Measure cooldown efficiency
│   │
│   ├── MechanicDetector (GenServer)
│   │   ├── Detect boss abilities
│   │   ├── Track mechanic timings
│   │   ├── Validate player responses
│   │   └── Alert on mechanic failures
│   │
│   └── MetricsAggregator (GenServer)
│       ├── Calculate real-time DPS
│       ├── Track damage by ability
│       ├── Compute efficiency metrics
│       └── Maintain encounter statistics
│
├── Dashboard (Phoenix LiveView)
│   ├── Real-time metrics display
│   ├── Live alerts and warnings
│   ├── Performance graphs
│   ├── Rotation timeline
│   └── Mechanic tracking UI
│
└── [Future] MLEngine (Nx.Serving)
    ├── Load trained models
    ├── Real-time inference
    ├── Personalized suggestions
    └── Pattern recognition
```

---

## Data Flow

```
WoW Combat Log
    ↓ (file tailing)
CombatLogWatcher
    ↓ (raw events)
EventProcessor (parse & filter)
    ↓ (normalized events)
    ├→ RotationAnalyzer → Alerts
    ├→ UptimeTracker → Metrics
    ├→ CooldownAnalyzer → Suggestions
    ├→ MechanicDetector → Warnings
    └→ MetricsAggregator → Statistics
         ↓ (aggregated data)
    Phoenix LiveView Dashboard
         ↓ (WebSocket)
    Browser (real-time display)
```

---

## Development Phases

### Phase 1: Historical Analysis (Current)
**Goal:** Understand data structures using CSV exports

**Technology:**
- Python or Elixir scripts
- Livebook for exploration
- CSV parsing

**Deliverables:**
- Understanding of combat log format
- Key metrics identification
- Performance review templates

### Phase 2: Combat Log Parser
**Goal:** Read and parse WoW combat log files

**Technology:**
- Elixir with File.stream!/1
- Pattern matching for event parsing
- GenServer for state management

**Deliverables:**
- Combat log event parser
- Event normalization pipeline
- Parsed event data structures

### Phase 3: Rule-Based Analysis Engine
**Goal:** Implement rotation and performance analysis

**Technology:**
- Elixir GenServers for analyzers
- GenStage/Flow for event processing
- ETS for fast state lookups

**Deliverables:**
- Rotation validation (spec-specific)
- Uptime tracking
- Cooldown analysis
- Metrics aggregation

### Phase 4: Real-Time Implementation
**Goal:** Parse combat log in real-time during gameplay

**Technology:**
- File.stream!/1 with tail mode
- Concurrent event processing
- Low-latency state updates

**Deliverables:**
- Real-time log tailing
- Live metrics updates
- Minimal latency (<100ms event → analysis)

### Phase 5: Web Dashboard
**Goal:** Display live analysis in web browser

**Technology:**
- Phoenix LiveView
- TailwindCSS for UI
- Chart libraries (e.g., Contex, Apache ECharts)

**Deliverables:**
- Real-time dashboard UI
- Live metrics visualization
- Alerts and notifications
- Encounter timeline view

### Phase 6: ML Integration (Optional)
**Goal:** Add personalized, ML-based insights

**Technology:**
- Nx for numerical computing
- Axon for neural networks
- Livebook for model training
- Nx.Serving for inference

**Deliverables:**
- Trained models on historical data
- Real-time ML inference
- Personalized recommendations
- Adaptive suggestions

---

## Technology Justifications

### Why Elixir over Python?

**Python Advantages:**
- Larger data science ecosystem
- More WoW combat log libraries
- Easier to find examples and resources
- Pandas, NumPy, scikit-learn mature ecosystem

**Elixir Advantages (Why We Chose It):**
- **Real-time performance**: Critical for live analysis during raids
- **Fault tolerance**: Built-in supervision for long-running processes
- **Concurrency**: Natural fit for multi-dimensional game state tracking
- **Phoenix LiveView**: Excellent for real-time dashboards
- **Hot code reloading**: Update rules during raid nights
- **Lower latency**: Consistent sub-100ms event processing
- **Developer expertise**: User knows Elixir really well, doesn't know Python much at all

**Decision:** Elixir's real-time capabilities combined with developer expertise make it the clear choice. The user's strong Elixir background means faster development and better code quality compared to learning Python from scratch.

### Why Livebook?

**Advantages:**
- Interactive development (like Jupyter notebooks)
- Built-in for Elixir (no context switching)
- Great for exploratory data analysis
- Reproducible analysis documentation
- Easy to share analysis notebooks
- Visual feedback during development

**Use Cases:**
- Exploring historical combat logs
- Developing and testing analysis rules
- Training ML models (if we go that route)
- Documenting analysis approaches
- Prototyping new features

### Why Phoenix LiveView?

**Advantages:**
- Real-time updates without complex WebSocket code
- Server-rendered, minimal JavaScript
- Built-in state management
- Optimized for low-latency updates
- Easy to reason about (stateful server processes)

**Alternatives Considered:**
- React + WebSocket: More complex, more JavaScript
- Traditional Phoenix + AJAX: Not real-time enough
- Desktop app (Electron): Overkill, more complexity

---

## Alternative Architectures Considered

### Option 1: Python for Everything
**Pros:** Rich ecosystem, easier prototyping
**Cons:** Less suited for real-time, more complex concurrency
**Verdict:** Rejected due to real-time requirements

### Option 2: Hybrid (Python ML + Elixir Dashboard)
**Pros:** Best of both worlds
**Cons:** Increased complexity, inter-process communication overhead
**Verdict:** Viable if ML becomes critical, overkill for now

### Option 3: Rust for Parser, Elixir for Analysis
**Pros:** Maximum performance
**Cons:** Unnecessary complexity, Elixir fast enough
**Verdict:** Rejected, premature optimization

---

## Performance Requirements

### Real-Time Constraints

**Target latency:** <100ms from event occurrence to analysis feedback

**Why this matters:**
- Combat events happen every 1-2 seconds (GCD)
- User needs feedback before next decision
- Alerts must appear in time to react

**How Elixir achieves this:**
- BEAM VM optimized for low-latency message passing
- Concurrent event processing (no blocking)
- Efficient pattern matching for event parsing
- GenStage for backpressure handling

### Throughput Requirements

**Estimated event rate:** ~100-500 events/second during heavy combat

**Elixir handling:**
- GenStage/Flow for high-throughput processing
- ETS for fast in-memory state lookups
- Concurrent analyzers processing in parallel
- Minimal garbage collection pauses

---

## Future Considerations

### Scalability

**Multi-character analysis:**
- Current architecture: One analyzer per character
- Future: Supervisor spawns analyzers dynamically
- ETS tables partitioned by character

**Historical data storage:**
- Current: In-memory during encounter
- Future: PostgreSQL or ETS for historical queries
- Potential: TimescaleDB for time-series data

### Integration Points

**Warcraft Logs API:**
- Fetch parse percentiles for comparison
- Retrieve top player rotations for ML training
- Historical data enrichment

**SimulationCraft:**
- Import APL (Action Priority List) for rotation rules
- Compare real performance to simulated
- Validate against theoretical maximum

**WeakAuras:**
- Potential: Send alerts back to WoW via addon
- Display in-game notifications
- Bi-directional communication (advanced)

---

## Open Questions

1. **Combat log file format:**
   - Exact structure of events?
   - How does WoW handle log rotation?
   - What's the maximum line length?

2. **State management:**
   - How much game state to track in memory?
   - When to persist vs. keep ephemeral?
   - How to handle disconnects/restarts?

3. **Analysis rule sources:**
   - Import from SimulationCraft APLs?
   - Manual definition per spec?
   - Community-sourced rotation guides?

4. **ML necessity:**
   - What patterns can't rules capture?
   - Is personalization worth the complexity?
   - When to revisit this decision?

5. **Dashboard UX:**
   - What metrics are most actionable?
   - How to present without overwhelming?
   - In-raid vs. post-raid views?

---

## Success Metrics

**For the real-time engine:**
- Event processing latency <100ms
- Zero crashes during 3+ hour raid nights
- Accurate rotation validation (validated against known-good logs)
- Actionable alerts (not overwhelming, not missing important issues)

**For the dashboard:**
- Live updates feel instant (<200ms perceived latency)
- Clear, understandable visualizations
- Alerts are timely and relevant
- Usable on second monitor during raids

**For the analysis quality:**
- Suggestions improve parse percentiles
- Catches rotation mistakes humans miss
- Doesn't generate false positives
- Adapts to different fight contexts

---

**Last Updated:** 2025-11-21
**Status:** Architecture defined, implementation pending
