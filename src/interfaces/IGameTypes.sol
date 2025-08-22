// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

enum GameMode {
    HARDCORE_MYSTERY,
    LAST_STAND
}

enum GameStatus {
    WAITING,
    ACTIVE,
    FINISHED
}

enum MoveResult {
    MOVE_ACCEPTED,
    GAME_WON,
    GAME_LOST
}

struct Game {
    uint256 gameId;
    GameMode mode;
    uint256 actualNumber; // ALWAYS 0 - Never reveals true number
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
