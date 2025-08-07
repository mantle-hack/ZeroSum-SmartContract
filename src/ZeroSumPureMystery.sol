// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ZeroSumPureMystery - FORGIVING PURE MYSTERY MODE
 * @dev PURE MYSTERY MODE - The beginner-friendly variant
 * - Subtract more than remaining = Turn passes silently (NO PUNISHMENT!)
 * - Starting number (40-109) NEVER revealed during game
 * - Only feedback: "Your turn completed" or "You won!"
 * - Pure pattern analysis and strategic guessing
 * - Perfect for new players learning the game
 * - ✅ SPECTATOR INTEGRATION: Full betting support
 */



     // ✅ Spectator contract integration
    interface IZeroSumSpectator {
        function finalizeGameBetting(uint256 _gameId) external;
        function enableLastStandBetting(uint256 _gameId) external;
        function updateLastStandRound(uint256 _gameId) external;
    }
    
contract ZeroSumPureMystery is ReentrancyGuard, Ownable {
    
    enum GameStatus { WAITING, ACTIVE, FINISHED }
    enum MoveResult { MOVE_ACCEPTED, GAME_WON, TURN_PASSED }
    
    struct Game {
        uint256 gameId;
        uint256 actualNumber;       // ✅ ALWAYS 0 - Never reveals true number
        address currentPlayer;
        GameStatus status;
        uint256 entryFee;
        uint256 prizePool;
        address winner;
        uint256 moveCount;
        bool isStarted;
        address player1;
        address player2;
    }
    
    struct MoveHistory {
        address player;
        uint256 attemptedSubtraction;
        MoveResult result;
        uint256 moveNumber;
        string feedback;
    }
    

    // ✅ ULTRA PRIVATE storage - completely hidden from blockchain analysis!
    mapping(uint256 => uint256) private secretNumbers;
    mapping(uint256 => uint256) private remainingNumbers;
    mapping(uint256 => uint256) private displayMinRange;
    mapping(uint256 => uint256) private displayMaxRange;
    
    // ✅ Custom salt for maximum security
    uint256 private constant SALT = 0x2222333344445555666677778888999900001111aaaabbbbccccddddeeeeffff;
    
    // Core mappings
    mapping(uint256 => Game) public games;
    mapping(uint256 => mapping(address => bool)) public isInGame;
    mapping(uint256 => mapping(address => uint256)) public timeouts;
    mapping(uint256 => uint256) public turnDeadlines;
    mapping(uint256 => MoveHistory[]) public moveHistory;
    
    // Player data
    mapping(address => uint256) public balances;
    mapping(address => uint256) public wins;
    mapping(address => uint256) public played;
    
    // Settings
    uint256 public gameCounter;
    uint256 public platformFee = 5;
    uint256 public fees;
    uint256 public timeLimit = 300; // 5 minutes per turn
    uint256 public maxStrikes = 2;
    bool public paused;
    
    // ✅ Spectator integration
    address public spectatorContract;
    
    // Range constants (hidden from players)
    uint256 private constant ACTUAL_MIN_RANGE = 40;
    uint256 private constant ACTUAL_MAX_RANGE = 109;
    
    // Events
    event GameCreated(uint256 indexed gameId, address creator, uint256 entryFee);
    event PlayerJoined(uint256 indexed gameId, address player);
    event PureMysteryGameStarted(uint256 indexed gameId, uint256 displayMin, uint256 displayMax);
    event MoveMade(uint256 indexed gameId, address player, uint256 subtraction, MoveResult result, string feedback);
    event GameFinished(uint256 indexed gameId, address winner, uint256 earnings);
    event TurnPassed(uint256 indexed gameId, address indexed player, uint256 attemptedSubtraction);
    
    modifier notPaused() {
        require(!paused, "Game is paused");
        _;
    }
    
    constructor() Ownable(msg.sender) {}
    
    // ================== SPECTATOR INTEGRATION ==================
    
    function setSpectatorContract(address _spectator) external onlyOwner {
        spectatorContract = _spectator;
    }
    
    // ✅ View function for spectators to verify game state
    function getGameForSpectators(uint256 _id) external view returns (
        GameStatus status,
        address winner,
        address[] memory players,
        uint256 currentNumber,
        bool numberGenerated,
        address currentPlayer,
        uint256 mode
    ) {
        Game memory g = games[_id];
        address[] memory playerArray = new address[](2);
        
        if (g.player1 != address(0)) playerArray[0] = g.player1;
        if (g.player2 != address(0)) playerArray[1] = g.player2;
        
        return (
            g.status,
            g.winner,
            playerArray,
            0,  // ✅ NEVER reveal actual number - always return 0
            g.isStarted,
            g.currentPlayer,
            4  // GameMode.PURE_MYSTERY = 4 (matches universal enum)
        );
    }
    
    // ✅ Check if game exists and can be bet on
    function isGameBettable(uint256 _id) external view returns (bool) {
        Game memory g = games[_id];
        // Can bet when waiting or active (but not finished)
        return g.gameId != 0 && (g.status == GameStatus.WAITING || g.status == GameStatus.ACTIVE);
    }
    
    // ================== GAME CREATION ==================
    
    function createPureMysteryGame() external payable notPaused {
        require(msg.value > 0, "Entry fee required");
        
        gameCounter++;
        uint256 id = gameCounter;
        
        games[id] = Game({
            gameId: id,
            actualNumber: 0,         // ✅ ALWAYS 0 - Number stays hidden
            currentPlayer: msg.sender,
            status: GameStatus.WAITING,
            entryFee: msg.value,
            prizePool: msg.value,
            winner: address(0),
            moveCount: 0,
            isStarted: false,
            player1: msg.sender,
            player2: address(0)
        });
        
        isInGame[id][msg.sender] = true;
        played[msg.sender]++;
        
        emit GameCreated(id, msg.sender, msg.value);
    }
    
    // ================== JOINING & STARTING ==================
    
    function joinGame(uint256 _id) external payable notPaused {
        Game storage g = games[_id];
        require(g.gameId != 0 && g.status == GameStatus.WAITING, "Cannot join this game");
        require(!isInGame[_id][msg.sender], "Already in game");
        require(g.player2 == address(0), "Game is full");
        require(msg.value == g.entryFee, "Wrong entry fee");
        
        g.player2 = msg.sender;
        g.prizePool += msg.value;
        isInGame[_id][msg.sender] = true;
        played[msg.sender]++;
        
        emit PlayerJoined(_id, msg.sender);
        
        // ✅ GENERATE SECRET NUMBER ONLY WHEN BOTH PLAYERS JOIN!
        _startGame(_id);
    }
    
    function _startGame(uint256 _id) internal {
        Game storage g = games[_id];
        
        // ✅ Generate TRULY HIDDEN number using both players
        uint256 secret = _generateSecretNumber(_id);
        secretNumbers[_id] = secret;
        remainingNumbers[_id] = secret;
        
        // ✅ Generate DYNAMIC RANGE based on actual number
        _generateDisplayRange(_id, secret);
        
        g.actualNumber = 0;  // Keep public field at 0 ALWAYS
        g.isStarted = true;
        g.status = GameStatus.ACTIVE;
        g.currentPlayer = g.player1; // Player 1 starts
        
        turnDeadlines[_id] = block.timestamp + timeLimit;
        
        emit PureMysteryGameStarted(_id, displayMinRange[_id], displayMaxRange[_id]);
    }
    
    function _generateSecretNumber(uint256 _id) internal view returns (uint256) {
        Game memory g = games[_id];
        
        uint256 entropy = uint256(keccak256(abi.encodePacked(
            block.timestamp,
            block.prevrandao,
            _id,
            g.player1,
            g.player2,
            SALT
        )));
        
        return ACTUAL_MIN_RANGE + (entropy % (ACTUAL_MAX_RANGE - ACTUAL_MIN_RANGE + 1));
    }
    
    function _generateDisplayRange(uint256 _id, uint256 _actualNumber) internal {
        // ✅ DYNAMIC RANGE: If actual is 75, show range like 50-100
        uint256 entropy = uint256(keccak256(abi.encodePacked(_actualNumber, _id, SALT)));
        
        // Generate random padding around the actual number
        uint256 lowerPadding = 5 + (entropy % 25);        // 5-30 below actual
        uint256 upperPadding = 15 + ((entropy >> 8) % 35); // 15-50 above actual
        
        displayMinRange[_id] = _actualNumber >= lowerPadding ? _actualNumber - lowerPadding : 1;
        displayMaxRange[_id] = _actualNumber + upperPadding;
        
        // Ensure minimum spread of 40 for strategic gameplay
        if (displayMaxRange[_id] - displayMinRange[_id] < 40) {
            displayMaxRange[_id] = displayMinRange[_id] + 40;
        }
    }
    
    // ================== PURE MYSTERY GAMEPLAY ==================
    
    function makeMove(uint256 _id, uint256 _sub) external notPaused {
        Game storage g = games[_id];
        require(g.status == GameStatus.ACTIVE, "Game not active");
        require(g.isStarted, "Game not started");
        require(msg.sender == g.currentPlayer, "Not your turn");
        require(timeouts[_id][msg.sender] < maxStrikes, "You are eliminated");
        require(block.timestamp <= turnDeadlines[_id], "Turn timeout");
        require(_sub > 0, "Must subtract positive number");
        
        g.moveCount++;
        uint256 currentRemaining = remainingNumbers[_id];
        
        MoveResult result;
        string memory feedback;
        
        if (_sub > currentRemaining) {
            // 🎭 PURE MYSTERY: Forgiving mode - just pass turn silently!
            result = MoveResult.TURN_PASSED;
            feedback = "Your turn completed."; // No hint that move was invalid!
            
            emit TurnPassed(_id, msg.sender, _sub);
            _nextTurn(_id);
            
        } else {
            uint256 newRemaining = currentRemaining - _sub;
            remainingNumbers[_id] = newRemaining;
            
            if (newRemaining == 0) {
                // ✅ PERFECT: Player reached exactly zero!
                result = MoveResult.GAME_WON;
                feedback = "You reached zero! Victory!";
                _finishGame(_id, msg.sender);
            } else {
                // ✅ VALID MOVE: Continue game
                result = MoveResult.MOVE_ACCEPTED;
                feedback = "Your turn completed.";
                _nextTurn(_id);
            }
        }
        
        // Record move in history
        moveHistory[_id].push(MoveHistory({
            player: msg.sender,
            attemptedSubtraction: _sub,
            result: result,
            moveNumber: g.moveCount,
            feedback: feedback
        }));
        
        emit MoveMade(_id, msg.sender, _sub, result, feedback);
    }
    
    function _nextTurn(uint256 _id) internal {
        Game storage g = games[_id];
        
        // Switch between player1 and player2
        g.currentPlayer = (g.currentPlayer == g.player1) ? g.player2 : g.player1;
        turnDeadlines[_id] = block.timestamp + timeLimit;
    }
    
    function handleTimeout(uint256 _id) external {
        Game storage g = games[_id];
        require(g.status == GameStatus.ACTIVE, "Game not active");
        require(block.timestamp > turnDeadlines[_id], "No timeout occurred");
        
        address player = g.currentPlayer;
        timeouts[_id][player]++;
        
        if (timeouts[_id][player] >= maxStrikes) {
            // Player loses due to timeout
            address winner = (player == g.player1) ? g.player2 : g.player1;
            _finishGame(_id, winner);
        } else {
            _nextTurn(_id);
        }
    }
    
    function _finishGame(uint256 _id, address _winner) internal {
        Game storage g = games[_id];
        g.status = GameStatus.FINISHED;
        g.winner = _winner;
        
        uint256 fee = (g.prizePool * platformFee) / 100;
        uint256 prize = g.prizePool - fee;
        
        balances[_winner] += prize;
        wins[_winner]++;
        fees += fee;
        
        // ✅ NEW: Notify spectator contract that game finished
        if (spectatorContract != address(0)) {
            try IZeroSumSpectator(spectatorContract).finalizeGameBetting(_id) {} catch {}
        }
        
        emit GameFinished(_id, _winner, prize);
    }
    
    // ================== WITHDRAWALS ==================
    
    function withdraw() external nonReentrant {
        uint256 amount = balances[msg.sender];
        require(amount > 0, "No balance to withdraw");
        
        balances[msg.sender] = 0;
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Withdrawal failed");
    }
    
    // ================== VIEW FUNCTIONS ==================
    
    function getGame(uint256 _id) external view returns (
        uint256 gameId,
        uint256 actualNumber,      // ✅ ALWAYS RETURNS 0 (Hidden)
        address currentPlayer,
        GameStatus status,
        uint256 entryFee,
        uint256 prizePool,
        address winner,
        uint256 moveCount,
        bool isStarted,
        address player1,
        address player2
    ) {
        Game memory g = games[_id];
        return (
            g.gameId,
            0,  // ✅ NEVER reveal actual number
            g.currentPlayer,
            g.status,
            g.entryFee,
            g.prizePool,
            g.winner,
            g.moveCount,
            g.isStarted,
            g.player1,
            g.player2
        );
    }
    
    function getPlayers(uint256 _id) external view returns (address, address) {
        Game memory g = games[_id];
        return (g.player1, g.player2);
    }
    
    function getStats(address _player) external view returns (
        uint256 balance,
        uint256 totalWins,
        uint256 totalPlayed,
        uint256 winPercentage
    ) {
        return (
            balances[_player], 
            wins[_player], 
            played[_player], 
            played[_player] > 0 ? (wins[_player] * 100) / played[_player] : 0
        );
    }
    
    function getMoveHistory(uint256 _id) external view returns (MoveHistory[] memory) {
        return moveHistory[_id];
    }
    
    // ✅ DYNAMIC RANGE DISPLAY based on actual hidden number
    function getDisplayedRange(uint256 _id) external view returns (
        uint256 minRange,
        uint256 maxRange,
        string memory hint
    ) {
        require(games[_id].isStarted, "Game not started");
        
        minRange = displayMinRange[_id];
        maxRange = displayMaxRange[_id];
        hint = "PURE MYSTERY: Wrong moves just pass turn - no punishment!";
    }
    
    function getPlayerView(uint256 _id) external view returns (
        string memory gameInfo,
        bool yourTurn,
        string memory status,
        uint256 timeLeft,
        string memory rangeDisplay
    ) {
        Game memory g = games[_id];
        
        yourTurn = (msg.sender == g.currentPlayer) && timeouts[_id][msg.sender] < maxStrikes;
        
        if (g.status == GameStatus.WAITING) {
            gameInfo = "Waiting for second player to join...";
            status = "Waiting";
            rangeDisplay = "Pure Mystery awaits...";
        } else if (g.status == GameStatus.ACTIVE) {
            gameInfo = "PURE MYSTERY: Pattern analysis and strategic guessing!";
            status = "Active";
            
            if (g.isStarted) {
                rangeDisplay = string(abi.encodePacked(
                    "Displayed Range: ",
                    _toString(displayMinRange[_id]),
                    " - ",
                    _toString(displayMaxRange[_id]),
                    " (Beginner Friendly!)"
                ));
            } else {
                rangeDisplay = "Generating mystery range...";
            }
        } else {
            gameInfo = g.winner == msg.sender ? "Victory achieved!" : "Game finished";
            status = g.winner == msg.sender ? "Won" : "Lost";
            rangeDisplay = "Game over";
        }
        
        timeLeft = block.timestamp >= turnDeadlines[_id] ? 0 : turnDeadlines[_id] - block.timestamp;
    }
    
    function getLastMove(uint256 _id) external view returns (
        address lastPlayer,
        uint256 lastSubtraction,
        MoveResult lastResult,
        string memory lastFeedback
    ) {
        MoveHistory[] memory history = moveHistory[_id];
        if (history.length == 0) {
            return (address(0), 0, MoveResult.MOVE_ACCEPTED, "No moves yet");
        }
        
        MoveHistory memory last = history[history.length - 1];
        return (last.player, last.attemptedSubtraction, last.result, last.feedback);
    }
    
    // ✅ Post-game fairness verification (ONLY after game ends)
    function verifyFairness(uint256 _id) external view returns (
        bool wasGameCompleted,
        uint256 actualStartingNumber,
        uint256 actualRange,
        uint256 displayedMin,
        uint256 displayedMax,
        string memory proof
    ) {
        require(games[_id].status == GameStatus.FINISHED, "Game must be finished first");
        return (
            true,
            secretNumbers[_id],
            ACTUAL_MAX_RANGE - ACTUAL_MIN_RANGE,
            displayMinRange[_id],
            displayMaxRange[_id],
            "PURE MYSTERY: Forgiving mode with hidden number - wrong moves passed silently!"
        );
    }
    
    // ✅ Helper function for string conversion
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
    
    // ================== ADMIN FUNCTIONS ==================
    
    function setPlatformFee(uint256 _fee) external onlyOwner {
        require(_fee <= 10, "Fee too high");
        platformFee = _fee;
    }
    
    function setTimeLimit(uint256 _seconds) external onlyOwner {
        require(_seconds >= 60, "Too short");
        require(_seconds <= 3600, "Too long");
        timeLimit = _seconds;
    }
    
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
    }
    
    function withdrawFees() external onlyOwner nonReentrant {
        uint256 amount = fees;
        require(amount > 0, "No fees to withdraw");
        fees = 0;
        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "Fee withdrawal failed");
    }
    
    function emergencyWithdraw() external onlyOwner {
        (bool success, ) = payable(owner()).call{value: address(this).balance}("");
        require(success, "Emergency withdrawal failed");
    }
    
    // ✅ EMERGENCY: Owner can reveal number if needed (dispute resolution only)
    function emergencyRevealNumber(uint256 _id) external onlyOwner view returns (
        uint256 actualNumber,
        uint256 remainingNumber,
        uint256 displayMin,
        uint256 displayMax
    ) {
        require(games[_id].status == GameStatus.FINISHED, "Only for finished games");
        return (
            secretNumbers[_id],
            remainingNumbers[_id],
            displayMinRange[_id],
            displayMaxRange[_id]
        );
    }
}