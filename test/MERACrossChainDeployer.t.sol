// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Test} from "forge-std/Test.sol";
import {DeployMERAWalletStack} from "../script/DeployMERAWalletStack.s.sol";
import {BaseMERAWallet} from "../src/BaseMERAWallet.sol";
import {MERACrossChainDeployer} from "../src/MERACrossChainDeployer.sol";
import {MERALoginSignatureVerifier} from "../src/MERALoginSignatureVerifier.sol";
import {MERAWalletLoginRegistry} from "../src/MERAWalletLoginRegistry.sol";
import {MERAWalletMetaProxyCloneFactory} from "../src/MERAWalletMetaProxyCloneFactory.sol";
import {MERACrossChainDeploymentConstants} from "../src/constants/MERACrossChainDeploymentConstants.sol";
import {MERAWalletLoginRegistryTypes} from "../src/types/MERAWalletLoginRegistryTypes.sol";

contract CrossChainDeploymentTarget {
    uint256 public immutable VALUE;

    constructor(uint256 value) {
        VALUE = value;
    }
}

contract MERACrossChainDeployerTest is Test {
    struct StackAddresses {
        address implementation;
        address registry;
        address verifier;
        address factory;
        address wallet;
    }

    MERACrossChainDeployer internal deployer;
    address internal authorizer = address(0xA11CE);

    function setUp() public {
        deployer = new MERACrossChainDeployer(address(this));
    }

    function testDeploysAtPredictedAddress() public {
        bytes32 salt = keccak256("target");
        bytes memory initCode = abi.encodePacked(type(CrossChainDeploymentTarget).creationCode, abi.encode(uint256(42)));
        address predicted = deployer.predict(salt);

        address deployed = deployer.deploy(salt, initCode);

        assertEq(deployed, predicted);
        assertEq(CrossChainDeploymentTarget(deployed).VALUE(), 42);
        assertEq(deployer.initCodeHashBySalt(salt), keccak256(initCode));
    }

    function testRejectsUnauthorizedDeployment() public {
        address attacker = address(0xBAD);
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        deployer.deploy(keccak256("target"), type(CrossChainDeploymentTarget).creationCode);
    }

    function testRejectsEmptyInitCode() public {
        vm.expectRevert(MERACrossChainDeployer.EmptyInitCode.selector);
        deployer.deploy(keccak256("target"), "");
    }

    function testRejectsDuplicateSalt() public {
        bytes32 salt = keccak256("target");
        bytes memory initCode = abi.encodePacked(type(CrossChainDeploymentTarget).creationCode, abi.encode(uint256(1)));
        address predicted = deployer.predict(salt);
        deployer.deploy(salt, initCode);

        vm.expectRevert(abi.encodeWithSelector(MERACrossChainDeployer.ComponentAlreadyDeployed.selector, predicted));
        deployer.deploy(salt, initCode);
    }

    function testCanonicalAndSatelliteStacksHaveTheSameAddresses() public {
        uint256 snapshot = vm.snapshotState();
        StackAddresses memory canonical = _deployStack(
            MERAWalletLoginRegistryTypes.RegistryMode.Canonical,
            MERACrossChainDeploymentConstants.MAINNET_WALLET_NAMESPACE
        );
        assertEq(
            uint256(MERAWalletLoginRegistry(payable(canonical.registry)).REGISTRY_MODE()),
            uint256(MERAWalletLoginRegistryTypes.RegistryMode.Canonical)
        );

        assertTrue(vm.revertToState(snapshot));
        vm.chainId(137);
        StackAddresses memory satellite = _deployStack(
            MERAWalletLoginRegistryTypes.RegistryMode.Satellite,
            MERACrossChainDeploymentConstants.MAINNET_WALLET_NAMESPACE
        );
        assertEq(
            uint256(MERAWalletLoginRegistry(payable(satellite.registry)).REGISTRY_MODE()),
            uint256(MERAWalletLoginRegistryTypes.RegistryMode.Satellite)
        );

        assertEq(satellite.implementation, canonical.implementation);
        assertEq(satellite.registry, canonical.registry);
        assertEq(satellite.verifier, canonical.verifier);
        assertEq(satellite.factory, canonical.factory);
        assertEq(satellite.wallet, canonical.wallet);
    }

    function testDifferentNetworkGroupsUseDifferentWalletAddresses() public {
        uint256 snapshot = vm.snapshotState();
        StackAddresses memory mainnet = _deployStack(
            MERAWalletLoginRegistryTypes.RegistryMode.Canonical,
            MERACrossChainDeploymentConstants.MAINNET_WALLET_NAMESPACE
        );

        assertTrue(vm.revertToState(snapshot));
        StackAddresses memory testnet = _deployStack(
            MERAWalletLoginRegistryTypes.RegistryMode.Canonical,
            MERACrossChainDeploymentConstants.TESTNET_WALLET_NAMESPACE
        );

        assertEq(testnet.factory, mainnet.factory);
        assertNotEq(testnet.wallet, mainnet.wallet);
    }

    function testChangedDeploymentArtifactsUseNewSaltsWithoutRotatingCompatibleImplementation() public {
        bytes32 legacyRegistrySalt = keccak256("WalletMera.LoginRegistry.v2");
        bytes32 legacyVerifierSalt = keccak256("WalletMera.LoginSignatureVerifier.v2");
        bytes32 legacyFactorySalt = keccak256("WalletMera.MetaProxyCloneFactory.v2");
        bytes memory legacyInitCode =
            abi.encodePacked(type(CrossChainDeploymentTarget).creationCode, abi.encode(uint256(2)));
        bytes memory upgradedVerifierInitCode =
            abi.encodePacked(type(MERALoginSignatureVerifier).creationCode, abi.encode(authorizer));
        bytes memory legacyVerifierInitCode = abi.encodePacked(
            _withDifferentMetadata(type(MERALoginSignatureVerifier).creationCode), abi.encode(authorizer)
        );
        bytes32 legacyVerifierInitCodeHash = keccak256(legacyVerifierInitCode);
        bytes32 upgradedVerifierInitCodeHash = keccak256(upgradedVerifierInitCode);

        address implementation = deployer.deploy(
            MERACrossChainDeploymentConstants.WALLET_IMPLEMENTATION_SALT,
            abi.encodePacked(
                type(BaseMERAWallet).creationCode,
                abi.encode(address(1), address(2), address(3), address(0), address(0))
            )
        );
        address legacyVerifier = deployer.deploy(legacyVerifierSalt, legacyVerifierInitCode);
        address upgradedVerifier =
            deployer.deploy(MERACrossChainDeploymentConstants.LOGIN_VERIFIER_SALT, upgradedVerifierInitCode);
        address legacyRegistry = deployer.deploy(legacyRegistrySalt, legacyInitCode);
        address legacyFactory = deployer.deploy(legacyFactorySalt, legacyInitCode);
        address upgradedRegistry = deployer.deploy(
            MERACrossChainDeploymentConstants.LOGIN_REGISTRY_SALT,
            abi.encodePacked(
                type(MERAWalletLoginRegistry).creationCode,
                abi.encode(address(this), MERAWalletLoginRegistryTypes.RegistryMode.Canonical)
            )
        );
        address upgradedFactory = deployer.deploy(
            MERACrossChainDeploymentConstants.WALLET_FACTORY_SALT,
            abi.encodePacked(
                type(MERAWalletMetaProxyCloneFactory).creationCode,
                abi.encode(implementation, upgradedRegistry, MERACrossChainDeploymentConstants.MAINNET_WALLET_NAMESPACE)
            )
        );

        assertNotEq(upgradedRegistry, legacyRegistry);
        assertNotEq(upgradedVerifier, legacyVerifier);
        assertNotEq(upgradedFactory, legacyFactory);
        assertNotEq(legacyVerifierInitCodeHash, upgradedVerifierInitCodeHash);
        assertEq(MERALoginSignatureVerifier(legacyVerifier).AUTHORIZER(), authorizer);
        assertEq(MERALoginSignatureVerifier(upgradedVerifier).AUTHORIZER(), authorizer);
        assertEq(deployer.initCodeHashBySalt(legacyVerifierSalt), legacyVerifierInitCodeHash);
        assertEq(
            deployer.initCodeHashBySalt(MERACrossChainDeploymentConstants.LOGIN_VERIFIER_SALT),
            upgradedVerifierInitCodeHash
        );
        assertEq(deployer.predict(MERACrossChainDeploymentConstants.WALLET_IMPLEMENTATION_SALT), implementation);
        assertEq(deployer.predict(MERACrossChainDeploymentConstants.LOGIN_VERIFIER_SALT), upgradedVerifier);
        assertEq(MERACrossChainDeploymentConstants.LOGIN_REGISTRY_SALT, keccak256("WalletMera.LoginRegistry.v3"));
        assertEq(
            MERACrossChainDeploymentConstants.WALLET_FACTORY_SALT, keccak256("WalletMera.MetaProxyCloneFactory.v3")
        );
        assertEq(
            MERACrossChainDeploymentConstants.WALLET_IMPLEMENTATION_SALT, keccak256("WalletMera.BaseMERAWallet.v2")
        );
        assertEq(
            MERACrossChainDeploymentConstants.LOGIN_VERIFIER_SALT, keccak256("WalletMera.LoginSignatureVerifier.v3")
        );
        assertEq(MERACrossChainDeploymentConstants.MAINNET_WALLET_NAMESPACE, keccak256("WalletMera.Account.mainnet.v2"));
        assertEq(MERACrossChainDeploymentConstants.TESTNET_WALLET_NAMESPACE, keccak256("WalletMera.Account.testnet.v2"));
        assertEq(MERACrossChainDeploymentConstants.LOCAL_WALLET_NAMESPACE, keccak256("WalletMera.Account.local.v2"));
    }

    function testRegistryModeMapping() public {
        DeployMERAWalletStack script = new DeployMERAWalletStack();

        assertEq(uint256(script.registryModeForChain(1)), uint256(MERAWalletLoginRegistryTypes.RegistryMode.Canonical));
        assertEq(
            uint256(script.registryModeForChain(11_155_111)),
            uint256(MERAWalletLoginRegistryTypes.RegistryMode.Canonical)
        );
        assertEq(
            uint256(script.registryModeForChain(31_337)), uint256(MERAWalletLoginRegistryTypes.RegistryMode.Canonical)
        );
        assertEq(uint256(script.registryModeForChain(56)), uint256(MERAWalletLoginRegistryTypes.RegistryMode.Satellite));
        assertEq(
            uint256(script.registryModeForChain(137)), uint256(MERAWalletLoginRegistryTypes.RegistryMode.Satellite)
        );
        assertEq(
            uint256(script.registryModeForChain(8_453)), uint256(MERAWalletLoginRegistryTypes.RegistryMode.Satellite)
        );
        assertEq(
            uint256(script.registryModeForChain(42_161)), uint256(MERAWalletLoginRegistryTypes.RegistryMode.Satellite)
        );
        assertEq(
            uint256(script.registryModeForChain(80_002)), uint256(MERAWalletLoginRegistryTypes.RegistryMode.Satellite)
        );

        assertEq(script.walletNamespaceForChain(1), MERACrossChainDeploymentConstants.MAINNET_WALLET_NAMESPACE);
        assertEq(script.walletNamespaceForChain(137), MERACrossChainDeploymentConstants.MAINNET_WALLET_NAMESPACE);
        assertEq(script.walletNamespaceForChain(11_155_111), MERACrossChainDeploymentConstants.TESTNET_WALLET_NAMESPACE);
        assertEq(script.walletNamespaceForChain(80_002), MERACrossChainDeploymentConstants.TESTNET_WALLET_NAMESPACE);
        assertEq(script.walletNamespaceForChain(31_337), MERACrossChainDeploymentConstants.LOCAL_WALLET_NAMESPACE);

        vm.expectRevert(abi.encodeWithSelector(DeployMERAWalletStack.UnsupportedChain.selector, uint256(999)));
        script.registryModeForChain(999);
        vm.expectRevert(abi.encodeWithSelector(DeployMERAWalletStack.UnsupportedChain.selector, uint256(999)));
        script.walletNamespaceForChain(999);
    }

    function _withDifferentMetadata(bytes memory creationCode) private pure returns (bytes memory) {
        uint256 codeLength = creationCode.length;
        uint256 metadataLength =
            (uint256(uint8(creationCode[codeLength - 2])) << 8) | uint256(uint8(creationCode[codeLength - 1]));
        require(metadataLength > 10 && metadataLength + 2 <= codeLength);
        uint256 metadataByte = codeLength - metadataLength - 2 + 10;
        creationCode[metadataByte] = bytes1(uint8(creationCode[metadataByte]) ^ 1);
        return creationCode;
    }

    function _deployStack(MERAWalletLoginRegistryTypes.RegistryMode mode, bytes32 walletNamespace)
        private
        returns (StackAddresses memory stack)
    {
        stack.implementation = deployer.deploy(
            MERACrossChainDeploymentConstants.WALLET_IMPLEMENTATION_SALT,
            abi.encodePacked(
                type(BaseMERAWallet).creationCode,
                abi.encode(address(1), address(2), address(3), address(0), address(0))
            )
        );
        stack.registry = deployer.deploy(
            MERACrossChainDeploymentConstants.LOGIN_REGISTRY_SALT,
            abi.encodePacked(type(MERAWalletLoginRegistry).creationCode, abi.encode(address(this), mode))
        );
        stack.verifier = deployer.deploy(
            MERACrossChainDeploymentConstants.LOGIN_VERIFIER_SALT,
            abi.encodePacked(type(MERALoginSignatureVerifier).creationCode, abi.encode(authorizer))
        );
        stack.factory = deployer.deploy(
            MERACrossChainDeploymentConstants.WALLET_FACTORY_SALT,
            abi.encodePacked(
                type(MERAWalletMetaProxyCloneFactory).creationCode,
                abi.encode(stack.implementation, stack.registry, walletNamespace)
            )
        );

        stack.wallet = MERAWalletMetaProxyCloneFactory(stack.factory).predictWallet(keccak256(bytes("alice")));
    }
}
