// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {MERAWalletTypes} from "./types/MERAWalletTypes.sol";
import {BaseMERAWallet} from "./BaseMERAWallet.sol";
import {IMERAWalletLoginRegistry} from "./interfaces/IMERAWalletLoginRegistry.sol";

/// @title MERAWalletMetaProxyCloneFactory
/// @notice Deploys deterministic `BaseMERAWallet` clones whose addresses are independent of controller roles.
contract MERAWalletMetaProxyCloneFactory {
    /// @notice Base wallet implementation cloned by this factory.
    address public immutable WALLET_IMPLEMENTATION;
    /// @notice Login registry used when registering deployed wallets.
    IMERAWalletLoginRegistry public immutable LOGIN_REGISTRY;
    /// @notice Versioned mainnet, testnet, or local namespace used in wallet salts.
    bytes32 public immutable WALLET_NAMESPACE;

    /// @notice Emitted after a wallet clone is deployed and registered.
    event WalletDeployed(bytes32 indexed loginHash, string login, address wallet);
    /// @notice Emitted with the immutable identity and exact active state used for initialization.
    event WalletIdentityDeployed(bytes32 indexed walletId, address indexed wallet, bytes32 indexed initParamsHash);

    /// @notice Reverts when the requested login is already registered.
    error LoginAlreadyRegistered();
    /// @notice Reverts when the wallet implementation address has no code.
    error WalletImplementationNotDeployed();
    /// @notice Reverts when the login registry address has no code.
    error LoginRegistryNotDeployed();
    /// @notice Reverts when the wallet identity or deployment namespace is zero.
    error InvalidWalletIdentity();

    /// @notice Creates the factory.
    /// @param walletImplementation Base wallet implementation to clone.
    /// @param loginRegistry Registry used for login registration.
    /// @param walletNamespace Versioned network-group namespace shared by equivalent chains.
    constructor(address walletImplementation, address loginRegistry, bytes32 walletNamespace) {
        require(walletImplementation.code.length != 0, WalletImplementationNotDeployed());
        require(loginRegistry.code.length != 0, LoginRegistryNotDeployed());
        require(walletNamespace != bytes32(0), InvalidWalletIdentity());
        WALLET_IMPLEMENTATION = walletImplementation;
        LOGIN_REGISTRY = IMERAWalletLoginRegistry(loginRegistry);
        WALLET_NAMESPACE = walletNamespace;
    }

    /// @notice Deploys a deterministic wallet clone and registers `login`.
    /// @param login Login to register for the new wallet.
    /// @param walletId Immutable identity assigned during canonical creation.
    /// @param params Active wallet state; it does not affect the deterministic address.
    /// @param secret Commitment secret for canonical registration.
    /// @param deadline Satellite authorization deadline, also bound into canonical commitments.
    /// @param authorization Satellite authorization payload, also bound into canonical commitments.
    /// @param referrerLogin Optional canonical referrer login; must be empty on satellite registries.
    /// @return wallet Deployed wallet clone address.
    function deployWallet(
        string calldata login,
        bytes32 walletId,
        MERAWalletTypes.WalletInitParams calldata params,
        bytes32 secret,
        uint256 deadline,
        bytes calldata authorization,
        string calldata referrerLogin
    ) external payable returns (address wallet) {
        require(walletId != bytes32(0), InvalidWalletIdentity());
        bytes32 loginHash = _loginHash(login);
        require(LOGIN_REGISTRY.walletByLoginHash(loginHash) == address(0), LoginAlreadyRegistered());

        bytes32 initParamsHash = hashInitParams(params);
        wallet = Clones.cloneDeterministic(WALLET_IMPLEMENTATION, walletSalt(walletId));
        BaseMERAWallet(payable(wallet)).initialize(params);

        LOGIN_REGISTRY.registerLogin{value: msg.value}(
            login, walletId, wallet, initParamsHash, secret, deadline, authorization, referrerLogin
        );
        emit WalletDeployed(loginHash, login, wallet);
        emit WalletIdentityDeployed(walletId, wallet, initParamsHash);
    }

    /// @notice Counterfactual wallet address for an immutable wallet identity.
    /// @param walletId Identity assigned by the canonical registry.
    /// @return Counterfactual wallet address.
    function predictWallet(bytes32 walletId) external view returns (address) {
        require(walletId != bytes32(0), InvalidWalletIdentity());
        return Clones.predictDeterministicAddress(WALLET_IMPLEMENTATION, walletSalt(walletId), address(this));
    }

    /// @notice Returns the namespaced CREATE2 salt for an immutable wallet identity.
    function walletSalt(bytes32 walletId) public view returns (bytes32) {
        require(walletId != bytes32(0), InvalidWalletIdentity());
        return keccak256(abi.encode(WALLET_NAMESPACE, walletId));
    }

    /// @notice Commits the exact state that a newly deployed clone will activate.
    function hashInitParams(MERAWalletTypes.WalletInitParams calldata params) public pure returns (bytes32) {
        return keccak256(abi.encode(params));
    }

    function _loginHash(string calldata login) private pure returns (bytes32 loginHash) {
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            calldatacopy(ptr, login.offset, login.length)
            loginHash := keccak256(ptr, login.length)
        }
    }
}
