// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

contract Raffle is VRFConsumerBaseV2 {
    //errors
    error Raffle__NotEnoughEthSent();
    error Raffle__NotEnoughTimePassed();
    error Raffle__TransferFailed();
    error Raffle__RaffleClosed();
    error Raffle__UpkeepNotNeeded(
        uint256 currentBalance,
        uint256 numPlayers,
        uint256 raffleState
    );

    //type declarations
    enum LotteryState {
        OPEN,
        CALCULATING_WINNER
    }

    //state variables
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUMWORDS = 1;

    address owner;
    uint256 private ticketPrice;
    uint256 immutable i_interval;
    address payable[] private s_entrants;
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;
    LotteryState private s_lotteryState;

    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;

    //events
    event WinnerPicked(address winner, uint256 amount);
    event RaffleEntered(address indexed entrant);
    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 _ticketPrice,
        uint256 interval,
        address vrfcoordinator,
        bytes32 gasLane,
        uint64 subcriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2(vrfcoordinator) {
        owner = msg.sender;
        ticketPrice = _ticketPrice;
        i_interval = interval;
        s_lastTimeStamp = block.timestamp;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfcoordinator);
        i_gasLane = gasLane;
        i_subscriptionId = subcriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_lotteryState = LotteryState.OPEN;
    }

    function enterRaffle() public payable {
        if (msg.value < ticketPrice) {
            revert Raffle__NotEnoughEthSent();
        }
        if (s_lotteryState != LotteryState.OPEN) {
            revert Raffle__RaffleClosed();
        }
        s_entrants.push(payable(msg.sender));
        emit RaffleEntered(msg.sender);
    }

    /**
     * @dev This is the function that the Chainlink Keeper nodes call
     * they look for `upkeepNeeded` to return True.
     * the following should be true for this to return true:
     * 1. The time interval has passed between raffle runs.
     * 2. The lottery is open.
     * 3. The contract has ETH.
     * 4. Implicitly, your subscription is funded with LINK.
     */

    function checkUpkeep(
        bytes memory /* checkData */
    ) public view returns (bool upkeepNeeded, bytes memory /*performData*/) {
        bool timeHasPassed = ((block.timestamp - s_lastTimeStamp) >=
            i_interval);
        bool isOpen = (s_lotteryState == LotteryState.OPEN);
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_entrants.length > 0;
        //this will return upkeepNeeded due to the explicit declaration in the return statement above
        upkeepNeeded = timeHasPassed && isOpen && hasBalance && hasPlayers;
        return (upkeepNeeded, "");
    }

    function performUpkeep(bytes calldata /*performData*/) external {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_entrants.length,
                uint256(s_lotteryState)
            );
        }
        //set lottery state to calculating winner
        s_lotteryState = LotteryState.CALCULATING_WINNER;
        //pick winner
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane, //gas lane
            i_subscriptionId,
            REQUEST_CONFIRMATIONS, //block confirmations
            i_callbackGasLimit,
            NUMWORDS
        );
        emit RequestedRaffleWinner(requestId);
    }

    function fulfillRandomWords(
        uint256 /*requestId*/,
        uint256[] memory randomWords
    ) internal override {
        uint256 indexOfWinner = randomWords[0] % s_entrants.length;
        address payable winner = s_entrants[indexOfWinner];
        s_recentWinner = winner;
        s_entrants = new address payable[](0);
        s_lastTimeStamp = block.timestamp;
        s_lotteryState = LotteryState.OPEN;

        emit WinnerPicked(winner, address(this).balance);

        (bool success, ) = winner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    function setTicketPrice(uint256 _ticketPrice) public {
        require(msg.sender == owner);
        ticketPrice = _ticketPrice;
    }

    //getter functions

    function getTicketPrice() public view returns (uint256) {
        return ticketPrice;
    }

    function getNumberOfTickets() public view returns (uint256) {
        return s_entrants.length;
    }

    function getRaffleState() public view returns (LotteryState) {
        return s_lotteryState;
    }

    function getPlayer(uint256 index) public view returns (address) {
        return s_entrants[index];
    }

    function getRecentWinner() public view returns (address) {
        return s_recentWinner;
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }
}
