// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {ZeroSumSimplified} from "../src/ZeroSumSimplified.sol";
import {ZeroSumSpectator} from "../src/ZeroSumSpectator.sol";

contract DeployScript is Script {
    function setUp() public {}

    function run() public {
        // Handle private key with or without 0x prefix
        string memory privateKeyStr = vm.envString("PRIVATE_KEY");
        uint256 deployerPrivateKey;
        
        // Check if private key has 0x prefix
        if (bytes(privateKeyStr).length == 66) {
            // Has 0x prefix
            deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        } else {
            // No 0x prefix, add it
            deployerPrivateKey = vm.parseUint(string(abi.encodePacked("0x", privateKeyStr)));
        }
        
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying from address:", deployer);
        console.log("Deployer balance:", deployer.balance);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy ZeroSumSimplified first
        console.log("Deploying ZeroSumSimplified...");
        ZeroSumSimplified zeroSum = new ZeroSumSimplified();
        console.log("ZeroSumSimplified deployed to:", address(zeroSum));
        
        // Deploy ZeroSumSpectator
        console.log("Deploying ZeroSumSpectator...");
        ZeroSumSpectator spectator = new ZeroSumSpectator();
        console.log("ZeroSumSpectator deployed to:", address(spectator));
        
        // Register the game contract with the spectator
        console.log("Registering game contract with spectator...");
        spectator.registerGameContract(address(zeroSum));
        
        // Set the spectator contract in the game contract
        console.log("Setting spectator contract in game...");
        zeroSum.setSpectatorContract(address(spectator));
        
        // Verify initial state
        console.log("=== Deployment Summary ===");
        console.log("ZeroSumSimplified:", address(zeroSum));
        console.log("ZeroSumSpectator:", address(spectator));
        console.log("Game counter:", zeroSum.gameCounter());
        console.log("Platform fee:", zeroSum.platformFee());
        console.log("Time limit:", zeroSum.timeLimit());
        console.log("Spectator contract set:", zeroSum.spectatorContract());
        console.log("Game contract registered:", address(zeroSum));
        
        vm.stopBroadcast();
        
        // Note: File writing removed due to Foundry security restrictions
        // Contract addresses are displayed in the console output above
        console.log("=== Copy these addresses for your frontend ===");
        console.log("NEXT_PUBLIC_GAME_CONTRACT_ADDRESS=", vm.toString(address(zeroSum)));
        console.log("NEXT_PUBLIC_SPECTATOR_CONTRACT_ADDRESS=", vm.toString(address(spectator)));
    }
}