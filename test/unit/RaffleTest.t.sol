//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {Test, console} from "forge-std/Test.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

contract RaffleTest is Test {
    // events
    event RaffleEntered(address indexed entrant);

    Raffle raffle;
    HelperConfig helperConfig;
    uint256 _ticketPrice;
    uint256 interval;
    address vrfcoordinator;
    bytes32 gasLane;
    uint64 subcriptionId;
    uint32 callbackGasLimit;
    address link;
    uint256 deployerKey;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        vm.deal(PLAYER, STARTING_USER_BALANCE);
        (raffle, helperConfig) = deployer.run();
        (
            _ticketPrice,
            interval,
            vrfcoordinator,
            gasLane,
            subcriptionId,
            callbackGasLimit,
            link,
            deployerKey
        ) = helperConfig.activeNetworkConfig();
    }

    function testRaffleIntializedInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.LotteryState.OPEN);
    }

    // Enter Raffle //

    function testRaffleRevertsWhenYouDontSendEnoughEth() public {
        // Arrange
        vm.prank(PLAYER);
        // Assert // Act
        vm.expectRevert(Raffle.Raffle__NotEnoughEthSent.selector);
        raffle.enterRaffle();
    }

    function testRaffleRecordsPlayersOnEnter() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: _ticketPrice}();
        assert(raffle.getNumberOfTickets() == 1);
    }

    function testRaffleReturnsPlayerWhenEntered() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: _ticketPrice}();
        assert(raffle.getPlayer(0) == PLAYER);
    }

    function testRaffleEmitsEventsOnEntrance() public {
        vm.prank(PLAYER);
        vm.expectEmit(true, false, false, false, address(raffle));
        emit RaffleEntered(PLAYER);
        raffle.enterRaffle{value: _ticketPrice}();
    }

    function testCantEnterWhenRaffleNotOpen() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: _ticketPrice}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");
        vm.expectRevert(Raffle.Raffle__RaffleClosed.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: _ticketPrice}();
    }

    // Check Upkeep //
    function testCheckUpkeepReturnsFalseWithZeroBalance() public {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        assert(!upkeepNeeded);

        // vm.expectRevert(Raffle.Raffle__UpkeepNotNeeded.selector);
        // raffle.performUpkeep("");
    }

    function testCheckUpkeepReturnsFalseWhenRaffleNotOpen() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: _ticketPrice}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseWhenIntervalHasNotPassed() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: _ticketPrice}();
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsTrueWhenParametersAreGood() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: _ticketPrice}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(upkeepNeeded);
    }

    // Perform Upkeep //

    function testPerformUpkeepRunsWhenCheckUpkeepTrue() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: _ticketPrice}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        //vm.expectRevert(Raffle.Raffle__UpkeepNotNeeded.selector);
        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfCheckUpkeepFalse() public {
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        uint256 state = 0;

        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpkeepNotNeeded.selector,
                currentBalance,
                numPlayers,
                state
            )
        );
        raffle.performUpkeep("");
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: _ticketPrice}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 requestId = logs[1].topics[1];
        assert(uint256(requestId) > 0);
        Raffle.LotteryState rState = raffle.getRaffleState();
        assert(uint256(rState) == 1);
    }

    // FulfillRandomWords //

    function testFulFillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(
        uint256 randomRequestId
    ) public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: _ticketPrice}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfcoordinator).fulfillRandomWords(
            randomRequestId,
            address(raffle)
        );
    }

    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: _ticketPrice}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        uint256 additionalEntrants = 5;
        uint256 startingIndex = 1;
        for (
            uint256 i = startingIndex;
            i < startingIndex + additionalEntrants;
            i++
        ) {
            address player = address(uint160(i)); //address(i)
            hoax(player, STARTING_USER_BALANCE);
            raffle.enterRaffle{value: _ticketPrice}();
        }

        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 requestId = logs[1].topics[1];
        uint256 previousTimeStamp = raffle.getLastTimeStamp();
        uint256 prize = _ticketPrice * (additionalEntrants + 1);
        // Mocking VRF to get random number and pick winner
        VRFCoordinatorV2Mock(vrfcoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );

        // assert(uint256(raffle.getRaffleState()) == 0);
        // address recentWinner = raffle.getRecentWinner();
        // assert(recentWinner != address(0));
        // assert(raffle.getNumberOfTickets() == 0);
        // assert(raffle.getLastTimeStamp() > previousTimeStamp);
        console.log(raffle.getRecentWinner().balance);
        console.log(prize + STARTING_USER_BALANCE - _ticketPrice);
        console.log(_ticketPrice);
        assert(
            raffle.getRecentWinner().balance ==
                prize + STARTING_USER_BALANCE - _ticketPrice
        );
    }
}
