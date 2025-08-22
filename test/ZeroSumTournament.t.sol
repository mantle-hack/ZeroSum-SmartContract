// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/ZeroSumTournament.sol";

contract ZeroSumTournamentTest is Test {
    ZeroSumTournament public tournament;
    
    // Test accounts
    address public owner;
    address public player1;
    address public player2;
    address public player3;
    address public player4;
    address public player5;
    
    // Constants
    uint256 constant ENTRY_FEE = 0.001 ether;
    uint256 constant PLATFORM_FEE = 10; // 10%
    
    function setUp() public {
        // Setup test accounts
        owner = address(this);
        player1 = makeAddr("player1");
        player2 = makeAddr("player2");
        player3 = makeAddr("player3");
        player4 = makeAddr("player4");
        player5 = makeAddr("player5");
        
        // Give test accounts some ETH
        vm.deal(player1, 10 ether);
        vm.deal(player2, 10 ether);
        vm.deal(player3, 10 ether);
        vm.deal(player4, 10 ether);
        vm.deal(player5, 10 ether);
        
        // Deploy tournament contract
        tournament = new ZeroSumTournament();
        
        console.log("Tournament deployed at:", address(tournament));
        console.log("Owner:", owner);
    }
    
    function testInitialState() public view {
        // Check initial counter
        assertEq(tournament.counter(), 1, "Counter should be 1 after deployment");
        
        // Check default tournament was created
        ZeroSumTournament.Tournament memory t = tournament.getTournament(1);
        assertEq(t.id, 1, "Tournament ID should be 1");
        assertEq(t.entryFee, ENTRY_FEE, "Entry fee should be 0.001 ETH");
        assertEq(t.maxParticipants, 4, "Max participants should be 4");
        assertEq(uint8(t.mode), uint8(ZeroSumTournament.Mode.HARDCORE_MYSTERY), "Mode should be HARDCORE_MYSTERY");
        assertEq(uint8(t.status), uint8(ZeroSumTournament.Status.REG), "Status should be REG");
        assertEq(t.totalRounds, 2, "Total rounds should be 2 for 4 players");
        
        console.log("Initial state tests passed");
    }
    
    function testSinglePlayerJoin() public {
        // Player 1 joins
        vm.prank(player1);
        tournament.join{value: ENTRY_FEE}(1);
        
        // Check tournament state
        ZeroSumTournament.Tournament memory t = tournament.getTournament(1);
        assertEq(t.prizePool, ENTRY_FEE, "Prize pool should equal entry fee");
        assertEq(uint8(t.status), uint8(ZeroSumTournament.Status.REG), "Status should still be REG");
        
        // Check participants
        address[] memory participants = tournament.getParticipants(1);
        assertEq(participants.length, 1, "Should have 1 participant");
        assertEq(participants[0], player1, "First participant should be player1");
        
        // Check player joined mapping
        assertTrue(tournament.joined(1, player1), "Player1 should be marked as joined");
        
        console.log("Single player join tests passed");
    }
    
    function testMultiplePlayersJoin() public {
        // Players 1-3 join
        vm.prank(player1);
        tournament.join{value: ENTRY_FEE}(1);
        
        vm.prank(player2);
        tournament.join{value: ENTRY_FEE}(1);
        
        vm.prank(player3);
        tournament.join{value: ENTRY_FEE}(1);
        
        // Check tournament state
        ZeroSumTournament.Tournament memory t = tournament.getTournament(1);
        assertEq(t.prizePool, ENTRY_FEE * 3, "Prize pool should be 3x entry fee");
        assertEq(uint8(t.status), uint8(ZeroSumTournament.Status.REG), "Status should still be REG");
        
        // Check participants
        address[] memory participants = tournament.getParticipants(1);
        assertEq(participants.length, 3, "Should have 3 participants");
        
        console.log("Multiple players join tests passed");
    }
    
    function testTournamentAutoStart() public {
        // All 4 players join
        vm.prank(player1);
        tournament.join{value: ENTRY_FEE}(1);
        
        vm.prank(player2);
        tournament.join{value: ENTRY_FEE}(1);
        
        vm.prank(player3);
        tournament.join{value: ENTRY_FEE}(1);
        
        // Tournament should auto-start when 4th player joins
        vm.prank(player4);
        tournament.join{value: ENTRY_FEE}(1);
        
        // Check tournament state
        ZeroSumTournament.Tournament memory t = tournament.getTournament(1);
        assertEq(t.prizePool, ENTRY_FEE * 4, "Prize pool should be 4x entry fee");
        assertEq(uint8(t.status), uint8(ZeroSumTournament.Status.ACTIVE), "Status should be ACTIVE");
        assertEq(t.currentRound, 1, "Should be in round 1");
        
        // Check round 1 matches were created
        ZeroSumTournament.Match[] memory matches = tournament.getRoundMatches(1, 1);
        assertEq(matches.length, 2, "Should have 2 matches in round 1");
        
        // Check match 1
        assertEq(matches[0].p1, player1, "Match 1 player 1 should be player1");
        assertEq(matches[0].p2, player2, "Match 1 player 2 should be player2");
        assertFalse(matches[0].done, "Match 1 should not be done");
        
        // Check match 2
        assertEq(matches[1].p1, player3, "Match 2 player 1 should be player3");
        assertEq(matches[1].p2, player4, "Match 2 player 2 should be player4");
        assertFalse(matches[1].done, "Match 2 should not be done");
        
        console.log("Tournament auto-start tests passed");
    }
    
    function testRecordMatchResults() public {
        // Setup: Start tournament
        _fillTournament();
        
        // Record result for match 1: player1 wins
        tournament.recordResult(1, 1, 0, player1);
        
        // Check match 1 is completed
        ZeroSumTournament.Match[] memory matches = tournament.getRoundMatches(1, 1);
        assertTrue(matches[0].done, "Match 1 should be done");
        assertEq(matches[0].winner, player1, "Match 1 winner should be player1");
        
        // Tournament should still be in round 1 (waiting for match 2)
        ZeroSumTournament.Tournament memory t = tournament.getTournament(1);
        assertEq(t.currentRound, 1, "Should still be in round 1");
        assertEq(uint8(t.status), uint8(ZeroSumTournament.Status.ACTIVE), "Should still be ACTIVE");
        
        console.log("Record match result tests passed");
    }
    
    function testRoundAdvancement() public {
        // Setup: Start tournament
        _fillTournament();
        
        // Record results for both round 1 matches
        tournament.recordResult(1, 1, 0, player1); // player1 beats player2
        tournament.recordResult(1, 1, 1, player3); // player3 beats player4
        
        // Check tournament advanced to round 2
        ZeroSumTournament.Tournament memory t = tournament.getTournament(1);
        assertEq(t.currentRound, 2, "Should be in round 2");
        assertEq(uint8(t.status), uint8(ZeroSumTournament.Status.ACTIVE), "Should still be ACTIVE");
        
        // Check round 2 match was created
        ZeroSumTournament.Match[] memory round2Matches = tournament.getRoundMatches(1, 2);
        assertEq(round2Matches.length, 1, "Should have 1 match in round 2");
        assertEq(round2Matches[0].p1, player1, "Final match player 1 should be player1");
        assertEq(round2Matches[0].p2, player3, "Final match player 2 should be player3");
        
        console.log("Round advancement tests passed");
    }
    
    function testTournamentCompletion() public {
        // Setup: Start tournament and complete round 1
        _fillTournament();
        tournament.recordResult(1, 1, 0, player1);
        tournament.recordResult(1, 1, 1, player3);
        
        // Get initial balances
        uint256 initialPlayer1Balance = player1.balance;
        uint256 initialOwnerBalance = owner.balance;
        
        // Record final match: player1 wins tournament
        tournament.recordResult(1, 2, 0, player1);
        
        // Check tournament is finished
        ZeroSumTournament.Tournament memory t = tournament.getTournament(1);
        assertEq(uint8(t.status), uint8(ZeroSumTournament.Status.FINISHED), "Status should be FINISHED");
        assertEq(t.winner, player1, "Winner should be player1");
        
        // Check prize distribution
        uint256 totalPrize = ENTRY_FEE * 4;
        uint256 platformFee = (totalPrize * PLATFORM_FEE) / 100;
        uint256 winnerPrize = totalPrize - platformFee;
        
        assertEq(player1.balance, initialPlayer1Balance + winnerPrize, "Player1 should receive winner prize");
        assertEq(owner.balance, initialOwnerBalance + platformFee, "Owner should receive platform fee");
        
        // Check stats
        (, uint256 won, uint256 earnings,) = tournament.getStats(player1);
        assertEq(won, 1, "Player1 should have 1 win");
        assertEq(earnings, winnerPrize, "Player1 earnings should match prize");
        
        console.log("Tournament completion tests passed");
    }
    
    function test_RevertWhen_PlayerTriesToJoinTwice() public {
        // Player 1 joins
        vm.prank(player1);
        tournament.join{value: ENTRY_FEE}(1);
        
        // Player 1 tries to join again - should fail
        vm.prank(player1);
        vm.expectRevert(bytes("Already joined"));
        tournament.join{value: ENTRY_FEE}(1);
    }
    
    function test_RevertWhen_WrongEntryFeeProvided() public {
        // Try to join with wrong fee - should fail
        vm.prank(player1);
        vm.expectRevert(bytes("Wrong fee"));
        tournament.join{value: ENTRY_FEE / 2}(1);
    }
    
    function test_RevertWhen_TournamentIsFull() public {
        // Fill tournament
        _fillTournament();
        
        // Try to join full tournament - should fail
        vm.prank(player5);
        vm.expectRevert(bytes("Closed"));
        tournament.join{value: ENTRY_FEE}(1);
    }
    
    function test_RevertWhen_NonOwnerTriesToRecordResult() public {
        // Setup tournament
        _fillTournament();
        
        // Non-owner tries to record result - should fail
        vm.prank(player1);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        tournament.recordResult(1, 1, 0, player1);
    }
    
    function test_RevertWhen_InvalidWinnerProvided() public {
        // Setup tournament
        _fillTournament();
        
        // Try to record invalid winner - should fail
        vm.expectRevert(bytes("Invalid"));
        tournament.recordResult(1, 1, 0, player5); // player5 not in match
    }
    
    function testCreateNewTournament() public {
        // Create a new tournament as owner
        uint256 newTournamentId = tournament.create(
            "Test Tournament",
            0.01 ether,
            8,
            ZeroSumTournament.Mode.STRATEGIC,
            48
        );
        
        assertEq(newTournamentId, 2, "New tournament ID should be 2");
        
        // Check new tournament details
        ZeroSumTournament.Tournament memory t = tournament.getTournament(2);
        assertEq(t.entryFee, 0.01 ether, "Entry fee should be 0.01 ETH");
        assertEq(t.maxParticipants, 8, "Max participants should be 8");
        assertEq(uint8(t.mode), uint8(ZeroSumTournament.Mode.STRATEGIC), "Mode should be STRATEGIC");
        assertEq(t.totalRounds, 3, "Total rounds should be 3 for 8 players");
        
        console.log("Create new tournament tests passed");
    }
    
    function testGetUpcoming() public {
        // Initially should have 1 upcoming tournament
        uint256[] memory upcoming = tournament.getUpcoming();
        assertEq(upcoming.length, 1, "Should have 1 upcoming tournament");
        assertEq(upcoming[0], 1, "First upcoming should be tournament 1");
        
        // Create another tournament
        tournament.create("Test 2", 0.05 ether, 16, ZeroSumTournament.Mode.LAST_STAND, 72);
        
        // Should now have 2 upcoming
        upcoming = tournament.getUpcoming();
        assertEq(upcoming.length, 2, "Should have 2 upcoming tournaments");
        
        console.log("Get upcoming tournaments tests passed");
    }
    
    function testTournamentCancel() public {
        // Player joins tournament
        vm.prank(player1);
        tournament.join{value: ENTRY_FEE}(1);
        
        uint256 initialBalance = player1.balance;
        
        // Owner cancels tournament
        tournament.cancel(1);
        
        // Check tournament is cancelled
        ZeroSumTournament.Tournament memory t = tournament.getTournament(1);
        assertEq(uint8(t.status), uint8(ZeroSumTournament.Status.CANCELLED), "Status should be CANCELLED");
        assertEq(t.prizePool, 0, "Prize pool should be 0");
        
        // Check player got refund
        assertEq(player1.balance, initialBalance + ENTRY_FEE, "Player should be refunded");
        
        console.log("Tournament cancel tests passed");
    }
    
    function testUIInfo() public view {
        // Test UI info for initial tournament
        (
            uint256 entryFee,
            uint256 prizePool,
            uint256 partCount,
            uint256 maxParticipants,
            uint256 timeLeft,
            ZeroSumTournament.Status status,
            ZeroSumTournament.Mode mode
        ) = tournament.getUIInfo(1);
        
        assertEq(entryFee, ENTRY_FEE, "Entry fee should match");
        assertEq(prizePool, 0, "Initial prize pool should be 0");
        assertEq(partCount, 0, "Initial participant count should be 0");
        assertEq(maxParticipants, 4, "Max participants should be 4");
        assertGt(timeLeft, 0, "Time left should be greater than 0");
        assertEq(uint8(status), uint8(ZeroSumTournament.Status.REG), "Status should be REG");
        assertEq(uint8(mode), uint8(ZeroSumTournament.Mode.HARDCORE_MYSTERY), "Mode should be HARDCORE_MYSTERY");
        
        console.log("UI info tests passed");
    }
    
    // Helper function to fill tournament with 4 players
    function _fillTournament() internal {
        vm.prank(player1);
        tournament.join{value: ENTRY_FEE}(1);
        
        vm.prank(player2);
        tournament.join{value: ENTRY_FEE}(1);
        
        vm.prank(player3);
        tournament.join{value: ENTRY_FEE}(1);
        
        vm.prank(player4);
        tournament.join{value: ENTRY_FEE}(1);
    }
    
    // Test edge cases
    function testCalculateRounds() public {
        // Test different participant counts
        assertEq(tournament.create("Test 4", 0.001 ether, 4, ZeroSumTournament.Mode.QUICK_DRAW, 24), 2);
        ZeroSumTournament.Tournament memory t4 = tournament.getTournament(2);
        assertEq(t4.totalRounds, 2, "4 players should have 2 rounds");
        
        assertEq(tournament.create("Test 8", 0.001 ether, 8, ZeroSumTournament.Mode.QUICK_DRAW, 24), 3);
        ZeroSumTournament.Tournament memory t8 = tournament.getTournament(3);
        assertEq(t8.totalRounds, 3, "8 players should have 3 rounds");
        
        assertEq(tournament.create("Test 16", 0.001 ether, 16, ZeroSumTournament.Mode.QUICK_DRAW, 24), 4);
        ZeroSumTournament.Tournament memory t16 = tournament.getTournament(4);
        assertEq(t16.totalRounds, 4, "16 players should have 4 rounds");
        
        console.log("Calculate rounds tests passed");
    }
    
    function testGasUsage() public {
        // Test gas usage for key functions
        uint256 gasBefore;
        uint256 gasAfter;
        
        // Test join gas usage
        gasBefore = gasleft();
        vm.prank(player1);
        tournament.join{value: ENTRY_FEE}(1);
        gasAfter = gasleft();
        console.log("Join gas usage:", gasBefore - gasAfter);
        
        // Fill rest of tournament
        vm.prank(player2);
        tournament.join{value: ENTRY_FEE}(1);
        vm.prank(player3);
        tournament.join{value: ENTRY_FEE}(1);
        vm.prank(player4);
        tournament.join{value: ENTRY_FEE}(1);
        
        // Test record result gas usage
        gasBefore = gasleft();
        tournament.recordResult(1, 1, 0, player1);
        gasAfter = gasleft();
        console.log("Record result gas usage:", gasBefore - gasAfter);
        
        console.log("Gas usage tests completed");
    }
    
    // Receive function to accept ETH
    receive() external payable {}
}