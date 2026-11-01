# Documentation

| Document | What it covers |
|---|---|
| [api/v1.md](api/v1.md) | The read-only `/api/v1` contract: endpoints, envelopes, pagination, filters, versioning, known gaps |
| [architecture/public-api.md](architecture/public-api.md) | The typed Elixir boundary, the builders, the spec gate, and why the HTTP layer uses `open_api_spex` |
| [architecture/scalability-and-operations.md](architecture/scalability-and-operations.md) | Measured read cost and wire volume (including the 1 November directory fix), the resource that fails first, Railway and Postgres limits, ordered recommendations |
| [covers.md](covers.md) | Cover sourcing, cache/thumbnail/R2 delivery, operator commands, and per-publisher refresh paths |
| [audit/2026-10-31-repository-audit.md](audit/2026-10-31-repository-audit.md) | Repository-wide findings, what was fixed, what remains, and how each claim was checked |

The README answers what the project is and how to run it. These documents answer
how the public contract is enforced, where the system breaks under load, and
what the audit found.
