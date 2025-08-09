// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ZeroSumHardcoreMystery - INSTANT LOSS VERSION WITH AUTO-TIMEOUT
 * @dev HARDCORE MYSTERY MODE - Subtract too much = YOU LOSE IMMEDIATELY!
 * - Subtract more than remaining = Instant loss
 * - Higher skill requirement and faster games
 * - Dynamic range display based on actual hidden number
 * - Maximum psychological pressure
 * - ✅ AUTO-TIMEOUT SYSTEM: 2 timeouts = elimination
 * - ✅ SPECTATOR INTEGRATION: Full betting support
 */


  // ✅ Spectator contract integration
    interface IZeroSumSpectator {
        function finalizeGameBetting(uint256 _gameId) external;
        function enableLastStandBetting(uint256 _gameId) external;
        function updateLastStandRound(uint256 _gameId) external;
    }
contract ZeroSumHardcoreMystery is ReentrancyGuard, Ownable {
    
    enum GameMode { HARDCORE_MYSTERY, LAST_STAND }
    enum GameStatus { WAITING, ACTIVE, FINISHED }
    enum MoveResult { MOVE_ACCEPTED, GAME_WON, GAME_LOST }
    
    struct Game {
        uint256 gameId;
        GameMode mode;
        uint256 actualNumber;       // ✅ ALWAYS 0 - Never reveals true number
        address currentPlayer;
        GameStatus status;
        uint256 entryFee;
        uint256 prizePool;
        address winner;
        uint256 maxPlayers;
        uint256 moveCount;
        bool isStarted;
    }
    
    struct MoveHistory {
        address player;
        uint256 attemptedSubtraction;
        MoveResult result;
        uint256 moveNumber;
        string feedback;
    }
    
   
    
    // ✅ ULTRA PRIVATE storage - completely hidden from Etherscan!
    mapping(uint256 => uint256) private secretNumbers;
    mapping(uint256 => uint256) private remainingNumbers;
    mapping(uint256 => uint256) private displayMinRange;
    mapping(uint256 => uint256) private displayMaxRange;
    
    // ✅ Custom salt for maximum security
    uint256 private constant SALT = 0x2222333344445555666677778888999900001111aaaabbbbccccddddeeeeffff;
    
    // Core mappings
    mapping(uint256 => Game) public games;
    mapping(uint256 => address[]) public gamePlayers;
    mapping(uint256 => address[]) public activePlayers;
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
    uint256 public timeLimit = 300;
    uint256 public maxStrikes = 2;  // ✅ 2 timeouts = elimination
    bool public paused;
    
    // ✅ Spectator integration
    address public spectatorContract;
    
    // Actual range constants (hidden)
    uint256 private constant ACTUAL_MIN_RANGE = 40;
    uint256 private constant ACTUAL_MAX_RANGE = 109;
    uint256 private constant LAST_STAND_MIN = 200;
    uint256 private constant LAST_STAND_MAX = 499;
    
    // Events
    event GameCreated(uint256 indexed gameId, GameMode mode, address creator, uint256 entryFee);
    event PlayerJoined(uint256 indexed gameId, address player);
    event HardcoreMysteryGameStarted(uint256 indexed gameId, uint256 displayMin, uint256 displayMax);
    event MoveMade(uint256 indexed gameId, address player, uint256 subtraction, MoveResult result, string feedback);
    event GameFinished(uint256 indexed gameId, address winner, uint256 earnings);
    event PlayerEliminated(uint256 indexed gameId, address indexed player, uint256 position);
    event InstantLoss(uint256 indexed gameId, address indexed player, uint256 attemptedSubtraction, uint256 actualRemaining);
    event PlayerTimeout(uint256 indexed gameId, address indexed player, uint256 timeoutCount);
    event TurnSkipped(uint256 indexed gameId, address indexed player, uint256 timeoutCount);
    
    modifier notPaused() {
        require(!paused, "Paused");
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
        return (
            g.status,
            g.winner,
            g.mode == GameMode.LAST_STAND ? activePlayers[_id] : gamePlayers[_id],
            0,  // ✅ NEVER reveal actual number - always return 0
            g.isStarted,
            g.currentPlayer,
            uint256(g.mode)
        );
    }
    
    // ✅ Check if game exists and can be bet on
    function isGameBettable(uint256 _id) external view returns (bool) {
        Game memory g = games[_id];
        // Can bet when waiting or active (but not finished)
        return g.gameId != 0 && (g.status == GameStatus.WAITING || g.status == GameStatus.ACTIVE);
    }
    
    // ================== GAME CREATION ==================
    
    function createHardcoreMysteryGame() external payable notPaused {
        require(msg.value > 0, "Fee required");
        _createGame(GameMode.HARDCORE_MYSTERY, 2);
    }
    
    function createLastStandGame() external payable notPaused {
        require(msg.value > 0, "Fee required");
        _createGame(GameMode.LAST_STAND, 8);
    }
    
    function _createGame(GameMode _mode, uint256 _maxPlayers) internal {
        gameCounter++;
        uint256 id = gameCounter;
        
        games[id] = Game({
            gameId: id,
            mode: _mode,
            actualNumber: 0,         // ✅ ALWAYS 0 - Number stays hidden
            currentPlayer: address(0),
            status: GameStatus.WAITING,
            entryFee: msg.value,
            prizePool: msg.value,
            winner: address(0),
            maxPlayers: _maxPlayers,
            moveCount: 0,
            isStarted: false
        });
        
        // ✅ Reset timeout counter for creator
        timeouts[id][msg.sender] = 0;
        
        _joinGame(id, msg.sender);
        emit GameCreated(id, _mode, msg.sender, msg.value);
    }
    
    // ================== JOINING & STARTING ==================
    
    function joinGame(uint256 _id) external payable notPaused {
        _joinGame(_id, msg.sender);
    }
    
    function _joinGame(uint256 _id, address _player) internal {
        Game storage g = games[_id];
        require(g.gameId != 0 && g.status == GameStatus.WAITING, "Cannot join");
        require(!isInGame[_id][_player], "Already in");
        require(gamePlayers[_id].length < g.maxPlayers, "Full");
        require(msg.value == g.entryFee, "Wrong fee");
        
        gamePlayers[_id].push(_player);
        g.prizePool += msg.value;
        isInGame[_id][_player] = true;
        played[_player]++;
        
        // ✅ Reset timeout counter for joining player
        timeouts[_id][_player] = 0;
        
        emit PlayerJoined(_id, _player);
        
        // ✅ GENERATE SECRET NUMBER ONLY WHEN ALL PLAYERS JOIN!
        if (gamePlayers[_id].length == g.maxPlayers) {
            _startGame(_id);
        }
    }
    
    function _startGame(uint256 _id) internal {
        Game storage g = games[_id];
        
        // ✅ Generate TRULY HIDDEN number using ALL players
        uint256 secret = _generateSecretNumber(_id, g.mode);
        secretNumbers[_id] = secret;
        remainingNumbers[_id] = secret;
        
        // ✅ Generate DYNAMIC RANGE based on actual number
        _generateDisplayRange(_id, secret, g.mode);
        
        g.actualNumber = 0;  // Keep public field at 0 ALWAYS
        g.isStarted = true;
        g.status = GameStatus.ACTIVE;
        g.currentPlayer = gamePlayers[_id][0];
        
        if (g.mode == GameMode.LAST_STAND) {
            address[] storage players = gamePlayers[_id];
            for (uint i = 0; i < players.length; i++) {
                activePlayers[_id].push(players[i]);
            }
            
            // ✅ Enable Last Stand betting
            if (spectatorContract != address(0)) {
                try IZeroSumSpectator(spectatorContract).enableLastStandBetting(_id) {} catch {}
            }
        }
        
        turnDeadlines[_id] = block.timestamp + timeLimit;
        
        emit HardcoreMysteryGameStarted(_id, displayMinRange[_id], displayMaxRange[_id]);
    }
    
    function _generateSecretNumber(uint256 _id, GameMode _mode) internal view returns (uint256) {
        address[] memory players = gamePlayers[_id];
        
        uint256 entropy = uint256(keccak256(abi.encodePacked(
            block.timestamp,
            block.prevrandao,
            _id,
            players[0],
            players.length > 1 ? players[1] : address(0),
            players.length > 2 ? players[2] : address(0),
            players.length > 3 ? players[3] : address(0),
            players.length > 4 ? players[4] : address(0),
            players.length > 5 ? players[5] : address(0),
            players.length > 6 ? players[6] : address(0),
            players.length > 7 ? players[7] : address(0),
            SALT
        )));
        
        if (_mode == GameMode.HARDCORE_MYSTERY) {
            return ACTUAL_MIN_RANGE + (entropy % (ACTUAL_MAX_RANGE - ACTUAL_MIN_RANGE + 1));
        } else {
            return LAST_STAND_MIN + (entropy % (LAST_STAND_MAX - LAST_STAND_MIN + 1));
        }
    }
    
    function _generateDisplayRange(uint256 _id, uint256 _actualNumber, GameMode _mode) internal {
        if (_mode == GameMode.HARDCORE_MYSTERY) {
            // ✅ DYNAMIC RANGE: If actual is 50, show range like 25-80
            uint256 entropy = uint256(keccak256(abi.encodePacked(_actualNumber, _id, SALT)));
            
            // Generate random padding
            uint256 lowerPadding = 1 + (entropy % 20);        // 1-20 below actual
            uint256 upperPadding = 10 + ((entropy >> 8) % 30); // 10-40 above actual
            
            displayMinRange[_id] = _actualNumber >= lowerPadding ? _actualNumber - lowerPadding : 1;
            displayMaxRange[_id] = _actualNumber + upperPadding;
            
            // Ensure minimum spread of 30
            if (displayMaxRange[_id] - displayMinRange[_id] < 30) {
                displayMaxRange[_id] = displayMinRange[_id] + 30;
            }
        } else {
            // Last Stand: Wide range
            displayMinRange[_id] = 1;
            displayMaxRange[_id] = 999;
        }
    }
    
    // ================== HARDCORE MYSTERY GAMEPLAY ==================
    
    // ✅ UPDATED makeMove with AUTO-TIMEOUT handling
    function makeMove(uint256 _id, uint256 _sub) external notPaused {
        Game storage g = games[_id];
        require(g.status == GameStatus.ACTIVE, "Not active");
        require(g.isStarted, "Not started");
        
        // ✅ AUTO-HANDLE timeout if it occurred
        if (block.timestamp > turnDeadlines[_id]) {
            address slowPlayer = g.currentPlayer;
            
            // Only auto-handle if caller is not the slow player
            if (msg.sender != slowPlayer) {
                timeouts[_id][slowPlayer]++;
                emit PlayerTimeout(_id, slowPlayer, timeouts[_id][slowPlayer]);
                
                if (timeouts[_id][slowPlayer] >= maxStrikes) {
                    if (g.mode == GameMode.LAST_STAND) {
                        _eliminate(_id, slowPlayer);
                        return;
                    } else {
                        _finishWithLoser(_id, slowPlayer);
                        return;
                    }
                }
                
                _nextTurn(_id);
                emit TurnSkipped(_id, slowPlayer, timeouts[_id][slowPlayer]);
            }
        }
        
        require(msg.sender == g.currentPlayer, "Not turn");
        require(timeouts[_id][msg.sender] < maxStrikes, "Eliminated");
        require(block.timestamp <= turnDeadlines[_id], "Timeout");
        require(_sub > 0, "Must subtract positive");
        
        g.moveCount++;
        uint256 currentRemaining = remainingNumbers[_id];
        
        MoveResult result;
        string memory feedback;
        
        if (_sub > currentRemaining) {
            // 🔥 HARDCORE: Subtract too much = INSTANT LOSS!
            result = MoveResult.GAME_LOST;
            feedback = "You lost! You tried to subtract more than the remaining number!";
            
            if (g.mode == GameMode.LAST_STAND) {
                // In Last Stand, eliminate the player
                emit InstantLoss(_id, msg.sender, _sub, currentRemaining);
                _eliminate(_id, msg.sender);
            } else {
                // In 1v1, opponent wins immediately
                address[] memory players = gamePlayers[_id];
                address winner = players[0] == msg.sender ? players[1] : players[0];
                emit InstantLoss(_id, msg.sender, _sub, currentRemaining);
                _finishGame(_id, winner);
            }
            
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
        
        if (g.mode == GameMode.LAST_STAND) {
            address[] storage active = activePlayers[_id];
            uint256 current = 0;
            for (uint i = 0; i < active.length; i++) {
                if (active[i] == g.currentPlayer) {
                    current = i;
                    break;
                }
            }
            g.currentPlayer = active[(current + 1) % active.length];
        } else {
            address[] memory players = gamePlayers[_id];
            g.currentPlayer = players[0] == g.currentPlayer ? players[1] : players[0];
        }
        
        turnDeadlines[_id] = block.timestamp + timeLimit;
    }
    
    // ✅ UPDATED handleTimeout with 2-timeout system
    function handleTimeout(uint256 _id) external {
        Game storage g = games[_id];
        require(g.status == GameStatus.ACTIVE, "Not active");
        require(block.timestamp > turnDeadlines[_id], "No timeout");
        
        address player = g.currentPlayer;
        timeouts[_id][player]++;
        emit PlayerTimeout(_id, player, timeouts[_id][player]);
        
        if (timeouts[_id][player] >= maxStrikes) {
            if (g.mode == GameMode.LAST_STAND) {
                _eliminate(_id, player);
            } else {
                _finishWithLoser(_id, player);
            }
        } else {
            _nextTurn(_id);
            emit TurnSkipped(_id, player, timeouts[_id][player]);
        }
    }
    
    function _eliminate(uint256 _id, address _player) internal {
        address[] storage active = activePlayers[_id];
        
        for (uint i = 0; i < active.length; i++) {
            if (active[i] == _player) {
                active[i] = active[active.length - 1];
                active.pop();
                break;
            }
        }
        
        uint256 position = 9 - active.length;
        emit PlayerEliminated(_id, _player, position);
        
        // ✅ Update Last Stand round for spectators
        if (spectatorContract != address(0)) {
            try IZeroSumSpectator(spectatorContract).updateLastStandRound(_id) {} catch {}
        }
        
        if (active.length == 1) {
            _finishGame(_id, active[0]);
        } else {
            _nextTurn(_id);
        }
    }
    
    function _finishWithLoser(uint256 _id, address _loser) internal {
        address[] memory players = gamePlayers[_id];
        address winner = players[0] == _loser ? players[1] : players[0];
        _finishGame(_id, winner);
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
        require(amount > 0, "No balance");
        
        balances[msg.sender] = 0;
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Failed");
    }
    
    // ================== VIEW FUNCTIONS ==================
    
    function getGame(uint256 _id) external view returns (
        uint256 gameId,
        GameMode mode,
        uint256 actualNumber,      // ✅ ALWAYS RETURNS 0 (Hidden)
        address currentPlayer,
        GameStatus status,
        uint256 entryFee,
        uint256 prizePool,
        address winner,
        uint256 maxPlayers,
        uint256 moveCount,
        bool isStarted
    ) {
        Game memory g = games[_id];
        return (
            g.gameId,
            g.mode,
            0,  // ✅ NEVER reveal actual number
            g.currentPlayer,
            g.status,
            g.entryFee,
            g.prizePool,
            g.winner,
            g.maxPlayers,
            g.moveCount,
            g.isStarted
        );
    }
    
    function getPlayers(uint256 _id) external view returns (address[] memory) {
        return gamePlayers[_id];
    }
    
    function getActive(uint256 _id) external view returns (address[] memory) {
        return activePlayers[_id];
    }
    
    function getStats(address _player) external view returns (uint256, uint256, uint256, uint256) {
        return (balances[_player], wins[_player], played[_player], 
                played[_player] > 0 ? (wins[_player] * 100) / played[_player] : 0);
    }
    
    function getMoveHistory(uint256 _id) external view returns (MoveHistory[] memory) {
        return moveHistory[_id];
    }
    
    // ✅ NEW: Get timeout status for a player
    function getTimeoutStatus(uint256 _id, address _player) 
        external view returns (uint256 currentTimeouts, uint256 remaining) 
    {
        currentTimeouts = timeouts[_id][_player];
        remaining = currentTimeouts >= maxStrikes ? 0 : maxStrikes - currentTimeouts;
    }
    
    // ✅ NEW: Check if player is on final warning
    function isOnFinalWarning(uint256 _id, address _player) external view returns (bool) {
        return timeouts[_id][_player] == maxStrikes - 1;
    }
    
    // ✅ Check if game is timed out
    function isTimedOut(uint256 _id) external view returns (bool) {
        Game memory g = games[_id];
        return g.status == GameStatus.ACTIVE && block.timestamp > turnDeadlines[_id];
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
        
        if (games[_id].mode == GameMode.HARDCORE_MYSTERY) {
            hint = "HARDCORE MODE: Subtract too much = Instant Loss!";
        } else {
            hint = "Battle royale - survival mode!";
        }
    }
    
    // ✅ UPDATED getPlayerView with timeout info
    function getPlayerView(uint256 _id) external view returns (
        string memory gameInfo,
        bool yourTurn,
        string memory status,
        uint256 timeLeft,
        string memory rangeDisplay,
        uint256 yourTimeouts,
        uint256 timeoutsRemaining
    ) {
        Game memory g = games[_id];
        
        yourTimeouts = timeouts[_id][msg.sender];
        timeoutsRemaining = yourTimeouts >= maxStrikes ? 0 : maxStrikes - yourTimeouts;
        yourTurn = (msg.sender == g.currentPlayer) && timeouts[_id][msg.sender] < maxStrikes;
        
        if (g.status == GameStatus.WAITING) {
            gameInfo = "Waiting for players...";
            status = "Waiting";
            rangeDisplay = "Hardcore Mystery awaits...";
        } else if (g.status == GameStatus.ACTIVE) {
            gameInfo = "HARDCORE MYSTERY: Subtract too much = INSTANT LOSS!";
            
            if (block.timestamp > turnDeadlines[_id]) {
                uint256 currentTimeouts = timeouts[_id][g.currentPlayer];
                if (currentTimeouts >= maxStrikes - 1) {
                    status = "FINAL WARNING - Next timeout = ELIMINATION!";
                } else {
                    status = "Timeout - Turn will be skipped";
                }
            } else {
                uint256 currentTimeouts = timeouts[_id][g.currentPlayer];
                if (currentTimeouts == 1) {
                    status = "Active (WARNING: 1 timeout used)";
                } else {
                    status = "Active";
                }
            }
            
            if (g.isStarted) {
                rangeDisplay = string(abi.encodePacked(
                    "Range: ",
                    _toString(displayMinRange[_id]),
                    " - ",
                    _toString(displayMaxRange[_id]),
                    " (BE CAREFUL!)"
                ));
            } else {
                rangeDisplay = "Generating range...";
            }
        } else {
            gameInfo = g.winner == msg.sender ? "Victory!" : "Game finished";
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
        require(games[_id].status == GameStatus.FINISHED, "Game must be finished");
        return (
            true,
            secretNumbers[_id],
            ACTUAL_MAX_RANGE - ACTUAL_MIN_RANGE,
            displayMinRange[_id],
            displayMaxRange[_id],
            "HARDCORE: Number was hidden with instant loss for overshooting!"
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
    
    // ================== ADMIN ==================
    
    function setPlatformFee(uint256 _fee) external onlyOwner {
        require(_fee <= 10, "Too high");
        platformFee = _fee;
    }
    
    function setMaxStrikes(uint256 _strikes) external onlyOwner {
        require(_strikes > 0 && _strikes <= 5, "Invalid range");
        maxStrikes = _strikes;
    }
    
    function setTimeLimit(uint256 _timeLimit) external onlyOwner {
        require(_timeLimit >= 60 && _timeLimit <= 3600, "Invalid range");
        timeLimit = _timeLimit;
    }
    
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
    }
    
    function withdrawFees() external onlyOwner nonReentrant {
        uint256 amount = fees;
        require(amount > 0, "No fees");
        fees = 0;
        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "Failed");
    }
    
    function emergency() external onlyOwner {
        (bool success, ) = payable(owner()).call{value: address(this).balance}("");
        require(success, "Failed");
    }
    
    // ✅ EMERGENCY: Owner can reveal number if needed (extreme cases only)
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