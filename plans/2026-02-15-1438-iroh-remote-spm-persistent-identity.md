# Switch IrohLib to Remote SPM + Persistent Identity with Key Management

Switch IrohLib dependency from local path to remote SPM URL (`https://github.com/kylehowells/iroh-ffi` v0.96.0) in all three Package.swift files, and add persistent identity with key management to IrohTransportAdapter.

## Part 1: Update SPM Dependencies

- [x] Update root `Package.swift` - remote URL + package name fix
- [x] Update `iroh-transport/Package.swift` - remote URL + package name fix
- [x] Update `cli/Package.swift` - remote URL + package name fix

## Part 2: Persistent Identity

- [x] Add `forceNewIdentity` parameter to `IrohTransportAdapter.init`
- [x] Add key file management (load/create/save secret key)
- [x] Add `exportSecretKey()`, `importSecretKey()`, `resetIdentity()` public methods
- [x] Update `startAsync()` to use persistent key via `NodeOptions.secretKey`
- [x] Import Security framework for `SecRandomCopyBytes`

## Verification

- [x] Build root package
- [x] Build iroh-transport package
- [x] Build CLI
- [x] Server tests (pre-existing failures in LogStoreTests unrelated to these changes)
