// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

contract DeployMockERC20 is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the MockERC20 contract
        MockERC20 token = new MockERC20("Mock Token", "MOCK", 18);
        token.mint(
            address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266),
            100000e18
        );
        token.mint(
            address(0x70997970C51812dc3A010C7d01b50e0d17dc79C8),
            100000e18
        );
        token.mint(
            address(0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC),
            100000e18
        );
        console.log("MockERC20 deployed to:", address(token));
        vm.stopBroadcast();
    }
}
