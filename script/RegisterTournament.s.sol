// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";

interface IZeroSumSpectator {
    function registerGameContract(address _gameContract) external;
}

contract RegisterTournamentScript is Script {
    address constant SPECTATOR = 0x151A0A2227B42D299b01a7D5AD3e1A81cB3BE1aE;
    address constant TOURNAMENT = 0x39fdd70dc8A2C85A23A65B4775ecC3bBEa373db7;
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("Registering tournament with spectator...");
        IZeroSumSpectator(SPECTATOR).registerGameContract(TOURNAMENT);
        console.log("Tournament registered successfully!");
        
        vm.stopBroadcast();
    }
}