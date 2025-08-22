// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";

// Import your enhanced spectator contract
// Make sure this path matches your contract location
import "../src/ZeroSumSpectator.sol";

contract DeploySpectatorScript is Script {
    // Your existing game contract addresses
    address constant ZEROSUM_SIMPLIFIED = 0xfb40c6BACc74019E01C0dD5b434CE896806D7579;
    address constant HARDCORE_MYSTERY = 0x2E56044dB3be726772D6E5afFD7BD813C6895025;
    address constant TOURNAMENT = 0x39fdd70dc8A2C85A23A65B4775ecC3bBEa373db7;

    function run() external {
        // Get the deployer's private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deployer address:", deployer);
        console.log("Deployer balance:", deployer.balance);
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy the enhanced ZeroSumSpectator contract
        console.log("Deploying Enhanced ZeroSumSpectator contract...");
        ZeroSumSpectator spectatorContract = new ZeroSumSpectator();
        
        console.log("ZeroSumSpectator deployed at:", address(spectatorContract));

        // 2. Register all three game contracts
        console.log("\nRegistering game contracts...");
        
        // Register ZeroSum Simplified
        console.log("Registering ZeroSum Simplified:", ZEROSUM_SIMPLIFIED);
        spectatorContract.registerGameContract(ZEROSUM_SIMPLIFIED);
        console.log("ZeroSum Simplified registered");

        // Register Hardcore Mystery
        console.log("Registering Hardcore Mystery:", HARDCORE_MYSTERY);
        spectatorContract.registerGameContract(HARDCORE_MYSTERY);
        console.log("Hardcore Mystery registered");

        // Register Tournament
        console.log("Registering Tournament:", TOURNAMENT);
        spectatorContract.registerGameContract(TOURNAMENT);
        console.log("Tournament registered");

        // 3. Enable global betting
        console.log("\nConfiguring spectator contract...");
        spectatorContract.setGlobalBettingEnabled(true);
        console.log("Global betting enabled");

        // 4. Set reasonable minimum bet (0.001 ETH)
        spectatorContract.setMinimumBet(0.001 ether);
        console.log("Minimum bet set to 0.001 ETH");

        // 5. Set betting fee to 3%
        spectatorContract.setBettingFee(3);
        console.log("Betting fee set to 3%");

        vm.stopBroadcast();

        // 6. Verify the setup
        console.log("\nVerifying deployment...");
        
        // Check if contracts are registered
        bool simplifiedRegistered = spectatorContract.registeredContracts(ZEROSUM_SIMPLIFIED);
        bool mysteryRegistered = spectatorContract.registeredContracts(HARDCORE_MYSTERY);
        bool tournamentRegistered = spectatorContract.registeredContracts(TOURNAMENT);
        bool globalEnabled = spectatorContract.globalBettingEnabled();
        uint256 minBet = spectatorContract.minimumBet();
        uint256 fee = spectatorContract.bettingFeePercent();

        console.log("ZeroSum Simplified registered:", simplifiedRegistered);
        console.log("Hardcore Mystery registered:", mysteryRegistered);
        console.log("Tournament registered:", tournamentRegistered);
        console.log("Global betting enabled:", globalEnabled);
        console.log("Minimum bet:", minBet);
        console.log("Betting fee:", fee, "%");

        // 7. Print summary
        console.log("\nDEPLOYMENT SUMMARY");
        console.log("====================");
        console.log("Spectator Contract:", address(spectatorContract));
        console.log("Owner:", spectatorContract.owner());
        console.log("Registered Contracts:");
        console.log("  - ZeroSum Simplified:", ZEROSUM_SIMPLIFIED, simplifiedRegistered ? "SUCCESS" : "FAILED");
        console.log("  - Hardcore Mystery:", HARDCORE_MYSTERY, mysteryRegistered ? "SUCCESS" : "FAILED");
        console.log("  - Tournament:", TOURNAMENT, tournamentRegistered ? "SUCCESS" : "FAILED");
        console.log("Global Betting Enabled:", globalEnabled ? "YES" : "NO");
        console.log("Configuration:");
        console.log("  - Minimum Bet: 0.001 ETH");
        console.log("  - Betting Fee: 3%");

        // 8. Print environment variables for frontend
        console.log("\nADD TO YOUR .env.local:");
        console.log("NEXT_PUBLIC_SPECTATOR_CONTRACT_ADDRESS=", address(spectatorContract));
        
        // 9. Verify all contracts are working
        console.log("\nTesting betting availability...");
        
        // This will help you test if betting works for your existing games
        console.log("To test betting, call:");
        console.log("spectatorContract.isBettingAllowed(GAME_CONTRACT, GAME_ID)");
        console.log("Replace GAME_CONTRACT and GAME_ID with actual values");
    }
}