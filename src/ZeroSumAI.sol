// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ZeroSumAI
 * @dev AI player management for Lucky Draw games and automated gameplay
 */
contract ZeroSumAI is Ownable {
    struct AIPlayer {
        string name;
        uint256 skillLevel; // 1-100
        string personality;
        bool isActive;
        address playerAddress; // Dedicated address for this AI
        uint256 gamesPlayed;
        uint256 gamesWon;
        uint256 totalEarnings;
        uint256 createdAt;
    }

    struct AIMove {
        uint256 gameId;
        uint256 aiPlayerId;
        uint256 subtraction;
        uint256 timestamp;
        string reasoning; // AI's explanation for the move
        uint256 numberBefore;
        uint256 numberAfter;
    }

    struct AIStrategy {
        uint256 aiPlayerId;
        string strategyName;
        uint256 aggressiveness; // 1-100
        uint256 riskTolerance; // 1-100
        bool prefersEarlyGame; // True if AI plays aggressively early
        bool avoidsZero; // True if AI tries to avoid reaching zero
    }

    // Core mappings
    mapping(uint256 => AIPlayer) public aiPlayers;
    mapping(address => uint256) public addressToAIId;
    mapping(uint256 => uint256[]) public gameAIPlayers; // gameId => aiPlayerIds
    mapping(uint256 => AIMove[]) public aiMoveHistory;
    mapping(uint256 => mapping(uint256 => bool)) public isAIInGame; // gameId => aiId => bool
    mapping(uint256 => AIStrategy) public aiStrategies;

    // Game state for AI decisions
    mapping(uint256 => uint256) public aiGameStates; // gameId => current number
    mapping(uint256 => address) public aiGameCurrentPlayer; // gameId => current player

    address public gameContract;
    uint256 public aiPlayerCounter;
    address public aiBackendSigner; // Address that signs AI moves

    // AI earnings tracking
    mapping(uint256 => uint256) public aiTotalEarnings;
    mapping(uint256 => uint256) public aiAvailableBalance;

    // Events
    event AIPlayerCreated(uint256 indexed aiPlayerId, string name, uint256 skillLevel, address playerAddress);
    event AIMoveExecuted(uint256 indexed gameId, uint256 indexed aiPlayerId, uint256 subtraction, string reasoning);
    event AIGameFinished(uint256 indexed gameId, uint256 indexed winnerAIId, uint256 earnings);
    event AIBackendSignerUpdated(address newSigner);
    event AIStrategyUpdated(uint256 indexed aiPlayerId, string strategyName);
    event AIEarningsWithdrawn(uint256 indexed aiPlayerId, uint256 amount);
    event AIMoveSuggestion(uint256 indexed gameId, uint256 indexed aiPlayerId, uint256 suggestedMove, string reasoning);

    constructor(address _gameContract, address _aiBackendSigner) Ownable(msg.sender) {
        gameContract = _gameContract;
        aiBackendSigner = _aiBackendSigner;
        _createDefaultAIPlayers();
    }

    function _createDefaultAIPlayers() internal {
        _createAIPlayer("Calculus Cat", 90, "Mathematical genius who calculates optimal moves");
        _createAIPlayer("Random Rick", 30, "Chaotic player who makes wild, unpredictable moves");
        _createAIPlayer("Steady Steve", 60, "Conservative player with consistent, safe strategy");
        _createAIPlayer("Risky Rita", 45, "High-risk, high-reward gambler who goes for big plays");
        _createAIPlayer("Perfect Petra", 95, "Near-perfect AI that almost never makes mistakes");
        _createAIPlayer("Newbie Nancy", 20, "Beginner AI that makes obvious mistakes");
        _createAIPlayer("Adaptive Alex", 75, "AI that adapts strategy based on opponent behavior");
        _createAIPlayer("Bluff Betty", 65, "AI that tries to mislead opponents with unexpected moves");
    }

    function _createAIPlayer(string memory _name, uint256 _skillLevel, string memory _personality) internal {
        aiPlayerCounter++;

        // Create deterministic address for AI player
        address aiAddress =
            address(uint160(uint256(keccak256(abi.encodePacked("ZeroSumAI", aiPlayerCounter, block.timestamp)))));

        aiPlayers[aiPlayerCounter] = AIPlayer({
            name: _name,
            skillLevel: _skillLevel,
            personality: _personality,
            isActive: true,
            playerAddress: aiAddress,
            gamesPlayed: 0,
            gamesWon: 0,
            totalEarnings: 0,
            createdAt: block.timestamp
        });

        addressToAIId[aiAddress] = aiPlayerCounter;

        // Set default strategy
        _setDefaultStrategy(aiPlayerCounter, _skillLevel);

        emit AIPlayerCreated(aiPlayerCounter, _name, _skillLevel, aiAddress);
    }

    function _setDefaultStrategy(uint256 _aiPlayerId, uint256 _skillLevel) internal {
        AIStrategy memory strategy;
        strategy.aiPlayerId = _aiPlayerId;

        if (_skillLevel >= 90) {
            strategy.strategyName = "Optimal";
            strategy.aggressiveness = 70;
            strategy.riskTolerance = 30;
            strategy.prefersEarlyGame = false;
            strategy.avoidsZero = true;
        } else if (_skillLevel >= 70) {
            strategy.strategyName = "Adaptive";
            strategy.aggressiveness = 60;
            strategy.riskTolerance = 50;
            strategy.prefersEarlyGame = true;
            strategy.avoidsZero = true;
        } else if (_skillLevel >= 50) {
            strategy.strategyName = "Balanced";
            strategy.aggressiveness = 50;
            strategy.riskTolerance = 50;
            strategy.prefersEarlyGame = false;
            strategy.avoidsZero = false;
        } else if (_skillLevel >= 30) {
            strategy.strategyName = "Random";
            strategy.aggressiveness = 80;
            strategy.riskTolerance = 80;
            strategy.prefersEarlyGame = true;
            strategy.avoidsZero = false;
        } else {
            strategy.strategyName = "Beginner";
            strategy.aggressiveness = 90;
            strategy.riskTolerance = 90;
            strategy.prefersEarlyGame = true;
            strategy.avoidsZero = false;
        }

        aiStrategies[_aiPlayerId] = strategy;
    }

    // ================== AI PLAYER MANAGEMENT ==================

    function createCustomAIPlayer(string memory _name, uint256 _skillLevel, string memory _personality)
        external
        onlyOwner
        returns (uint256)
    {
        require(_skillLevel >= 1 && _skillLevel <= 100, "Invalid skill level");
        _createAIPlayer(_name, _skillLevel, _personality);
        return aiPlayerCounter;
    }

    function updateAIPlayer(
        uint256 _aiPlayerId,
        string memory _name,
        uint256 _skillLevel,
        string memory _personality,
        bool _isActive
    ) external onlyOwner {
        require(_aiPlayerId <= aiPlayerCounter, "AI player does not exist");
        require(_skillLevel >= 1 && _skillLevel <= 100, "Invalid skill level");

        AIPlayer storage ai = aiPlayers[_aiPlayerId];
        ai.name = _name;
        ai.skillLevel = _skillLevel;
        ai.personality = _personality;
        ai.isActive = _isActive;
    }

    function updateAIStrategy(
        uint256 _aiPlayerId,
        string memory _strategyName,
        uint256 _aggressiveness,
        uint256 _riskTolerance,
        bool _prefersEarlyGame,
        bool _avoidsZero
    ) external onlyOwner {
        require(_aiPlayerId <= aiPlayerCounter, "AI player does not exist");
        require(_aggressiveness <= 100 && _riskTolerance <= 100, "Invalid strategy parameters");

        aiStrategies[_aiPlayerId] = AIStrategy({
            aiPlayerId: _aiPlayerId,
            strategyName: _strategyName,
            aggressiveness: _aggressiveness,
            riskTolerance: _riskTolerance,
            prefersEarlyGame: _prefersEarlyGame,
            avoidsZero: _avoidsZero
        });

        emit AIStrategyUpdated(_aiPlayerId, _strategyName);
    }

    // ================== GAME INTEGRATION ==================

    function addAIToGame(uint256 _gameId, uint256 _aiPlayerId) external onlyOwner {
        require(aiPlayers[_aiPlayerId].isActive, "AI player not active");
        require(!isAIInGame[_gameId][_aiPlayerId], "AI already in this game");

        gameAIPlayers[_gameId].push(_aiPlayerId);
        isAIInGame[_gameId][_aiPlayerId] = true;

        aiPlayers[_aiPlayerId].gamesPlayed++;
    }

    function removeAIFromGame(uint256 _gameId, uint256 _aiPlayerId) external onlyOwner {
        require(isAIInGame[_gameId][_aiPlayerId], "AI not in this game");

        // Remove from gameAIPlayers array
        uint256[] storage ais = gameAIPlayers[_gameId];
        for (uint256 i = 0; i < ais.length; i++) {
            if (ais[i] == _aiPlayerId) {
                ais[i] = ais[ais.length - 1];
                ais.pop();
                break;
            }
        }

        isAIInGame[_gameId][_aiPlayerId] = false;
    }

    function updateGameState(uint256 _gameId, uint256 _currentNumber, address _currentPlayer) external {
        require(msg.sender == gameContract || msg.sender == owner(), "Not authorized");

        aiGameStates[_gameId] = _currentNumber;
        aiGameCurrentPlayer[_gameId] = _currentPlayer;
    }

    // ================== AI MOVE CALCULATION ==================

    function calculateAIMove(uint256 _gameId, uint256 _aiPlayerId)
        external
        view
        returns (uint256 suggestedMove, string memory reasoning)
    {
        require(aiPlayers[_aiPlayerId].isActive, "AI player not active");
        require(isAIInGame[_gameId][_aiPlayerId], "AI not in this game");

        uint256 currentNumber = aiGameStates[_gameId];
        require(currentNumber > 0, "Invalid game state");

        AIPlayer memory ai = aiPlayers[_aiPlayerId];
        AIStrategy memory strategy = aiStrategies[_aiPlayerId];

        return _calculateOptimalMove(currentNumber, ai, strategy);
    }

    function _calculateOptimalMove(uint256 _currentNumber, AIPlayer memory _ai, AIStrategy memory _strategy)
        internal
        view
        returns (uint256 move, string memory reasoning)
    {
        // High skill AIs use mathematical approach
        if (_ai.skillLevel >= 80) {
            return _calculateOptimalMathMove(_currentNumber, _strategy);
        }
        // Medium skill AIs use heuristics
        else if (_ai.skillLevel >= 50) {
            return _calculateHeuristicMove(_currentNumber, _strategy);
        }
        // Low skill AIs use random/simple logic
        else {
            return _calculateRandomMove(_currentNumber, _strategy);
        }
    }

    function _calculateOptimalMathMove(uint256 _currentNumber, AIStrategy memory _strategy)
        internal
        view
        returns (uint256 move, string memory reasoning)
    {
        // Try to leave opponent in losing position
        // For numbers that are multiples of certain patterns

        if (_currentNumber <= 3) {
            move = _currentNumber - 1;
            reasoning = "Optimal: Force opponent to face 1";
        } else if (_currentNumber % 4 == 1) {
            move = (_currentNumber * 20) / 100; // 20% when at disadvantage
            reasoning = "Optimal: Take 20% to maintain winning position";
        } else {
            move = _currentNumber % 4;
            if (move == 0) move = 1;
            reasoning = "Optimal: Move to put opponent in losing position";
        }

        // Ensure move is valid (at least 1, at most current number)
        if (move == 0) move = 1;
        if (move > _currentNumber) move = _currentNumber;
    }

    function _calculateHeuristicMove(uint256 _currentNumber, AIStrategy memory _strategy)
        internal
        view
        returns (uint256 move, string memory reasoning)
    {
        uint256 seed = uint256(keccak256(abi.encodePacked(block.timestamp, _currentNumber)));

        if (_strategy.avoidsZero && _currentNumber <= 5) {
            move = 1; // Play safe when close to zero
            reasoning = "Heuristic: Playing safe near zero";
        } else if (_strategy.prefersEarlyGame && _currentNumber > 50) {
            move = (_currentNumber * _strategy.aggressiveness) / 100;
            reasoning = "Heuristic: Aggressive early game play";
        } else {
            // Balanced approach
            uint256 percentage = 15 + (seed % 20); // 15-35%
            move = (_currentNumber * percentage) / 100;
            if (move == 0) move = 1;
            reasoning = "Heuristic: Balanced percentage play";
        }

        if (move > _currentNumber) move = _currentNumber;
    }

    function _calculateRandomMove(uint256 _currentNumber, AIStrategy memory _strategy)
        internal
        view
        returns (uint256 move, string memory reasoning)
    {
        uint256 seed = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, _currentNumber)));

        if (_strategy.riskTolerance >= 70) {
            // High risk - random large moves
            move = 1 + (seed % _currentNumber);
            reasoning = "Random: High risk random move";
        } else {
            // Low risk - smaller random moves
            uint256 maxMove = (_currentNumber * 30) / 100;
            if (maxMove == 0) maxMove = 1;
            move = 1 + (seed % maxMove);
            reasoning = "Random: Conservative random move";
        }

        if (move > _currentNumber) move = _currentNumber;
    }

    // ================== AI MOVE EXECUTION ==================

    function executeAIMove(uint256 _gameId, uint256 _aiPlayerId, uint256 _subtraction, bytes memory _signature)
        external
    {
        require(_verifyAISignature(_gameId, _aiPlayerId, _subtraction, _signature), "Invalid AI signature");
        require(isAIInGame[_gameId][_aiPlayerId], "AI not in this game");

        AIPlayer storage ai = aiPlayers[_aiPlayerId];
        uint256 numberBefore = aiGameStates[_gameId];
        uint256 numberAfter = numberBefore - _subtraction;

        // Record the move
        (uint256 calculatedMove, string memory reasoning) =
            _calculateOptimalMove(numberBefore, ai, aiStrategies[_aiPlayerId]);

        aiMoveHistory[_gameId].push(
            AIMove({
                gameId: _gameId,
                aiPlayerId: _aiPlayerId,
                subtraction: _subtraction,
                timestamp: block.timestamp,
                reasoning: reasoning,
                numberBefore: numberBefore,
                numberAfter: numberAfter
            })
        );

        // Update game state
        aiGameStates[_gameId] = numberAfter;

        emit AIMoveExecuted(_gameId, _aiPlayerId, _subtraction, reasoning);
    }

    function recordAIGameResult(uint256 _gameId, uint256 _winnerAIId, uint256 _earnings) external {
        require(msg.sender == gameContract || msg.sender == owner(), "Not authorized");
        require(isAIInGame[_gameId][_winnerAIId], "AI not in this game");

        AIPlayer storage winner = aiPlayers[_winnerAIId];
        winner.gamesWon++;
        winner.totalEarnings += _earnings;

        aiTotalEarnings[_winnerAIId] += _earnings;
        aiAvailableBalance[_winnerAIId] += _earnings;

        emit AIGameFinished(_gameId, _winnerAIId, _earnings);
    }

    // ================== AI SUGGESTIONS FOR HUMAN PLAYERS ==================

    function getAIMoveAdvice(uint256 _gameId, uint256 _advisorAIId)
        external
        view
        returns (uint256 suggestedMove, string memory reasoning, uint256 confidence)
    {
        require(aiPlayers[_advisorAIId].isActive, "AI advisor not active");

        uint256 currentNumber = aiGameStates[_gameId];
        AIPlayer memory advisor = aiPlayers[_advisorAIId];
        AIStrategy memory strategy = aiStrategies[_advisorAIId];

        (suggestedMove, reasoning) = _calculateOptimalMove(currentNumber, advisor, strategy);
        confidence = advisor.skillLevel;

        return (suggestedMove, reasoning, confidence);
    }

    function getMultipleAIAdvice(uint256 _gameId)
        external
        view
        returns (
            uint256[] memory aiIds,
            uint256[] memory suggestedMoves,
            string[] memory reasonings,
            uint256[] memory confidences
        )
    {
        uint256 activeAICount = 0;

        // Count active AIs
        for (uint256 i = 1; i <= aiPlayerCounter; i++) {
            if (aiPlayers[i].isActive) {
                activeAICount++;
            }
        }

        aiIds = new uint256[](activeAICount);
        suggestedMoves = new uint256[](activeAICount);
        reasonings = new string[](activeAICount);
        confidences = new uint256[](activeAICount);

        uint256 index = 0;
        uint256 currentNumber = aiGameStates[_gameId];

        for (uint256 i = 1; i <= aiPlayerCounter; i++) {
            if (aiPlayers[i].isActive) {
                aiIds[index] = i;
                (suggestedMoves[index], reasonings[index]) =
                    _calculateOptimalMove(currentNumber, aiPlayers[i], aiStrategies[i]);
                confidences[index] = aiPlayers[i].skillLevel;
                index++;
            }
        }
    }

    // ================== AI EARNINGS MANAGEMENT ==================

    function withdrawAIEarnings(uint256 _aiPlayerId, uint256 _amount) external onlyOwner {
        require(aiAvailableBalance[_aiPlayerId] >= _amount, "Insufficient AI balance");

        aiAvailableBalance[_aiPlayerId] -= _amount;

        // Transfer to owner (representing the AI's earnings)
        (bool success,) = payable(owner()).call{value: _amount}("");
        require(success, "AI earnings withdrawal failed");

        emit AIEarningsWithdrawn(_aiPlayerId, _amount);
    }

    function fundAIPlayer(uint256 _aiPlayerId) external payable onlyOwner {
        require(aiPlayers[_aiPlayerId].isActive, "AI player not active");
        aiAvailableBalance[_aiPlayerId] += msg.value;
    }

    // ================== SIGNATURE VERIFICATION ==================

    function _verifyAISignature(uint256 _gameId, uint256 _aiPlayerId, uint256 _subtraction, bytes memory _signature)
        internal
        view
        returns (bool)
    {
        bytes32 hash = keccak256(abi.encodePacked(_gameId, _aiPlayerId, _subtraction, address(this)));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));

        (bytes32 r, bytes32 s, uint8 v) = _splitSignature(_signature);
        address recovered = ecrecover(ethSignedMessageHash, v, r, s);

        return recovered == aiBackendSigner;
    }

    function _splitSignature(bytes memory _signature) internal pure returns (bytes32 r, bytes32 s, uint8 v) {
        require(_signature.length == 65, "Invalid signature length");

        assembly {
            r := mload(add(_signature, 32))
            s := mload(add(_signature, 64))
            v := byte(0, mload(add(_signature, 96)))
        }
    }

    function setAIBackendSigner(address _newSigner) external onlyOwner {
        aiBackendSigner = _newSigner;
        emit AIBackendSignerUpdated(_newSigner);
    }

    // ================== VIEW FUNCTIONS ==================

    function getAIPlayer(uint256 _aiPlayerId) external view returns (AIPlayer memory) {
        return aiPlayers[_aiPlayerId];
    }

    function getAIStrategy(uint256 _aiPlayerId) external view returns (AIStrategy memory) {
        return aiStrategies[_aiPlayerId];
    }

    function getAllAIPlayers() external view returns (AIPlayer[] memory) {
        AIPlayer[] memory allAIs = new AIPlayer[](aiPlayerCounter);
        for (uint256 i = 1; i <= aiPlayerCounter; i++) {
            allAIs[i - 1] = aiPlayers[i];
        }
        return allAIs;
    }

    function getActiveAIPlayers() external view returns (AIPlayer[] memory) {
        // Count active AIs first
        uint256 activeCount = 0;
        for (uint256 i = 1; i <= aiPlayerCounter; i++) {
            if (aiPlayers[i].isActive) {
                activeCount++;
            }
        }

        // Create array with active AIs
        AIPlayer[] memory activeAIs = new AIPlayer[](activeCount);
        uint256 index = 0;
        for (uint256 i = 1; i <= aiPlayerCounter; i++) {
            if (aiPlayers[i].isActive) {
                activeAIs[index] = aiPlayers[i];
                index++;
            }
        }

        return activeAIs;
    }

    function getGameAIPlayers(uint256 _gameId) external view returns (uint256[] memory) {
        return gameAIPlayers[_gameId];
    }

    function getAIMoveHistory(uint256 _gameId) external view returns (AIMove[] memory) {
        return aiMoveHistory[_gameId];
    }

    function getAIStats(uint256 _aiPlayerId)
        external
        view
        returns (
            uint256 gamesPlayed,
            uint256 gamesWon,
            uint256 winRate,
            uint256 totalEarnings,
            uint256 availableBalance,
            uint256 skillLevel
        )
    {
        AIPlayer memory ai = aiPlayers[_aiPlayerId];

        gamesPlayed = ai.gamesPlayed;
        gamesWon = ai.gamesWon;
        winRate = gamesPlayed > 0 ? (gamesWon * 100) / gamesPlayed : 0;
        totalEarnings = ai.totalEarnings;
        availableBalance = aiAvailableBalance[_aiPlayerId];
        skillLevel = ai.skillLevel;
    }

    function getAILeaderboard()
        external
        view
        returns (
            uint256[] memory aiIds,
            string[] memory names,
            uint256[] memory winRates,
            uint256[] memory totalEarnings
        )
    {
        uint256 activeCount = 0;
        for (uint256 i = 1; i <= aiPlayerCounter; i++) {
            if (aiPlayers[i].isActive && aiPlayers[i].gamesPlayed > 0) {
                activeCount++;
            }
        }

        aiIds = new uint256[](activeCount);
        names = new string[](activeCount);
        winRates = new uint256[](activeCount);
        totalEarnings = new uint256[](activeCount);

        uint256 index = 0;
        for (uint256 i = 1; i <= aiPlayerCounter; i++) {
            if (aiPlayers[i].isActive && aiPlayers[i].gamesPlayed > 0) {
                AIPlayer memory ai = aiPlayers[i];

                aiIds[index] = i;
                names[index] = ai.name;
                winRates[index] = (ai.gamesWon * 100) / ai.gamesPlayed;
                totalEarnings[index] = ai.totalEarnings;
                index++;
            }
        }

        // Simple bubble sort by win rate (for small arrays)
        for (uint256 i = 0; i < activeCount - 1; i++) {
            for (uint256 j = 0; j < activeCount - i - 1; j++) {
                if (winRates[j] < winRates[j + 1]) {
                    // Swap all arrays
                    (aiIds[j], aiIds[j + 1]) = (aiIds[j + 1], aiIds[j]);
                    (names[j], names[j + 1]) = (names[j + 1], names[j]);
                    (winRates[j], winRates[j + 1]) = (winRates[j + 1], winRates[j]);
                    (totalEarnings[j], totalEarnings[j + 1]) = (totalEarnings[j + 1], totalEarnings[j]);
                }
            }
        }
    }

    // ================== ADMIN FUNCTIONS ==================

    function setGameContract(address _gameContract) external onlyOwner {
        gameContract = _gameContract;
    }

    function emergencyWithdraw() external onlyOwner {
        (bool success,) = payable(owner()).call{value: address(this).balance}("");
        require(success, "Emergency withdrawal failed");
    }

    function bulkUpdateAIActivity(uint256[] memory _aiIds, bool[] memory _activities) external onlyOwner {
        require(_aiIds.length == _activities.length, "Array length mismatch");

        for (uint256 i = 0; i < _aiIds.length; i++) {
            require(_aiIds[i] <= aiPlayerCounter, "Invalid AI ID");
            aiPlayers[_aiIds[i]].isActive = _activities[i];
        }
    }
}
