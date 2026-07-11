// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {CREATE3} from "solady/src/utils/CREATE3.sol";

/// @title MERACrossChainDeployer
/// @notice Deploys approved WalletMera components at addresses independent of their initialization code.
/// @dev The same instance address, owner and component salts must be used on every supported chain.
contract MERACrossChainDeployer is Ownable {
    /// @notice Init-code hash recorded for each deployed component salt.
    mapping(bytes32 salt => bytes32 initCodeHash) public initCodeHashBySalt;

    /// @notice Emitted after a component is deployed at its deterministic address.
    event ComponentDeployed(bytes32 indexed salt, address indexed component, bytes32 initCodeHash);

    /// @notice Reverts when no contract creation code is supplied.
    error EmptyInitCode();
    /// @notice Reverts when a component already exists for the supplied salt.
    error ComponentAlreadyDeployed(address component);

    constructor(address initialOwner) Ownable(initialOwner) {}

    /// @notice Deploys one component at the deterministic address associated with `salt`.
    function deploy(bytes32 salt, bytes calldata initCode) external onlyOwner returns (address component) {
        require(initCode.length != 0, EmptyInitCode());
        component = CREATE3.predictDeterministicAddress(salt);
        require(component.code.length == 0, ComponentAlreadyDeployed(component));

        bytes32 initCodeHash = keccak256(initCode);
        component = CREATE3.deployDeterministic(initCode, salt);
        initCodeHashBySalt[salt] = initCodeHash;
        emit ComponentDeployed(salt, component, initCodeHash);
    }

    /// @notice Returns the component address associated with `salt`.
    function predict(bytes32 salt) external view returns (address) {
        return CREATE3.predictDeterministicAddress(salt);
    }
}
