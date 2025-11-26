# Session: 2025-11-23 - WoWAnalyzer Architecture Research

**Date:** November 23, 2025
**Session Type:** Research & Planning
**Status:** Complete

---

## Session Overview

Conducted deep dive research into WoWAnalyzer (github.com/WoWAnalyzer/WoWAnalyzer), a mature TypeScript-based combat log analysis tool, to extract architectural patterns and implementation strategies applicable to our Elixir-based parser. This session establishes the roadmap for transforming our basic parser into a comprehensive analysis engine.

---

## Research Findings

### WoWAnalyzer Project Profile

**Technology Stack:**
- **Language:** TypeScript (96.5%)
- **Framework:** React + Vite
- **Architecture:** Monorepo with pnpm workspaces
- **Scale:** 32,403 commits, 299 contributors
- **License:** AGPL-3.0
- **Status:** Active (The War Within expansion branch)

**Project Structure:**
```
src/
├── parser/              # Combat log parsing engine
│   ├── core/           # Shared parsing infrastructure
│   ├── retail/         # Current expansion parsers
│   ├── classic/        # Classic WoW parsers
│   ├── shared/         # Cross-version utilities
│   └── ui/             # Parser UI components
├── analysis/           # Class/spec analyzers
│   └── retail/
│       └── warlock/
│           ├── shared/
│           ├── affliction/
│           ├── demonology/
│           │   └── modules/
│           │       ├── pets/          # Pet damage tracking
│           │       ├── talents/
│           │       └── features/
│           └── destruction/
├── common/             # Shared utilities
├── game/               # WoW game data
├── interface/          # UI components
└── localization/       # i18n support
```

### Key Architectural Patterns

#### 1. Event-Driven Modular Architecture

**Core Components:**
- `EventSubscriber` - Base class for event listening
- `Analyzer` - Base class for analysis modules
- `Module` - Base class for all system components
- `CombatLogParser` - Orchestrator with dependency injection

**Pattern:**
```typescript
class MyAnalyzer extends Analyzer {
  // Declare dependencies (automatically injected)
  static dependencies = {
    combatants: Combatants,
    abilities: Abilities,
  };

  // Subscribe to specific events
  addEventListener(EventType.Damage, this.onDamage);

  // Provide output
  statistic() { return <Component />; }
  suggestions(when) { return [...]; }
}
```

**Dependency Resolution:**
- Iterative initialization (up to 100 iterations)
- Modules load only after dependencies available
- Graceful degradation on failures
- Priority-based ordering for normalizers

#### 2. Multi-Stage Event Processing Pipeline

**Pipeline Flow:**
```
Raw Events
  → EventOrderNormalizer (fix temporal issues)
  → EventLinkNormalizer (create relationships)
  → BuffRefreshNormalizer (track buff stacks)
  → PrepullPetNormalizer (fabricate missing summons)
  → SummonOrderNormalizer (sequence pet events)
  → [Other normalizers...]
  → Analyzer Modules (parallel processing)
  → Statistics & Suggestions
```

**Normalizer Pattern:**
```typescript
class EventsNormalizer extends Module {
  priority = 0;  // Lower = earlier execution

  normalize(events: AnyEvent[]): AnyEvent[] {
    // Transform event array
    // Can add, remove, or modify events
    return transformedEvents;
  }
}
```

**Key Insight:** Normalizers run in priority order and **transform the entire event array** before analyzers see it. This separates data cleaning from analysis logic.

#### 3. Event Linking System

**Purpose:** Create bidirectional relationships between related events

**Example Links:**
- Cast → Damage (which damage came from which cast)
- Summon → Despawn (track pet lifetime)
- Buff Application → Buff Refresh → Buff Removal
- Cooldown Use → Effects (track cooldown efficiency)

**Implementation Pattern:**
```typescript
const LINKS = [
  {
    linkingEventId: SPELL_ID,
    linkingEventType: EventType.Cast,
    referencedEventId: SPELL_ID,
    referencedEventType: EventType.Damage,
    forwardBufferMs: 5000,  // Search 5s forward
    anyTarget: true,         // Match any target
    maximumLinks: 10,        // Max 10 damage events per cast
  }
];
```

**Result:** Events gain `_linkedEvents` property for querying relationships

#### 4. Pet Damage Attribution (CRITICAL)

**The Problem We Face:**
- Pet damage has different source GUIDs
- Direct name matching misses 70%+ of Warlock/Hunter damage
- Need to track ownership through `SPELL_SUMMON` events

**WoWAnalyzer's Solution:**

**Storage Structure:**
```typescript
pets: Record<petGUID, {
  name: string,
  instances: Record<instanceNumber, damageAmount>,
  total: totalDamage
}>
```

**Tracking Strategy:**
1. **Summon Event Tracking:** Parse `SPELL_SUMMON` to build `petGUID → ownerGUID` map
2. **Pet Classification Helpers:**
   - `isPermanentPet(guid)` - Felguard, Felhunter, etc.
   - `isWildImp(guid)` - Wild Imps (temp summons)
   - `isRandomPet(guid)` - Random demon summons
3. **Instance Tracking:** Track each individual summon separately
4. **Aggregation:** Sum both per-instance and total damage

**Prepull Pet Handling:**
- Scan first 30 seconds for pet activity
- Detect damage/casts from pets without summon events
- **Fabricate synthetic summon events** with `__fabricated: true` flag
- Insert at fight start to satisfy downstream analyzers

**Files to Study:**
- `src/analysis/retail/warlock/demonology/modules/pets/PetDamage.ts`
- `src/analysis/retail/warlock/demonology/modules/pets/helpers.ts`
- `src/analysis/retail/warlock/demonology/modules/pets/normalizers/PrepullPetNormalizer.ts`

#### 5. Core Analysis Modules

**Built-in Capabilities:**
- `EventEmitter.ts` - Event handling system
- `Abilities.ts` - Spell/ability tracking
- `Auras.ts` - Buff/debuff monitoring
- `SpellInfo.ts` - Spell metadata management
- `Combatants.ts` - Player/enemy state tracking
- `Pets.ts` - Pet ownership tracking

**Spec-Specific Organization:**
```
warlock/
├── shared/              # Cross-spec utilities
├── affliction/
│   └── modules/
│       ├── talents/
│       ├── features/
│       └── guide/
├── demonology/
│   └── modules/
│       ├── pets/        # Demonology-specific pet logic
│       ├── talents/
│       └── features/
└── destruction/
```

### Applicable Patterns for Our Parser

#### What to Adopt

**1. Normalizer Pipeline (High Priority)**
- Separate data cleaning from analysis
- Priority-ordered event transformations
- Clear separation of concerns

**2. Pet Damage Attribution (Critical)**
- Track `SPELL_SUMMON` events
- Build `pet_guid → owner` mapping
- Fabricate prepull summon events
- Aggregate pet + player damage

**3. Event Linking**
- Create relationships between events
- Enable complex queries (cooldown efficiency, proc tracking)
- Foundation for rotation analysis

**4. Modular Analyzer Architecture**
- Separate analyzers for different metrics
- Spec-specific modules inherit from base
- Parallel processing of independent metrics

**5. Spec-Specific Organization**
- `/specs/warlock/demonology/` structure
- Shared utilities in `/specs/warlock/shared/`
- Easier to maintain and extend

#### What to Skip

**1. Complex Dependency Injection**
- Elixir supervision trees handle this more naturally
- OTP provides better process management
- Don't need 100-iteration resolution

**2. React/TypeScript UI**
- Phoenix LiveView is better fit for real-time
- Less JavaScript complexity
- Better server-side state management

**3. Warcraft Logs API Integration** (for now)
- We're parsing raw logs directly
- Better for real-time analysis
- Can add later for comparisons

---

## Architecture Recommendations

### Proposed Elixir Structure

```
combat_log_parser/
├── lib/
│   ├── combat_log_parser.ex           # Main API
│   └── combat_log_parser/
│       ├── parser/
│       │   ├── log_reader.ex          # File parsing
│       │   └── event_parser.ex        # Event structure
│       │
│       ├── normalizers/               # NEW - Event preprocessing
│       │   ├── normalizer.ex          # Base behavior
│       │   ├── pet_normalizer.ex      # Pet ownership tracking
│       │   ├── event_linker.ex        # Link related events
│       │   └── prepull_normalizer.ex  # Handle prepull state
│       │
│       ├── analyzers/                 # REFACTOR from singular
│       │   ├── analyzer.ex            # Base behavior
│       │   ├── damage_analyzer.ex     # Direct damage
│       │   ├── pet_damage_analyzer.ex # Pet damage attribution
│       │   ├── healing_analyzer.ex    # Healing output
│       │   ├── death_analyzer.ex      # Death tracking
│       │   ├── buff_analyzer.ex       # Buff uptime
│       │   └── cooldown_analyzer.ex   # Cooldown tracking
│       │
│       ├── specs/                     # NEW - Spec-specific logic
│       │   ├── warlock/
│       │   │   ├── shared/
│       │   │   │   ├── pets.ex        # Pet definitions
│       │   │   │   └── spells.ex      # Warlock spells
│       │   │   ├── demonology/
│       │   │   │   ├── rotation_analyzer.ex
│       │   │   │   └── pet_analyzer.ex
│       │   │   ├── affliction/
│       │   │   └── destruction/
│       │   └── [other classes]/
│       │
│       └── models/
│           ├── encounter.ex           # Encounter structure
│           ├── event.ex               # Event structure
│           └── player.ex              # Player state
│
└── test/
```

### Data Flow Architecture

```
Raw Combat Log
    ↓
LogReader (stream file)
    ↓
EventParser (parse & structure)
    ↓
Normalizers (priority-ordered pipeline)
    ├→ PetNormalizer (build ownership map)
    ├→ PrepullNormalizer (fabricate missing events)
    └→ EventLinker (create relationships)
    ↓
Analyzers (parallel processing)
    ├→ DamageAnalyzer
    ├→ PetDamageAnalyzer
    ├→ HealingAnalyzer
    ├→ BuffAnalyzer
    └→ CooldownAnalyzer
    ↓
Statistics & Metrics
    ↓
Output / Dashboard
```

### Process Architecture (OTP)

```
CombatLogParser (Application)
├── Parser.Supervisor
│   ├── LogReader (GenServer)
│   └── EventParser (GenStage)
│
├── Normalizer.Supervisor
│   ├── PetNormalizer (GenServer)
│   ├── EventLinker (GenServer)
│   └── PrepullNormalizer (GenServer)
│
├── Analyzer.Supervisor
│   ├── DamageAnalyzer (GenServer)
│   ├── PetDamageAnalyzer (GenServer)
│   ├── HealingAnalyzer (GenServer)
│   ├── BuffAnalyzer (GenServer)
│   └── CooldownAnalyzer (GenServer)
│
└── [Future] Dashboard.Supervisor
    └── Phoenix.LiveView processes
```

---

## Detailed Roadmap

### Phase 1: Foundation Enhancement (Next 2-3 Sessions)

**Priority 1A: Pet Damage Attribution** ⭐ CRITICAL
- **Why:** Fixes 70% DPS undercount for Warlock/Hunter
- **Effort:** Medium
- **Impact:** High

Tasks:
1. Create `PetNormalizer` module
2. Parse `SPELL_SUMMON` events to build ownership map
3. Track pet GUIDs → owner name mapping
4. Modify `DamageAnalyzer` to attribute pet damage to owner
5. Handle prepull pets (fabricate summon events)
6. Test with Demonology Warlock logs (should see 3-5x DPS increase)

**Priority 1B: Normalizer Architecture**
- **Why:** Foundation for all advanced features
- **Effort:** Medium
- **Impact:** High

Tasks:
1. Define `Normalizer` behavior
2. Create normalizer pipeline (priority-ordered execution)
3. Refactor existing code to use normalizer pattern
4. Add `_normalized` metadata to events
5. Create test suite for normalizers

**Priority 1C: Event Structure Enhancement**
- **Why:** Support event linking and metadata
- **Effort:** Low
- **Impact:** Medium

Tasks:
1. Add `_linked_events` field to event struct
2. Add `_fabricated` flag for synthetic events
3. Add `_normalized` flag to track processing
4. Update `Encounter` struct to include normalized events

### Phase 2: Analysis Engine Expansion (Next 3-5 Sessions)

**Priority 2A: Healing Analysis**
- Parse `SPELL_HEAL`, `SPELL_PERIODIC_HEAL` events
- Track healing by source
- Calculate HPS (healing per second)
- Distinguish effective vs. overheal

**Priority 2B: Death Tracking**
- Parse `UNIT_DIED` events
- Track death causes (last damage source)
- Identify avoidable deaths
- Track death timings within encounter

**Priority 2C: Buff/Debuff Uptime**
- Parse `SPELL_AURA_APPLIED`, `SPELL_AURA_REMOVED` events
- Track buff durations
- Calculate uptime percentages
- Alert on dropped DoTs/buffs

**Priority 2D: Cooldown Tracking**
- Parse `SPELL_CAST_SUCCESS` for major cooldowns
- Track cooldown usage timestamps
- Calculate cooldown efficiency
- Detect unused cooldowns

**Priority 2E: Event Linking System**
- Implement `EventLinker` normalizer
- Link casts → damage events
- Link summons → despawns
- Link buff applications → refreshes

### Phase 3: Spec-Specific Analysis (Next 5-8 Sessions)

**Priority 3A: Warlock Base Classes**
- Define Warlock spell IDs
- Create Warlock pet definitions
- Implement shared Warlock utilities
- Base rotation validation framework

**Priority 3B: Demonology Analysis**
- Pet rotation tracking (which demons, when)
- Soul shard management
- Tyrant cooldown alignment
- Hand of Gul'dan shard optimization
- Wild Imp spawn tracking
- Rotation mistake detection

**Priority 3C: Affliction Analysis**
- DoT uptime tracking (Agony, Corruption, Unstable Affliction, Wither)
- Soul shard generation tracking
- Malefic Rapture optimization
- Drain Soul timing
- Cooldown alignment

**Priority 3D: Destruction Analysis**
- Soul shard generation and spending
- Chaos Bolt timing
- Backdraft proc tracking
- Infernal cooldown usage
- Rain of Fire optimization

### Phase 4: Real-Time Implementation (Next 3-5 Sessions)

**Priority 4A: File Watching**
- Implement combat log file tailing
- Handle file rotation (WoW creates new logs)
- Stream new events as they're written
- Incremental processing pipeline

**Priority 4B: Live Event Processing**
- GenStage/Flow for streaming events
- Backpressure handling
- Real-time normalizer application
- Live metric updates

**Priority 4C: State Management**
- Track encounter state in real-time
- Maintain player state across events
- Handle combat start/end boundaries
- Reset state appropriately

**Priority 4D: Performance Optimization**
- Profile event processing latency
- Optimize hot paths
- Target <100ms event → analysis
- Memory usage optimization

### Phase 5: Web Dashboard (Next 5-8 Sessions)

**Priority 5A: Phoenix Setup**
- Create Phoenix application
- Integrate with combat log parser
- Set up LiveView architecture
- Basic page routing

**Priority 5B: Real-Time Metrics Display**
- Live DPS meter
- Ability breakdown
- Buff/debuff tracking
- Cooldown status

**Priority 5C: Encounter Timeline**
- Visual timeline of encounter
- Major events markers
- Cooldown usage visualization
- Death markers

**Priority 5D: Alerts & Notifications**
- Real-time rotation alerts
- Dropped DoT warnings
- Cooldown reminders
- Mechanic warnings

**Priority 5E: Performance Graphs**
- DPS over time chart
- Resource generation/spending
- Buff uptime bars
- Comparison to previous pulls

### Phase 6: Advanced Features (Future)

**Priority 6A: Rotation Analysis**
- Define optimal rotation patterns
- Detect rotation mistakes
- Suggest improvements
- Compare to SimulationCraft APL

**Priority 6B: Mechanic Tracking**
- Boss ability detection
- Avoidable damage identification
- Interrupt tracking
- Mechanic success/failure

**Priority 6C: Warcraft Logs Integration**
- API integration for percentile comparisons
- Historical performance tracking
- Rank estimation
- Top player rotation analysis

**Priority 6D: Multi-Character Support**
- Track multiple characters simultaneously
- Compare performance across alts
- Guild-wide analysis
- Raid composition insights

**Priority 6E: ML Integration (Optional)**
- Train models on historical logs
- Personalized recommendations
- Pattern recognition
- Adaptive suggestions

---

## Implementation Priority Matrix

### Critical Path (Must Have)
1. **Pet Damage Attribution** - Blocks accurate Warlock analysis
2. **Normalizer Architecture** - Foundation for everything else
3. **Event Linking** - Enables rotation analysis
4. **Real-Time File Watching** - Core requirement for vision

### High Value (Should Have Soon)
5. **Healing Analysis** - Complete combat picture
6. **Death Tracking** - Important for progression
7. **Buff Uptime** - Key performance metric
8. **Cooldown Tracking** - Optimization opportunities

### Medium Value (Nice to Have)
9. **Spec-Specific Analysis** - Deep insights
10. **Web Dashboard** - User interface
11. **Rotation Analysis** - Advanced optimization

### Low Priority (Future)
12. **Warcraft Logs Integration** - Comparison features
13. **Multi-Character Support** - Scalability
14. **ML Integration** - Advanced personalization

---

## Key Insights from WoWAnalyzer

### What They Do Well

**1. Clear Separation of Concerns**
- Parsing → Normalization → Analysis → Presentation
- Each stage has single responsibility
- Easy to test and maintain

**2. Extensible Module System**
- New analyzers don't modify core
- Spec-specific modules inherit from base
- Community contributions enabled

**3. Event Linking**
- Makes complex queries simple
- Tracks relationships automatically
- Foundation for advanced analysis

**4. Pet Damage Handling**
- Fabricating missing events is clever
- Instance tracking handles multiple summons
- Classification helpers simplify logic

**5. Priority-Based Processing**
- Ensures data dependencies resolved
- Normalizers run in correct order
- Predictable execution flow

### What We Can Improve

**1. Simpler Dependency Management**
- Elixir supervision trees > 100-iteration resolution
- OTP provides better process management
- GenServer dependencies explicit and clear

**2. Better Real-Time Support**
- WoWAnalyzer is batch-oriented (Warcraft Logs)
- Our streaming approach is superior for live analysis
- Elixir's BEAM VM designed for this

**3. Cleaner State Management**
- Phoenix LiveView > React for real-time
- Server-side state is simpler
- Less JavaScript complexity

**4. Fault Tolerance**
- OTP supervisors provide better resilience
- "Let it crash" philosophy
- Automatic restart on failures

---

## Context for Future Sessions

### Critical Files to Reference

**Current Parser:**
- `combat_log_parser/lib/combat_log_parser.ex` - Main API (lines 1-76)
- `combat_log_parser/lib/combat_log_parser/damage_analyzer.ex` - Current damage analysis (lines 1-116)
  - **Line 49-52:** Where pet damage filtering fails (only checks source name)
  - **Line 57-74:** Damage extraction logic (needs to handle pets)
- `combat_log_parser/lib/combat_log_parser/encounter.ex` - Encounter struct
- `combat_log_parser/lib/combat_log_parser/log_reader.ex` - Event parsing

**WoWAnalyzer Reference Files:**
- Demonology pet damage: `src/analysis/retail/warlock/demonology/modules/pets/PetDamage.ts`
- Pet helpers: `src/analysis/retail/warlock/demonology/modules/pets/helpers.ts`
- Prepull normalizer: `src/analysis/retail/warlock/demonology/modules/pets/normalizers/PrepullPetNormalizer.ts`
- Event linking: `src/parser/core/EventLinkNormalizer.ts`
- Main parser: `src/parser/core/CombatLogParser.tsx`

### Known Combat Log Format Details

**Event Structure:**
```
MM/DD/YYYY HH:MM:SS.mmm-TZ  EVENT_TYPE,field1,field2,...
```

**Key Event Types:**
- `ENCOUNTER_START`, `ENCOUNTER_END` - Encounter boundaries
- `SPELL_DAMAGE`, `SPELL_PERIODIC_DAMAGE` - Damage events
- `SPELL_SUMMON` - Pet summoning (CRITICAL for ownership)
- `SPELL_CAST_SUCCESS` - Ability casts
- `SPELL_AURA_APPLIED`, `SPELL_AURA_REMOVED` - Buff/debuff tracking
- `UNIT_DIED` - Death events
- `SPELL_HEAL`, `SPELL_PERIODIC_HEAL` - Healing events

**GUID Structure:**
- Players: `Player-[serverID]-[playerID]`
- NPCs: `Creature-0-[...]-[npcID]-[instanceID]`
- Pets: `Pet-0-[...]-[npcID]-[instanceID]` (different from owner GUID)

**Advanced Logging Fields:**
- Adds variable-length data between spell info and damage suffix
- Includes HP, power, position data
- Damage position: ~7-10 fields from end of array

### Current Known Limitations

**1. Pet Damage Not Attributed** ⚠️ CRITICAL
- Impact: Warlock/Hunter DPS 70%+ too low
- Root cause: `damage_analyzer.ex:49-52` only checks source name
- Fix: Track `SPELL_SUMMON` events, build ownership map

**2. DoT Damage May Be Undercounted**
- Status: Needs verification
- Test: Affliction fights should show high Wither/Agony percentages

**3. No Multi-Target Detection**
- Can't distinguish trash vs. boss damage
- Need to track target GUIDs

**4. Memory Usage for Large Files**
- 603MB works fine
- Larger logs may cause issues
- Streaming will help

### Test Data Available

**Primary Combat Log:**
- Path: `/mnt/g/World of Warcraft/_retail_/Logs/WoWCombatLog-*.txt`
- Most recent parsed: 603MB, 20 encounters
- Character: Mittwoch (Warlock)
- Content: Heroic Manaforge Omega

**Analysis Output:**
- `analysis_output_20251122.txt` - 20 encounter analysis

**CSV Exports (Historical):**
- `data/guild_reports.csv`
- `data/[boss_name]_[difficulty]/` - Per-encounter folders

### Development Environment

**Elixir Project:**
- Location: `combat_log_parser/`
- Run: `cd combat_log_parser && mix run test_parse.exs`
- Compile: `mix compile`

**Combat Log Location:**
- Windows: `/mnt/g/World of Warcraft/_retail_/Logs/`
- Written in real-time during gameplay
- Advanced logging enabled

### Character Context

**Main:** Mittwoch (Warlock, Wyrmrest Accord-US)
- Specs: Demonology (primary), Affliction, Destruction
- Guild: Hand of Algalon
- Content: Mythic Manaforge Omega progression

**Alts:** 10 other characters (all Wyrmrest Accord)
- See CLAUDE.md for full list

---

## Next Session Goals

When starting the next session, priorities should be:

**1. Implement Pet Damage Attribution** (Highest Impact)
- Create `PetNormalizer` module
- Track `SPELL_SUMMON` events
- Build pet ownership mapping
- Test with Demonology Warlock logs
- Verify DPS increases to expected levels

**2. Set Up Normalizer Architecture** (Foundation)
- Define `Normalizer` behavior
- Create pipeline infrastructure
- Refactor to use normalizer pattern

**3. Validate Against Real Data** (Quality Assurance)
- Compare parser output to Warcraft Logs
- Verify pet damage attribution accuracy
- Check DoT damage tracking

---

## Questions for Future Exploration

**Architecture:**
1. Should normalizers be GenServers or pure functions?
2. How to handle normalizer priorities in Elixir?
3. ETS vs. Agent for ownership mapping?

**Pet Tracking:**
1. What's the exact SPELL_SUMMON event format?
2. How to handle pet despawns and re-summons?
3. Do Wild Imps have consistent naming?

**Performance:**
1. What's our current event processing latency?
2. Can we process events faster than WoW generates them?
3. Memory usage patterns for streaming?

**Feature Scope:**
1. Which specs to prioritize after Warlock?
2. How much rotation analysis is practical?
3. When to add ML vs. continue with rules?

---

## Resources & References

**WoWAnalyzer GitHub:**
- Main repo: https://github.com/WoWAnalyzer/WoWAnalyzer
- Docs: Check wiki for contributing guide
- Discord: Active community for questions

**Combat Log Documentation:**
- WoW API: https://wowpedia.fandom.com/wiki/COMBAT_LOG_EVENT
- Advanced logging: Search Wowhead for "advanced combat logging"

**Elixir Resources:**
- GenStage: For event streaming
- Phoenix LiveView: For real-time dashboard
- Nx/Axon: For future ML integration

**WoW Resources:**
- Warcraft Logs API: https://www.warcraftlogs.com/api/docs
- SimulationCraft: For rotation patterns
- Icy Veins: For rotation guides

---

## Session Artifacts

**Created This Session:**
- `docs/sessions/2025-11-23_wowanalyzer_research.md` (this file)
- `docs/ROADMAP.md` (comprehensive feature roadmap)
- Updated `CLAUDE.md` with new context

**Research Notes:**
- 15+ WoWAnalyzer source files examined
- Architecture patterns documented
- Implementation strategies extracted

---

**Status:** Research complete, roadmap established, ready to implement!
