# Trifle::Traces driver contracts

Trifle::Traces persists traces through two pluggable, duck-typed drivers.
Clients (mongo, aws-sdk-s3, ...) are always injected — the gem has zero
runtime dependencies. To support a new backend, implement the contract
below and run the shared contract specs against it
(`spec/support/index_driver_contract.rb`, `spec/support/data_driver_contract.rb`).

Both drivers receive `Trifle::Traces::TraceRecord` value objects.
`record.segments` derives cumulative key-path prefixes (`"a/b/c"` →
`["a", "a/b", "a/b/c"]`); a driver decides whether to materialize them
(Mongo stores the array) or derive them at query time (a SQL driver can
use key-prefix matching).

## Index driver

Stores one metadata entry per trace and answers `find`/`search`.

```ruby
generate_reference  # -> String. MUST be I/O-free and time-sortable
                    #    (lexicographic order == chronological order).
                    #    This enables :deferred mode (zero writes until
                    #    wrapup) and append-only backends.
create(record)      # Insert. In :deferred mode this is the only index
                    #    write and record.state is already final.
update(record)      # OPTIONAL (declare via capabilities). Persist the
                    #    mutable fields: state, tags, context, length,
                    #    parts, last_at, expires_at.
delete(reference)   # OPTIONAL. Used by ignore! in :live mode.
find(reference)     # -> TraceRecord | nil
search(segment: nil, tags: nil, state: nil, limit: 20, cursor: nil)
                    # -> { traces: [TraceRecord], cursor: String | nil }
capabilities        # -> { update:, delete:, search:, ttl: }
self.setup!(...)    # Create indexes / DDL. Run once.
```

The search contract is deliberately narrow — segment prefix match
(ANY over a small array), tags ANY-match, exact state, newest-first
only, opaque cursor, no counts. Do not widen it per driver; wide ad-hoc
search multiplies write or query cost at high volume.

`capabilities[:ttl]` describes retention handling: `:native` (backend
expires rows itself, e.g. Mongo TTL index), `:cleanup` (driver provides
a `cleanup!` method to run from cron), `:none`. Retention arrives as
data on the record (`retention` days, `expires_at`); the driver maps it
to TTL columns, partition drops or index rollover as fits the backend.

## Data driver

Stores the trace payload as numbered parts plus named artifacts.

```ruby
generate_bucket_id                    # -> Integer shard id, chosen once
                                      #    per trace at liftoff.
write_part(record, part:, entries:)   # Persist entries (array of
                                      #    {at:, message:, state:, type:, level:}).
                                      #    MUST raise on failure — the
                                      #    dispatcher re-queues entries.
write_artifact(record, name:, payload: nil, path: nil)  # -> name
read_part(record, part:)              # -> Array<Hash> (symbol keys)
read(record)                          # -> all parts concatenated
read_artifact(record, name:)          # -> String
delete(record)                        # Best-effort purge (ignore!).
self.setup!(...)                      # mkdir / lifecycle rules.
```

Storage layout (S3/File): `<retention>/<prefix>/<key>/<reference>/`
with `data_<part>.json[.gz]` and `artifacts/<name>` inside. Retention
days as the top-level prefix means payload expiry is one lifecycle rule
per retention class — never per tenant or namespace.
