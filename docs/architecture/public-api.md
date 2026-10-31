# Typed public boundary

The public surface has two halves that share one data shape: an Elixir boundary
for the browser, tasks, and the HTTP controllers, and an OpenAPI document for
external clients. This note records how the boundary is built, what enforces it,
and which limits remain.

## What counts as public

| Module | Role |
|---|---|
| `Hiraeth.Catalog.PublicProjection` | Builders for every public read shape |
| `Hiraeth.Catalog.PublicProjection.*` | Structs and types for books, editions, publishers, series, contributors, pages, covers, sources, facets |
| `HiraethWeb.PublicCatalog` | The read operations, each with a typespec |
| `Hiraeth.Ingestion.SidecarClient` | The typed contract to the private sidecar |
| `HiraethWeb.Api.Spec` | The served OpenAPI document |
| `HiraethWeb.Api.V1.Schemas` | The wire schemas |

Ash resources remain the write-side source of truth. Their attributes,
constraints, and actions carry their own types through Ash, but Ash generates the
domain functions, so those functions do not appear in the hand-written spec
gate. That limit is stated rather than papered over.

## Structs, not maps

Before this boundary existed, `PublicCatalog` returned a mix of structs and bare
maps. A book was a `%Book{}`; an edition detail was a map; a publisher detail was
a map that gained `:editions` and `:groupings` through `Map.put`. A template
could read a field that did not exist and only fail at render time.

Every read shape is now a struct with a `t/0` type. The builders in
`Hiraeth.Catalog.PublicProjection` are the only way a projection is constructed.
They pass the input map to `struct!/2`, which raises on an unknown key, and they
are idempotent, so passing an already-built struct returns it unchanged. A SQL
column added without a matching struct field fails at the boundary instead of
leaking into a response.

Collections are typed through the page envelope:
`PublicProjection.Page.t(Book.t())`. A page of books, editions, publishers,
series, or contributors keeps its entry type in the spec.

## The spec gate

`test/hiraeth/public_api_contract_test.exs` loads each public module and checks
two things with `Code.Typespec`:

- every exported function has a `@spec`, including each arity produced by a
  default argument;
- every projection module exports a `t/0` type.

A function added without a spec fails the fast lane. The gate does not prove the
spec is correct. Dialyzer does that, and `mix ci` now runs `mix dialyzer` after
the static gates. The test environment includes `test/support`, so support
modules are analysed too.

## HTTP serialization

`HiraethWeb.Api.V1.Serializer` is the only module that turns a projection into
wire data. It emits every declared field on every response, including nulls, so
the schema can mark fields as required and clients never have to distinguish an
absent key from a null value. Internal row identifiers and cache paths are
dropped. A cover without a cached public URL is dropped rather than emitted with
a null image URL.

The OpenAPI document is assembled from `OpenApiSpex.ControllerSpecs` operations
and the schema modules. Tests do two separate jobs:

- `test/hiraeth_web/api/spec_contract_test.exs` asserts the document covers
  exactly the versioned routes, with no browser or health route, and that each
  operation has an operation id, a JSON success schema, and a 4xx response.
- `test/hiraeth_web/api/v1_catalog_api_test.exs` calls every endpoint against
  the committed corpus and validates the response body against the document.

A serializer change without a schema change fails the second test.

## Choices and rejections

`open_api_spex` was chosen over `oaskit`. Oaskit targets OpenAPI 3.1 and JSON
Schema 2020-12 and is built on a JSON Schema test-suite-compliant validator, but
it is at 0.17 with a small install base and pulls four transitive packages.
`open_api_spex` is at 3.22, has a single small dependency surface, casts request
parameters, and validates responses in tests, which is what the read-only v1
needs. The cost is OpenAPI 3.0: no `type: ["string", "null"]` unions. Nullable
fields use `nullable: true`, which every client this catalog targets supports.
Revisit the choice if a consumer needs 3.1 features.

`AshJsonApi` was rejected. The public reads are hand-written SQL projections
gated by source policy, not Ash resource reads. Exposing Ash resources would
either duplicate the projection rules or change what the public sees. JSON:API's
document structure also costs bytes and client complexity for a read-only list
of records.

Opaque types were rejected for the projection structs. `@opaque` would stop the
LiveView templates and serializer from reading fields, which is the point of the
struct. The types are transparent and the builders are the enforcement point.

## Remaining limits

- The hand-written SQL in `PublicCatalog` is checked by tests against the real
  corpus, not by Dialyzer. A column type change can still produce a runtime
  error that the spec cannot see.
- The browser uses the same structs, so a field removed from a struct breaks the
  templates at compile time only when the template uses dot access. Bracket
  access on a struct without `Access` is a runtime error. The remaining bracket
  access sites were converted to dot access when the structs landed.
- The OpenAPI document describes the contract but the server does not validate
  incoming query parameters against it. The controller validates page, page
  size, sort, and role by hand and drops unknown shapes. A stricter mode would
  route requests through `OpenApiSpex.Plug.CastAndValidate`, at the cost of
  atom-keyed params.
