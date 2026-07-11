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
import {MERAWalletTypes} from "../src/types/MERAWalletTypes.sol";

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
        StackAddresses memory canonical = _deployStack(MERAWalletLoginRegistryTypes.RegistryMode.Canonical);
        assertEq(
            uint256(MERAWalletLoginRegistry(payable(canonical.registry)).REGISTRY_MODE()),
            uint256(MERAWalletLoginRegistryTypes.RegistryMode.Canonical)
        );

        assertTrue(vm.revertToState(snapshot));
        vm.chainId(137);
        StackAddresses memory satellite = _deployStack(MERAWalletLoginRegistryTypes.RegistryMode.Satellite);
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

        vm.expectRevert(abi.encodeWithSelector(DeployMERAWalletStack.UnsupportedChain.selector, uint256(999)));
        script.registryModeForChain(999);
    }

    function _deployStack(MERAWalletLoginRegistryTypes.RegistryMode mode)
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
                type(MERAWalletMetaProxyCloneFactory).creationCode, abi.encode(stack.implementation, stack.registry)
            )
        );

        MERAWalletTypes.WalletInitParams memory params = MERAWalletTypes.WalletInitParams({
            initialPrimary: address(0xA11CE),
            initialBackup: address(0xB0B),
            initialEmergency: address(0xE911),
            initialSigner: address(0xA11CE),
            initialGuardian: address(0xCAFE)
        });
        stack.wallet = MERAWalletMetaProxyCloneFactory(stack.factory).predictWallet("alice", params);
    }
}
