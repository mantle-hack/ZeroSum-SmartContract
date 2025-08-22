// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ZeroSumTournament - ULTRA OPTIMIZED UNDER 24KB
 * @dev Tournament management - size optimized
 */
contract ZeroSumTournament is ReentrancyGuard, Ownable {
    enum Status {
        REG,
        ACTIVE,
        FINISHED,
        CANCELLED
    }
    enum Mode {
        QUICK_DRAW,
        STRATEGIC,
        HARDCORE_MYSTERY,
        LAST_STAND
    }

    struct Tournament {
        uint64 id;
        uint64 entryFee;
        uint32 maxParticipants;
        uint64 prizePool;
        uint32 deadline;
        Status status;
        Mode mode;
        uint8 currentRound;
        uint8 totalRounds;
        address winner;
    }

    struct Match {
        address p1;
        address p2;
        address winner;
        bool done;
    }

    // Core mappings
    mapping(uint256 => Tournament) public tournaments;
    mapping(uint256 => address[]) public participants;
    mapping(uint256 => mapping(uint256 => Match[])) public matches;
    mapping(uint256 => mapping(address => bool)) public joined;

    // Stats
    mapping(address => uint256) public won;
    mapping(address => uint256) public played;
    mapping(address => uint256) public earnings;

    // Settings
    uint256 public counter;
    uint256 public fee = 10;
    uint256 public minPart = 4;
    uint256 public maxPart = 64;

    // Events
    event Created(uint256 indexed id, Mode mode, uint256 entryFee, uint256 maxPart);
    event Joined(uint256 indexed id, address indexed player);
    event Started(uint256 indexed id, uint256 participants);
    event Finished(uint256 indexed id, address indexed winner, uint256 prize);
    event MatchDone(uint256 indexed id, uint256 round, address winner, address loser);

    constructor() Ownable(msg.sender) {
        _createDefaults();
    }

    function _createDefaults() internal {
        _create("Hardcore Cup", 0.001 ether, 4, Mode.HARDCORE_MYSTERY, 24);
    }

    // ================== CREATION ==================

    function create(string memory _name, uint256 _fee, uint256 _maxPart, Mode _mode, uint256 _hours)
        external
        onlyOwner
        returns (uint256)
    {
        return _create(_name, _fee, _maxPart, _mode, _hours);
    }

    function _create(
        string memory, // name - not stored to save space
        uint256 _fee,
        uint256 _maxPart,
        Mode _mode,
        uint256 _hours
    ) internal returns (uint256) {
        require(_maxPart >= minPart && _maxPart <= maxPart, "Invalid size");
        require(_isPowerOfTwo(_maxPart), "Must be power of 2");
        require(_hours >= 1 && _hours <= 168, "Invalid time");
        require(_fee > 0, "Fee required");

        counter++;

        tournaments[counter] = Tournament({
            id: uint64(counter),
            entryFee: uint64(_fee),
            maxParticipants: uint32(_maxPart),
            prizePool: 0,
            deadline: uint32(block.timestamp + (_hours * 1 hours)),
            status: Status.REG,
            mode: _mode,
            currentRound: 0,
            totalRounds: uint8(_calcRounds(_maxPart)),
            winner: address(0)
        });

        emit Created(counter, _mode, _fee, _maxPart);
        return counter;
    }

    // ================== JOINING ==================

    function join(uint256 _id) external payable nonReentrant {
        Tournament storage t = tournaments[_id];
        require(t.id != 0, "Not found");
        require(t.status == Status.REG, "Closed");
        require(block.timestamp <= t.deadline, "Expired");
        require(participants[_id].length < t.maxParticipants, "Full");
        require(msg.value == t.entryFee, "Wrong fee");
        require(!joined[_id][msg.sender], "Already joined");

        participants[_id].push(msg.sender);
        t.prizePool += uint64(msg.value);
        joined[_id][msg.sender] = true;
        played[msg.sender]++;

        emit Joined(_id, msg.sender);

        if (participants[_id].length == t.maxParticipants) {
            _start(_id);
        }
    }

    function _start(uint256 _id) internal {
        Tournament storage t = tournaments[_id];
        t.status = Status.ACTIVE;
        t.currentRound = 1;

        emit Started(_id, participants[_id].length);
        _createRound1(_id);
    }

    function _createRound1(uint256 _id) internal {
        address[] memory players = participants[_id];

        for (uint256 i = 0; i < players.length; i += 2) {
            matches[_id][1].push(Match({p1: players[i], p2: players[i + 1], winner: address(0), done: false}));
        }
    }

    // ================== MATCH RECORDING ==================

    function recordResult(uint256 _id, uint256 _round, uint256 _matchIdx, address _winner) external onlyOwner {
        Tournament storage t = tournaments[_id];
        require(t.status == Status.ACTIVE, "Not active");
        require(_round == t.currentRound, "Wrong round");

        Match storage m = matches[_id][_round][_matchIdx];
        require(!m.done, "Done");
        require(_winner == m.p1 || _winner == m.p2, "Invalid");

        m.winner = _winner;
        m.done = true;

        address loser = (_winner == m.p1) ? m.p2 : m.p1;
        emit MatchDone(_id, _round, _winner, loser);

        _checkRoundDone(_id, _round);
    }

    function _checkRoundDone(uint256 _id, uint256 _round) internal {
        Match[] storage roundMatches = matches[_id][_round];

        for (uint256 i = 0; i < roundMatches.length; i++) {
            if (!roundMatches[i].done) return;
        }

        address[] memory winners = new address[](roundMatches.length);
        for (uint256 i = 0; i < roundMatches.length; i++) {
            winners[i] = roundMatches[i].winner;
        }

        Tournament storage t = tournaments[_id];

        if (_round == t.totalRounds) {
            _finish(_id, winners[0]);
        } else {
            t.currentRound++;
            _createNextRound(_id, winners, t.currentRound);
        }
    }

    function _createNextRound(uint256 _id, address[] memory _winners, uint256 _round) internal {
        for (uint256 i = 0; i < _winners.length; i += 2) {
            matches[_id][_round].push(Match({p1: _winners[i], p2: _winners[i + 1], winner: address(0), done: false}));
        }
    }

    // ================== COMPLETION ==================

    function _finish(uint256 _id, address _winner) internal {
        Tournament storage t = tournaments[_id];
        t.winner = _winner;
        t.status = Status.FINISHED;

        won[_winner]++;

        uint256 platformFee = (t.prizePool * fee) / 100;
        uint256 prize = t.prizePool - platformFee;

        earnings[_winner] += prize;

        (bool success,) = payable(_winner).call{value: prize}("");
        require(success, "Prize failed");

        if (platformFee > 0) {
            (success,) = payable(owner()).call{value: platformFee}("");
            require(success, "Fee failed");
        }

        emit Finished(_id, _winner, prize);
    }

    // ================== VIEW FUNCTIONS ==================

    function getTournament(uint256 _id) external view returns (Tournament memory) {
        return tournaments[_id];
    }

    function getParticipants(uint256 _id) external view returns (address[] memory) {
        return participants[_id];
    }

    function getRoundMatches(uint256 _id, uint256 _round) external view returns (Match[] memory) {
        return matches[_id][_round];
    }

    function getStats(address _player) external view returns (uint256, uint256, uint256, uint256) {
        return (
            played[_player],
            won[_player],
            earnings[_player],
            played[_player] > 0 ? (won[_player] * 100) / played[_player] : 0
        );
    }

    function getUpcoming() external view returns (uint256[] memory) {
        uint256 count = 0;
        for (uint256 i = 1; i <= counter; i++) {
            if (tournaments[i].status == Status.REG) count++;
        }

        uint256[] memory upcoming = new uint256[](count);
        uint256 idx = 0;
        for (uint256 i = 1; i <= counter; i++) {
            if (tournaments[i].status == Status.REG) {
                upcoming[idx] = i;
                idx++;
            }
        }
        return upcoming;
    }

    function getUIInfo(uint256 _id)
        external
        view
        returns (
            uint256 entryFee,
            uint256 prizePool,
            uint256 partCount,
            uint256 maxParticipants,
            uint256 timeLeft,
            Status status,
            Mode mode
        )
    {
        Tournament memory t = tournaments[_id];

        entryFee = t.entryFee;
        prizePool = t.prizePool;
        partCount = participants[_id].length;
        maxParticipants = t.maxParticipants;
        timeLeft = (t.status == Status.REG && block.timestamp < t.deadline) ? t.deadline - block.timestamp : 0;
        status = t.status;
        mode = t.mode;
    }

    // ================== UTILITIES ==================

    function _calcRounds(uint256 _participants) internal pure returns (uint256) {
        uint256 rounds = 0;
        uint256 remaining = _participants;
        while (remaining > 1) {
            remaining = remaining / 2;
            rounds++;
        }
        return rounds;
    }

    function _isPowerOfTwo(uint256 n) internal pure returns (bool) {
        return n > 0 && (n & (n - 1)) == 0;
    }

    // ================== ADMIN ==================

    function setFee(uint256 _fee) external onlyOwner {
        require(_fee <= 25, "Too high");
        fee = _fee;
    }

    function setLimits(uint256 _min, uint256 _max) external onlyOwner {
        require(_min >= 2 && _max <= 256, "Invalid");
        require(_isPowerOfTwo(_min) && _isPowerOfTwo(_max), "Power of 2");
        minPart = _min;
        maxPart = _max;
    }

    function cancel(uint256 _id) external onlyOwner {
        Tournament storage t = tournaments[_id];
        require(t.status == Status.REG, "Cannot cancel");

        t.status = Status.CANCELLED;

        address[] memory parts = participants[_id];
        uint256 entryFee = t.entryFee;

        for (uint256 i = 0; i < parts.length; i++) {
            played[parts[i]]--;
            (bool success,) = payable(parts[i]).call{value: entryFee}("");
            require(success, "Refund failed");
        }

        t.prizePool = 0;
    }

    function emergency() external onlyOwner {
        (bool success,) = payable(owner()).call{value: address(this).balance}("");
        require(success, "Failed");
    }
}