// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @title MERACrossChainDeploymentConstants
/// @notice Versioned salts for deterministic WalletMera deployments.
library MERACrossChainDeploymentConstants {
    bytes32 internal constant CROSS_CHAIN_DEPLOYER_SALT = keccak256("WalletMera.CrossChainDeployer.v1");
    bytes32 internal constant WALLET_IMPLEMENTATION_SALT = keccak256("WalletMera.BaseMERAWallet.v1");
    bytes32 internal constant LOGIN_REGISTRY_SALT = keccak256("WalletMera.LoginRegistry.v1");
    bytes32 internal constant LOGIN_VERIFIER_SALT = keccak256("WalletMera.LoginSignatureVerifier.v1");
    bytes32 internal constant WALLET_FACTORY_SALT = keccak256("WalletMera.MetaProxyCloneFactory.v1");
}
