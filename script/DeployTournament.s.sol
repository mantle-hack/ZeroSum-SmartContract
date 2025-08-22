// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {ZeroSumTournament} from "../src/ZeroSumTournament.sol";

interface IZeroSumSpectator {
    function registerGameContract(address _gameContract) external;
}

contract DeployTournamentScript is Script {
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
        
        console.log("Deploying Tournament Contract from address:", deployer);
        console.log("Deployer balance:", deployer.balance);
        console.log("Existing spectator contract:", EXISTING_SPECTATOR);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy ZeroSumTournament
        console.log("Deploying ZeroSumTournament...");
        ZeroSumTournament tournament = new ZeroSumTournament();
        console.log("ZeroSumTournament deployed to:", address(tournament));
        
        // Verify initial state and default tournament
        console.log("=== Verifying Deployment ===");
        console.log("Tournament counter:", tournament.counter());
        console.log("Platform fee (%):", tournament.fee());
        console.log("Min participants:", tournament.minPart());
        console.log("Max participants:", tournament.maxPart());
        
        // Check default tournament details
        console.log("=== Default Tournament Created ===");
        ZeroSumTournament.Tournament memory defaultTournament = tournament.getTournament(1);
        console.log("Tournament ID:", defaultTournament.id);
        console.log("Entry fee (wei):", defaultTournament.entryFee);
        console.log("Entry fee (milli-ETH):", defaultTournament.entryFee / 1e15);
        console.log("Max participants:", defaultTournament.maxParticipants);
        console.log("Total rounds:", defaultTournament.totalRounds);
        console.log("Status (0=REG, 1=ACTIVE, 2=FINISHED, 3=CANCELLED):", uint8(defaultTournament.status));
        console.log("Mode (0=QUICK_DRAW, 1=STRATEGIC, 2=HARDCORE_MYSTERY, 3=LAST_STAND):", uint8(defaultTournament.mode));
        console.log("Deadline (timestamp):", defaultTournament.deadline);
        
        // Check upcoming tournaments
        uint256[] memory upcoming = tournament.getUpcoming();
        console.log("Number of upcoming tournaments:", upcoming.length);
        
        // Get UI info for default tournament
        (
            uint256 entryFee,
            uint256 prizePool,
            uint256 partCount,
            uint256 maxParticipants,
            uint256 timeLeft,
            ZeroSumTournament.Status status,
            ZeroSumTournament.Mode mode
        ) = tournament.getUIInfo(1);
        
        console.log("=== Tournament UI Info ===");
        console.log("Entry fee (milli-ETH):", entryFee / 1e15);
        console.log("Current participants:", partCount);
        console.log("Max participants:", maxParticipants);
        console.log("Time left (seconds):", timeLeft);
        console.log("Time left (hours):", timeLeft / 3600);
        console.log("Status:", uint8(status));
        console.log("Mode:", uint8(mode));
        
        vm.stopBroadcast();
        
        // Display addresses for frontend configuration
        console.log("=== Copy these addresses for your frontend ===");
        console.log("NEXT_PUBLIC_TOURNAMENT_CONTRACT_ADDRESS=", vm.toString(address(tournament)));
        console.log("NEXT_PUBLIC_SPECTATOR_CONTRACT_ADDRESS=", vm.toString(EXISTING_SPECTATOR));
        
        // Display deployment details
        console.log("=== Deployment Summary ===");
        console.log("ZeroSumTournament:", address(tournament));
        console.log("Spectator Contract:", EXISTING_SPECTATOR);
        console.log("Owner:", tournament.owner());
        console.log("Default tournament ready for players!");
        
        // Display tournament joining information
        console.log("=== How to Join Default Tournament ===");
        console.log("1. Tournament ID: 1");
        console.log("2. Entry Fee: 0.001 ETH");
        console.log("3. Max Players: 4");
        console.log("4. Mode: Hardcore Mystery");
        console.log("5. Call: tournament.join(1) with 0.001 ETH value");
        
        console.log("=== Deployment Complete ===");
        console.log("- ZeroSumTournament contract deployed");
        console.log("- Default tournament created (4 players, 0.001 ETH entry)");
        console.log("- Ready for players to join!");
        console.log("- Tournament will auto-start when 4 players join");
    }
}