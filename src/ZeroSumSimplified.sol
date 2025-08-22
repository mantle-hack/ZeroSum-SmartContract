// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {SimplifiedLibrary} from "./libraries/SimplifiedLibrary.sol";

/**
 * @title ZeroSumSimplified - FIXED VERSION
 */

interface IZeroSumSpectator {
    function finalizeGameBetting(uint256 _gameId) external;
}

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

enum GameMode { QUICK_DRAW, STRATEGIC }
enum GameStatus { WAITING, ACTIVE, FINISHED }

struct StakingInfo {
    uint256 amount;
    uint256 lastReward;
    uint256 rewards;
}

// ✅ Enhanced events


contract ZeroSumSimplified is ReentrancyGuard, Ownable {
    event GameCreated(uint256 indexed gameId, GameMode mode, address creator, uint256 entryFee);
event PlayerJoined(uint256 indexed gameId, address player);
event MoveMade(uint256 indexed gameId, address player, uint256 subtraction, uint256 newNumber);
event GameFinished(uint256 indexed gameId, address winner, uint256 earnings);
event NumberGenerated(uint256 indexed gameId, uint256 number);
event TimeoutHandled(uint256 indexed gameId, address timedOutPlayer, uint256 timeoutCount); // ✅ NEW
event GameCancelled(uint256 indexed gameId, address creator, uint256 refund); // ✅ NEW
    uint256 private constant SALT = 0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890;
    uint256 public constant MAX_TIMEOUTS = 2;

    // Core mappings
    mapping(uint256 => Game) public games;
    mapping(uint256 => address[]) public gamePlayers;
    mapping(uint256 => mapping(address => bool)) public isInGame;
    mapping(uint256 => uint256) public turnDeadlines;
    mapping(uint256 => mapping(address => uint256)) public playerTimeouts;

    // Player data
    mapping(address => uint256) public balances;
    mapping(address => uint256) public wins;
    mapping(address => uint256) public played;
    mapping(address => StakingInfo) public staking;

    // Platform settings
    uint256 public gameCounter = 1; // ✅ START FROM 1 instead of 0
    uint256 public platformFee = 5;
    uint256 public fees;
    uint256 public totalStaked;
    uint256 public stakingAPY = 1000;
    uint256 public timeLimit = 300;
    bool public paused;
    address public spectatorContract;

    modifier notPaused() {
        require(!paused, "Paused");
        _;
    }

    constructor() Ownable(msg.sender) {}

    // ================== CORE FUNCTIONS ==================

    function createQuickDraw() external payable notPaused {
        require(msg.value > 0, "Fee required");
        uint256 gameId = gameCounter;
        SimplifiedLibrary._createGame(GameMode.QUICK_DRAW, gameId, games, playerTimeouts, isInGame, gamePlayers, played, turnDeadlines);
        gameCounter++;
        emit GameCreated(gameId, GameMode.QUICK_DRAW, msg.sender, msg.value);
    }

    function createStrategic() external payable notPaused {
        require(msg.value > 0, "Fee required");
        uint256 gameId = gameCounter;
        SimplifiedLibrary._createGame(GameMode.STRATEGIC, gameId, games, playerTimeouts, isInGame, gamePlayers, played, turnDeadlines);
        gameCounter++;
        emit GameCreated(gameId, GameMode.STRATEGIC, msg.sender, msg.value);
    }

    function joinGame(uint256 _id) external payable notPaused {
        SimplifiedLibrary._joinGame(_id, msg.sender, games, isInGame, gamePlayers, played, playerTimeouts, turnDeadlines);
        emit PlayerJoined(_id, msg.sender);
        
        if (gamePlayers[_id].length == 2) {
            Game memory g = games[_id];
            if (g.numberGenerated) {
                emit NumberGenerated(_id, g.currentNumber);
            }
        }
    }

    function makeMove(uint256 _id, uint256 _sub) external notPaused {
        Game storage g = games[_id];
        require(g.status == GameStatus.ACTIVE && g.numberGenerated, "Invalid state");
        require(msg.sender == g.currentPlayer && block.timestamp <= turnDeadlines[_id], "Not authorized");
        require(_isValid(_id, _sub), "Invalid move");

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

    function handleTimeout(uint256 _id) external {
        Game storage g = games[_id];
        require(g.status == GameStatus.ACTIVE && block.timestamp > turnDeadlines[_id], "No timeout");

        address slowPlayer = g.currentPlayer;
        playerTimeouts[_id][slowPlayer]++;

        // ✅ ADD TIMEOUT EVENT
        emit TimeoutHandled(_id, slowPlayer, playerTimeouts[_id][slowPlayer]);

        if (playerTimeouts[_id][slowPlayer] >= MAX_TIMEOUTS) {
            _finishWithLoser(_id, slowPlayer);
        } else {
            _nextTurn(_id);
        }
    }

    // ✅ NEW: Cancel waiting games
    function cancelWaitingGame(uint256 _gameId) external {
        Game storage g = games[_gameId];
        require(g.status == GameStatus.WAITING, "Game not waiting");
        require(gamePlayers[_gameId][0] == msg.sender, "Not your game");
        
        // Refund the creator
        g.status = GameStatus.FINISHED;
        balances[msg.sender] += g.entryFee;
        g.prizePool = 0;
        
        emit GameCancelled(_gameId, msg.sender, g.entryFee);
    }

    // ✅ NEW: Force finish stuck games
    function forceFinishInactiveGame(uint256 _gameId) external {
        Game storage g = games[_gameId];
        require(g.status == GameStatus.ACTIVE, "Game not active");
        require(block.timestamp > turnDeadlines[_gameId] + 3600, "Not stuck long enough"); // 1 hour
        
        // Winner is whoever's turn it's NOT (they're not the one who timed out)
        address[] memory players = gamePlayers[_gameId];
        address winner = players[0] == g.currentPlayer ? players[1] : players[0];
        _finishGame(_gameId, winner);
    }

    // ================== VIEW FUNCTIONS ==================

    function getGame(uint256 _id) external view returns (Game memory) {
        return games[_id];
    }

    function getPlayers(uint256 _id) external view returns (address[] memory) {
        return gamePlayers[_id];
    }

    function getStats(address _player) external view returns (uint256, uint256, uint256, uint256, uint256) {
        return (balances[_player], wins[_player], played[_player], 
                played[_player] > 0 ? (wins[_player] * 100) / played[_player] : 0, 
                staking[_player].amount);
    }

    function isGameBettable(uint256 _id) external view returns (bool) {
        Game memory g = games[_id];
        return g.gameId != 0 && (g.status == GameStatus.WAITING || g.status == GameStatus.ACTIVE);
    }

    function getGameForSpectators(uint256 _id) external view returns (GameStatus status, address winner, address[] memory players, uint256 currentNumber, bool numberGenerated, address currentPlayer, uint256 mode) {
        return SimplifiedLibrary.getGameForSpectators(games, _id, gamePlayers);
    }

    // ✅ ENHANCED getPlayerView with stuck detection
    function getPlayerView(uint256 _id) external view returns (
        uint256 number, 
        bool yourTurn, 
        uint256 timeLeft, 
        uint256 yourTimeouts, 
        uint256 opponentTimeouts,
        bool gameStuck,
        address stuckPlayer
    ) {
        Game memory g = games[_id];
        address[] memory players = gamePlayers[_id];
        address opponent = players.length == 2 ? (players[0] == msg.sender ? players[1] : players[0]) : address(0);

        number = g.numberGenerated ? g.currentNumber : 0;
        yourTurn = (msg.sender == g.currentPlayer);
        yourTimeouts = playerTimeouts[_id][msg.sender];
        opponentTimeouts = opponent != address(0) ? playerTimeouts[_id][opponent] : 0;
        
        bool isActive = g.status == GameStatus.ACTIVE;
        bool timeExpired = block.timestamp > turnDeadlines[_id];
        timeLeft = isActive && !timeExpired ? turnDeadlines[_id] - block.timestamp : 0;
        
        // NEW: Game stuck detection
        gameStuck = isActive && timeExpired;
        stuckPlayer = gameStuck ? g.currentPlayer : address(0);
    }

    // ✅ NEW: Get game summary in one call
    function getGameSummary(uint256 _id) external view returns (
        uint256 gameId,
        GameMode mode,
        GameStatus status,
        uint256 currentNumber,
        address currentPlayer,
        address winner,
        uint256 entryFee,
        uint256 prizePool,
        address[] memory players,
        bool numberGenerated,
        uint256 timeLeft,
        bool isStuck
    ) {
        Game memory g = games[_id];
        address[] memory _players = gamePlayers[_id];
        
        bool isActive = g.status == GameStatus.ACTIVE;
        bool timeExpired = block.timestamp > turnDeadlines[_id];
        uint256 _timeLeft = isActive && !timeExpired ? turnDeadlines[_id] - block.timestamp : 0;
        bool _isStuck = isActive && timeExpired;
        
        return (
            g.gameId,
            g.mode,
            g.status,
            g.currentNumber,
            g.currentPlayer,
            g.winner,
            g.entryFee,
            g.prizePool,
            _players,
            g.numberGenerated,
            _timeLeft,
            _isStuck
        );
    }

    // ✅ NEW: Batch getter for multiple games
    function getGamesBatch(uint256[] calldata gameIds) external view returns (Game[] memory) {
        Game[] memory result = new Game[](gameIds.length);
        for (uint256 i = 0; i < gameIds.length; i++) {
            result[i] = games[gameIds[i]];
        }
        return result;
    }

    // ✅ NEW: Get user's games efficiently
    function getUserGames(address user, uint256 fromGameId, uint256 limit) external view returns (
        uint256[] memory gameIds,
        Game[] memory userGames
    ) {
        uint256[] memory tempGameIds = new uint256[](limit);
        uint256 count = 0;
        
        // Search backwards from the latest games
        for (uint256 i = gameCounter; i > fromGameId && count < limit; i--) {
            uint256 gameId = i - 1;
            if (isInGame[gameId][user]) {
                tempGameIds[count] = gameId;
                count++;
            }
        }
        
        // Resize arrays to actual count
        gameIds = new uint256[](count);
        userGames = new Game[](count);
        
        for (uint256 i = 0; i < count; i++) {
            gameIds[i] = tempGameIds[i];
            userGames[i] = games[tempGameIds[i]];
        }
    }

    // ================== STAKING ==================

    function stake() external payable {
        SimplifiedLibrary.stake(staking, msg.value);
        totalStaked += msg.value;
    }

    function unstake(uint256 _amount) external nonReentrant {
        require(staking[msg.sender].amount >= _amount, "Insufficient");
        SimplifiedLibrary.unstake(staking, _amount);
        totalStaked -= _amount;
        (bool success,) = payable(msg.sender).call{value: _amount}("");
        require(success, "Failed");
    }

    function claimRewards() external nonReentrant {
        SimplifiedLibrary._calcRewards(staking);
    }

    function withdraw() external nonReentrant {
        uint256 amount = balances[msg.sender];
        require(amount > 0, "No balance");
        balances[msg.sender] = 0;
        (bool success,) = payable(msg.sender).call{value: amount}("");
        require(success, "Failed");
    }

    // ================== INTERNAL FUNCTIONS ==================

    // ✅ FIXED: Handle small numbers properly
    function _isValid(uint256 _id, uint256 _sub) internal view returns (bool) {
        if (_sub == 0) return false;
        Game memory g = games[_id];
        if (g.mode == GameMode.QUICK_DRAW) return _sub == 1;
        
        uint256 min = g.currentNumber * 10 / 100;
        if (min == 0) min = 1;
        
        uint256 max = g.currentNumber * 30 / 100;
        if (max < min) max = min;  // ✅ Ensure max is at least min
        
        return _sub >= min && _sub <= max;
    }

    function _nextTurn(uint256 _id) internal {
        address[] memory players = gamePlayers[_id];
        games[_id].currentPlayer = players[0] == games[_id].currentPlayer ? players[1] : players[0];
        turnDeadlines[_id] = block.timestamp + timeLimit;
    }

    function _finishWithLoser(uint256 _id, address _loser) internal {
        address[] memory players = gamePlayers[_id];
        _finishGame(_id, players[0] == _loser ? players[1] : players[0]);
    }

    function _finishGame(uint256 _id, address _winner) internal {
        Game storage g = games[_id];
        g.status = GameStatus.FINISHED;
        g.winner = _winner;

        uint256 fee = (g.prizePool * platformFee) / 100;
        uint256 base = g.prizePool - fee;
        uint256 bonus = _getBonus(_winner);
        uint256 finals = (base * bonus) / 100;

        balances[_winner] += finals;
        wins[_winner]++;
        fees += fee;

        if (spectatorContract != address(0)) {
            try IZeroSumSpectator(spectatorContract).finalizeGameBetting(_id) {} catch {}
        }

        emit GameFinished(_id, _winner, finals);
    }

    function _getBonus(address _player) internal view returns (uint256) {
        uint256 staked = staking[_player].amount;
        if (staked >= 5 ether) return 150;
        if (staked >= 1 ether) return 125;
        if (staked >= 0.1 ether) return 110;
        return 100;
    }

    // ================== ADMIN FUNCTIONS ==================

    function setSpectatorContract(address _spectator) external onlyOwner { spectatorContract = _spectator; }
    function setPlatformFee(uint256 _fee) external onlyOwner { require(_fee <= 10); platformFee = _fee; }
    function setStakingAPY(uint256 _apy) external onlyOwner { require(_apy <= 5000); stakingAPY = _apy; }
    function setTimeLimit(uint256 _timeLimit) external onlyOwner { require(_timeLimit >= 60 && _timeLimit <= 3600); timeLimit = _timeLimit; }
    function setPaused(bool _paused) external onlyOwner { paused = _paused; }

    function withdrawFees() external onlyOwner nonReentrant {
        uint256 amount = fees;
        require(amount > 0);
        fees = 0;
        (bool success,) = payable(owner()).call{value: amount}("");
        require(success);
    }

    function emergency() external onlyOwner {
        (bool success,) = payable(owner()).call{value: address(this).balance}("");
        require(success);
    }
}