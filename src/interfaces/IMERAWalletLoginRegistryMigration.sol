// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Canonical registry API for exchanging the logins owned by two registered wallets.
interface IMERAWalletLoginRegistryMigration {
    /// @notice Requests an exchange of the logins currently owned by the caller and `newWallet`.
    /// @param oldLogin Login currently owned by the caller.
    /// @param newLogin Login currently owned by `newWallet`.
    /// @param newWallet Wallet that must confirm the exchange.
    function requestLoginMigration(string calldata oldLogin, string calldata newLogin, address newWallet) external;
    /// @notice Cancels a pending login exchange as the wallet that requested it.
    /// @param oldLogin Existing login whose pending exchange should be cancelled.
    function cancelLoginMigration(string calldata oldLogin) external;
    /// @notice Confirms a pending login exchange as the other wallet.
    /// @param oldLogin Existing login whose pending exchange is being confirmed.
    function confirmLoginMigration(string calldata oldLogin) external;
}
