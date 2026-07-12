# diana_generator

Code generator for the [Diana framework](../../README.md). Add it to
`dev_dependencies` next to `build_runner`; no `build.yaml` needed in your
application.

Three builders:

- **diana_metadata** — per-library summaries of Diana-annotated declarations
  (cached, invisible).
- **diana_part** — per-library `.diana.dart` part files: route adapters, DTO
  validators, configuration binders.
- **diana_bootstrap** — aggregates the summaries, resolves the DI graph at
  build time (missing providers, ambiguous bindings, cycles and scope
  violations are build errors with precise locations), and emits the
  composition root (`DianaContext`, `buildDianaServer()`, `runDiana()`)
  next to the `@DianaApplication` class.

Architecture notes: all analyzer touch-points live in `src/readers/`, which
immediately convert elements to plain-data models (`src/model/`); graph
resolution (`src/graph/`) and code emission (`src/emit/`) never see analyzer
types. Generated output is deterministic — rebuilding unchanged sources is
byte-identical.
