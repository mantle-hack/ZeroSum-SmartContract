// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.19;

// import {GameStatus, Game, IZeroSumSpectator, MoveResult, MoveHistory} from "../ZeroSumPureMystery.sol";

// library MysteryLibrary {
//     uint256 private constant ACTUAL_MIN_RANGE = 40;
//     uint256 private constant ACTUAL_MAX_RANGE = 109;
//     uint256 private constant timeLimit = 180;
//     uint256 private constant platformFee = 5;
//     uint256 private constant maxStrikes = 2;
//     uint256 private constant SALT = 0x2222333344445555666677778888999900001111aaaabbbbccccddddeeeeffff;

//     function _getGameForSpectators(uint256 _id, mapping(uint256 => Game) storage games)
//         internal
//         view
//         returns (
//             GameStatus status,
//             address winner,
//             address[] memory players,
//             uint256 currentNumber,
//             bool numberGenerated,
//             address currentPlayer,
//             uint256 mode
//         )
//     {
//         Game memory g = games[_id];
//         address[] memory playerArray = new address[](2);

//         if (g.player1 != address(0)) playerArray[0] = g.player1;
//         if (g.player2 != address(0)) playerArray[1] = g.player2;

//         return (
//             g.status,
//             g.winner,
//             playerArray,
//             0, // ✅ NEVER reveal actual number - always return 0
//             g.isStarted,
//             g.currentPlayer,
//             4 // GameMode.PURE_MYSTERY = 4 (matches universal enum)
//         );
//     }

//     function _createPureMysteryGame(
//         mapping(uint256 => mapping(address => bool)) storage isInGame,
//         uint256 gameCounter,
//         mapping(uint256 => Game) storage games,
//         mapping(address => uint256) storage played
//     ) internal {
//         require(msg.value > 0, "Entry fee required");

//         uint256 id = gameCounter;

//         games[id] = Game({
//             gameId: id,
//             actualNumber: 0, // ✅ ALWAYS 0 - Number stays hidden
//             currentPlayer: msg.sender,
//             status: GameStatus.WAITING,
//             entryFee: msg.value,
//             prizePool: msg.value,
//             winner: address(0),
//             moveCount: 0,
//             isStarted: false,
//             player1: msg.sender,
//             player2: address(0)
//         });

//         isInGame[id][msg.sender] = true;
//         played[msg.sender]++;
//     }

//     function _startGame(
//         uint256 _id,
//         mapping(uint256 => Game) storage games,
//         mapping(uint256 => uint256) storage secretNumbers,
//         mapping(uint256 => uint256) storage remainingNumbers,
//         mapping(uint256 => uint256) storage turnDeadlines,
//         mapping(uint256 => uint256) storage displayMinRange,
//         mapping(uint256 => uint256) storage displayMaxRange
//     ) internal {
//         Game storage g = games[_id];

//         // ✅ Generate TRULY HIDDEN number using both players
//         uint256 secret = _generateSecretNumber(_id, games);
//         secretNumbers[_id] = secret;
//         remainingNumbers[_id] = secret;

//         // ✅ Generate DYNAMIC RANGE based on actual number
//         _generateDisplayRange(_id, secret, displayMinRange, displayMaxRange);

//         g.actualNumber = 0; // Keep public field at 0 ALWAYS
//         g.isStarted = true;
//         g.status = GameStatus.ACTIVE;
//         g.currentPlayer = g.player1; // Player 1 starts

//         turnDeadlines[_id] = block.timestamp + timeLimit;

//         // emit PureMysteryGameStarted(_id, displayMinRange[_id], displayMaxRange[_id]);
//     }

//     function _generateDisplayRange(
//         uint256 _id,
//         uint256 _actualNumber,
//         mapping(uint256 => uint256) storage displayMinRange,
//         mapping(uint256 => uint256) storage displayMaxRange
//     ) internal {
//         // ✅ DYNAMIC RANGE: If actual is 75, show range like 50-100
//         uint256 entropy = uint256(keccak256(abi.encodePacked(_actualNumber, _id, SALT)));

//         // Generate random padding around the actual number
//         uint256 lowerPadding = 5 + (entropy % 25); // 5-30 below actual
//         uint256 upperPadding = 15 + ((entropy >> 8) % 35); // 15-50 above actual

//         displayMinRange[_id] = _actualNumber >= lowerPadding ? _actualNumber - lowerPadding : 1;
//         displayMaxRange[_id] = _actualNumber + upperPadding;

//         // Ensure minimum spread of 40 for strategic gameplay
//         if (displayMaxRange[_id] - displayMinRange[_id] < 40) {
//             displayMaxRange[_id] = displayMinRange[_id] + 40;
//         }
//     }

//     function _generateSecretNumber(uint256 _id, mapping(uint256 => Game) storage games)
//         internal
//         view
//         returns (uint256)
//     {
//         Game memory g = games[_id];

//         uint256 entropy =
//             uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, _id, g.player1, g.player2, SALT)));

//         return ACTUAL_MIN_RANGE + (entropy % (ACTUAL_MAX_RANGE - ACTUAL_MIN_RANGE + 1));
//     }

//     function _verifyFairness(
//         uint256 _id,
//         // mapping(uint256 => Game) memory games,
//         mapping(uint256 => uint256) storage secretNumbers,
//         mapping(uint256 => uint256) storage displayMinRange,
//         mapping(uint256 => uint256) storage displayMaxRange
//     )
//         internal
//         view
//         returns (
//             bool wasGameCompleted,
//             uint256 actualStartingNumber,
//             uint256 actualRange,
//             uint256 displayedMin,
//             uint256 displayedMax,
//             string memory proof
//         )
//     {
//         // require(games[_id].status == GameStatus.FINISHED, "Game must be finished first");
//         return (
//             true,
//             secretNumbers[_id],
//             ACTUAL_MAX_RANGE - ACTUAL_MIN_RANGE,
//             displayMinRange[_id],
//             displayMaxRange[_id],
//             "PURE MYSTERY: Forgiving mode with hidden number - wrong moves passed silently!"
//         );
//     }

//     function _toString(uint256 value) internal pure returns (string memory) {
//         if (value == 0) {
//             return "0";
//         }
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

//     function _finishGame(
//         uint256 _id,
//         address _winner,
//         mapping(uint256 => Game) storage games,
//         mapping(address => uint256) storage balances,
//         mapping(address => uint256) storage wins,
//         address spectatorContract
//     ) internal returns (uint256, uint256) {
//         Game storage g = games[_id];
//         g.status = GameStatus.FINISHED;
//         g.winner = _winner;

//         uint256 fee = (g.prizePool * platformFee) / 100;
//         uint256 prize = g.prizePool - fee;

//         balances[_winner] += prize;
//         wins[_winner]++;
//         // fees += fee;

//         // ✅ NEW: Notify spectator contract that game finished
//         if (spectatorContract != address(0)) {
//             try IZeroSumSpectator(spectatorContract).finalizeGameBetting(_id) {} catch {}
//         }

//         // emit GameFinished(_id, _winner, prize);

//         return (fee, prize);
//     }

//     function _nextTurn(
//         uint256 _id,
//         mapping(uint256 => Game) storage games,
//         mapping(uint256 => uint256) storage turnDeadlines
//     ) internal {
//         Game storage g = games[_id];
//         // Switch between player1 and player2
//         g.currentPlayer = (g.currentPlayer == g.player1) ? g.player2 : g.player1;
//         turnDeadlines[_id] = block.timestamp + 300;
//     }

//     function _getPlayerView(
//         uint256 _id,
//         mapping(uint256 => Game) storage games,
//         mapping(uint256 => mapping(address => uint256)) storage timeouts,
//         mapping(uint256 => uint256) storage displayMinRange,
//         mapping(uint256 => uint256) storage displayMaxRange,
//         mapping(uint256 => uint256) storage turnDeadlines
//     )
//         internal
//         view
//         returns (
//             string memory gameInfo,
//             bool yourTurn,
//             string memory status,
//             uint256 timeLeft,
//             string memory rangeDisplay
//         )
//     {
//         Game memory g = games[_id];

//         yourTurn = (msg.sender == g.currentPlayer) && timeouts[_id][msg.sender] < maxStrikes;

//         if (g.status == GameStatus.WAITING) {
//             gameInfo = "Waiting for second player to join...";
//             status = "Waiting";
//             rangeDisplay = "Pure Mystery awaits...";
//         } else if (g.status == GameStatus.ACTIVE) {
//             gameInfo = "PURE MYSTERY: Pattern analysis and strategic guessing!";
//             status = "Active";

//             if (g.isStarted) {
//                 rangeDisplay = string(
//                     abi.encodePacked(
//                         "Displayed Range: ",
//                         MysteryLibrary._toString(displayMinRange[_id]),
//                         " - ",
//                         MysteryLibrary._toString(displayMaxRange[_id]),
//                         " (Beginner Friendly!)"
//                     )
//                 );
//             } else {
//                 rangeDisplay = "Generating mystery range...";
//             }
//         } else {
//             gameInfo = g.winner == msg.sender ? "Victory achieved!" : "Game finished";
//             status = g.winner == msg.sender ? "Won" : "Lost";
//             rangeDisplay = "Game over";
//         }

//         timeLeft = block.timestamp >= turnDeadlines[_id] ? 0 : turnDeadlines[_id] - block.timestamp;
//     }

//     function _recordMoveHistory(
//         uint256 _id,
//         uint256 _sub,
//         MoveResult moveResult,
//         uint256 moveCount,
//         string memory feedback,
//         mapping(uint256 => MoveHistory[]) storage moveHistory
//     ) internal {
//         moveHistory[_id].push(
//             MoveHistory({
//                 player: msg.sender,
//                 attemptedSubtraction: _sub,
//                 result: moveResult,
//                 moveNumber: moveCount,
//                 feedback: feedback
//             })
//         );
//     }
// }
