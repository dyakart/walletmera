// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletLoginRegistryTypes} from "../types/MERAWalletLoginRegistryTypes.sol";

/// @notice Verifier hooks used by satellite registries for canonical login registrations and swaps.
interface IMERALoginAuthorizationVerifier {
    /// @notice Validates a login registration request.
    /// @param params Registration context supplied by {MERAWalletLoginRegistry}.
    /// @dev Reverts when the registration is not authorized.
    function validateRegistration(MERAWalletLoginRegistryTypes.RegistrationValidationParams calldata params)
        external
        view;

    /// @notice Validates a canonical login swap before a satellite registry applies it.
    /// @param params Migration context supplied by {MERAWalletLoginRegistry}.
    /// @dev Reverts when the migration replay is not authorized.
    function validateMigration(MERAWalletLoginRegistryTypes.MigrationValidationParams calldata params) external view;
}
