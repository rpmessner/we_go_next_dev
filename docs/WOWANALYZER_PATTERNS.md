# WoWAnalyzer Architectural Patterns Reference

**Source:** https://github.com/WoWAnalyzer/WoWAnalyzer
**Date Analyzed:** 2025-11-23
**Purpose:** Quick reference for implementation patterns learned from WoWAnalyzer

---

## Table of Contents

1. [Event Processing Pipeline](#event-processing-pipeline)
2. [Pet Damage Attribution](#pet-damage-attribution)
3. [Event Linking System](#event-linking-system)
4. [Module Architecture](#module-architecture)
5. [Normalizer Pattern](#normalizer-pattern)
6. [Analyzer Pattern](#analyzer-pattern)
7. [Code Examples](#code-examples)

---

## Event Processing Pipeline

### Overview

WoWAnalyzer processes events through a multi-stage pipeline:

```
Raw Events
  ↓
Normalizers (priority-ordered, sequential)
  ├─ EventOrderNormalizer (priority 0)
  ├─ EventLinkNormalizer (priority 10)
  ├─ BuffRefreshNormalizer (priority 20)
  ├─ PrepullPetNormalizer (priority 30)
  └─ [Other normalizers...]
  ↓
Analyzers (parallel)
  ├─ DamageAnalyzer
  ├─ HealingAnalyzer
  ├─ BuffAnalyzer
  └─ [Spec-specific analyzers...]
  ↓
Statistics & Suggestions
```

### Key Concepts

**Normalizers:**
- Transform the entire event array before analysis
- Run sequentially in priority order (lower = earlier)
- Can add, remove, or modify events
- Add metadata to events (links, flags)

**Analyzers:**
- Process normalized events
- Run in parallel (no dependencies between analyzers)
- Subscribe to specific event types
- Produce statistics and suggestions

### Implementation

```typescript
normalize(events: AnyEvent[]) {
  this.activeModules
    .filter((module) => module instanceof EventsNormalizer)
    .sort((a, b) => a.priority - b.priority)
    .forEach((normalizer) => {
      if (normalizer.normalize) {
        events = normalizer.normalize(events);
      }
    });
  return events;
}
```

### Elixir Translation

```elixir
defmodule CombatLogParser.Normalizers.Pipeline do
  def normalize(events, normalizers) do
    normalizers
    |> Enum.sort_by(& &1.priority())
    |> Enum.reduce(events, fn normalizer, acc_events ->
      normalizer.normalize(acc_events)
    end)
  end
end
```

---

## Pet Damage Attribution

### The Problem

- Pet damage has separate source GUIDs from owner
- Need to track `SPELL_SUMMON` events to build ownership mapping
- Pets present before combat log starts need special handling

### WoWAnalyzer's Solution

**Data Structure:**
```typescript
pets: Record<petGUID, {
  name: string,
  instances: Record<instanceNumber, damageAmount>,
  total: totalDamage
}>
```

**Process:**

1. **Track Summon Events:**
   ```typescript
   on_summon(event) {
     this.petOwners[event.targetID] = event.sourceID;
     this.petInfo[event.targetID] = {
       name: event.targetName,
       owner: event.sourceID,
       summonTime: event.timestamp
     };
   }
   ```

2. **Attribute Pet Damage:**
   ```typescript
   on_damage(event) {
     if (this.petOwners[event.sourceID]) {
       const owner = this.petOwners[event.sourceID];
       this.addPetDamage(owner, event.sourceID, event.amount);
     }
   }
   ```

3. **Handle Prepull Pets (Critical!):**
   ```typescript
   // Scan first 30 seconds for pet activity without summons
   for (const event of events) {
     if (event.timestamp - fightStart > 30000) break;

     if (isPetEvent(event) && !hasSummonEvent(event.sourceID)) {
       // Fabricate synthetic summon event
       const summonEvent = {
         type: EventType.Summon,
         sourceID: getPlayerGUID(),
         targetID: event.sourceID,
         timestamp: fightStart,
         __fabricated: true
       };
       events.unshift(summonEvent);
     }
   }
   ```

### Pet Classification Helpers

```typescript
function isPermanentPet(guid: string): boolean {
  return PERMANENT_PETS.includes(extractNPCID(guid));
}

function isWildImp(guid: string): boolean {
  return [WILD_IMP_HOG, WILD_IMP_INNER_DEMONS].includes(extractNPCID(guid));
}

function isWarlockPet(guid: string): boolean {
  return isPermanentPet(guid) || Boolean(PETS[extractNPCID(guid)]);
}
```

### Elixir Implementation Pattern

```elixir
defmodule CombatLogParser.Normalizers.PetNormalizer do
  @moduledoc """
  Tracks pet ownership and attributes pet damage to owners.
  """

  @behaviour CombatLogParser.Normalizers.Normalizer

  def priority, do: 10  # Run early, after event ordering

  def normalize(events) do
    # Pass 1: Build ownership map from SPELL_SUMMON events
    pet_owners = build_ownership_map(events)

    # Pass 2: Fabricate summons for prepull pets
    events = fabricate_prepull_summons(events, pet_owners)

    # Pass 3: Add ownership metadata to all pet events
    add_ownership_metadata(events, pet_owners)
  end

  defp build_ownership_map(events) do
    events
    |> Enum.filter(&(&1.type == "SPELL_SUMMON"))
    |> Enum.reduce(%{}, fn event, acc ->
      pet_guid = get_target_guid(event)
      owner_guid = get_source_guid(event)
      owner_name = get_source_name(event)

      Map.put(acc, pet_guid, %{
        owner_guid: owner_guid,
        owner_name: owner_name,
        summon_time: event.timestamp
      })
    end)
  end
end
```

---

## Event Linking System

### Purpose

Create bidirectional relationships between related events for complex queries.

### Link Types

**Common Links:**
- Cast → Damage (track which damage came from which cast)
- Summon → Despawn (track pet lifetime)
- Buff Application → Buff Removal (track duration)
- Cooldown → Effects (measure cooldown efficiency)

### Implementation Pattern

**Link Specification:**
```typescript
const LINKS: EventLink[] = [
  {
    linkingEventId: SPELL_ID,
    linkingEventType: EventType.Cast,
    referencedEventId: SPELL_ID,
    referencedEventType: EventType.Damage,
    forwardBufferMs: 5000,      // Search 5s forward
    backwardBufferMs: 0,         // Don't search backward
    anyTarget: true,              // Match any target
    anySource: false,             // Must match source
    maximumLinks: 10,             // Max 10 damage per cast
    reverseLinkRelation: 'cast', // Add reverse link
  }
];
```

**Linking Process:**
```typescript
linkEvents(events: AnyEvent[], specs: EventLink[]): AnyEvent[] {
  for (const spec of specs) {
    for (let i = 0; i < events.length; i++) {
      const linkingEvent = events[i];

      if (!matchesSpec(linkingEvent, spec)) continue;

      // Search forward for referenced events
      const startIdx = i + 1;
      const endIdx = findEndIndex(events, linkingEvent.timestamp + spec.forwardBufferMs);

      for (let j = startIdx; j < endIdx; j++) {
        const referencedEvent = events[j];

        if (matchesReference(referencedEvent, linkingEvent, spec)) {
          // Add bidirectional link
          linkingEvent._linkedEvents.push(referencedEvent);
          if (spec.reverseLinkRelation) {
            referencedEvent._linkedEvents.push(linkingEvent);
          }
        }
      }
    }
  }
  return events;
}
```

### Elixir Implementation Pattern

```elixir
defmodule CombatLogParser.Normalizers.EventLinker do
  @behaviour CombatLogParser.Normalizers.Normalizer

  def priority, do: 20  # Run after pet normalization

  def normalize(events) do
    link_specs()
    |> Enum.reduce(events, fn spec, acc_events ->
      link_events(acc_events, spec)
    end)
  end

  defp link_specs do
    [
      # Link casts to damage
      %{
        linking_event_type: "SPELL_CAST_SUCCESS",
        referenced_event_type: "SPELL_DAMAGE",
        forward_buffer_ms: 5000,
        match_spell: true,
        max_links: 10
      },
      # Link summons to despawns
      %{
        linking_event_type: "SPELL_SUMMON",
        referenced_event_type: "SPELL_INSTAKILL",
        forward_buffer_ms: 30000,
        match_target: true,
        max_links: 1
      }
    ]
  end
end
```

---

## Module Architecture

### Class Hierarchy

```
Module (base class)
  ├─ EventSubscriber
  │   └─ Analyzer
  │       ├─ DamageAnalyzer
  │       ├─ HealingAnalyzer
  │       └─ [Spec analyzers...]
  └─ EventsNormalizer
      ├─ EventOrderNormalizer
      ├─ EventLinkNormalizer
      └─ [Other normalizers...]
```

### Dependency Injection

```typescript
class DemonologyAnalyzer extends Analyzer {
  // Declare dependencies (automatically injected)
  static dependencies = {
    combatants: Combatants,
    abilities: Abilities,
    pets: Pets,
  };

  // Access injected dependencies
  analyze() {
    const myPets = this.pets.getPlayerPets(this.owner);
    // ...
  }
}
```

**Resolution:**
- Modules initialized iteratively (up to 100 iterations)
- Each iteration tries to initialize modules with satisfied dependencies
- Failed modules tracked and retried
- Graceful degradation on permanent failures

### Elixir Translation (Use OTP Instead)

Don't replicate 100-iteration dependency injection. Use Elixir's supervision trees:

```elixir
defmodule CombatLogParser.Analyzer.Supervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def init(_init_arg) do
    children = [
      {CombatLogParser.Analyzers.DamageAnalyzer, []},
      {CombatLogParser.Analyzers.PetDamageAnalyzer, []},
      {CombatLogParser.Analyzers.HealingAnalyzer, []},
      # Dependencies resolved via process lookup
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

---

## Normalizer Pattern

### Base Class

```typescript
abstract class EventsNormalizer extends Module {
  abstract priority: number;  // Lower = earlier execution

  abstract normalize(events: AnyEvent[]): AnyEvent[];
}
```

### Example: PrepullPetNormalizer

```typescript
class PrepullPetNormalizer extends EventsNormalizer {
  priority = 30;

  normalize(events: AnyEvent[]): AnyEvent[] {
    const fightStart = events[0].timestamp;
    const summonedPets = new Set<string>();
    const fabricatedEvents: AnyEvent[] = [];

    // Track legitimate summons
    for (const event of events) {
      if (event.type === EventType.Summon) {
        summonedPets.add(event.targetID);
      }
    }

    // Scan first 30 seconds for orphan pet events
    for (const event of events) {
      if (event.timestamp - fightStart > 30000) break;

      if (this.isPetEvent(event) && !summonedPets.has(event.sourceID)) {
        // Fabricate summon event
        const summon = this.fabricateSummon(event.sourceID, fightStart);
        fabricatedEvents.push(summon);
        summonedPets.add(event.sourceID);
      }
    }

    // Insert fabricated events at beginning
    return [...fabricatedEvents, ...events];
  }

  private fabricateSummon(petGUID: string, timestamp: number): SummonEvent {
    const petInfo = this.getPetInfo(petGUID);

    return {
      type: EventType.Summon,
      timestamp: timestamp,
      sourceID: this.owner.playerId,
      targetID: petGUID,
      abilityGameID: petInfo.summonAbility,
      __fabricated: true,
    };
  }
}
```

### Elixir Implementation

```elixir
defmodule CombatLogParser.Normalizers.PrepullPetNormalizer do
  @behaviour CombatLogParser.Normalizers.Normalizer

  def priority, do: 30

  def normalize(events) do
    fight_start = hd(events).timestamp
    summoned_pets = track_summoned_pets(events)

    # Find orphan pet events in first 30 seconds
    orphan_pets =
      events
      |> Enum.take_while(&(time_diff(&1.timestamp, fight_start) <= 30_000))
      |> Enum.filter(&is_pet_event?/1)
      |> Enum.reject(&MapSet.member?(summoned_pets, get_source_guid(&1)))
      |> Enum.map(&get_source_guid/1)
      |> Enum.uniq()

    # Fabricate summon events
    fabricated_summons =
      orphan_pets
      |> Enum.map(&fabricate_summon(&1, fight_start))

    # Prepend fabricated events
    fabricated_summons ++ events
  end

  defp fabricate_summon(pet_guid, timestamp) do
    %Event{
      type: "SPELL_SUMMON",
      timestamp: timestamp,
      data: [...],  # Fill in summon data
      fabricated: true
    }
  end
end
```

---

## Analyzer Pattern

### Base Class

```typescript
abstract class Analyzer extends EventSubscriber {
  // Subscribe to events
  addEventListener<ET extends EventType>(
    eventType: ET,
    listener: EventListener<ET>
  ): void;

  // Produce outputs
  statistic?(): React.ReactNode;
  suggestions?(when: When): Suggestion[];
  tab?(): React.ReactNode;
}
```

### Example: PetDamageAnalyzer

```typescript
class PetDamage extends Analyzer {
  static dependencies = {
    pets: Pets,
  };

  pets: Record<number, PetDamageInfo> = {};

  constructor(options: Options) {
    super(options);
    this.addEventListener(EventType.Damage, this.onDamage);
  }

  onDamage(event: DamageEvent) {
    const petInfo = this.pets.getPetInfo(event.sourceID);
    if (!petInfo) return;  // Not a pet

    this.addDamage(petInfo.guid, petInfo.instance, event.amount);
  }

  addDamage(petGuid: number, instance: number, amount: number) {
    if (!this.pets[petGuid]) {
      this.pets[petGuid] = { instances: {}, total: 0 };
    }

    this.pets[petGuid].instances[instance] =
      (this.pets[petGuid].instances[instance] || 0) + amount;
    this.pets[petGuid].total += amount;
  }

  get permanentPetDamage(): number {
    return Object.entries(this.pets)
      .filter(([guid]) => isPermanentPet(Number(guid)))
      .reduce((sum, [, info]) => sum + info.total, 0);
  }

  statistic() {
    return (
      <StatisticBox
        icon={<SpellIcon id={SPELLS.SUMMON_FELGUARD} />}
        value={`${formatNumber(this.permanentPetDamage)}`}
        label="Pet Damage"
      />
    );
  }
}
```

### Elixir Implementation

```elixir
defmodule CombatLogParser.Analyzers.PetDamageAnalyzer do
  use GenServer

  alias CombatLogParser.Event

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(_) do
    {:ok, %{
      pet_damage: %{},
      pet_owners: %{}
    }}
  end

  def analyze(encounter) do
    GenServer.call(__MODULE__, {:analyze, encounter})
  end

  def handle_call({:analyze, encounter}, _from, state) do
    result =
      encounter.events
      |> Enum.filter(&damage_event?/1)
      |> Enum.reduce(%{}, &accumulate_damage/2)
      |> aggregate_by_owner(state.pet_owners)

    {:reply, result, state}
  end

  defp accumulate_damage(event, acc) do
    source_guid = get_source_guid(event)
    damage = extract_damage(event)

    Map.update(acc, source_guid, damage, &(&1 + damage))
  end

  defp aggregate_by_owner(pet_damage, pet_owners) do
    pet_damage
    |> Enum.group_by(fn {pet_guid, _} ->
      Map.get(pet_owners, pet_guid, pet_guid)
    end)
    |> Enum.map(fn {owner, damages} ->
      total = damages |> Enum.map(&elem(&1, 1)) |> Enum.sum()
      {owner, total}
    end)
    |> Map.new()
  end
end
```

---

## Code Examples

### Example 1: Building Pet Ownership Map

```elixir
def build_pet_ownership_map(events, player_name) do
  events
  |> Enum.filter(&(&1.type == "SPELL_SUMMON"))
  |> Enum.reduce(%{}, fn event, acc ->
    source_name = Enum.at(event.data, 2, "")
    target_guid = Enum.at(event.data, 6, "")

    if String.contains?(source_name, player_name) do
      Map.put(acc, target_guid, player_name)
    else
      acc
    end
  end)
end
```

### Example 2: Attributing Pet Damage

```elixir
def analyze_with_pets(encounter, player_name) do
  pet_owners = build_pet_ownership_map(encounter.events, player_name)

  encounter.events
  |> Enum.filter(&damage_event?/1)
  |> Enum.reduce(%{player: 0, pets: 0}, fn event, acc ->
    source_guid = Enum.at(event.data, 1, "")
    source_name = Enum.at(event.data, 2, "")
    damage = extract_damage(event)

    cond do
      String.contains?(source_name, player_name) ->
        %{acc | player: acc.player + damage}

      Map.has_key?(pet_owners, source_guid) ->
        %{acc | pets: acc.pets + damage}

      true ->
        acc
    end
  end)
end
```

### Example 3: Event Linking

```elixir
def link_casts_to_damage(events) do
  events
  |> Enum.with_index()
  |> Enum.reduce(events, fn {event, idx}, acc ->
    if event.type == "SPELL_CAST_SUCCESS" do
      spell_id = Enum.at(event.data, 9, "")
      cast_time = event.timestamp

      # Find damage events within 5 seconds
      linked_damage =
        events
        |> Enum.drop(idx + 1)
        |> Enum.take_while(&(time_diff(&1.timestamp, cast_time) <= 5000))
        |> Enum.filter(fn e ->
          e.type == "SPELL_DAMAGE" and
          Enum.at(e.data, 9, "") == spell_id
        end)

      # Update event with links
      updated_event = %{event | linked_events: linked_damage}
      List.replace_at(acc, idx, updated_event)
    else
      acc
    end
  end)
end
```

### Example 4: Detecting Rotation Mistakes

```elixir
def detect_shard_capping(events, player_name) do
  events
  |> Enum.filter(&resource_event?/1)
  |> Enum.filter(&player_source?(&1, player_name))
  |> Enum.chunk_every(2, 1, :discard)
  |> Enum.filter(fn [prev, curr] ->
    get_resource(prev) == 5 and get_resource(curr) == 5
  end)
  |> length()
end
```

---

## Key Takeaways for Elixir Implementation

### 1. Use OTP, Not Complex DI
- Don't replicate 100-iteration dependency injection
- Use supervision trees and GenServers
- Process lookup for dependencies

### 2. Normalizers as Pipeline
- Pure functions that transform event lists
- Priority-based ordering
- Sequential execution (reduce pattern)

### 3. Event Metadata
- Add `_linked_events`, `_fabricated` flags
- Update Event struct to support metadata
- Maintain event immutability

### 4. Pet Attribution is Critical
- Track `SPELL_SUMMON` events first
- Build GUID → owner mapping
- Fabricate prepull summons
- Aggregate pet + player damage

### 5. GenStage for Real-Time
- WoWAnalyzer is batch-oriented
- Use GenStage/Flow for streaming
- Better for real-time use case

### 6. Leverage Elixir Strengths
- Pattern matching for event types
- Streams for large files
- Concurrent analyzers via OTP
- Phoenix LiveView for dashboard

---

**Reference:** This document should be consulted when implementing normalizers, analyzers, or pet tracking features.
