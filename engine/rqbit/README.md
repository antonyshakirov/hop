# Selective torrent storage

The source patch targets rqbit v9.0.1 at the commit recorded in `source.json`.
It includes storage regressions and uses existing dependencies. The engine is
built separately from Hop. Adding these sources does not replace an installed
engine or update the downloadable engine manifest.

## Storage contract

- Apply the confirmed file selection before creating payload files. Skipped
  directories and files remain absent. Existing skipped files retain their bytes
  and length, including when a downloaded piece crosses a file boundary.
- Store skipped ranges from shared pieces in a lazy per-torrent journal under
  the session persistence folder's `parts-v1` directory. The cache identity
  includes the info hash and output path. A session without JSON persistence
  uses rqbit's default session folder for this cache.
- Read cached ranges over read-only existing payloads. Missing ranges return an
  error. Piece hashes still determine which data is valid; selective and cached
  restarts run a complete hash check even with fast resume enabled.
- A newly selected file receives its cached ranges before the effective
  selection changes. Deselecting redirects subsequent writes to the journal.
  Previously created files remain on disk. No selection operation deletes
  existing payloads or infers ownership from their names.
- Preserve ownership of opened files across deselection and partial failures.
  With overwrite disabled, a retry can reuse an owned file; a previously
  existing file is refused. An unsuccessful multi-file selection can leave
  files that were explicitly requested in that selection on disk. The previous
  effective selection remains in force.
- Protect the journal with an exclusive lock, bounded records, range validation
  and checksums. Ignore an incomplete final record; reject corrupt complete
  records. Compact obsolete ranges through an atomic replacement. Flushing a
  promoted payload precedes invalidation of its cached ranges.
- Explicit torrent-file deletion also removes the journal without requiring a
  successful cache replay. Cleanup failures reach the caller. Forgetting a
  torrent or changing its selection does not invoke deletion.
- Custom backends that do not implement selective storage reject a partial
  selection before initialization. Middleware forwards selection, verification
  and deletion hooks.

The patch does not migrate or remove placeholders produced by a stock engine.
Torrent metadata and the peer protocol are unchanged.

## Prepare and verify

Use a dedicated, clean checkout of the pinned upstream commit. `prepare.py`
checks the revision and patch checksum before applying the patch, then verifies
all patched file checksums. It refuses a dirty checkout.

```sh
python3 engine/rqbit/prepare.py /path/to/rqbit-source
```

Use Rust 1.99.1, an isolated Cargo cache and a target directory outside synced
folders. In the patched checkout run:

```sh
cargo fmt --all -- --check
cargo check --locked --no-default-features --features rqbit/rust-tls,librqbit/storage_middleware --all-targets
cargo clippy --locked --no-default-features --features rqbit/rust-tls,librqbit/storage_middleware --all-targets -- -D warnings
E2E_NUM_SERVERS=2 E2E_CLIENT_ITERS=1 cargo test --locked --no-default-features --features rqbit/rust-tls,librqbit/storage_middleware -- --test-threads=1
cargo build --locked -p rqbit --no-default-features --features rust-tls
```

On macOS, pass the built binary and an evidence directory to the loopback check:

```sh
python3 engine/rqbit/verify-loopback.py /path/to/target/debug/rqbit /path/to/evidence
```

The check creates synthetic files in a system temporary directory. It confines
engine networking to localhost through `sandbox-exec`, disables discovery and
trackers, and checks shared and aligned pieces, existing skipped data, pause,
restart without the original seed, seeding to another client and changing file
selection. Its `finally` blocks stop owned processes and remove temporary data.
JSON results and engine logs remain in the evidence directory.

The verified target is Apple Silicon macOS. Six upstream tests remain explicitly
ignored, including external-peer/DHT/tracker scenarios and a Miri-specific test.
Intel, Windows, production signing, delivery and a complete Hop release check
require their own validation. The CLI still reports upstream version 9.0.1;
identify this build through the pinned patch and binary checksum. Publishing
requires a distinct engine artifact and the normal signed-engine release flow.
