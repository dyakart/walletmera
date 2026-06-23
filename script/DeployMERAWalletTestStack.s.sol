// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Script, console2} from "forge-std/Script.sol";
import {BaseMERAWallet} from "../src/BaseMERAWallet.sol";
import {MERALoginSignatureVerifier} from "../src/MERALoginSignatureVerifier.sol";
import {MERAWalletLoginRegistry} from "../src/MERAWalletLoginRegistry.sol";
import {MERAWalletMetaProxyCloneFactory} from "../src/MERAWalletMetaProxyCloneFactory.sol";

/// @notice Deploys a production-like WalletMera test stack.
contract DeployMERAWalletTestStack is Script {
    function run()
        external
        returns (
            BaseMERAWallet implementation,
            MERAWalletLoginRegistry registry,
            MERAWalletMetaProxyCloneFactory factory,
            MERALoginSignatureVerifier verifier
        )
    {
        address authorizer = vm.envAddress("WALLET_MERA_LOGIN_AUTHORIZER_ADDRESS");

        vm.startBroadcast();
        address deployer = msg.sender;
        console2.log("Deployer:", deployer);
        console2.log("Login authorizer:", authorizer);

        implementation = new BaseMERAWallet(address(1), address(2), address(3), address(0), address(0));
        registry = new MERAWalletLoginRegistry(deployer, true);
        factory = new MERAWalletMetaProxyCloneFactory(address(implementation), address(registry));
        verifier = new MERALoginSignatureVerifier(authorizer);

        registry.addFactory(address(factory));
        registry.setAuthorizationVerifier(address(verifier));

        vm.stopBroadcast();

        console2.log("BaseMERAWallet implementation deployed at:", address(implementation));
        console2.log("MERAWalletLoginRegistry deployed at:", address(registry));
        console2.log("MERAWalletMetaProxyCloneFactory deployed at:", address(factory));
        console2.log("MERALoginSignatureVerifier deployed at:", address(verifier));
    }
}
