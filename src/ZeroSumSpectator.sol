// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

enum GameStatus {
    WAITING,
    ACTIVE,
    FINISHED
}

interface IZeroSumGame {
    function getGameForSpectators(uint256 _id)
        external
        view
        returns (
            GameStatus status,
            address winner,
            address[] memory players,
            uint256 currentNumber,
            bool numberGenerated,
            address currentPlayer,
            uint256 mode
        );
    function isGameBettable(uint256 _id) external view returns (bool);
}

contract ZeroSumSpectator is ReentrancyGuard, Ownable {
    struct Bet {
        address bettor;
        uint256 gameId;
        address predictedWinner;
        uint256 amount;
        bool claimed;
        address gameContract;
        uint256 timestamp;
    }

    struct UserBetInfo {
        bool hasBet;
        address predictedWinner;
        uint256 amount;
        bool claimed;
        uint256 timestamp;
    }

    struct GameBettingSummary {
        uint256 totalBetAmount;
        uint256 numberOfBets;
        bool bettingAllowed;
        address[] uniqueBettors;
        mapping(address => uint256) playerBetCounts;
        address[] playersWithBets;
    }

    // ✅ ENHANCED MAPPINGS FOR BETTER USER TRACKING
    mapping(bytes32 => Bet[]) public gameBets;
    mapping(bytes32 => mapping(address => uint256)) public totalBetsOnPlayer;
    mapping(bytes32 => uint256) public totalGameBets;
    mapping(address => uint256) public spectatorBalances;
    mapping(bytes32 => bool) public bettingClosed;
    mapping(address => bool) public registeredContracts;
    
    // ✅ NEW: Track user betting per game
    mapping(bytes32 => mapping(address => UserBetInfo)) public userGameBets;
    mapping(bytes32 => address[]) public gameBettors; // List of all users who bet on a game
    mapping(address => bytes32[]) public userBettingHistory; // All games a user has bet on
    mapping(bytes32 => mapping(address => uint256)) public userBetCount; // How many bets user placed on specific game
    
    // ✅ NEW: Quick lookup for player betting stats
    mapping(bytes32 => address[]) public playersInGame;
    mapping(bytes32 => mapping(address => address[])) public playerBettors; // Who bet on each player

    uint256 public bettingFeePercent = 3;
    uint256 public minimumBet = 0.01 ether;
    bool public globalBettingEnabled = true;

    event BetPlaced(address indexed gameContract, uint256 indexed gameId, address indexed bettor, uint256 amount, address predictedWinner);
    event BetsClaimed(address indexed gameContract, uint256 indexed gameId, address indexed bettor, uint256 winnings);
    event BettingClosed(address indexed gameContract, uint256 indexed gameId);

    constructor() Ownable(msg.sender) {}

    modifier onlyRegisteredContract() {
        require(registeredContracts[msg.sender], "Only registered");
        _;
    }

    function registerGameContract(address _gameContract) external onlyOwner {
        registeredContracts[_gameContract] = true;
    }

    function _getGameKey(address _gameContract, uint256 _gameId) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_gameContract, _gameId));
    }

    function isBettingAllowed(address _gameContract, uint256 _gameId) public view returns (bool) {
        if (!globalBettingEnabled || !registeredContracts[_gameContract]) return false;
        bytes32 gameKey = _getGameKey(_gameContract, _gameId);
        if (bettingClosed[gameKey]) return false;

        try IZeroSumGame(_gameContract).isGameBettable(_gameId) returns (bool bettable) {
            return bettable;
        } catch {
            return false;
        }
    }

    // ✅ ENHANCED: Place bet with better tracking
    function placeBet(address _gameContract, uint256 _gameId, address _predictedWinner) external payable nonReentrant {
        require(msg.value >= minimumBet, "Bet too low");
        require(isBettingAllowed(_gameContract, _gameId), "Betting not allowed");

        bytes32 gameKey = _getGameKey(_gameContract, _gameId);
        
        // ✅ Check if user already bet on this game
        require(!userGameBets[gameKey][msg.sender].hasBet, "Already bet on this game");

        bool validPlayer = false;
        address[] memory players;
        
        try IZeroSumGame(_gameContract).getGameForSpectators(_gameId) returns (
            GameStatus status,
            address, /* winner */
            address[] memory _players,
            uint256, /* currentNumber */
            bool, /* numberGenerated */
            address, /* currentPlayer */
            uint256 /* mode */
        ) {
            players = _players;
            for (uint256 i = 0; i < players.length; i++) {
                if (players[i] == _predictedWinner) {
                    validPlayer = true;
                    break;
                }
            }
            require(validPlayer, "Invalid player");
            require(status != GameStatus.FINISHED, "Game finished");
        } catch {
            revert("Cannot verify game");
        }

        // ✅ Store players in game if not already stored
        if (playersInGame[gameKey].length == 0) {
            for (uint256 i = 0; i < players.length; i++) {
                playersInGame[gameKey].push(players[i]);
            }
        }

        // ✅ Create and store bet
        Bet memory newBet = Bet({
            bettor: msg.sender,
            gameId: _gameId,
            predictedWinner: _predictedWinner,
            amount: msg.value,
            claimed: false,
            gameContract: _gameContract,
            timestamp: block.timestamp
        });

        gameBets[gameKey].push(newBet);

        // ✅ Update user betting info
        userGameBets[gameKey][msg.sender] = UserBetInfo({
            hasBet: true,
            predictedWinner: _predictedWinner,
            amount: msg.value,
            claimed: false,
            timestamp: block.timestamp
        });

        // ✅ Add to tracking arrays
        gameBettors[gameKey].push(msg.sender);
        userBettingHistory[msg.sender].push(gameKey);
        userBetCount[gameKey][msg.sender]++;
        playerBettors[gameKey][_predictedWinner].push(msg.sender);

        // ✅ Update totals
        totalBetsOnPlayer[gameKey][_predictedWinner] += msg.value;
        totalGameBets[gameKey] += msg.value;

        emit BetPlaced(_gameContract, _gameId, msg.sender, msg.value, _predictedWinner);
    }

    // ✅ NEW: Check if user has bet on specific game
    function hasUserBetOnGame(address _gameContract, uint256 _gameId, address _user) external view returns (bool) {
        bytes32 gameKey = _getGameKey(_gameContract, _gameId);
        return userGameBets[gameKey][_user].hasBet;
    }

    // ✅ NEW: Get user's bet info for specific game
    function getUserBetInfo(address _gameContract, uint256 _gameId, address _user) 
        external 
        view 
        returns (
            bool hasBet,
            address predictedWinner,
            uint256 amount,
            bool claimed,
            uint256 timestamp
        ) 
    {
        bytes32 gameKey = _getGameKey(_gameContract, _gameId);
        UserBetInfo memory betInfo = userGameBets[gameKey][_user];
        
        return (
            betInfo.hasBet,
            betInfo.predictedWinner,
            betInfo.amount,
            betInfo.claimed,
            betInfo.timestamp
        );
    }

    // ✅ NEW: Get all users who bet on a game
    function getGameBettors(address _gameContract, uint256 _gameId) external view returns (address[] memory) {
        bytes32 gameKey = _getGameKey(_gameContract, _gameId);
        return gameBettors[gameKey];
    }

    // ✅ NEW: Get all users who bet on specific player
    function getPlayerBettors(address _gameContract, uint256 _gameId, address _player) external view returns (address[] memory) {
        bytes32 gameKey = _getGameKey(_gameContract, _gameId);
        return playerBettors[gameKey][_player];
    }

    // ✅ NEW: Get user's betting history
    function getUserBettingHistory(address _user) external view returns (bytes32[] memory) {
        return userBettingHistory[_user];
    }

    // ✅ NEW: Get user's betting history with details
    function getUserBettingHistoryDetailed(address _user, uint256 _limit) 
        external 
        view 
        returns (
            bytes32[] memory gameKeys,
            address[] memory gameContracts,
            uint256[] memory gameIds,
            address[] memory predictedWinners,
            uint256[] memory amounts,
            bool[] memory claimed,
            uint256[] memory timestamps
        ) 
    {
        bytes32[] memory history = userBettingHistory[_user];
        uint256 length = history.length > _limit ? _limit : history.length;
        
        gameKeys = new bytes32[](length);
        gameContracts = new address[](length);
        gameIds = new uint256[](length);
        predictedWinners = new address[](length);
        amounts = new uint256[](length);
        claimed = new bool[](length);
        timestamps = new uint256[](length);
        
        for (uint256 i = 0; i < length; i++) {
            bytes32 gameKey = history[history.length - 1 - i]; // Most recent first
            UserBetInfo memory betInfo = userGameBets[gameKey][_user];
            
            gameKeys[i] = gameKey;
            // Decode gameKey to get contract and gameId (approximate - for display only)
            gameContracts[i] = address(0); // Would need additional mapping to decode properly
            gameIds[i] = 0; // Would need additional mapping to decode properly
            predictedWinners[i] = betInfo.predictedWinner;
            amounts[i] = betInfo.amount;
            claimed[i] = betInfo.claimed;
            timestamps[i] = betInfo.timestamp;
        }
    }

    // ✅ NEW: Get comprehensive game betting stats
    function getGameBettingStats(address _gameContract, uint256 _gameId) 
        external 
        view 
        returns (
            uint256 totalBetAmount,
            uint256 numberOfBets,
            uint256 numberOfUniqueBettors,
            bool bettingAllowed,
            address[] memory players,
            uint256[] memory playerBetAmounts,
            uint256[] memory playerBetCounts
        ) 
    {
        bytes32 gameKey = _getGameKey(_gameContract, _gameId);
        
        totalBetAmount = totalGameBets[gameKey];
        numberOfBets = gameBets[gameKey].length;
        numberOfUniqueBettors = gameBettors[gameKey].length;
        bettingAllowed = isBettingAllowed(_gameContract, _gameId);
        players = playersInGame[gameKey];
        
        playerBetAmounts = new uint256[](players.length);
        playerBetCounts = new uint256[](players.length);
        
        for (uint256 i = 0; i < players.length; i++) {
            playerBetAmounts[i] = totalBetsOnPlayer[gameKey][players[i]];
            playerBetCounts[i] = playerBettors[gameKey][players[i]].length;
        }
    }

    // ✅ ENHANCED: Claim winnings with better tracking
    function claimBettingWinnings(address _gameContract, uint256 _gameId) external nonReentrant {
        require(registeredContracts[_gameContract], "Not registered");

        bytes32 gameKey = _getGameKey(_gameContract, _gameId);
        require(userGameBets[gameKey][msg.sender].hasBet, "No bet placed");
        require(!userGameBets[gameKey][msg.sender].claimed, "Already claimed");

        address actualWinner;
        try IZeroSumGame(_gameContract).getGameForSpectators(_gameId) returns (
            GameStatus status,
            address winner,
            address[] memory, /* players */
            uint256, /* currentNumber */
            bool, /* numberGenerated */
            address, /* currentPlayer */
            uint256 /* mode */
        ) {
            require(status == GameStatus.FINISHED, "Game not finished");
            require(winner != address(0), "No winner");
            actualWinner = winner;
        } catch {
            revert("Cannot verify");
        }

        UserBetInfo storage userBet = userGameBets[gameKey][msg.sender];
        require(userBet.predictedWinner == actualWinner, "Wrong prediction");

        // Calculate winnings
        uint256 winnerPool = totalBetsOnPlayer[gameKey][actualWinner];
        require(winnerPool > 0, "No winning pool");
        
        uint256 betShare = (userBet.amount * 10000) / winnerPool;
        uint256 totalPrizePool = (totalGameBets[gameKey] * (100 - bettingFeePercent)) / 100;
        uint256 winnings = (totalPrizePool * betShare) / 10000;

        require(winnings > 0, "No winnings");

        // Mark as claimed
        userBet.claimed = true;
        
        // Also update in the gameBets array
        Bet[] storage bets = gameBets[gameKey];
        for (uint256 i = 0; i < bets.length; i++) {
            if (bets[i].bettor == msg.sender && bets[i].predictedWinner == actualWinner && !bets[i].claimed) {
                bets[i].claimed = true;
                break;
            }
        }

        spectatorBalances[msg.sender] += winnings;
        emit BetsClaimed(_gameContract, _gameId, msg.sender, winnings);
    }

    function withdrawSpectatorBalance() external nonReentrant {
        uint256 amount = spectatorBalances[msg.sender];
        require(amount > 0, "No balance");
        spectatorBalances[msg.sender] = 0;
        (bool success,) = payable(msg.sender).call{value: amount}("");
        require(success, "Failed");
    }

    function finalizeGameBetting(uint256 _gameId) external onlyRegisteredContract {
        bytes32 gameKey = _getGameKey(msg.sender, _gameId);
        bettingClosed[gameKey] = true;
        emit BettingClosed(msg.sender, _gameId);
    }

    // Keep compatibility with existing functions
    function enableLastStandBetting(uint256 /* _gameId */ ) external onlyRegisteredContract {}
    function updateLastStandRound(uint256 /* _gameId */ ) external onlyRegisteredContract {}

    function getBettingOdds(address _gameContract, uint256 _gameId, address[] memory _players)
        external
        view
        returns (uint256[] memory betAmounts, uint256[] memory oddPercentages)
    {
        betAmounts = new uint256[](_players.length);
        oddPercentages = new uint256[](_players.length);
        bytes32 gameKey = _getGameKey(_gameContract, _gameId);
        uint256 totalBets = totalGameBets[gameKey];

        for (uint256 i = 0; i < _players.length; i++) {
            betAmounts[i] = totalBetsOnPlayer[gameKey][_players[i]];
            if (totalBets > 0) {
                oddPercentages[i] = (betAmounts[i] * 100) / totalBets;
            }
        }
    }

    function getGameBettingInfo(address _gameContract, uint256 _gameId)
        external
        view
        returns (uint256 totalBetAmount, uint256 numberOfBets, bool bettingAllowed)
    {
        bytes32 gameKey = _getGameKey(_gameContract, _gameId);
        return (totalGameBets[gameKey], gameBets[gameKey].length, isBettingAllowed(_gameContract, _gameId));
    }

    function setBettingFee(uint256 _feePercent) external onlyOwner {
        require(_feePercent <= 10, "Too high");
        bettingFeePercent = _feePercent;
    }

    function setMinimumBet(uint256 _minimumBet) external onlyOwner {
        minimumBet = _minimumBet;
    }

    function setGlobalBettingEnabled(bool _enabled) external onlyOwner {
        globalBettingEnabled = _enabled;
    }

    function emergencyWithdraw() external onlyOwner {
        (bool success,) = payable(owner()).call{value: address(this).balance}("");
        require(success, "Failed");
    }
}