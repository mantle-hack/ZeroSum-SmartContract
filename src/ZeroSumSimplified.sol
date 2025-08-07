// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ZeroSumSimplified - ULTRA OPTIMIZED UNDER 24KB
 * @dev Privacy-fixed basic games with minimal code size, 2-timeout system, and spectator integration
 */



   // ✅ Spectator contract integration
    interface IZeroSumSpectator {
        function finalizeGameBetting(uint256 _gameId) external;
        function enableLastStandBetting(uint256 _gameId) external;
        function updateLastStandRound(uint256 _gameId) external;
    }
    
contract ZeroSumSimplified is ReentrancyGuard, Ownable {
    
    enum GameMode { QUICK_DRAW, STRATEGIC }
    enum GameStatus { WAITING, ACTIVE, FINISHED }
    
    struct Game {
        uint256 gameId;
        GameMode mode;
        uint256 currentNumber;
        address currentPlayer;
        GameStatus status;
        uint256 entryFee;
        uint256 prizePool;
        address winner;
        bool numberGenerated;
    }
    
    struct StakingInfo {
        uint256 amount;
        uint256 lastReward;
        uint256 rewards;
    }
    
  
    // ✅ Custom salt for security
    uint256 private constant SALT = 0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890;
    
    // ✅ Timeout system
    uint256 public constant MAX_TIMEOUTS = 2; // Lose after 2 timeouts
    mapping(uint256 => mapping(address => uint256)) public playerTimeouts;
    
    // Core mappings
    mapping(uint256 => Game) public games;
    mapping(uint256 => address[]) public gamePlayers;
    mapping(uint256 => mapping(address => bool)) public isInGame;
    mapping(uint256 => uint256) public turnDeadlines;
    
    // Player data
    mapping(address => uint256) public balances;
    mapping(address => uint256) public wins;
    mapping(address => uint256) public played;
    mapping(address => StakingInfo) public staking;
    
    // Platform settings
    uint256 public gameCounter;
    uint256 public platformFee = 5;
    uint256 public fees;
    uint256 public totalStaked;
    uint256 public stakingAPY = 1000; // 10%
    uint256 public timeLimit = 300;
    bool public paused;
    
    // ✅ Spectator integration
    address public spectatorContract;
    
    // Events
    event GameCreated(uint256 indexed gameId, GameMode mode, address creator, uint256 entryFee);
    event PlayerJoined(uint256 indexed gameId, address player);
    event NumberGenerated(uint256 indexed gameId, uint256 number);
    event MoveMade(uint256 indexed gameId, address player, uint256 subtraction, uint256 newNumber);
    event GameFinished(uint256 indexed gameId, address winner, uint256 earnings);
    event Staked(address indexed staker, uint256 amount);
    event Unstaked(address indexed staker, uint256 amount);
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
            gamePlayers[_id],
            g.numberGenerated ? g.currentNumber : 0,
            g.numberGenerated,
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
    
    // ================== STAKING ==================
    
    function stake() external payable {
        require(msg.value > 0, "Must stake");
        
        StakingInfo storage s = staking[msg.sender];
        
        if (s.amount > 0) {
            uint256 pending = _calcRewards(msg.sender);
            s.rewards += pending;
        }
        
        s.amount += msg.value;
        s.lastReward = block.timestamp;
        totalStaked += msg.value;
        
        emit Staked(msg.sender, msg.value);
    }
    
    function unstake(uint256 _amount) external nonReentrant {
        StakingInfo storage s = staking[msg.sender];
        require(s.amount >= _amount, "Insufficient");
        
        uint256 pending = _calcRewards(msg.sender);
        s.rewards += pending;
        s.amount -= _amount;
        s.lastReward = block.timestamp;
        totalStaked -= _amount;
        
        (bool success, ) = payable(msg.sender).call{value: _amount}("");
        require(success, "Failed");
        
        emit Unstaked(msg.sender, _amount);
    }
    
    function claimRewards() external nonReentrant {
        StakingInfo storage s = staking[msg.sender];
        
        uint256 pending = _calcRewards(msg.sender);
        uint256 total = s.rewards + pending;
        require(total > 0, "No rewards");
        
        s.rewards = 0;
        s.lastReward = block.timestamp;
        
        (bool success, ) = payable(msg.sender).call{value: total}("");
        require(success, "Failed");
    }
    
    function _calcRewards(address _staker) internal view returns (uint256) {
        StakingInfo memory s = staking[_staker];
        if (s.amount == 0) return 0;
        
        uint256 time = block.timestamp - s.lastReward;
        uint256 annual = (s.amount * stakingAPY) / 10000;
        return (annual * time) / 365 days;
    }
    
    function getBonus(address _player) public view returns (uint256) {
        uint256 staked = staking[_player].amount;
        
        if (staked >= 5 ether) return 150;
        if (staked >= 1 ether) return 125;
        if (staked >= 0.1 ether) return 110;
        return 100;
    }
    
    // ================== GAME CREATION ==================
    
    function createQuickDraw() external payable notPaused {
        require(msg.value > 0, "Fee required");
        _createGame(GameMode.QUICK_DRAW);
    }
    
    function createStrategic() external payable notPaused {
        require(msg.value > 0, "Fee required");
        _createGame(GameMode.STRATEGIC);
    }
    
    function _createGame(GameMode _mode) internal {
        gameCounter++;
        uint256 id = gameCounter;
        
        games[id] = Game({
            gameId: id,
            mode: _mode,
            currentNumber: 0,
            currentPlayer: address(0),
            status: GameStatus.WAITING,
            entryFee: msg.value,
            prizePool: msg.value,
            winner: address(0),
            numberGenerated: false
        });
        
        // ✅ Reset timeout counters for creator
        playerTimeouts[id][msg.sender] = 0;
        
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
        require(gamePlayers[_id].length < 2, "Full");
        require(msg.value == g.entryFee, "Wrong fee");
        
        gamePlayers[_id].push(_player);
        g.prizePool += msg.value;
        isInGame[_id][_player] = true;
        played[_player]++;
        
        // ✅ Reset timeout counter for joining player
        playerTimeouts[_id][_player] = 0;
        
        emit PlayerJoined(_id, _player);
        
        // ✅ GENERATE NUMBER ONLY WHEN BOTH PLAYERS JOIN!
        if (gamePlayers[_id].length == 2) {
            _startGame(_id);
        }
    }
    
    function _startGame(uint256 _id) internal {
        Game storage g = games[_id];
        
        // ✅ Generate number using BOTH players for fairness
        uint256 startNum = _generateNumber(_id, g.mode);
        g.currentNumber = startNum;
        g.numberGenerated = true;
        g.status = GameStatus.ACTIVE;
        g.currentPlayer = gamePlayers[_id][0];
        turnDeadlines[_id] = block.timestamp + timeLimit;
        
        emit NumberGenerated(_id, startNum);
    }
    
    function _generateNumber(uint256 _id, GameMode _mode) internal view returns (uint256) {
        address[] memory players = gamePlayers[_id];
        
        uint256 entropy = uint256(keccak256(abi.encodePacked(
            block.timestamp,
            block.prevrandao,
            _id,
            players[0],
            players[1],
            SALT
        )));
        
        return _mode == GameMode.QUICK_DRAW ? 15 + (entropy % 35) : 80 + (entropy % 120);
    }
    
    // ================== GAMEPLAY ==================
    
    function makeMove(uint256 _id, uint256 _sub) external notPaused {
        Game storage g = games[_id];
        require(g.status == GameStatus.ACTIVE, "Not active");
        require(g.numberGenerated, "No number");
        
        // ✅ Auto-handle timeout if it occurred
        if (block.timestamp > turnDeadlines[_id]) {
            address slowPlayer = g.currentPlayer;
            
            // Only auto-handle if caller is not the slow player
            if (msg.sender != slowPlayer) {
                playerTimeouts[_id][slowPlayer]++;
                emit PlayerTimeout(_id, slowPlayer, playerTimeouts[_id][slowPlayer]);
                
                if (playerTimeouts[_id][slowPlayer] >= MAX_TIMEOUTS) {
                    _finishWithLoser(_id, slowPlayer);
                    return;
                }
                
                _nextTurn(_id);
                emit TurnSkipped(_id, slowPlayer, playerTimeouts[_id][slowPlayer]);
            }
        }
        
        require(msg.sender == g.currentPlayer, "Not turn");
        require(block.timestamp <= turnDeadlines[_id], "Timeout");
        require(_isValid(_id, _sub), "Invalid");
        
        uint256 newNum = g.currentNumber - _sub;
        g.currentNumber = newNum;
        
        emit MoveMade(_id, msg.sender, _sub, newNum);
        
        if (newNum == 0) {
            if (g.mode == GameMode.STRATEGIC) {
                _finishWithLoser(_id, msg.sender);
            } else {
                _finishGame(_id, msg.sender);
            }
        } else {
            _nextTurn(_id);
        }
    }
    
    function _isValid(uint256 _id, uint256 _sub) internal view returns (bool) {
        if (_sub == 0) return false;
        
        Game memory g = games[_id];
        
        if (g.mode == GameMode.QUICK_DRAW) {
            return _sub == 1;
        } else {
            uint256 min = g.currentNumber * 10 / 100;
            if (min == 0) min = 1;
            uint256 max = g.currentNumber * 30 / 100;
            return _sub >= min && _sub <= max;
        }
    }
    
    function _nextTurn(uint256 _id) internal {
        address[] memory players = gamePlayers[_id];
        address current = games[_id].currentPlayer;
        
        games[_id].currentPlayer = players[0] == current ? players[1] : players[0];
        turnDeadlines[_id] = block.timestamp + timeLimit;
    }
    
    // ✅ UPDATED handleTimeout with 2-timeout system
    function handleTimeout(uint256 _id) external {
        Game storage g = games[_id];
        require(g.status == GameStatus.ACTIVE, "Not active");
        require(block.timestamp > turnDeadlines[_id], "No timeout");
        
        address slowPlayer = g.currentPlayer;
        
        // Increment timeout count for this player
        playerTimeouts[_id][slowPlayer]++;
        emit PlayerTimeout(_id, slowPlayer, playerTimeouts[_id][slowPlayer]);
        
        // Check if player has reached the limit
        if (playerTimeouts[_id][slowPlayer] >= MAX_TIMEOUTS) {
            // 2nd timeout = you lose!
            _finishWithLoser(_id, slowPlayer);
            return;
        }
        
        // First timeout = skip turn, continue game
        _nextTurn(_id);
        emit TurnSkipped(_id, slowPlayer, playerTimeouts[_id][slowPlayer]);
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
        uint256 base = g.prizePool - fee;
        
        // Apply staking bonus
        uint256 bonus = getBonus(_winner);
        uint256 finals = (base * bonus) / 100;
        
        balances[_winner] += finals;
        wins[_winner]++;
        fees += fee;
        
        // ✅ NEW: Notify spectator contract that game finished
        if (spectatorContract != address(0)) {
            try IZeroSumSpectator(spectatorContract).finalizeGameBetting(_id) {} catch {}
        }
        
        emit GameFinished(_id, _winner, finals);
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
    
    function getGame(uint256 _id) external view returns (Game memory) {
        return games[_id];
    }
    
    function getPlayers(uint256 _id) external view returns (address[] memory) {
        return gamePlayers[_id];
    }
    
    function getStats(address _player) external view returns (uint256, uint256, uint256, uint256, uint256) {
        return (
            balances[_player],
            wins[_player],
            played[_player],
            played[_player] > 0 ? (wins[_player] * 100) / played[_player] : 0,
            staking[_player].amount
        );
    }
    
    // ✅ NEW: Get timeout status for a player
    function getTimeoutStatus(uint256 _id, address _player) 
        external view returns (uint256 timeouts, uint256 remaining) 
    {
        timeouts = playerTimeouts[_id][_player];
        remaining = timeouts >= MAX_TIMEOUTS ? 0 : MAX_TIMEOUTS - timeouts;
    }
    
    // ✅ NEW: Check if player is on final warning
    function isOnFinalWarning(uint256 _id, address _player) external view returns (bool) {
        return playerTimeouts[_id][_player] == MAX_TIMEOUTS - 1;
    }
    
    // ✅ Check if game is timed out
    function isTimedOut(uint256 _id) external view returns (bool) {
        Game memory g = games[_id];
        return g.status == GameStatus.ACTIVE && block.timestamp > turnDeadlines[_id];
    }
    
    // ✅ UPDATED getPlayerView with timeout info
    function getPlayerView(uint256 _id) external view returns (
        uint256 number,
        bool yourTurn,
        string memory status,
        uint256 timeLeft,
        string memory condition,
        uint256 yourTimeouts,
        uint256 opponentTimeouts
    ) {
        Game memory g = games[_id];
        address[] memory players = gamePlayers[_id];
        address opponent = address(0);
        
        // Find opponent
        if (players.length == 2) {
            opponent = players[0] == msg.sender ? players[1] : players[0];
        }
        
        number = g.numberGenerated ? g.currentNumber : 0;
        yourTurn = (msg.sender == g.currentPlayer);
        yourTimeouts = playerTimeouts[_id][msg.sender];
        opponentTimeouts = opponent != address(0) ? playerTimeouts[_id][opponent] : 0;
        
        condition = g.mode == GameMode.STRATEGIC ? "DON'T reach zero!" : "Reach zero to win!";
        
        if (g.status == GameStatus.WAITING) {
            uint256 current = players.length;
            if (current == 2 && !g.numberGenerated) {
                status = "Generating number...";
            } else {
                status = current == 1 ? "Waiting for opponent" : "Ready to start";
            }
            timeLeft = 0;
        } else if (g.status == GameStatus.ACTIVE) {
            if (block.timestamp > turnDeadlines[_id]) {
                uint256 currentTimeouts = playerTimeouts[_id][g.currentPlayer];
                if (currentTimeouts >= MAX_TIMEOUTS - 1) {
                    status = "FINAL WARNING - Next timeout = LOSS!";
                } else {
                    status = "Timeout - Turn will be skipped";
                }
                timeLeft = 0;
            } else {
                timeLeft = turnDeadlines[_id] - block.timestamp;
                
                uint256 currentTimeouts = playerTimeouts[_id][g.currentPlayer];
                if (currentTimeouts == 1) {
                    status = "Game active (WARNING: 1 timeout used)";
                } else {
                    status = "Game active";
                }
            }
        } else {
            status = g.winner == msg.sender ? "You won!" : "Game finished";
            timeLeft = 0;
        }
    }
    
    function getPlatformStats() external view returns (uint256, uint256, uint256) {
        return (gameCounter, fees, totalStaked);
    }
    
    // ✅ Verify fairness
    function verifyFairness(uint256 _id) external view returns (bool, uint256, string memory) {
        Game memory g = games[_id];
        return (
            g.numberGenerated,
            gamePlayers[_id].length,
            "Both players + block data + custom salt"
        );
    }
    
    // ================== ADMIN ==================
    
    function setPlatformFee(uint256 _fee) external onlyOwner {
        require(_fee <= 10, "Too high");
        platformFee = _fee;
    }
    
    function setStakingAPY(uint256 _apy) external onlyOwner {
        require(_apy <= 5000, "Too high");
        stakingAPY = _apy;
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
}