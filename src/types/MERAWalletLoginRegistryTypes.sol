// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Structs used by MERAWalletLoginRegistry (must stay ABI-compatible if field order changes).
library MERAWalletLoginRegistryTypes {
    /// @notice Operating mode of a login registry deployment.
    enum RegistryMode {
        /// @notice Source of truth: handles payment, referrals, and user-confirmed login swaps.
        Canonical,
        /// @notice Read-only projection: accepts only authorizer-approved registrations and swaps.
        Satellite
    }

    /// @notice Untrusted inputs supplied by an allowed factory when registering a wallet.
    /// @dev The registry derives the factory from `msg.sender`, payment from `msg.value`, and hashes from these fields.
    struct RegistrationParams {
        /// @notice Plain-text login being registered.
        string login;
        /// @notice Immutable wallet identity assigned on the canonical registry.
        bytes32 walletId;
        /// @notice Wallet address being registered.
        address wallet;
        /// @notice Hash of the exact controller state used to initialize the wallet.
        bytes32 initParamsHash;
        /// @notice Secret used by the canonical commit-reveal flow.
        bytes32 secret;
        /// @notice Satellite authorization deadline, also bound into canonical commitments.
        uint256 deadline;
        /// @notice Opaque satellite authorization payload, also bound into canonical commitments.
        bytes authorization;
        /// @notice Optional canonical referrer login; empty on satellite registries.
        string referrerLogin;
    }

    /// @notice Pending exchange of the logins currently owned by two registered wallets.
    struct PendingLoginMigration {
        /// @notice Wallet currently owning the old login.
        address previousWallet;
        /// @notice Wallet that owns `newLoginHash` and must confirm the exchange.
        address newWallet;
        /// @notice Login hash currently owned by `newWallet` and assigned to `previousWallet` after confirmation.
        bytes32 newLoginHash;
    }

    /// @notice Inputs passed to the satellite login authorization verifier.
    struct RegistrationValidationParams {
        /// @notice Registry contract performing the validation.
        address registry;
        /// @notice Factory registering the wallet.
        address factory;
        /// @notice Keccak256 hash of the login string.
        bytes32 loginHash;
        /// @notice Immutable wallet identity assigned on the canonical registry.
        bytes32 walletId;
        /// @notice Plain-text login being registered.
        string login;
        /// @notice Wallet address being registered.
        address wallet;
        /// @notice Hash of the exact controller state used to initialize the wallet.
        bytes32 initParamsHash;
        /// @notice Authorization deadline supplied by the caller.
        uint256 deadline;
        /// @notice Opaque authorization payload consumed by the verifier.
        bytes authorization;
    }

    /// @notice Inputs passed to the verifier when replaying a canonical login swap on a satellite registry.
    struct MigrationValidationParams {
        /// @notice Satellite registry applying the canonical swap.
        address registry;
        /// @notice Login hash moving from `previousWallet` to `newWallet`.
        bytes32 oldLoginHash;
        /// @notice Login hash moving from `newWallet` to `previousWallet`.
        bytes32 newLoginHash;
        /// @notice Wallet owning `oldLoginHash` before the swap.
        address previousWallet;
        /// @notice Wallet owning `newLoginHash` before the swap.
        address newWallet;
        /// @notice Registry-wide satellite replay sequence number.
        uint256 nonce;
        /// @notice Authorization expiry timestamp.
        uint256 deadline;
        /// @notice Opaque authorization payload consumed by the verifier.
        bytes authorization;
    }
}
