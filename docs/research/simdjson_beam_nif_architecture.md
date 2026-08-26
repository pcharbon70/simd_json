# Designing a simdjson On-Demand NIF for Elixir / BEAM

## Overview

For Elixir, I would design a simdjson wrapper around **three constraints**:

1. **Never materialize the whole JSON tree unless explicitly requested.**
2. **Never let simdjson work run unpredictably on a normal BEAM scheduler.**
3. **Keep the JSON binary alive for exactly as long as the native On-Demand cursor needs it.**

The crucial observation is that simdjson’s On-Demand API and the BEAM have very different ownership and execution models, so the wrapper should not pretend that an On-Demand document is simply an Elixir struct.

---

# Recommended Architecture

I would expose an Elixir API roughly like this:

```elixir
{:ok, doc} = SimdJson.open(json)

{:ok, name} =
  doc
  |> SimdJson.get("customer")
  |> SimdJson.get("name")
  |> SimdJson.string()

SimdJson.close(doc)
```

But internally:

```text
Elixir
   │
   ▼
%SimdJson.Document{resource: ref}
   │
   ▼
BEAM Resource
   │
   ├── owns input binary
   ├── owns simdjson parser
   ├── owns On-Demand document/cursor state
   ├── tracks current cursor generation
   └── lock / ownership metadata
             │
             ▼
       simdjson C++
             │
             ▼
     structural index
          +
     On-Demand cursor
```

The `Document` should be an **opaque NIF resource**, not a collection of BEAM terms.

---

# 1. Do Not Run Parsing on Normal Schedulers

This is the first hard rule.

OTP's NIF model is designed around the idea that ordinary NIFs should be very short. If native work cannot reliably complete within a very small bounded time, it should not monopolize an ordinary scheduler thread.

So I would categorize operations.

## Tiny operations

Something like:

```elixir
SimdJson.type(cursor)
```

might safely execute synchronously **if we can prove it is bounded**.

Initially, however, I would favor safety over cleverness.

## Potentially expensive operations

These should never be ordinary synchronous NIFs:

```elixir
SimdJson.open(json)
SimdJson.find(doc, path)
SimdJson.array(doc, ...)
SimdJson.materialize(doc)
SimdJson.each(...)
```

There are two reasonable implementation strategies:

```text
A. dirty_cpu NIF

B. private native worker threads
```

For this project, I favor **B for long-running traversal**, with dirty NIFs reserved for well-bounded operations.

---

# 2. Dirty CPU vs Native Worker Threads

This distinction matters.

A dirty CPU NIF protects the **normal schedulers**, but it can still occupy one of the limited dirty CPU scheduler threads.

Imagine 32 clients simultaneously doing:

```elixir
SimdJson.scan(2_gb_json)
```

If all of them become dirty CPU jobs:

```text
Normal schedulers
      │
      │ protected
      ▼

Dirty schedulers

D1   █████████████
D2   █████████████
D3   █████████████
...
```

The VM survives, but you have now turned dirty schedulers into your JSON worker pool.

I would not do that.

Instead:

```text
BEAM process
     │
     │ request
     ▼
NIF
     │
     │ enqueue
     ▼
native JSON worker pool
     │
     ▼
simdjson
     │
     │ enif_send()
     ▼
BEAM process
```

The native worker approach lets the NIF return immediately, while the actual work executes outside BEAM scheduler threads.

That is especially attractive here.

---

# 3. Use a Fixed Native Worker Pool

Do not spawn an OS thread for every request.

Instead:

```text
                    ┌──────── Worker 1 ─── simdjson parser
                    │
BEAM ── work queue ─┼──────── Worker 2 ─── simdjson parser
                    │
                    ├──────── Worker 3 ─── simdjson parser
                    │
                    └──────── Worker N ─── simdjson parser
```

Something like:

```elixir
config :simdjson,
  workers: System.schedulers_online()
```

or perhaps a smaller default:

```text
max(2, schedulers_online / 2)
```

This gives explicit backpressure.

```text
1000 simultaneous JSON requests

        │
        ▼
bounded queue
        │
   ┌────┴────┐
   ▼         ▼
worker     worker
```

rather than:

```text
1000 calls
    ↓
1000 native threads
```

or:

```text
1000 dirty NIFs
    ↓
dirty scheduler queue
```

---

# 4. Preserve simdjson's On-Demand Design

This is the most important part.

I would **not** make the primary API:

```elixir
SimdJson.decode(json)
```

because that immediately turns:

```text
simdjson
   ↓
very efficient native traversal
```

into:

```text
simdjson
   ↓
allocate everything as BEAM maps/lists
   ↓
GC pressure
```

Instead, the primary abstraction should be a **native document handle**.

```elixir
{:ok, doc} = SimdJson.parse(json)

{:ok, user} = SimdJson.at(doc, ["users", 125])
{:ok, name} = SimdJson.at(user, "name")
```

Internally, `doc` could conceptually resemble:

```c
struct BeamDocument {
    ErlNifBinary input;

    simdjson::ondemand::parser parser;
    simdjson::ondemand::document document;

    uint64_t generation;

    mutex lock;
};
```

Not necessarily that exact C++ layout, but that ownership model.

---

# 5. Keep the Original BEAM Binary Alive

This is essential.

simdjson On-Demand operates against the source buffer. That memory must remain valid while the parser still references it.

When the caller gives:

```elixir
json = File.read!("huge.json")
```

the NIF should retain the binary through the resource lifetime.

Conceptually:

```text
BEAM binary
██████████████████████████████

       ▲
       │ retained
       │
Document resource
       │
       └── simdjson points here
```

Then:

```text
%SimdJson.Document{}
```

keeps:

```text
input binary
+
native parser
+
cursor state
```

alive together.

When the resource is garbage-collected:

```text
BEAM resource destructor
        │
        ├── destroy On-Demand document
        ├── destroy parser
        └── release binary
```

This gives natural lifetime semantics.

---

# 6. Avoid Copying the JSON Input Where Possible

Ideally:

```elixir
SimdJson.parse(binary)
```

should become:

```text
BEAM refc binary
      │
      │ zero-copy
      ▼
simdjson
```

rather than:

```text
BEAM binary
      │
      │ memcpy
      ▼
native buffer
      │
      ▼
simdjson
```

There is one complication.

simdjson expects safe padding around input for some fast parsing paths. So the wrapper must verify whether the chosen simdjson API can safely operate on the BEAM-provided memory.

If not, I would support two modes.

## Fast zero-copy when possible

```text
BEAM binary
    │
    ▼
simdjson view
```

## Padded native copy otherwise

```text
BEAM binary
    │
    │ copy once
    ▼
native aligned/padded buffer
    │
    ▼
simdjson
```

Even with one copy, On-Demand can still be far cheaper than building millions of BEAM terms.

---

# 7. Do Not Expose Raw Cursors Too Freely

There is a subtle issue with simdjson On-Demand.

It is fundamentally **forward-moving**.

It is not:

```text
immutable JSON tree
```

It is closer to:

```text
iterator through structural index
```

Therefore something like:

```elixir
a = SimdJson.get(doc, "a")
b = SimdJson.get(doc, "b")
c = SimdJson.get(doc, "a")
```

may not map cleanly to the underlying semantics.

I would make this explicit in the API.

Possibly:

```elixir
SimdJson.cursor(doc, fn cursor ->
  {:ok, name} = SimdJson.field(cursor, "name")
  {:ok, age} = SimdJson.field(cursor, "age")

  {name, age}
end)
```

or:

```elixir
SimdJson.select(doc, [
  ["customer", "name"],
  ["customer", "address", "city"],
  ["order", "total"]
])
```

The latter is especially appealing for Elixir.

---

# 8. `select/2` Could Be the Killer BEAM API

Imagine:

```elixir
{:ok, result} =
  SimdJson.select(json, %{
    id: ["customer", "id"],
    name: ["customer", "name"],
    total: ["order", "total"]
  })
```

returning:

```elixir
%{
  id: 1234,
  name: "Acme",
  total: 987.42
}
```

Internally:

```text
500 MB JSON
       │
       ▼
structural scan
       │
       ▼
On-Demand traversal
       │
       ├── customer.id
       ├── customer.name
       └── order.total
              │
              ▼
      only 3 BEAM terms
```

That is where this becomes genuinely different from Jason.

Jason fundamentally gives you:

```text
JSON
 ↓
entire BEAM representation
```

whereas this could offer:

```text
JSON
 ↓
native indexed representation
 ↓
requested projection
 ↓
small BEAM result
```

That could be extremely powerful.

---

# 9. Think Database Query, Not Parser

I would model the Elixir API more like a query engine.

For example:

```elixir
SimdJson.query(json,
  customer_name: "$.customer.name",
  amount: "$.order.total"
)
```

or, preferably without introducing JSONPath initially:

```elixir
SimdJson.query(json, [
  {:customer_name, ["customer", "name"]},
  {:amount, ["order", "total"]}
])
```

Architecturally:

```text
JSON document
       │
       ▼
simdjson structural index
       │
       ▼
projection specification
       │
       ▼
On-Demand traversal
       │
       ▼
minimal Elixir terms
```

This preserves the value proposition of On-Demand.

---

# 10. Streaming Arrays Are Particularly Interesting

Suppose you have:

```json
{
  "customers": [
     {...},
     {...},
     {...},
     ...
  ]
}
```

with ten million objects.

You do not want:

```elixir
SimdJson.decode(json)
```

You want something closer to:

```elixir
SimdJson.stream(json, ["customers"])
|> Stream.map(&extract_customer/1)
|> Stream.run()
```

But there is an important caveat.

We should not implement an Elixir stream by having every element perform:

```text
BEAM → NIF → BEAM → NIF → BEAM
```

for every primitive field.

That would destroy performance.

Instead, batch.

```text
Native parser
    │
    ├── parse 1,000 records
    │
    ▼
BEAM
    │
    ├── process batch
    │
    ▼
next 1,000
```

So something like:

```elixir
SimdJson.stream_array(json, ["customers"],
  batch_size: 1_000,
  fields: [
    id: ["id"],
    name: ["name"]
  ]
)
```

would be much better.

---

# 11. Scheduler-Safe Batching

This also gives cooperative execution boundaries.

Instead of native code doing:

```text
parse all 10 million
████████████████████████████████
```

we do:

```text
parse batch
████

return/yield

parse batch
████

return/yield

parse batch
████
```

For native worker threads, the BEAM scheduler is not blocked anyway.

But batching additionally provides:

- cancellation points;
- backpressure;
- bounded BEAM allocations;
- bounded message size;
- fairness between consumers.

---

# 12. Resource Ownership Should Be Process-Aware

I would make a document/cursor owned by one Elixir process by default.

Something like:

```elixir
{:ok, doc} = SimdJson.open(json)
```

records:

```text
owner_pid = self()
```

Then calls from another process return:

```elixir
{:error, :not_owner}
```

unless explicitly transferred.

Why?

Because On-Demand cursors are stateful.

You do not want:

```text
Process A ──► cursor
Process B ──► cursor
Process C ──► cursor
```

all advancing the same native iterator.

A resource lock prevents memory corruption, but it does not make those semantics sensible.

So I would make cursors **single-owner**.

---

# 13. Allow Immutable Document-Level Operations Separately

Eventually we could expose two modes:

```text
Document
  │
  ├── immutable-ish operations
  │
  └── creates Cursor
            │
            └── single owner / forward only
```

For example:

```elixir
{:ok, doc} = SimdJson.open(json)
{:ok, cursor} = SimdJson.cursor(doc)
```

with types:

```elixir
%SimdJson.Document{}
%SimdJson.Cursor{}
```

This makes the statefulness explicit.

---

# 14. Prevent Resource Use-After-Free

The native resource graph needs to preserve lifetimes:

```text
Input Buffer
      ▲
      │
Document
      ▲
      │
Cursor
```

A Cursor resource therefore needs to retain the parent Document resource.

That means:

```text
cursor alive
   ↓
document cannot disappear
   ↓
buffer cannot disappear
```

The resource destructor chain then becomes safe.

---

# 15. Avoid Retaining Tiny Substrings Through Giant Binaries

This is a classic BEAM concern.

Suppose:

```text
JSON = 2 GB
```

and someone asks for:

```text
"name": "Bob"
```

If we return a sub-binary referencing the original 2 GB binary:

```text
<<"Bob">>
   │
   └──────── retains 2GB source binary
```

that is undesirable.

So values crossing into BEAM should usually be **copied into fresh small binaries**.

That sounds counterintuitive for performance, but:

```text
copy 3 bytes
```

is much better than:

```text
retain 2 GB for hours
```

So I would establish:

```text
input side: zero-copy when possible
output strings: normally copy
```

and perhaps expose an advanced option later:

```elixir
copy_strings: false
```

only for controlled short-lived pipelines.

---

# 16. Atom Keys Should Never Be Automatic

Absolutely do not do:

```elixir
%{some_json_key_as_atom: ...}
```

for arbitrary JSON.

Default:

```elixir
%{"some_json_key" => ...}
```

For projections:

```elixir
SimdJson.select(json,
  name: ["customer", "name"]
)
```

the atoms come from **caller code**, not JSON input.

That is safe.

---

# 17. The Elixir API I Would Build

I think there should be three layers.

## Layer 1 — Compatibility

```elixir
SimdJson.decode(json)
SimdJson.decode!(json)
```

Jason-like convenience.

Internally this materializes everything.

Useful for adoption, but **not the flagship API**.

## Layer 2 — Projection

```elixir
SimdJson.select(json, [
  {:id, ["user", "id"]},
  {:name, ["user", "name"]}
])
```

This should be the primary high-performance API.

## Layer 3 — Streaming

```elixir
SimdJson.stream(json,
  path: ["users"],
  fields: [
    id: ["id"],
    email: ["email"]
  ],
  batch_size: 1_000
)
```

For huge data.

---

# 18. Where Zigler Fits

Zigler is genuinely interesting here.

Useful concurrency modes include:

```text
:synchronous
:dirty_cpu
:dirty_io
:threaded
:yielding
```

Zigler also offers facilities around:

- BEAM marshalling;
- resources;
- binaries;
- BEAM-compatible allocators;
- native threading;
- direct access to `erl_nif`;
- C-library integration.

For example, a NIF can conceptually be marked:

```elixir
nifs: [
  parse: [concurrency: :dirty_cpu]
]
```

or:

```elixir
nifs: [
  parse: [concurrency: :threaded]
]
```

A threaded mode is a particularly good fit for third-party native libraries that do not conveniently cooperate with BEAM scheduler yielding.

simdjson fits that description well.

---

# 19. Zig Will Not Make simdjson Faster

This distinction is important.

If we are using:

```text
Zig
  ↓
C++ simdjson
```

Zigler will not somehow make the SIMD parser itself faster.

The hot path remains:

```text
simdjson C++
    ↓
AVX2 / AVX-512 / NEON etc.
```

The performance value of Zigler is primarily:

```text
better NIF ergonomics
+
safer memory handling
+
nice Elixir integration
+
easy C ABI interaction
+
concurrency helpers
```

not:

```text
faster SIMD
```

---

# 20. simdjson Is C++: Use a Tiny C ABI Shim

Zig's C interoperability is excellent.

C++ interoperability is less straightforward.

So I would introduce a **tiny C ABI shim**:

```text
Elixir
   │
   ▼
Zigler / Zig
   │
   ▼
C API shim
   │
   ▼
simdjson C++
```

For example:

```c
typedef void* sj_parser;
typedef void* sj_document;
typedef void* sj_cursor;

sj_parser sj_parser_create(void);
void sj_parser_destroy(sj_parser);

int sj_parse(
    sj_parser,
    const uint8_t *data,
    size_t length,
    sj_document *out
);

int sj_get_string(
    sj_document,
    const char *path,
    size_t path_len,
    const char **value,
    size_t *value_len
);
```

The C++ implementation hides all templates and exceptions.

That produces a stable boundary:

```text
C++ implementation details
          │
          X
       C ABI
          │
          ▼
        Zig
          │
          ▼
        BEAM
```

I like that design even if Zigler is not used.

---

# 21. Preferred Stack for a First Implementation

My preferred stack would be:

```text
┌────────────────────────────┐
│          Elixir            │
│                            │
│ SimdJson                   │
│ SimdJson.Document          │
│ SimdJson.Cursor            │
│ SimdJson.Stream            │
└─────────────┬──────────────┘
              │
              ▼
┌────────────────────────────┐
│          Zigler            │
│                            │
│ resources                  │
│ binaries                   │
│ threaded execution         │
│ BEAM messaging             │
└─────────────┬──────────────┘
              │
              ▼
┌────────────────────────────┐
│           Zig              │
│                            │
│ lifetime management        │
│ work queue                 │
│ result conversion          │
│ scheduler cooperation      │
└─────────────┬──────────────┘
              │ C ABI
              ▼
┌────────────────────────────┐
│         C++ shim           │
│                            │
│ stable opaque handles      │
│ exception boundary         │
└─────────────┬──────────────┘
              │
              ▼
┌────────────────────────────┐
│        simdjson            │
│                            │
│ SIMD stage 1               │
│ On-Demand traversal        │
└────────────────────────────┘
```

---

# 22. One Thing I Would Not Do

I would not implement this:

```elixir
doc["foo"]["bar"][3]["baz"]
```

with every operator turning into another NIF call.

That produces:

```text
BEAM
 ↓
NIF
 ↑
BEAM
 ↓
NIF
 ↑
BEAM
 ↓
NIF
```

The NIF crossing is relatively cheap, but repeated thousands or millions of times defeats the architecture.

Instead:

```elixir
SimdJson.at(doc, ["foo", "bar", 3, "baz"])
```

should cross the boundary **once**.

Even better:

```elixir
SimdJson.select(doc, %{
  baz: ["foo", "bar", 3, "baz"],
  qux: ["foo", "bar", 3, "qux"]
})
```

One crossing.

---

# 23. Cancellation Needs to Be Designed In

For a large job:

```elixir
task =
  Task.async(fn ->
    SimdJson.select(huge_json, spec)
  end)
```

if the calling process dies, we do not want native code consuming CPU for another minute.

The worker should periodically check an atomic cancellation flag.

With our own worker pool, I would explicitly monitor the calling PID and mark work cancelled.

```text
caller dies
    │
    ▼
monitor DOWN
    │
    ▼
cancel flag
    │
    ▼
native worker stops at next safe boundary
```

Good cancellation boundaries include:

- projection completion;
- record batches;
- array batch boundaries;
- fixed byte or structural-index intervals.

---

# 24. Error Representation

Do not throw native exceptions through the boundary.

C++ shim:

```text
simdjson error
      ↓
numeric error code
```

Zig:

```text
numeric code
      ↓
BEAM tuple
```

Elixir:

```elixir
{:error, %SimdJson.Error{
  reason: :incorrect_type,
  byte_offset: 123_442
}}
```

Potential categories:

```elixir
:invalid_json
:invalid_utf8
:unexpected_eof
:incorrect_type
:no_such_field
:number_out_of_range
:cursor_consumed
:cancelled
```

---

# 25. Benchmark the Right Things

I would **not** begin by benchmarking only:

```text
SimdJson.decode()
vs
Jason.decode()
```

That is useful, but it misses the point.

I would benchmark three workloads.

## Full Materialization

```text
JSON → full BEAM tree
```

Jason vs simdjson.

## Projection

```text
1 GB JSON
→ retrieve five fields
```

This is where simdjson On-Demand should have a major advantage.

## Array ETL

```text
1 GB JSON array
→ extract 3 fields/record
→ batches
```

This is likely one of the strongest real-world cases.

Measure:

```text
throughput
latency
scheduler utilization
dirty scheduler utilization
BEAM reductions
memory
binary memory
GC time
native memory
99th-percentile scheduler latency
```

The **scheduler latency** benchmark matters as much as GB/s.

---

# Proposed Implementation Phases

If I were starting the library, I would build it in this order:

```text
Phase 1
────────────────────────
C++ simdjson
+
tiny C ABI
+
Zigler NIF
+
opaque Document resource


Phase 2
────────────────────────
SimdJson.select/2

one native traversal
one BEAM result


Phase 3
────────────────────────
batched streaming arrays

native cursor
       ↓
batch of projected rows
       ↓
Elixir Enumerable


Phase 4
────────────────────────
worker pool
cancellation
backpressure
telemetry


Phase 5
────────────────────────
Jason-compatible decode API
```

Notice that I would implement `decode/1` **last**.

The interesting value proposition is not:

> **Jason, except faster.**

It is:

> **A BEAM-native interface to simdjson's On-Demand query model that avoids constructing data the Elixir program never asked for.**

That is a substantially more interesting library.

---

# Final Recommendation

For an Elixir-first implementation, I would use:

```text
Elixir API
   │
   ▼
Zigler
   │
   ▼
Zig ownership / scheduling layer
   │
   ▼
small C ABI shim
   │
   ▼
official simdjson C++
```

The Zigler layer is attractive not because it can make simdjson's SIMD code faster, but because it gives us a strong place to solve the hard BEAM-specific problems:

- resource ownership;
- scheduler safety;
- native concurrency;
- cancellation;
- binary lifetime;
- batching;
- backpressure;
- result marshalling.

The most important product decision is to make **projection and batched streaming first-class APIs**, while treating complete JSON-to-BEAM decoding as a compatibility feature.

A compiled projection API could eventually be especially powerful:

```elixir
projection =
  SimdJson.compile(%{
    id: ["customer", "id"],
    name: ["customer", "name"],
    total: ["order", "total"]
  })

SimdJson.select(json, projection)
```

That would allow a projection specification to be prepared once and applied efficiently to millions of JSON documents without repeatedly rebuilding path metadata.

This approach preserves the architectural advantage of simdjson:

```text
SIMD structural discovery
        ↓
On-Demand traversal
        ↓
only requested values cross into BEAM
```

rather than reducing simdjson to a faster eager decoder.
