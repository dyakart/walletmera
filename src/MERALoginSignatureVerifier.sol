// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IMERALoginAuthorizationVerifier} from "./interfaces/IMERALoginAuthorizationVerifier.sol";
import {MERAWalletLoginRegistryTypes} from "./types/MERAWalletLoginRegistryTypes.sol";

/// @title MERALoginSignatureVerifier
/// @notice Verifies MERA login deployment authorizations signed by an EOA or EIP-1271 wallet.
contract MERALoginSignatureVerifier is EIP712, IMERALoginAuthorizationVerifier {
    /// @notice EIP-712 type hash for login authorization messages.
    bytes32 public constant AUTHORIZATION_TYPEHASH = keccak256(
        "LoginAuthorization(address registry,address factory,bytes32 loginHash,bytes32 walletId,address wallet,bytes32 initParamsHash,uint256 chainId,uint256 deadline)"
    );
    /// @notice EIP-712 type hash for canonical login swaps replayed on satellite registries.
    bytes32 public constant MIGRATION_AUTHORIZATION_TYPEHASH = keccak256(
        "LoginMigrationAuthorization(address registry,bytes32 oldLoginHash,bytes32 newLoginHash,address previousWallet,address newWallet,uint256 chainId,uint256 nonce,uint256 deadline)"
    );

    /// @notice Account whose EOA or EIP-1271 signature authorizes protected registrations.
    address public immutable AUTHORIZER;

    /// @notice Reverts when the configured authorizer is zero.
    error InvalidAuthorizer();
    /// @notice Reverts when a registration authorization is past its deadline.
    error AuthorizationExpired();
    /// @notice Reverts when authorization bytes are empty or fail signature validation.
    error InvalidAuthorization();

    /// @notice Creates a verifier bound to `authorizer`.
    /// @param authorizer EOA or EIP-1271 wallet allowed to sign login authorizations.
    constructor(address authorizer) EIP712("MERA Login Authorization", "2") {
        require(authorizer != address(0), InvalidAuthorizer());
        AUTHORIZER = authorizer;
    }

    /// @inheritdoc IMERALoginAuthorizationVerifier
    function validateRegistration(MERAWalletLoginRegistryTypes.RegistrationValidationParams calldata params)
        external
        view
    {
        bytes32 digest = hashAuthorization(
            params.registry,
            params.factory,
            params.loginHash,
            params.walletId,
            params.wallet,
            params.initParamsHash,
            params.deadline
        );
        _validateAuthorization(digest, params.deadline, params.authorization);
    }

    /// @inheritdoc IMERALoginAuthorizationVerifier
    function validateMigration(MERAWalletLoginRegistryTypes.MigrationValidationParams calldata params) external view {
        bytes32 digest = hashMigrationAuthorization(
            params.registry,
            params.oldLoginHash,
            params.newLoginHash,
            params.previousWallet,
            params.newWallet,
            params.nonce,
            params.deadline
        );
        _validateAuthorization(digest, params.deadline, params.authorization);
    }

    /// @notice Computes the EIP-712 digest that must be signed by {AUTHORIZER}.
    /// @param registry Registry address included in the authorization.
    /// @param factory Factory address included in the authorization.
    /// @param loginHash Login hash included in the authorization.
    /// @param walletId Immutable wallet identity included in the authorization.
    /// @param wallet Wallet address included in the authorization.
    /// @param initParamsHash Exact active initialization state included in the authorization.
    /// @param deadline Authorization deadline.
    /// @return EIP-712 digest for signature validation.
    function hashAuthorization(
        address registry,
        address factory,
        bytes32 loginHash,
        bytes32 walletId,
        address wallet,
        bytes32 initParamsHash,
        uint256 deadline
    ) public view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    AUTHORIZATION_TYPEHASH,
                    registry,
                    factory,
                    loginHash,
                    walletId,
                    wallet,
                    initParamsHash,
                    block.chainid,
                    deadline
                )
            )
        );
    }

    /// @notice Computes the EIP-712 digest for an exact canonical login swap on the current chain.
    function hashMigrationAuthorization(
        address registry,
        bytes32 oldLoginHash,
        bytes32 newLoginHash,
        address previousWallet,
        address newWallet,
        uint256 nonce,
        uint256 deadline
    ) public view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    MIGRATION_AUTHORIZATION_TYPEHASH,
                    registry,
                    oldLoginHash,
                    newLoginHash,
                    previousWallet,
                    newWallet,
                    block.chainid,
                    nonce,
                    deadline
                )
            )
        );
    }

    function _validateAuthorization(bytes32 digest, uint256 deadline, bytes calldata authorization) private view {
        require(authorization.length != 0, InvalidAuthorization());
        require(block.timestamp <= deadline, AuthorizationExpired());
        require(SignatureChecker.isValidSignatureNow(AUTHORIZER, digest, authorization), InvalidAuthorization());
    }
}
