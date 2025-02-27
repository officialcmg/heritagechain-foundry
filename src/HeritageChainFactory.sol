// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import { HeritageChain } from "./HeritageChain.sol";

contract HeritageChainFactory {

    function deployHeritageChain() public returns (address) {
        address owner = msg.sender;
        HeritageChain heritageChain = new HeritageChain(owner);
        return address(heritageChain);
    }
}