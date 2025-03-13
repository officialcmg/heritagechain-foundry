// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import { HeritageChain } from "./HeritageChain.sol";

contract HeritageChainFactory {
    // Mapping to store one contract address per user
    mapping(address => address) public userContracts;

    event HeritageChainCreated(address indexed creator);

    /**
     * @notice Deploys a new HeritageChain contract for the sender.
     * @dev Allows only one active contract per user unless the previous one has distributed its funds.
     * @return The address of the newly deployed HeritageChain contract.
     */
    function deployHeritageChain() public returns (address) {
        address existingContract = userContracts[msg.sender];

        // If user already has a contract deployed, check if funds are distributed
        if (existingContract != address(0)) {
            HeritageChain existingHeritageChain = HeritageChain(payable(existingContract));
            require(existingHeritageChain.getIsDistributed(), "Your previous HeritageChain contract is still active");
        }

        // Deploy a new HeritageChain contract
        HeritageChain newHeritageChain = new HeritageChain(msg.sender);
        userContracts[msg.sender] = address(newHeritageChain);

        emit HeritageChainCreated(msg.sender);

        return address(newHeritageChain);
    }

    /**
     * @notice Returns the user's current HeritageChain contract address.
     * @return The address of the user's HeritageChain contract or zero address if none exists.
     */
    function getUserHeritageChain(address _user) public view returns (address) {
        require (userContracts[_user] != address(0), "No deployed HeritageChain contract by this user");
        return userContracts[_user];
    }
}
