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
        /// @notice Plain-text login being registered.
        string login;
        /// @notice Wallet address being registered.
        address wallet;
        /// @notice Authorization deadline supplied by the caller.
        uint256 deadline;
        /// @notice Opaque authorization payload consumed by the verifier.
        bytes authorization;
    }
}
