// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {GameStatus, Game, StakingInfo, GameMode} from "../ZeroSumSimplified.sol";

library SimplifiedLibrary {
    
    function calculateBettingFee(uint256 amount, uint256 feePercent) internal pure returns (uint256) {
        return (amount * feePercent) / 100;
    }

    function isValidBetAmount(uint256 amount, uint256 minimumBet) internal pure returns (bool) {
        return amount >= minimumBet;
    }

    function getGameForSpectators(
        mapping(uint256 => Game) storage games,
        uint256 _id,
        mapping(uint256 => address[]) storage gamePlayers
    )
        internal
        view
        returns (
            GameStatus status,
            address winner,
            address[] memory players,
            uint256 currentNumber,
            bool numberGenerated,
            address currentPlayer,
            uint256 mode
        )
    {
        Game memory g = games[_id];
        address[] memory _gamePlayers = gamePlayers[_id];

        return (
            g.status,
            g.winner,
            _gamePlayers,
            g.numberGenerated ? g.currentNumber : 0,
            g.numberGenerated,
            g.currentPlayer,
            uint256(g.mode)
        );
    }

    function stake(mapping(address => StakingInfo) storage staking, uint256 value) internal {
        require(value > 0, "Must stake");

        StakingInfo storage s = staking[msg.sender];

        if (s.amount > 0) {
            uint256 pending = _calcRewards(s);
            s.rewards += pending;
        }

        s.amount += msg.value;
        s.lastReward = block.timestamp;
    }

    function _calcRewards(StakingInfo memory s) internal view returns (uint256) {
        uint256 stakingAPY = 1000;
        if (s.amount == 0) return 0;

        uint256 time = block.timestamp - s.lastReward;
        uint256 annual = (s.amount * stakingAPY) / 10000;
        return (annual * time) / 365 days;
    }

    function unstake(mapping(address => StakingInfo) storage staking, uint256 amount) internal {
        StakingInfo storage s = staking[msg.sender];
        require(s.amount >= amount, "Insufficient staked amount");

        uint256 pending = _calcRewards(s);
        s.rewards += pending;
        s.amount -= amount;
        s.lastReward = block.timestamp;
    }

    function _calcRewards(mapping(address => StakingInfo) storage staking) internal {
        StakingInfo storage s = staking[msg.sender];

        uint256 pending = _calcRewards(s);
        uint256 total = s.rewards + pending;
        require(total > 0, "No rewards");

        s.rewards = 0;
        s.lastReward = block.timestamp;

        (bool success,) = payable(msg.sender).call{value: total}("");
        require(success, "Failed");
    }

    // ✅ FIXED: Prevent double-counting money
    function _createGame(
        GameMode _mode,
        uint256 id,
        mapping(uint256 => Game) storage games,
        mapping(uint256 => mapping(address => uint256)) storage playerTimeouts,
        mapping(uint256 => mapping(address => bool)) storage isInGame,
        mapping(uint256 => address[]) storage gamePlayers,
        mapping(address => uint256) storage played,
        mapping(uint256 => uint256) storage turnDeadlines
    ) internal {
        // ✅ START WITH PRIZE POOL = 0 (no double counting)
        games[id] = Game({
            gameId: id,
            mode: _mode,
            currentNumber: 0,
            currentPlayer: address(0),
            status: GameStatus.WAITING,
            entryFee: msg.value,
            prizePool: 0,  // ✅ FIXED: Start at 0, _joinGame will add money
            winner: address(0),
            numberGenerated: false
        });

        // Reset timeout counters for creator
        playerTimeouts[id][msg.sender] = 0;

        // Join the game (this will add msg.value to prizePool correctly)
        _joinGame(id, msg.sender, games, isInGame, gamePlayers, played, playerTimeouts, turnDeadlines);
    }

    function _joinGame(
        uint256 _id,
        address _player,
        mapping(uint256 => Game) storage games,
        mapping(uint256 => mapping(address => bool)) storage isInGame,
        mapping(uint256 => address[]) storage gamePlayers,
        mapping(address => uint256) storage played,
        mapping(uint256 => mapping(address => uint256)) storage playerTimeouts,
        mapping(uint256 => uint256) storage turnDeadlines
    ) internal {
        Game storage g = games[_id];
        require(g.status == GameStatus.WAITING, "Cannot join");
        require(msg.value == g.entryFee, "Wrong fee");

        // ✅ ADD PROPER VALIDATION
        require(!isInGame[_id][_player], "Already in game");
        require(gamePlayers[_id].length < 2, "Game is full");

        gamePlayers[_id].push(_player);
        g.prizePool += msg.value;  // ✅ This now correctly adds money only once
        isInGame[_id][_player] = true;
        played[_player]++;

        // Reset timeout counter for joining player
        playerTimeouts[_id][_player] = 0;

        // Generate number only when both players join
        if (gamePlayers[_id].length == 2) {
            _startGame(_id, games, gamePlayers, turnDeadlines);
        }
    }

    function _startGame(
        uint256 _id,
        mapping(uint256 => Game) storage games,
        mapping(uint256 => address[]) storage gamePlayers,
        mapping(uint256 => uint256) storage turnDeadlines
    ) internal {
        Game storage g = games[_id];
        uint256 timeLimit = 300;

        // Generate number using both players for fairness
        uint256 startNum = _generateNumber(_id, g.mode, gamePlayers);
        g.currentNumber = startNum;
        g.numberGenerated = true;
        g.status = GameStatus.ACTIVE;
        g.currentPlayer = gamePlayers[_id][0];
        turnDeadlines[_id] = block.timestamp + timeLimit;
    }

    function _generateNumber(uint256 _id, GameMode _mode, mapping(uint256 => address[]) storage gamePlayers)
        internal
        view
        returns (uint256)
    {
        uint256 SALT = 0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890;
        address[] memory players = gamePlayers[_id];

        uint256 entropy =
            uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, _id, players[0], players[1], SALT)));

        return _mode == GameMode.QUICK_DRAW ? 15 + (entropy % 35) : 80 + (entropy % 120);
    }
}