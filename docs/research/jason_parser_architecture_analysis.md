# Jason JSON Parser Architecture Analysis

## Overview

This document analyzes the Elixir **Jason** JSON library, clarifies whether it wraps another BEAM JSON implementation, and compares its parsing architecture with **simdjson**.

The key conclusion is:

> **Jason is not a wrapper around another Erlang/BEAM JSON parser. It is a pure Elixir JSON parser and encoder implemented directly in the Jason project.**

It does not depend on `jsx`, `jiffy`, `jsone`, Poison, or another JSON parser for its core decoding work.

You may be thinking of **`exjsx`**, which is an Elixir wrapper around the Erlang `jsx` library.

---

# 1. Jason's General Parsing Model

Jason is much closer to a **hand-written recursive/state-machine parser** than to simdjson.

The decoder begins in `Jason.Decoder.parse/2`, which sets up configurable functions for handling keys, strings, objects, and floats before entering the parser through a call conceptually equivalent to:

```elixir
value(data, data, 0, [@terminate], decode)
```

The main parser entry point behaves roughly like:

```text
JSON binary
    │
    ▼
value()
    │
    ├── whitespace → value()
    ├── digit      → number()
    ├── "-"        → number_minus()
    ├── '"'        → string()
    ├── "["        → array()
    ├── "{"        → object()
    ├── "true"     → true
    ├── "false"    → false
    └── "null"     → nil
```

This is fundamentally different from simdjson.

## Jason

```text
read next byte
      ↓
identify token
      ↓
parse token
      ↓
continue
      ↓
identify next token
```

## simdjson

```text
scan many bytes in parallel
      ↓
discover structural positions
      ↓
build structural index
      ↓
interpret values
```

Jason combines **structure discovery and parsing into one pass**.

simdjson deliberately separates those concerns.

---

# 2. Jason Uses BEAM Binary Pattern Matching Heavily

Jason relies strongly on binary pattern matching rather than generic string operations.

Typical parser patterns conceptually look like:

```elixir
<<byte, rest::bits>>
```

or matching known continuations after an initial byte.

For example:

```text
t + "rue"  → true
f + "alse" → false
n + "ull"  → nil
```

This allows the parser to stay very close to operations the BEAM virtual machine and JIT can optimize efficiently.

The parser is therefore built around:

```text
binary matching
+
generated matching clauses
+
integer parser-state tags
+
jump-table-friendly control flow
+
tail-recursive state transitions
```

Jason is not naïve Elixir code; it is carefully structured for the BEAM.

---

# 3. The `bytecase` Optimization

Jason imports an internal code-generation helper:

```elixir
import Codegen, only: [bytecase: 2, bytecase: 3]
```

Rather than relying entirely on ordinary `case` expressions, Jason uses generated code for byte dispatch.

It also represents parser states as integers, conceptually:

```text
0 = terminate
1 = array
2 = key
3 = object
```

This is done to help the compiler/JIT use efficient jump-table-like dispatch.

The parser therefore resembles a compact state machine rather than a large tree of generic function calls.

---

# 4. Number Parsing

Numbers are parsed through specialized states.

Conceptually:

```text
number
   │
   ├── digits
   │
   ├── "."
   │     ↓
   │   fraction
   │
   └── e/E
         ↓
      exponent
```

Jason scans through the number token one byte at a time.

For:

```json
123456
```

the flow is approximately:

```text
1
 ↓
2
 ↓
3
 ↓
4
 ↓
5
 ↓
6
 ↓
extract original binary slice
 ↓
String.to_integer
 ↓
123456
```

The parser tracks the original source binary and extracts the token with operations such as:

```elixir
binary_part(original, skip, len)
```

Integers are then converted to BEAM integers.

Floating-point values are converted through Erlang's native float conversion routines.

This differs from simdjson, where the structural scan can identify the beginning of a token before later stages convert it.

---

# 5. String Parsing

Strings are particularly interesting because Jason has both fast and slow paths.

For a normal unescaped string, Jason scans until it encounters one of:

```text
"
\
control character
non-ASCII UTF-8
```

For the common fast path, it does not copy every byte while scanning.

It remembers the start position and length and later extracts the entire string using:

```elixir
binary_part(original, skip, len)
```

Conceptually:

```text
"name of customer"
 ^                ^
 start            closing quote

remember start
scan until "
binary_part(original, start, length)
```

This is an efficient strategy.

---

# 6. Copy vs Reference Strings

Jason internally supports an important distinction:

```text
strings: :copy
```

versus:

```text
strings: :reference
```

With a reference strategy, a decoded string may be returned as a sub-binary referencing the original JSON binary.

With a copy strategy, Jason creates a fresh binary.

This is exactly the issue that matters for a simdjson BEAM wrapper.

If a tiny returned value references a giant source document:

```text
3-byte result
    │
    └──────── retains 2 GB source binary
```

the source binary may stay alive much longer than intended.

So a simdjson NIF should probably follow a similar policy:

```text
input side: zero-copy when possible
output strings: normally copy
```

---

# 7. Escaped Strings

If the string contains escapes such as:

```json
"Hello\nWorld"
```

the parser can no longer simply return one contiguous slice of the input.

Instead it builds pieces:

```text
"Hello"
"\n"
"World"
```

and accumulates them as iodata.

At the end, the pieces are converted to a binary with something conceptually equivalent to:

```elixir
IO.iodata_to_binary(...)
```

So:

```text
no escapes
──────────
binary_part()
very cheap
```

versus:

```text
escapes
───────
piece
piece
decoded escape
piece
     ↓
iodata
     ↓
new binary
```

This is a very BEAM-friendly design.

---

# 8. Unicode Escape Handling

Jason has an internal Unicode unescaping module:

```elixir
Jason.Decoder.Unescape
```

It uses generated matching clauses and bitwise operations for sequences such as:

```json
"\u00E9"
```

and surrogate pairs.

Rather than repeatedly performing fully general hexadecimal parsing at runtime, parts of this work are code-generated.

This is another example of Jason being optimized around the strengths of the BEAM.

---

# 9. Array Parsing

Arrays are parsed using a list accumulator.

For:

```json
[10, 20, 30]
```

Jason conceptually builds:

```elixir
[30, 20, 10]
```

while parsing.

At the end it reverses the list:

```elixir
:lists.reverse(...)
```

So the flow is:

```text
[
 ↓
10 → [10]
 ↓
20 → [20,10]
 ↓
30 → [30,20,10]
 ↓
]
 ↓
reverse
 ↓
[10,20,30]
```

This is a classic efficient BEAM list-building technique.

---

# 10. Object Parsing

Objects use a similar accumulator strategy.

For:

```json
{
  "name": "Alice",
  "age": 30
}
```

Jason initially builds a list of key/value pairs, conceptually:

```elixir
[
  {"age", 30},
  {"name", "Alice"}
]
```

It then converts the accumulated list to a map:

```elixir
:maps.from_list(...)
```

So the allocation path is roughly:

```text
JSON object
     ↓
temporary tuple/list representation
     ↓
:maps.from_list
     ↓
BEAM map
```

This is one of the important differences from an On-Demand parser.

If a program only needs three values from a huge object, Jason still normally constructs the surrounding BEAM structures.

---

# 11. Jason Uses an Explicit Parser Stack

Jason does not simply depend on deep native recursive calls for every nesting level.

It maintains an explicit parser stack containing state markers such as:

```text
@array
@key
@object
@terminate
```

After parsing a value, a continuation function inspects the parser state and dispatches accordingly:

```text
                  ┌── array()
                  │
value → continue ─┼── object()
                  │
                  ├── key()
                  │
                  └── terminate()
```

This is effectively a hand-written pushdown automaton.

It gives Jason precise control over parser state and nesting.

---

# 12. Jason Architecture Summary

Conceptually, Jason looks like:

```text
                    JSON binary
                         │
                         ▼
                 ┌──────────────┐
                 │    value()   │
                 └──────┬───────┘
                        │
       ┌────────────────┼───────────────────┐
       ▼                ▼                   ▼
    string()         number()          array/object
       │                │                   │
       ▼                ▼                   ▼
 binary_part       binary_part        parser stack
       │                │                   │
       ▼                ▼                   ▼
BEAM binary        Integer/Float       list accumulators
                                           │
                                           ▼
                                    map/list creation
                                           │
                                           ▼
                                      BEAM terms
```

The key property is:

> **Jason constructs the resulting BEAM representation while it parses.**

---

# 13. Jason vs simdjson

| Characteristic | Jason | simdjson |
|---|---|---|
| Implementation | Pure Elixir | C++ |
| Native SIMD | No | Yes |
| Structural discovery | During parsing | Separate Stage 1 |
| Parse strategy | Sequential state machine | Structural index |
| Input scanning | Binary pattern matching | SIMD blocks |
| Branch reduction | BEAM/JIT-oriented codegen | Branchless SIMD |
| UTF-8 | During string parsing | Vectorized Stage 1 |
| Objects | Construct BEAM maps | Optional/lazy |
| Arrays | Construct BEAM lists | Optional/lazy |
| Strings | Sub-binary or copy | Native input references |
| Full tree required | Normally yes | No with On-Demand |
| Projection-only parsing | Not a core concept | Core strength |
| Huge documents | Full BEAM representation | Can avoid materialization |

---

# 14. Why a simdjson Elixir Library Should Not Merely Compete With Jason

Jason is already highly optimized for this transformation:

```text
JSON
 ↓
BEAM terms
```

Trying to build a NIF whose only purpose is:

```text
Jason.decode(json)
```

but somewhat faster would miss the strongest feature of simdjson.

The more interesting architecture is:

```text
            2 GB JSON
                │
                ▼
          SIMD Stage 1
                │
                ▼
        structural index
                │
                ▼
        On-Demand query
                │
        ┌───────┼────────┐
        ▼       ▼        ▼
       id      name     total
        │       │        │
        └───────┼────────┘
                ▼
         tiny BEAM result
```

This avoids building BEAM maps, lists, strings, and intermediate structures that the application never uses.

---

# 15. The More Meaningful Benchmark

The most interesting benchmark is not simply:

```text
Jason.decode(json)
vs
SimdJson.decode(json)
```

A better comparison is:

```text
Jason.decode(json)
    +
Map.get(...)
    +
Map.get(...)
    +
Map.get(...)
```

versus:

```elixir
SimdJson.select(json, [
  id: ["customer", "id"],
  name: ["customer", "name"],
  total: ["order", "total"]
])
```

For a 500 MB, 1 GB, or 2 GB document where only a handful of values are required, these are fundamentally different computational models.

Jason must normally:

```text
scan JSON
   ↓
parse all relevant syntax
   ↓
allocate complete BEAM tree
   ↓
perform map lookups
```

A simdjson On-Demand wrapper could instead:

```text
SIMD scan
   ↓
structural index
   ↓
follow requested paths
   ↓
allocate only requested BEAM values
```

---

# 16. Architectural Implication for a simdjson NIF

After examining Jason's parser design, the strongest conclusion is:

> **Projection should be the centerpiece of an Elixir simdjson API.**

For example:

```elixir
SimdJson.select(json, %{
  id: ["customer", "id"],
  name: ["customer", "name"],
  total: ["order", "total"]
})
```

would provide a genuinely different capability from Jason.

The value proposition should not be:

> Jason, except faster.

It should be:

> A BEAM-native interface to simdjson's On-Demand parser that avoids constructing data the application never asks for.

That preserves the architectural advantage of simdjson rather than reducing it to an eager decoder.

---

# 17. Final Takeaway

Jason is best understood as:

> **A highly optimized pure-Elixir parser written specifically around BEAM binary matching, generated dispatch, explicit parser state, list accumulation, and efficient BEAM term construction.**

simdjson is best understood as:

> **A low-level systems parser that separates structural discovery from value interpretation and can avoid materializing most of a document entirely.**

They therefore solve overlapping but not identical problems.

The strongest opportunity for a new Elixir simdjson NIF is not to replace Jason's normal full-document decoding API, but to add a new class of JSON access:

```text
huge JSON
   ↓
native structural index
   ↓
On-Demand projection
   ↓
minimal BEAM allocations
```

That is where the architectural difference becomes most valuable.
