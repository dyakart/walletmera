// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {Script, console2} from "forge-std/Script.sol";
import {BaseMERAWallet} from "../src/BaseMERAWallet.sol";
import {MERACrossChainDeployer} from "../src/MERACrossChainDeployer.sol";
import {MERALoginSignatureVerifier} from "../src/MERALoginSignatureVerifier.sol";
import {MERAWalletLoginRegistry} from "../src/MERAWalletLoginRegistry.sol";
import {MERAWalletMetaProxyCloneFactory} from "../src/MERAWalletMetaProxyCloneFactory.sol";
import {MERACrossChainDeploymentConstants} from "../src/constants/MERACrossChainDeploymentConstants.sol";
import {MERAWalletConstants} from "../src/constants/MERAWalletConstants.sol";
import {MERAWalletLoginRegistryTypes} from "../src/types/MERAWalletLoginRegistryTypes.sol";

/// @notice Deterministically deploys and configures the complete canonical cross-chain WalletMera stack.
contract DeployMERAWalletStack is Script {
    error UnsupportedChain(uint256 chainId);
    error DeterministicCreate2DeployerUnavailable();
    error CrossChainDeployerBootstrapFailed();
    error InvalidGovernance();
    error CrossChainDeployerOwnerMismatch(address expected, address actual);
    error ComponentInitCodeHashMismatch(bytes32 salt, bytes32 expected, bytes32 actual);
    error RegistryOwnerMismatch(address expected, address actual);
    error RegistryModeMismatch(
        MERAWalletLoginRegistryTypes.RegistryMode expected, MERAWalletLoginRegistryTypes.RegistryMode actual
    );
    error WalletImplementationCodeHashMismatch(bytes32 expected, bytes32 actual);
    error VerifierAuthorizerMismatch(address expected, address actual);
    error FactoryImplementationMismatch(address expected, address actual);
    error FactoryRegistryMismatch(address expected, address actual);

    function run()
        external
        returns (
            BaseMERAWallet implementation,
            MERAWalletLoginRegistry registry,
            MERAWalletMetaProxyCloneFactory factory,
            MERALoginSignatureVerifier verifier
        )
    {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address authorizer = vm.envAddress("WALLET_MERA_LOGIN_AUTHORIZER_ADDRESS");
        address governance = vm.envOr("WALLET_MERA_GOVERNANCE_ADDRESS", deployer);
        require(governance != address(0), InvalidGovernance());
        MERAWalletLoginRegistryTypes.RegistryMode registryMode = registryModeForChain(block.chainid);

        vm.startBroadcast(deployerPrivateKey);

        MERACrossChainDeployer crossChainDeployer = _crossChainDeployer(deployer);
        implementation = BaseMERAWallet(
            payable(_deployIfMissing(
                    crossChainDeployer,
                    MERACrossChainDeploymentConstants.WALLET_IMPLEMENTATION_SALT,
                    abi.encodePacked(
                        type(BaseMERAWallet).creationCode,
                        abi.encode(address(1), address(2), address(3), address(0), address(0))
                    )
                ))
        );
        registry = MERAWalletLoginRegistry(
            payable(_deployIfMissing(
                    crossChainDeployer,
                    MERACrossChainDeploymentConstants.LOGIN_REGISTRY_SALT,
                    abi.encodePacked(type(MERAWalletLoginRegistry).creationCode, abi.encode(deployer, registryMode))
                ))
        );
        verifier = MERALoginSignatureVerifier(
            _deployIfMissing(
                crossChainDeployer,
                MERACrossChainDeploymentConstants.LOGIN_VERIFIER_SALT,
                abi.encodePacked(type(MERALoginSignatureVerifier).creationCode, abi.encode(authorizer))
            )
        );
        factory = MERAWalletMetaProxyCloneFactory(
            _deployIfMissing(
                crossChainDeployer,
                MERACrossChainDeploymentConstants.WALLET_FACTORY_SALT,
                abi.encodePacked(
                    type(MERAWalletMetaProxyCloneFactory).creationCode,
                    abi.encode(address(implementation), address(registry))
                )
            )
        );

        _validateStack(
            deployer,
            governance,
            authorizer,
            registryMode,
            crossChainDeployer,
            implementation,
            registry,
            factory,
            verifier
        );
        if (!registry.isFactory(address(factory))) {
            require(registry.owner() == deployer, RegistryOwnerMismatch(deployer, registry.owner()));
            registry.addFactory(address(factory));
        }
        if (registry.authorizationVerifier() != address(verifier)) {
            require(registry.owner() == deployer, RegistryOwnerMismatch(deployer, registry.owner()));
            registry.setAuthorizationVerifier(address(verifier));
        }
        if (governance != deployer) {
            if (registry.owner() == deployer) {
                registry.transferOwnership(governance);
            }
            if (crossChainDeployer.owner() == deployer) {
                crossChainDeployer.transferOwnership(governance);
            }
        }

        _validateOwners(governance, crossChainDeployer, registry);

        vm.stopBroadcast();

        _logDeployment(
            deployer,
            governance,
            authorizer,
            registryMode,
            crossChainDeployer,
            implementation,
            registry,
            factory,
            verifier
        );
    }

    /// @notice Returns the immutable registry mode for a supported deployment chain.
    function registryModeForChain(uint256 chainId) public pure returns (MERAWalletLoginRegistryTypes.RegistryMode) {
        if (chainId == 1 || chainId == 11_155_111 || chainId == 31_337) {
            return MERAWalletLoginRegistryTypes.RegistryMode.Canonical;
        }
        if (chainId == 56 || chainId == 137 || chainId == 8_453 || chainId == 42_161 || chainId == 80_002) {
            return MERAWalletLoginRegistryTypes.RegistryMode.Satellite;
        }
        revert UnsupportedChain(chainId);
    }

    function _crossChainDeployer(address deployer) private returns (MERACrossChainDeployer crossChainDeployer) {
        bytes memory initCode = abi.encodePacked(type(MERACrossChainDeployer).creationCode, abi.encode(deployer));
        address predicted = Create2.computeAddress(
            MERACrossChainDeploymentConstants.CROSS_CHAIN_DEPLOYER_SALT,
            keccak256(initCode),
            MERAWalletConstants.DETERMINISTIC_CREATE2_DEPLOYER
        );

        if (predicted.code.length == 0) {
            require(
                MERAWalletConstants.DETERMINISTIC_CREATE2_DEPLOYER.code.length != 0,
                DeterministicCreate2DeployerUnavailable()
            );
            (bool ok,) = MERAWalletConstants.DETERMINISTIC_CREATE2_DEPLOYER
                .call(abi.encodePacked(MERACrossChainDeploymentConstants.CROSS_CHAIN_DEPLOYER_SALT, initCode));
            require(ok && predicted.code.length != 0, CrossChainDeployerBootstrapFailed());
        }

        crossChainDeployer = MERACrossChainDeployer(predicted);
    }

    function _deployIfMissing(MERACrossChainDeployer deployer, bytes32 salt, bytes memory initCode)
        private
        returns (address component)
    {
        bytes32 expectedInitCodeHash = keccak256(initCode);
        component = deployer.predict(salt);
        if (component.code.length == 0) {
            component = deployer.deploy(salt, initCode);
        }
        bytes32 actualInitCodeHash = deployer.initCodeHashBySalt(salt);
        require(
            actualInitCodeHash == expectedInitCodeHash,
            ComponentInitCodeHashMismatch(salt, expectedInitCodeHash, actualInitCodeHash)
        );
    }

    function _validateStack(
        address deployer,
        address governance,
        address authorizer,
        MERAWalletLoginRegistryTypes.RegistryMode registryMode,
        MERACrossChainDeployer crossChainDeployer,
        BaseMERAWallet implementation,
        MERAWalletLoginRegistry registry,
        MERAWalletMetaProxyCloneFactory factory,
        MERALoginSignatureVerifier verifier
    ) private view {
        address crossChainDeployerOwner = crossChainDeployer.owner();
        require(
            crossChainDeployerOwner == deployer || crossChainDeployerOwner == governance,
            CrossChainDeployerOwnerMismatch(governance, crossChainDeployerOwner)
        );
        address registryOwner = registry.owner();
        require(
            registryOwner == deployer || registryOwner == governance, RegistryOwnerMismatch(governance, registryOwner)
        );
        require(registry.REGISTRY_MODE() == registryMode, RegistryModeMismatch(registryMode, registry.REGISTRY_MODE()));
        bytes32 expectedImplementationCodeHash = keccak256(type(BaseMERAWallet).runtimeCode);
        require(
            address(implementation).codehash == expectedImplementationCodeHash,
            WalletImplementationCodeHashMismatch(expectedImplementationCodeHash, address(implementation).codehash)
        );
        require(verifier.AUTHORIZER() == authorizer, VerifierAuthorizerMismatch(authorizer, verifier.AUTHORIZER()));
        require(
            factory.WALLET_IMPLEMENTATION() == address(implementation),
            FactoryImplementationMismatch(address(implementation), factory.WALLET_IMPLEMENTATION())
        );
        require(
            address(factory.LOGIN_REGISTRY()) == address(registry),
            FactoryRegistryMismatch(address(registry), address(factory.LOGIN_REGISTRY()))
        );
    }

    function _validateOwners(
        address expectedOwner,
        MERACrossChainDeployer crossChainDeployer,
        MERAWalletLoginRegistry registry
    ) private view {
        require(
            crossChainDeployer.owner() == expectedOwner,
            CrossChainDeployerOwnerMismatch(expectedOwner, crossChainDeployer.owner())
        );
        require(registry.owner() == expectedOwner, RegistryOwnerMismatch(expectedOwner, registry.owner()));
    }

    function _logDeployment(
        address deployer,
        address governance,
        address authorizer,
        MERAWalletLoginRegistryTypes.RegistryMode registryMode,
        MERACrossChainDeployer crossChainDeployer,
        BaseMERAWallet implementation,
        MERAWalletLoginRegistry registry,
        MERAWalletMetaProxyCloneFactory factory,
        MERALoginSignatureVerifier verifier
    ) private pure {
        console2.log("Deployer:", deployer);
        console2.log("Governance:", governance);
        console2.log("Login authorizer:", authorizer);
        console2.log("Registry mode:", uint256(registryMode));
        console2.log("MERACrossChainDeployer:", address(crossChainDeployer));
        console2.log("BaseMERAWallet implementation:", address(implementation));
        console2.log("MERAWalletLoginRegistry:", address(registry));
        console2.log("MERAWalletMetaProxyCloneFactory:", address(factory));
        console2.log("MERALoginSignatureVerifier:", address(verifier));
    }
}
