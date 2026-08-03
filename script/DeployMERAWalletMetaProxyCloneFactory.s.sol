// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Script, console2} from "forge-std/Script.sol";
import {BaseMERAWallet} from "../src/BaseMERAWallet.sol";
import {MERAWalletLoginRegistry} from "../src/MERAWalletLoginRegistry.sol";
import {MERAWalletMetaProxyCloneFactory} from "../src/MERAWalletMetaProxyCloneFactory.sol";
import {MERAWalletLoginRegistryTypes} from "../src/types/MERAWalletLoginRegistryTypes.sol";

/// @notice Deploys the `BaseMERAWallet` implementation and `MERAWalletMetaProxyCloneFactory`.
contract DeployMERAWalletMetaProxyCloneFactory is Script {
    bytes32 private constant STANDALONE_WALLET_NAMESPACE = keccak256("WalletMera.Account.standalone.v2");

    function run()
        external
        returns (
            BaseMERAWallet implementation,
            MERAWalletLoginRegistry registry,
            MERAWalletMetaProxyCloneFactory factory
        )
    {
        vm.startBroadcast();
        address deployer = msg.sender;
        console2.log("Deployer:", deployer);

        implementation = new BaseMERAWallet(address(1), address(2), address(3), address(0), address(0));
        // Canonical registry: all logins use commit-reveal; short logins are paid and long logins remain free.
        registry = new MERAWalletLoginRegistry(deployer, MERAWalletLoginRegistryTypes.RegistryMode.Canonical);
        factory = new MERAWalletMetaProxyCloneFactory(
            address(implementation), address(registry), STANDALONE_WALLET_NAMESPACE
        );
        registry.addFactory(address(factory));

        vm.stopBroadcast();

        console2.log("BaseMERAWallet implementation deployed at:", address(implementation));
        console2.log("MERAWalletLoginRegistry deployed at:", address(registry));
        console2.log("MERAWalletMetaProxyCloneFactory deployed at:", address(factory));
    }
}
