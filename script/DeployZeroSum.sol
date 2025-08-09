// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {ZeroSumHardcoreMystery} from "../src/ZeroSumHardcoreMystery.sol";
import {ZeroSumPureMystery} from "../src/ZeroSumPureMystery.sol";
import {ZeroSumSimplified} from "../src/ZeroSumSimplified.sol";
import {ZeroSumSpectator} from "../src/ZeroSumSpectator.sol";
import {ZeroSumTournament} from "../src/ZeroSumTournament.sol";

contract DeployZeroSum is Script {
    ZeroSumHardcoreMystery public zeroSumHardCoreMystery;

    function setUp() public {}

    function run() public {
        uint128 privateKey = uint128(vm.envUint("PRIVATE_KEY"));
        vm.startBroadcast(privateKey);

        zeroSumHardCoreMystery = new ZeroSumHardcoreMystery();
        console.log("hard core contract address ::: ", address(zeroSumHardCoreMystery));

        ZeroSumPureMystery zeroSumPureMystery = new ZeroSumPureMystery();
        console.log("pure contract address ::: ", address(zeroSumPureMystery));

        ZeroSumSimplified zeroSumSimplified = new ZeroSumSimplified();
        console.log("simplified contract address ::: ", address(zeroSumSimplified));

        ZeroSumSpectator zeroSumSpectator = new ZeroSumSpectator();
        console.log("spectator contract address ::: ", address(zeroSumSpectator));

        ZeroSumTournament zeroSumTournament = new ZeroSumTournament();
        console.log("tournament contract address ::: ", address(zeroSumTournament));

        vm.stopBroadcast();
    }
}
