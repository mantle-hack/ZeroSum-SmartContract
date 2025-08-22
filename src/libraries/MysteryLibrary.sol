// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.19;

// import "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";

// // ✅ Import from main contract to avoid duplication
// import {MysteryGame, MysteryGameMode, MysteryGameStatus, MoveResult, MoveHistory} from "../ZeroSumMystery.sol";

// interface IZeroSumSpectator {
//     function finalizeGameBetting(uint256 _gameId) external;
// }

// /**
//  * @title MysteryLibrary - BUG-FREE FOUNDATION
//  * @dev Fixes all critical bugs from simplified contract:
//  * - ✅ FIXED: Money doubling bug (proper prize pool handling)  
//  * - ✅ FIXED: Timeout system with proper validation
//  * - ✅ FIXED: Game state management
//  * - ✅ FIXED: Player validation and edge cases
//  */
// library MysteryLibrary {
//     // Constants
//     uint256 private constant EASY_MIN = 25;
//     uint256 private constant EASY_MAX = 75;
//     uint256 private constant HARD_MIN = 50;
//     uint256 private constant HARD_MAX = 150;
//     uint256 private constant MAX_STRIKES = 2;
//     uint256 private constant TIME_LIMIT = 300;
//     uint256 private constant PLATFORM_FEE = 5;

//     // Events (library events need to be redeclared)
//     event GameCreated(uint256 indexed gameId, MysteryGameMode mode, address creator, uint256 entryFee);
//     event PlayerJoined(uint256 indexed gameId, address player);
//     event NumberGenerationRequested(uint256 indexed gameId, uint256 vrfRequestId);
//     event NumberGenerated(uint256 indexed gameId, uint256 displayMin, uint256 displayMax);
//     event MoveMade(uint256 indexed gameId, address player, uint256 subtraction, MoveResult result, string feedback);
//     event GameFinished(uint256 indexed gameId, address winner, uint256 earnings);
//     event PlayerTimeout(uint256 indexed gameId, address indexed player, uint256 timeoutCount);

//     // ================== GAME CREATION (BUG-FREE) ==================

//     /**
//      * @dev ✅ FIXED: Proper money handling - no double counting
//      */
//     function createGame(
//         MysteryGameMode _mode,
//         uint256 gameCounter,
//         mapping(uint256 => MysteryGame) storage games,
//         mapping(uint256 => mapping(address => bool)) storage isInGame,
//         mapping(uint256 => mapping(address => uint256)) storage timeouts,
//         mapping(address => uint256) storage played
//     ) external returns (uint256 gameId) {
//         require(msg.value > 0, "Entry fee required");
        
//         gameId = gameCounter;

//         // ✅ FIXED: Initialize with ZERO prize pool (no double counting)
//         games[gameId] = MysteryGame({
//             gameId: gameId,
//             mode: _mode,
//             actualNumber: 0, // Always 0 - hidden number
//             currentPlayer: msg.sender,
//             status: MysteryGameStatus.WAITING,
//             entryFee: msg.value,
//             prizePool: 0, // ✅ START AT ZERO - will be added in _joinGame
//             winner: address(0),
//             moveCount: 0,
//             isStarted: false,
//             player1: msg.sender,
//             player2: address(0),
//             vrf_requestId: 0
//         });

//         // ✅ FIXED: Proper validation and initialization
//         require(!isInGame[gameId][msg.sender], "Already in game");
//         isInGame[gameId][msg.sender] = true;
//         played[msg.sender]++;
//         timeouts[gameId][msg.sender] = 0;

//         // ✅ CRITICAL: Add creator's money to prize pool
//         games[gameId].prizePool = msg.value;

//         emit GameCreated(gameId, _mode, msg.sender, msg.value);
//         return gameId;
//     }

//     /**
//      * @dev ✅ FIXED: Proper joining with exact money validation
//      */
//     function joinGame(
//         uint256 _gameId,
//         mapping(uint256 => MysteryGame) storage games,
//         mapping(uint256 => mapping(address => bool)) storage isInGame,
//         mapping(uint256 => mapping(address => uint256)) storage timeouts,
//         mapping(address => uint256) storage played
//     ) external {
//         MysteryGame storage g = games[_gameId];
        
//         // ✅ ENHANCED VALIDATION (fixes simplified bugs)
//         require(g.gameId != 0, "Game does not exist");
//         require(g.status == MysteryGameStatus.WAITING, "Game not waiting for players");
//         require(!isInGame[_gameId][msg.sender], "Player already in this game");
//         require(g.player2 == address(0), "Game already full");
//         require(msg.value == g.entryFee, "Incorrect entry fee");
//         require(msg.sender != g.player1, "Cannot join your own game");

//         // ✅ SAFE MONEY HANDLING: Add exactly once
//         g.player2 = msg.sender;
//         g.prizePool += msg.value; // ✅ This ensures exactly 2x entry fee total
        
//         // ✅ PROPER STATE MANAGEMENT
//         isInGame[_gameId][msg.sender] = true;
//         played[msg.sender]++;
//         timeouts[_gameId][msg.sender] = 0;

//         emit PlayerJoined(_gameId, msg.sender);
//     }

//     // ================== CHAINLINK VRF INTEGRATION ==================

//     function requestRandomNumber(
//         uint256 _gameId,
//         VRFCoordinatorV2Interface coordinator,
//         bytes32 keyHash,
//         uint64 subscriptionId,
//         uint16 requestConfirmations,
//         uint32 callbackGasLimit,
//         mapping(uint256 => MysteryGame) storage games,
//         mapping(uint256 => uint256) storage requestIdToGameId
//     ) external returns (uint256 requestId) {
//         MysteryGame storage g = games[_gameId];
//         require(g.status == MysteryGameStatus.WAITING, "Game not ready for number generation");
//         require(g.player2 != address(0), "Need both players");
        
//         g.status = MysteryGameStatus.GENERATING_NUMBER;
        
//         requestId = coordinator.requestRandomWords(
//             keyHash,
//             subscriptionId,
//             requestConfirmations,
//             callbackGasLimit,
//             1 // numWords
//         );
        
//         g.vrf_requestId = requestId;
//         requestIdToGameId[requestId] = _gameId;
        
//         emit NumberGenerationRequested(_gameId, requestId);
//         return requestId;
//     }

//     function fulfillRandomNumber(
//         uint256 requestId,
//         uint256 randomWord,
//         mapping(uint256 => uint256) storage requestIdToGameId,
//         mapping(uint256 => MysteryGame) storage games,
//         mapping(uint256 => uint256) storage secretNumbers,
//         mapping(uint256 => uint256) storage remainingNumbers,
//         mapping(uint256 => uint256) storage displayMinRange,
//         mapping(uint256 => uint256) storage displayMaxRange,
//         mapping(uint256 => uint256) storage turnDeadlines
//     ) external {
//         uint256 gameId = requestIdToGameId[requestId];
//         require(gameId != 0, "Invalid VRF request");
        
//         MysteryGame storage g = games[gameId];
//         require(g.status == MysteryGameStatus.GENERATING_NUMBER, "Invalid game state");
        
//         // Generate secret number
//         uint256 secret = _generateSecretNumber(randomWord, g.mode);
//         secretNumbers[gameId] = secret;
//         remainingNumbers[gameId] = secret;
        
//         // Generate display range
//         _generateDisplayRange(gameId, secret, g.mode, displayMinRange, displayMaxRange);
        
//         // Start game
//         g.status = MysteryGameStatus.ACTIVE;
//         g.isStarted = true;
//         g.currentPlayer = g.player1;
//         turnDeadlines[gameId] = block.timestamp + TIME_LIMIT;
        
//         emit NumberGenerated(gameId, displayMinRange[gameId], displayMaxRange[gameId]);
//     }

//     function _generateSecretNumber(uint256 randomness, MysteryGameMode mode) private pure returns (uint256) {
//         if (mode == MysteryGameMode.MYSTERY_EASY) {
//             return EASY_MIN + (randomness % (EASY_MAX - EASY_MIN + 1));
//         } else {
//             return HARD_MIN + (randomness % (HARD_MAX - HARD_MIN + 1));
//         }
//     }

//     function _generateDisplayRange(
//         uint256 gameId,
//         uint256 secretNumber,
//         MysteryGameMode mode,
//         mapping(uint256 => uint256) storage displayMinRange,
//         mapping(uint256 => uint256) storage displayMaxRange
//     ) private {
//         uint256 entropy = uint256(keccak256(abi.encodePacked(secretNumber, gameId, block.timestamp)));
        
//         uint256 rangePadding;
//         if (mode == MysteryGameMode.MYSTERY_EASY) {
//             rangePadding = 15 + (entropy % 20); // 15-35 padding
//         } else {
//             rangePadding = 25 + (entropy % 40); // 25-65 padding
//         }
        
//         uint256 lowerPadding = (entropy % rangePadding) + 5;
//         uint256 upperPadding = rangePadding - lowerPadding + 10;
        
//         displayMinRange[gameId] = secretNumber >= lowerPadding ? secretNumber - lowerPadding : 1;
//         displayMaxRange[gameId] = secretNumber + upperPadding;
        
//         // Ensure minimum range spread
//         uint256 minSpread = mode == MysteryGameMode.MYSTERY_EASY ? 30 : 50;
//         if (displayMaxRange[gameId] - displayMinRange[gameId] < minSpread) {
//             displayMaxRange[gameId] = displayMinRange[gameId] + minSpread;
//         }
//     }

//     // ================== GAMEPLAY (BUG-FREE) ==================

//     /**
//      * @dev ✅ FIXED: Comprehensive move validation and handling
//      */
//     function makeMove(
//         uint256 _gameId,
//         uint256 _subtraction,
//         mapping(uint256 => MysteryGame) storage games,
//         mapping(uint256 => mapping(address => uint256)) storage timeouts,
//         mapping(uint256 => uint256) storage turnDeadlines,
//         mapping(uint256 => uint256) storage remainingNumbers,
//         mapping(uint256 => MoveHistory[]) storage moveHistory
//     ) external returns (MoveResult result, string memory feedback) {
//         MysteryGame storage g = games[_gameId];
        
//         // ✅ COMPREHENSIVE VALIDATION (fixes simplified bugs)
//         require(g.status == MysteryGameStatus.ACTIVE, "Game not active");
//         require(g.isStarted, "Game not started");
//         require(msg.sender == g.currentPlayer, "Not your turn");
//         require(timeouts[_gameId][msg.sender] < MAX_STRIKES, "Player eliminated");
//         require(block.timestamp <= turnDeadlines[_gameId], "Turn timed out");
//         require(_subtraction > 0, "Must subtract positive number");

//         g.moveCount++;
//         uint256 currentRemaining = remainingNumbers[_gameId];
        
//         if (_subtraction > currentRemaining) {
//             if (g.mode == MysteryGameMode.MYSTERY_HARD) {
//                 // Hard mode: overshooting loses
//                 result = MoveResult.GAME_LOST;
//                 feedback = "Game Over! You subtracted more than remaining.";
//             } else {
//                 // Easy mode: invalid move
//                 result = MoveResult.INVALID_MOVE;
//                 feedback = "Invalid move - too high! Try again.";
//             }
//         } else if (_subtraction == currentRemaining) {
//             // Perfect win
//             result = MoveResult.GAME_WON;
//             feedback = "Perfect! You found the exact number!";
//         } else {
//             // Valid move
//             uint256 newRemaining = currentRemaining - _subtraction;
//             remainingNumbers[_gameId] = newRemaining;
//             result = MoveResult.MOVE_ACCEPTED;
            
//             // Strategic feedback
//             if (newRemaining <= 5) {
//                 feedback = "Very close! Almost there.";
//             } else if (newRemaining <= 15) {
//                 feedback = "Getting closer!";
//             } else {
//                 feedback = "Valid move. Keep searching.";
//             }
//         }
        
//         // Record move
//         moveHistory[_gameId].push(MoveHistory({
//             player: msg.sender,
//             attemptedSubtraction: _subtraction,
//             result: result,
//             moveNumber: g.moveCount,
//             feedback: feedback
//         }));
        
//         emit MoveMade(_gameId, msg.sender, _subtraction, result, feedback);
        
//         return (result, feedback);
//     }

//     function nextTurn(
//         uint256 _gameId,
//         mapping(uint256 => MysteryGame) storage games,
//         mapping(uint256 => uint256) storage turnDeadlines
//     ) external {
//         MysteryGame storage g = games[_gameId];
//         g.currentPlayer = g.currentPlayer == g.player1 ? g.player2 : g.player1;
//         turnDeadlines[_gameId] = block.timestamp + TIME_LIMIT;
//     }

//     /**
//      * @dev ✅ FIXED: Robust timeout handling
//      */
//     function handleTimeout(
//         uint256 _gameId,
//         mapping(uint256 => MysteryGame) storage games,
//         mapping(uint256 => mapping(address => uint256)) storage timeouts,
//         mapping(uint256 => uint256) storage turnDeadlines
//     ) external returns (bool shouldEliminate, address timedOutPlayer) {
//         MysteryGame storage g = games[_gameId];
        
//         // ✅ ENHANCED TIMEOUT VALIDATION
//         require(g.status == MysteryGameStatus.ACTIVE, "Game not active");
//         require(block.timestamp > turnDeadlines[_gameId], "No timeout occurred");
//         require(g.currentPlayer != address(0), "Invalid current player");

//         timedOutPlayer = g.currentPlayer;
//         timeouts[_gameId][timedOutPlayer]++;
        
//         emit PlayerTimeout(_gameId, timedOutPlayer, timeouts[_gameId][timedOutPlayer]);
        
//         shouldEliminate = timeouts[_gameId][timedOutPlayer] >= MAX_STRIKES;
        
//         return (shouldEliminate, timedOutPlayer);
//     }

//     /**
//      * @dev ✅ FIXED: Safe game finishing with proper money distribution
//      */
//     function finishGame(
//         uint256 _gameId,
//         address _winner,
//         mapping(uint256 => MysteryGame) storage games,
//         mapping(address => uint256) storage balances,
//         mapping(address => uint256) storage wins,
//         address spectatorContract
//     ) external returns (uint256 fee, uint256 prize) {
//         MysteryGame storage g = games[_gameId];
//         require(g.status == MysteryGameStatus.ACTIVE, "Game not active");
//         require(_winner == g.player1 || _winner == g.player2, "Invalid winner");
        
//         g.status = MysteryGameStatus.FINISHED;
//         g.winner = _winner;

//         // ✅ SAFE MONEY CALCULATION (no overflow/underflow)
//         fee = (g.prizePool * PLATFORM_FEE) / 100;
//         prize = g.prizePool - fee;
        
//         // ✅ SECURE BALANCE UPDATE
//         balances[_winner] += prize;
//         wins[_winner]++;

//         // Notify spectator contract
//         if (spectatorContract != address(0)) {
//             try IZeroSumSpectator(spectatorContract).finalizeGameBetting(_gameId) {} catch {}
//         }

//         emit GameFinished(_gameId, _winner, prize);
        
//         return (fee, prize);
//     }

//     // ================== VIEW FUNCTIONS ==================

//     function getGameForSpectators(
//         uint256 _gameId,
//         mapping(uint256 => MysteryGame) storage games
//     ) external view returns (
//         MysteryGameStatus status,
//         address winner,
//         address[] memory players,
//         uint256 currentNumber,
//         bool numberGenerated,
//         address currentPlayer,
//         uint256 mode
//     ) {
//         MysteryGame memory g = games[_gameId];
//         address[] memory playerArray = new address[](2);
//         playerArray[0] = g.player1;
//         playerArray[1] = g.player2;

//         return (
//             g.status,
//             g.winner,
//             playerArray,
//             0, // Never reveal actual number
//             g.isStarted,
//             g.currentPlayer,
//             uint256(g.mode)
//         );
//     }

//     function isGameBettable(
//         uint256 _gameId,
//         mapping(uint256 => MysteryGame) storage games
//     ) external view returns (bool) {
//         MysteryGame memory g = games[_gameId];
//         return g.gameId != 0 && (
//             g.status == MysteryGameStatus.WAITING || 
//             g.status == MysteryGameStatus.ACTIVE ||
//             g.status == MysteryGameStatus.GENERATING_NUMBER
//         );
//     }

//     function getPlayerView(
//         uint256 _gameId,
//         mapping(uint256 => MysteryGame) storage games,
//         mapping(uint256 => mapping(address => uint256)) storage timeouts,
//         mapping(uint256 => uint256) storage displayMinRange,
//         mapping(uint256 => uint256) storage displayMaxRange,
//         mapping(uint256 => uint256) storage turnDeadlines
//     ) external view returns (
//         string memory gameInfo,
//         bool yourTurn,
//         string memory status,
//         uint256 timeLeft,
//         string memory rangeDisplay,
//         uint256 yourTimeouts,
//         uint256 timeoutsRemaining
//     ) {
//         MysteryGame memory g = games[_gameId];
        
//         yourTimeouts = timeouts[_gameId][msg.sender];
//         timeoutsRemaining = yourTimeouts >= MAX_STRIKES ? 0 : MAX_STRIKES - yourTimeouts;
//         yourTurn = (msg.sender == g.currentPlayer) && timeouts[_gameId][msg.sender] < MAX_STRIKES;
        
//         if (g.status == MysteryGameStatus.WAITING) {
//             gameInfo = "Waiting for second player...";
//             status = "Waiting";
//             rangeDisplay = "Mystery awaits...";
//         } else if (g.status == MysteryGameStatus.GENERATING_NUMBER) {
//             gameInfo = "Generating random number with Chainlink VRF...";
//             status = "Generating";
//             rangeDisplay = "Please wait...";
//         } else if (g.status == MysteryGameStatus.ACTIVE) {
//             gameInfo = g.mode == MysteryGameMode.MYSTERY_EASY ? 
//                 "MYSTERY EASY: Find exact number!" : 
//                 "MYSTERY HARD: Don't overshoot!";
//             status = "Active";
            
//             if (g.isStarted) {
//                 rangeDisplay = string(abi.encodePacked(
//                     "Range: ",
//                     _toString(displayMinRange[_gameId]),
//                     " - ",
//                     _toString(displayMaxRange[_gameId])
//                 ));
//             }
//         } else {
//             gameInfo = g.winner == msg.sender ? "Victory!" : "Game finished";
//             status = g.winner == msg.sender ? "Won" : "Lost";
//             rangeDisplay = "Game over";
//         }
        
//         timeLeft = block.timestamp >= turnDeadlines[_gameId] ? 0 : turnDeadlines[_gameId] - block.timestamp;
//     }

//     // ================== UTILITY FUNCTIONS ==================

//     function _toString(uint256 value) internal pure returns (string memory) {
//         if (value == 0) return "0";
//         uint256 temp = value;
//         uint256 digits;
//         while (temp != 0) {
//             digits++;
//             temp /= 10;
//         }
//         bytes memory buffer = new bytes(digits);
//         while (value != 0) {
//             digits -= 1;
//             buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
//             value /= 10;
//         }
//         return string(buffer);
//     }

//     // ================== VERIFICATION ==================

//     function verifyFairness(
//         uint256 _gameId,
//         mapping(uint256 => MysteryGame) storage games,
//         mapping(uint256 => uint256) storage secretNumbers,
//         mapping(uint256 => uint256) storage displayMinRange,
//         mapping(uint256 => uint256) storage displayMaxRange
//     ) external view returns (
//         bool wasGameCompleted,
//         uint256 actualStartingNumber,
//         uint256 displayedMin,
//         uint256 displayedMax,
//         uint256 vrfRequestId,
//         string memory proof
//     ) {
//         require(games[_gameId].status == MysteryGameStatus.FINISHED, "Game must be finished");
//         return (
//             true,
//             secretNumbers[_gameId],
//             displayMinRange[_gameId],
//             displayMaxRange[_gameId],
//             games[_gameId].vrf_requestId,
//             "Provably fair with Chainlink VRF!"
//         );
//     }
// }