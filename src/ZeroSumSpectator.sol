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
    }

    mapping(bytes32 => Bet[]) public gameBets;
    mapping(bytes32 => mapping(address => uint256)) public totalBetsOnPlayer;
    mapping(bytes32 => uint256) public totalGameBets;
    mapping(address => uint256) public spectatorBalances;
    mapping(bytes32 => bool) public bettingClosed;
    mapping(address => bool) public registeredContracts;

    uint256 public bettingFeePercent = 3;
    uint256 public minimumBet = 0.01 ether;
    bool public globalBettingEnabled = true;

    event BetPlaced(address indexed gameContract, uint256 indexed gameId, address indexed bettor, uint256 amount);
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

    function placeBet(address _gameContract, uint256 _gameId, address _predictedWinner) external payable nonReentrant {
        require(msg.value >= minimumBet, "Bet too low");
        require(isBettingAllowed(_gameContract, _gameId), "Betting not allowed");

        bool validPlayer = false;
        try IZeroSumGame(_gameContract).getGameForSpectators(_gameId) returns (
            GameStatus status,
            address, /* winner */
            address[] memory players,
            uint256, /* currentNumber */
            bool, /* numberGenerated */
            address, /* currentPlayer */
            uint256 /* mode */
        ) {
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

        bytes32 gameKey = _getGameKey(_gameContract, _gameId);

        gameBets[gameKey].push(
            Bet({
                bettor: msg.sender,
                gameId: _gameId,
                predictedWinner: _predictedWinner,
                amount: msg.value,
                claimed: false,
                gameContract: _gameContract
            })
        );

        totalBetsOnPlayer[gameKey][_predictedWinner] += msg.value;
        totalGameBets[gameKey] += msg.value;

        emit BetPlaced(_gameContract, _gameId, msg.sender, msg.value);
    }

    function claimBettingWinnings(address _gameContract, uint256 _gameId) external nonReentrant {
        require(registeredContracts[_gameContract], "Not registered");

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

        uint256 totalWinnings = 0;
        bytes32 gameKey = _getGameKey(_gameContract, _gameId);
        Bet[] storage bets = gameBets[gameKey];

        for (uint256 i = 0; i < bets.length; i++) {
            if (bets[i].bettor == msg.sender && bets[i].predictedWinner == actualWinner && !bets[i].claimed) {
                bets[i].claimed = true;

                uint256 winnerPool = totalBetsOnPlayer[gameKey][actualWinner];
                if (winnerPool > 0) {
                    uint256 betShare = (bets[i].amount * 10000) / winnerPool;
                    uint256 totalPrizePool = (totalGameBets[gameKey] * (100 - bettingFeePercent)) / 100;
                    totalWinnings += (totalPrizePool * betShare) / 10000;
                }
            }
        }

        require(totalWinnings > 0, "No winnings");
        spectatorBalances[msg.sender] += totalWinnings;
        emit BetsClaimed(_gameContract, _gameId, msg.sender, totalWinnings);
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
