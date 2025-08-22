// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {ZeroSumHardcoreMystery} from "../src/ZeroSumHardcoreMystery.sol";

interface IZeroSumSpectator {
    function registerGameContract(address _gameContract) external;
}

contract DeployHardcoreMysteryScript is Script {
    // Your existing spectator contract address
    address constant EXISTING_SPECTATOR = 0x151A0A2227B42D299b01a7D5AD3e1A81cB3BE1aE;
    
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
        console.log("Existing spectator contract:", EXISTING_SPECTATOR);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy ZeroSumHardcoreMystery
        console.log("Deploying ZeroSumHardcoreMystery...");
        ZeroSumHardcoreMystery hardcoreMystery = new ZeroSumHardcoreMystery();
        console.log("ZeroSumHardcoreMystery deployed to:", address(hardcoreMystery));
        
        // Set the existing spectator contract in the game contract
        console.log("Setting spectator contract in HardcoreMystery game...");
        hardcoreMystery.setSpectatorContract(EXISTING_SPECTATOR);
        
        // Register the new game contract with the existing spectator
        console.log("Registering HardcoreMystery game contract with existing spectator...");
        IZeroSumSpectator spectator = IZeroSumSpectator(EXISTING_SPECTATOR);
        spectator.registerGameContract(address(hardcoreMystery));
        
        // Verify initial state
        console.log("=== Deployment Summary ===");
        console.log("ZeroSumHardcoreMystery:", address(hardcoreMystery));
        console.log("Connected Spectator:", EXISTING_SPECTATOR);
        console.log("Game counter:", hardcoreMystery.gameCounter());
        console.log("Platform fee:", hardcoreMystery.platformFee());
        console.log("Time limit:", hardcoreMystery.timeLimit());
        console.log("Max strikes:", hardcoreMystery.maxStrikes());
        console.log("Spectator contract set:", hardcoreMystery.spectatorContract());
        console.log("Paused status:", hardcoreMystery.paused());
        
        vm.stopBroadcast();
        
        // Display addresses for frontend configuration
        console.log("=== Copy these addresses for your frontend ===");
        console.log("NEXT_PUBLIC_HARDCORE_MYSTERY_CONTRACT_ADDRESS=", vm.toString(address(hardcoreMystery)));
        console.log("NEXT_PUBLIC_SPECTATOR_CONTRACT_ADDRESS=", vm.toString(EXISTING_SPECTATOR));
        
        console.log("=== Deployment Complete ===");
        console.log("- ZeroSumHardcoreMystery contract deployed and configured");
        console.log("- Connected to existing spectator contract");
        console.log("- Ready for frontend integration");
    }
}